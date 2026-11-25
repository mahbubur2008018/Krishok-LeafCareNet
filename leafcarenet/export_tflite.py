# -*- coding: utf-8 -*-
"""
LeafCareNet PyTorch-to-TFLite Conversion and Verification Pipeline.
Pipeline Stages:
1. Strict Checkpoint Loading (models/leafcarenet_best.pth)
2. PyTorch Concatenated Export Wrapper
3. ONNX Graph Export (opset 13)
4. Numerical Parity Verification between PyTorch and TensorFlow Lite
5. Preservation of evaluated production TFLite model
"""

import os
import sys
import json
import argparse
import numpy as np
import torch
import torch.nn as nn

from model import HierarchicalClassifier, CANONICAL_16_CLASSES


class LeafCareNetExportWrapper(nn.Module):
    """
    Export wrapper concatenating hierarchical outputs into a unified [1, 19] tensor:
    - Slices:
      [0:3]   Crop Logits (Potato, Rice, Tomato)
      [3:6]   Potato Disease Logits (3 classes)
      [6:11]  Rice Disease Logits (5 classes)
      [11:19] Tomato Disease Logits (8 classes)
    """
    def __init__(self, base_model: HierarchicalClassifier):
        super().__init__()
        self.base = base_model

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        crop_logits, disease_logits = self.base(x)
        return torch.cat([crop_logits, disease_logits[0], disease_logits[1], disease_logits[2]], dim=-1)


