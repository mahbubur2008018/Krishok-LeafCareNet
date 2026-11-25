# -*- coding: utf-8 -*-
"""
LeafCareNet Single-Image and Batch Prediction Tool.
Supports both PyTorch (.pth) and TensorFlow Lite (.tflite) inference engines.
"""

import os
import argparse
import json
import numpy as np
from PIL import Image

try:
    import torch
    from torchvision import transforms
    from model import HierarchicalClassifier, CANONICAL_CROPS, CANONICAL_16_CLASSES
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False


def preprocess_image(image_path: str):
    image = Image.open(image_path).convert("RGB")
    image = image.resize((224, 224), Image.BILINEAR)
    arr = np.array(image, dtype=np.float32) / 255.0
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    norm = (arr - mean) / std
    return norm


def predict_tflite(tflite_path: str, image_path: str):
    try:
        import tensorflow as tf
        interpreter = tf.lite.Interpreter(model_path=tflite_path)
    except Exception:
        from ai_edge_litert.interpreter import Interpreter
        interpreter = Interpreter(model_path=tflite_path)

    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    norm_img = preprocess_image(image_path)
    input_data = np.expand_dims(norm_img, axis=0).astype(np.float32)

    interpreter.set_tensor(input_details[0]["index"], input_data)
    interpreter.invoke()
    raw_output = interpreter.get_tensor(output_details[0]["index"])[0]  # [19]

    # Slice geometry: crop [0:3], potato [3:6], rice [6:11], tomato [11:19]
    crop_logits = raw_output[0:3]
    crop_exp = np.exp(crop_logits - np.max(crop_logits))
    crop_probs = crop_exp / np.sum(crop_exp)
    pred_crop = int(np.argmax(crop_probs))

    crop_slices = [(3, 6), (6, 11), (11, 19)]
    start, end = crop_slices[pred_crop]
    disease_logits = raw_output[start:end]
    d_exp = np.exp(disease_logits - np.max(disease_logits))
    disease_probs = d_exp / np.sum(d_exp)
    pred_d = int(np.argmax(disease_probs))

    crop_offsets = [0, 3, 8]
    global_idx = crop_offsets[pred_crop] + pred_d
    confidence = float(crop_probs[pred_crop] * disease_probs[pred_d])

    crop_names = ["Potato", "Rice", "Tomato"]
    return {
        "engine": "tflite",
        "crop": crop_names[pred_crop],
        "crop_confidence": float(crop_probs[pred_crop]),
        "disease_index": pred_d,
        "disease_confidence": float(disease_probs[pred_d]),
        "global_class_index": global_idx,
        "overall_confidence": confidence,
    }


def main():
    parser = argparse.ArgumentParser(description="Run LeafCareNet Inference")
    parser.add_argument("--image", type=str, required=True, help="Path to leaf image")
    parser.add_argument("--model", type=str, default="models/LeafCareNet_final_float32.tflite")
    args = parser.parse_args()

    if not os.path.exists(args.image):
        print(f"Error: Image {args.image} not found.")
        return

    if args.model.endswith(".tflite"):
        result = predict_tflite(args.model, args.image)
        print("Prediction Result:")
        print(json.dumps(result, indent=2))
    else:
        print("Please provide a .tflite model or implement PyTorch checkpoint inference.")


if __name__ == "__main__":
    main()
