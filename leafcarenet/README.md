# LeafCareNet: Model Training, Architecture & Verification

This directory contains the core PyTorch model architecture, standalone demonstration pipeline, and original research training scripts for **LeafCareNet**.

---

## 1. Architecture Overview (`model.py`)

- **Backbone:** MobileNetV2 (`mobilenetv2_100.ra_in1k` via `timm`, 1280-dim feature output).
- **Stage 1 (Coarse Crop Router):** `Linear(1280 -> 3)` (Potato, Rice, Tomato).
- **Stage 2 (Decoupled Disease Heads):**
  - Potato Head: `Linear(1280 -> 3)` (Early Blight, Late Blight, Healthy).
  - Rice Head: `Linear(1280 -> 5)` (Bacterial Leaf Blight, Brown Spot, Healthy, Leaf Blast, Sheath Blight).
  - Tomato Head: `Linear(1280 -> 8)` (Bacterial Spot, Early Blight, Late Blight, Leaf Mold, Spider Mites, TYLCV, Mosaic Virus, Healthy).
- **Total Model Parameters:** Exactly **2,248,211** (100% strict match with `models/leafcarenet_best.pth`).

---

## 2. Distinction: `train.py` vs. Original Research Training Pipeline

To ensure absolute scientific integrity, the role of each training entry point is explicitly defined below:

| Component | Target File | Purpose & Scope | Execution Command |
|:---|:---|:---|:---|
| **Pipeline Smoke Test** | `train.py` | Minimal executable harness. Verifies forward/backward pass, multi-task loss ($2\mathcal{L}_{\text{crop}} + \mathcal{L}_{\text{disease}}$), and checkpoint saving. | `python train.py --smoke_test --device cpu` |
| **Standalone Training CLI** | `train.py` | Standalone trainer for single-node training on custom dataset directories. | `python train.py --data_dir /path/to/dataset --epochs 15` |
| **Original 8-Model Training Worker** | `training/leafcarenet_journal8_worker.py` | Full multi-model training worker executed during peer-reviewed benchmarking across all 8 configurations. | `python training/leafcarenet_journal8_worker.py --model_idx 5` |
| **Distributed Multi-GPU Notebook** | `training/leafcarenet3.ipynb` | 10-cell dynamic notebook orchestrating 2×T4 Kaggle GPU asynchronous training queue. | Execute on Kaggle / Jupyter environment |
| **Evaluation & Matrix Notebook** | `training/LeafCareNet_FINAL_8MODEL_...ipynb` | Full training, metric calculation, and raw-count confusion matrix generation. | Execute in Jupyter environment |

> [!NOTE]
> `train.py` is provided as an immediate, clean, local verification tool and architectural demonstration. Reproducing the complete eight-model peer-reviewed benchmark suite across all configurations utilizes `training/leafcarenet_journal8_worker.py`.

---

## 3. Quickstart Commands

### A. Run Architectural & Training Smoke Test
```bash
python train.py --smoke_test --device cpu
```
*Expected Output:*
- Instantiates `HierarchicalClassifier` (2,248,211 parameters).
- Generates 32 synthetic 16-class training samples.
- Executes 2 training and validation epochs in ~5 seconds.
- Saves `leafcarenet_smoke_test_best.pth` and exits with `STATUS: PASS`.

### B. Run Model Export & Parity Verification
```bash
python export_tflite.py
```
*Expected Output:*
- Strictly loads `models/leafcarenet_best.pth` (2,248,211 parameters, 0 missing/unexpected keys).
- Exports ONNX computational graph (`checkpoints/LeafCareNet_exported.onnx`).
- Validates numerical parity against production `models/LeafCareNet_final_float32.tflite` (Max absolute difference $< 10^{-4}$).

---

## 4. Replicating the Original Eight-Model Benchmark

The full comparative benchmark evaluated eight distinct architectures on the 18,296-image D1 cohort:
1. `01_flat_mobilenetv2` (2.24M params)
2. `02_flat_efficientnet_b3` (10.72M params)
3. `03_flat_fasternet_m` (52.26M params)
4. `04_flat_deit_tiny` (5.53M params)
5. `05_leafcarenet` (Proposed, 2.25M params)
6. `06_hier_efficientnet_b3` (10.73M params)
7. `07_hier_fasternet_m` (52.26M params)
8. `08_hier_deit_tiny` (5.53M params)

To run any specific baseline model worker:
```bash
python training/leafcarenet_journal8_worker.py --model_idx [1-8] --epochs 15 --batch_size 32 --lr 1e-3
```
Raw prediction outputs are saved to CSV and can be evaluated using `evaluation/evaluate_benchmark.py`.