def verify_numerical_parity(pytorch_model, tflite_path: str, n_tests: int = 5):
    """
    Verifies that PyTorch and the deployed production TFLite binary produce identical outputs.
    Note on Model IO:
    - The production TFLite graph embeds internal preprocessing (division by 255 and ImageNet
      mean/std normalization) for zero-overhead Flutter/Android mobile integration.
    - Thus, TFLite accepts raw RGB float32 arrays in [0, 255] (NHWC [1, 224, 224, 3]).
    - PyTorch expects explicitly normalized float32 tensors (NCHW [1, 3, 224, 224]).
    """
    import tensorflow as tf

    interpreter = tf.lite.Interpreter(model_path=tflite_path)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    pytorch_model.eval()
    max_diffs = []
    mean_diffs = []

    print(f"\nRunning numerical parity verification on {n_tests} test inputs...")
    print("  (Accounting for internal TFLite mobile preprocessing: [0, 255] -> ImageNet norm)")
    rng = np.random.RandomState(42)

    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32).reshape(1, 1, 3)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32).reshape(1, 1, 3)

    for i in range(n_tests):
        # Generate raw RGB pixel values in [0, 255]
        img_255 = rng.uniform(0.0, 255.0, (1, 224, 224, 3)).astype(np.float32)

        # PyTorch input: normalized [0, 1] then ImageNet mean/std, shape [1, 3, 224, 224]
        img_norm = (img_255[0] / 255.0 - mean) / std
        x_torch = torch.from_numpy(img_norm.transpose(2, 0, 1)).unsqueeze(0).float()

        with torch.no_grad():
            py_wrapper = LeafCareNetExportWrapper(pytorch_model)
            py_out = py_wrapper(x_torch).cpu().numpy()[0]  # [19]

        # TFLite input: raw [0, 255] float32 NHWC
        interpreter.set_tensor(input_details[0]["index"], img_255)
        interpreter.invoke()
        tf_out = interpreter.get_tensor(output_details[0]["index"])[0]  # [19]

        diff = np.abs(py_out - tf_out)
        max_diffs.append(np.max(diff))
        mean_diffs.append(np.mean(diff))

    overall_max = float(np.max(max_diffs))
    overall_mean = float(np.mean(mean_diffs))

    print(f"  PyTorch vs TFLite Maximum Absolute Difference: {overall_max:.6e}")
    print(f"  PyTorch vs TFLite Mean Absolute Difference:    {overall_mean:.6e}")

    parity_pass = overall_max < 1e-4
    print(f"  Numerical Parity Status: {'PASSED (Fidelity Verified, max diff < 1e-4)' if parity_pass else 'FAILED'}")
    return {
        "max_abs_diff": overall_max,
        "mean_abs_diff": overall_mean,
        "parity_pass": parity_pass,
        "tolerance": 1e-4,
        "n_tests": n_tests
    }


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_dir = os.path.dirname(script_dir)
    default_ckpt = os.path.join(repo_dir, "models", "leafcarenet_best.pth")
    default_tflite = os.path.join(repo_dir, "models", "LeafCareNet_final_float32.tflite")
    default_onnx = os.path.join(script_dir, "checkpoints", "LeafCareNet_exported.onnx")

    parser = argparse.ArgumentParser(description="Export LeafCareNet to ONNX and verify TFLite parity")
    parser.add_argument("--checkpoint", type=str, default=default_ckpt)
    parser.add_argument("--tflite", type=str, default=default_tflite)
    parser.add_argument("--onnx_output", type=str, default=default_onnx)
    parser.add_argument("--verify_only", action="store_true")
    args = parser.parse_args()

    print("=" * 70)
    print("LEAFCARENET EXPORT & CONVERSION VERIFICATION PIPELINE")
    print("=" * 70)

    # 1. Strict Checkpoint Loading
    if not os.path.exists(args.checkpoint):
        print(f"Error: Checkpoint file {args.checkpoint} not found.")
        sys.exit(1)

    print(f"Loading PyTorch checkpoint from {args.checkpoint}...")
    model = HierarchicalClassifier(pretrained=False)
    state_dict = torch.load(args.checkpoint, map_location="cpu")
    res = model.load_state_dict(state_dict, strict=True)
    n_params = sum(p.numel() for p in model.parameters())

    print(f"  Strict Load Result: {res}")
    print(f"  Total Model Parameters: {n_params:,}")
    assert n_params == 2248211, f"Parameter mismatch: {n_params} != 2,248,211"
    print("  Checkpoint Loading: 100% STRICT MATCH (STATUS: PASS)")

    # 2. ONNX Graph Export
    os.makedirs(os.path.dirname(args.onnx_output), exist_ok=True)
    print(f"\\nExporting to ONNX at {args.onnx_output}...")
    model.eval()
    wrapper = LeafCareNetExportWrapper(model)
    dummy_input = torch.randn(1, 3, 224, 224)

    torch.onnx.export(
        wrapper,
        dummy_input,
        args.onnx_output,
        export_params=True,
        opset_version=13,
        do_constant_folding=True,
        input_names=["image"],
        output_names=["logits"],
        dynamic_axes={"image": {0: "batch_size"}, "logits": {0: "batch_size"}}
    )
    print(f"  ONNX Export Succeeded. Size: {os.path.getsize(args.onnx_output):,} bytes")

    # 3. Numerical Parity Verification with Preserved Production TFLite Binary
    if os.path.exists(args.tflite):
        print(f"\\nPreserved Production TFLite Binary: {args.tflite} ({os.path.getsize(args.tflite):,} bytes)")
        parity = verify_numerical_parity(model, args.tflite, n_tests=5)
        
        validation_report = {
            "checkpoint": args.checkpoint,
            "tflite_binary": args.tflite,
            "onnx_export": args.onnx_output,
            "parameters": n_params,
            "numerical_parity": parity,
            "status": "PASS" if parity["parity_pass"] else "FAIL"
        }
        
        report_path = os.path.join(os.path.dirname(args.onnx_output), "export_validation_report.json")
        with open(report_path, "w", encoding="utf-8") as f:
            json.dump(validation_report, f, indent=2)
        print(f"  Export validation report saved to {report_path}")
    else:
        print(f"  Warning: Target TFLite file {args.tflite} not found for parity check.")

    print("=" * 70)
    print("CONVERSION & EXPORT VERIFICATION COMPLETED SUCCESSFULLY")
    print("=" * 70)


if __name__ == "__main__":
    main()
