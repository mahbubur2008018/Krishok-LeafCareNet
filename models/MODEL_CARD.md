# LeafCareNet Model Card

## Model Overview
- **Model Name:** LeafCareNet (Hierarchical Decoupled Crop Disease Recognition Network)
- **Model Version:** 1.0 (Journal Publication Checkpoint)
- **Architecture:** Two-stage hierarchical decoupled architecture
  - **Backbone:** MobileNetV2 (`mobilenetv2_100.ra_in1k`, feature dimension = 1280)
  - **Stage 1 (Coarse Crop Router):** Linear(1280 -> 3) [Potato, Rice, Tomato]
  - **Stage 2 (Decoupled Disease Heads):**
    - Potato Head: Linear(1280 -> 3) [Early Blight, Late Blight, Healthy]
    - Rice Head: Linear(1280 -> 5) [Bacterial Blight, Brown Spot, Healthy, Leaf Blast, Sheath Blight]
    - Tomato Head: Linear(1280 -> 8) [Bacterial Spot, Early Blight, Late Blight, Leaf Mold, Spider Mites, TYLCV, Mosaic Virus, Healthy]
- **Parameters:** 2,248,211 (2.25M)
- **FLOPs:** 0.31 GFLOPs
- **Checkpoint File:** `leafcarenet_best.pth` (9,254,415 bytes, SHA-256: `8511b9dde344760dfd6509709fc8e4896fc98cd1be3907d39535ecba757835e0`)
- **TFLite Export:** `LeafCareNet_final_float32.tflite` (8,951,484 bytes, SHA-256: `9e6e72392aa0c51c62f22b8ea375ecaa4f509aeb7b13783a31c6d31bb98d4077`)
- **TFLite Output Geometry:** `[1, 19]` (crop: `[0:3]`, potato: `[3:6]`, rice: `[6:11]`, tomato: `[11:19]`)

---

## Performance Summary

| Evaluation Cohort | Sample Size (N) | Accuracy (%) | Macro-F1 (%) | Weighted-F1 (%) | MCC | Crop Routing Accuracy |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| **Cohort D1 (In-Distribution)** | 916 | **99.13%** | **99.27%** | 99.13% | 0.9903 | 100.00% |
| **Cohort D2 (External Public)** | 2,337 | **98.33%** | **95.09%** | 98.31% | 0.9809 | 100.00% |
| **Cohort D3 (In-Field Smartphone)** | 295 | **95.59%** | **94.80%** | 95.59% | 0.9526 | 100.00% |

---

## Intended Use
- Real-time, on-device foliar disease diagnosis on resource-constrained mobile and edge IoT devices.
- Fully offline inference in rural agricultural settings without internet connectivity.
