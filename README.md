# Krishok–LeafCareNet
### Hierarchical Crop Disease Recognition, IoT Monitoring, and Intelligent Agricultural Advisory

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.10%2B-brightgreen.svg)](https://www.python.org/)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)](https://flutter.dev/)
[![TFLite](https://img.shields.io/badge/TensorFlow%20Lite-Float32-orange.svg)](models/MODEL_CARD.md)
[![Status](https://img.shields.io/badge/Status-Peer--Review%20Staging-orange.svg)](#)

---

## 1. Executive Overview

Smallholder farmers in developing nations face substantial crop yield losses caused by foliar plant pathogens, exacerbated by delayed diagnostic access and lack of in-situ soil nutrient monitoring. While computer vision models have achieved remarkable laboratory performance on benchmark datasets like PlantVillage, they frequently collapse when deployed on mobile devices in real-world agricultural fields due to background clutter, non-uniform solar illumination, and severe computational constraints.

**Krishok–LeafCareNet** is an end-to-end, edge-native agricultural diagnostic system combining:
1. **LeafCareNet:** A lightweight hierarchical deep learning architecture decoupling coarse crop routing (Rice, Potato, Tomato) from fine-grained disease identification (16 canonical classes) with only **2,248,211 parameters** (2.25M) and **0.31 GFLOPs**.
2. **Krishok Mobile Application:** A Flutter Android application delivering a **three-tier intelligence hierarchy**—on-device TFLite inference (Tier I), deterministic offline agronomic rules (Tier II), and optional cloud conversational advisory via Google Gemini (Tier III).
3. **IoT Microclimate Sensing Station:** An ESP32 microcontroller station reading soil macronutrients (Nitrogen, Phosphorus, Potassium) via industrial RS-485 Modbus RTU, ambient microclimate via SHT20 (I2C), and capacitive soil moisture, serving telemetry to the mobile phone via an isolated local SoftAP (`192.168.4.1`).

---

## 2. System Architecture

```
                                  [ FIELD ENVIRONMENT ]
                                             │
                       ┌─────────────────────┴─────────────────────┐
                       ▼                                           ▼
             [ Foliar Leaf Image ]                       [ In-Situ Soil Probe ]
                       │                                           │
                       │ Mobile Camera                             │ RS-485 Modbus RTU
                       ▼                                           ▼
         ┌───────────────────────────┐               ┌───────────────────────────┐
         │      KRISHOK APP          │◄───SoftAP─────│      ESP32 STATION        │
         │     (Flutter Client)      │   HTTP JSON   │   (7-in-1 NPK + SHT20)    │
         └─────────────┬─────────────┘               └───────────────────────────┘
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
  [ TIER I: CV ]  [ TIER II: KB ] [ TIER III: LLM ]
   LeafCareNet     Offline Rules   Cloud Gemini
   (On-Device)      (Bilingual)     (Optional)
```

---

## 3. Dataset Provenance & Cohort Distribution

The empirical evaluation of Krishok–LeafCareNet spans three rigorous evaluation cohorts:

| Cohort | Description | Image Count (N) | Crops & Classes | Purpose |
|:---|:---|:---:|:---|:---|
| **Cohort D1** | Controlled Laboratory Benchmark | 18,296 images (Train: 13,720, Val: 3,660, Test: 916) | Potato (3), Rice (5), Tomato (8) | Controlled model training, architectural optimization, and baseline benchmarking |
| **Cohort D2** | External Multi-Source Public Generalization | 2,337 images (Potato: 1,044, Rice: 884, Tomato: 409) | 16 Canonical Classes across 8 public repositories | Out-of-distribution evaluation against domain shift and unconstrained backgrounds |
| **Cohort D3** | Real-World In-Field Smartphone Generalization | 295 authentic field photos (Potato: 68, Rice: 92, Tomato: 135) | 16 Canonical Classes collected across Rajshahi, Bangladesh | Real-world validation on actual agricultural field conditions with mobile cameras |

### 16-Class Distribution Summary
- **Potato (3 Classes):** Early Blight, Late Blight, Healthy (D1 Test: 130 | D2: 1,044 | D3: 68)
- **Rice (5 Classes):** Bacterial Leaf Blight, Brown Spot, Healthy Leaf, Leaf Blast, Sheath Blight (D1 Test: 87 | D2: 884 | D3: 92)
- **Tomato (8 Classes):** Bacterial Spot, Early Blight, Late Blight, Leaf Mold, Spider Mites, TYLCV, Mosaic Virus, Healthy (D1 Test: 699 | D2: 409 | D3: 135)

---

## 4. Benchmark Results & Comparative Analysis

### 4.1 Eight-Model Benchmark Comparison (Cohort D1, N = 916)

All eight architectures were evaluated under identical training regimes (class-balanced sampling, AdamW optimizer, cosine annealing schedule) on the standardized D1 benchmark:

| Model Architecture | Paradigm | Parameters | D1 Accuracy (%) | D1 Macro-F1 (%) | D1 MCC | 95% Class-Stratified CI (10,000, Primary) | GPU Latency (ms) |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| MobileNetV2 Flat | Flat | 2,244,368 | 99.02% | 98.53% | 0.9890 | [98.36%, 99.56%] | 5.24 ms |
| EfficientNet-B3 Flat | Flat | 10,720,824 | 99.02% | 98.28% | 0.9890 | [98.36%, 99.56%] | 15.02 ms |
| FasterNet-M Flat | Flat | 52,258,912 | 98.47% | 98.40% | 0.9830 | [97.60%, 99.24%] | 13.02 ms |
| DeiT-Tiny Flat | Flat | 5,527,504 | 97.05% | 95.88% | 0.9672 | [95.96%, 98.03%] | 5.16 ms |
| EfficientNet-B3 Hierarchical | Hierarchical | 10,725,435 | 98.91% | 98.51% | 0.9878 | [98.25%, 99.56%] | 16.50 ms |
| FasterNet-M Hierarchical | Hierarchical | 52,262,371 | 98.25% | 96.86% | 0.9806 | [97.38%, 99.02%] | 10.01 ms |
| DeiT-Tiny Hierarchical | Hierarchical | 5,528,083 | 95.74% | 93.81% | 0.9526 | [94.43%, 96.94%] | 6.14 ms |
| **LeafCareNet (Proposed)** | **Hierarchical** | **2,248,211** | **99.13%** | **99.27%** | **0.9903** | **[98.47%, 99.67%]** | **5.67 ms** |

> **Bootstrap Protocol Note:** Primary intervals above reflect the manuscript-aligned **10,000 class-stratified bootstrap resamples (seed 42)**. Historical **1,000 unstratified empirical bootstrap results** from the original worker script are preserved side-by-side in [`evaluation/bootstrap_confidence_intervals_summary.csv`](evaluation/bootstrap_confidence_intervals_summary.csv) and [`evaluation/README.md`](evaluation/README.md).

### 4.2 Multi-Cohort Generalization Analysis (Table 1)

LeafCareNet demonstrated superior robustness across domain shifts while maintaining **100.00% coarse crop routing accuracy** across all cohorts:

| Cohort | Sample Size (N) | Correct | Errors | Accuracy (%) | Macro-F1 (%) | Weighted-F1 (%) | MCC | Cohen Kappa | Crop Routing | Mean Confidence |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Benchmark (D1)** | 916 | 908 | 8 | **99.13%** | **99.27%** | 99.13% | 0.9903 | 0.9902 | 100.00% | 0.9247 |
| **External Public (D2)** | 2,337 | 2,298 | 39 | **98.33%** | **95.09%** | 98.31% | 0.9809 | 0.9809 | 100.00% | 0.6894 |
| **Field-Collected (D3)** | 295 | 282 | 13 | **95.59%** | **94.80%** | 95.59% | 0.9526 | 0.9526 | 100.00% | 0.5989 |

---

## 5. Quickstart & Installation

### 5.1 Python Environment (Model Training & Evaluation)
```bash
git clone https://github.com/Mahbub-AI/Krishok-LeafCareNet.git
cd Krishok-LeafCareNet

# Create and activate virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r leafcarenet/requirements.txt
```

### 5.2 Running Model Inference
```bash
# Using TensorFlow Lite runtime
python leafcarenet/predict.py \
    --image path/to/leaf.jpg \
    --model models/LeafCareNet_final_float32.tflite
```

### 5.3 Reproducing Benchmark Evaluation
```bash
# Evaluate multi-cohort predictions across D1, D2, and D3
python evaluation/evaluate_benchmark.py

# Generate 10,000-replicate class-stratified bootstrap confidence intervals (Figure 11)
python evaluation/generate_bootstrap_ci.py
```

---

## 6. Krishok Mobile Application (Flutter)

The mobile application source is located in `krishok-mobile/`.

### 6.1 Architecture & Offline Runtime
- **Offline Classification:** Powered by on-device TensorFlow Lite (`assets/models/hierarchical_float32.tflite`).
- **Offline Advisory:** Integrated bilingual agronomic rule engine (`assets/knowledge/agri_knowledge.json`).
- **IoT Telemetry:** Connects directly to the ESP32 SoftAP (`http://192.168.4.1/api/data`).
- **Cloud Advisory (Optional):** Requires user to enter their personal Gemini API key in Settings. No credentials are hardcoded.

### 6.2 Building from Source
```bash
cd krishok-mobile
flutter pub get
flutter build apk --debug
```

Installable Android APK is available in `release-assets/krishok-app-v1.0-debug.apk`.

---

## 7. IoT Firmware (ESP32)

Microcontroller firmware is located in `esp32/firmware/`:
- `krishok_esp32_firmware.ino`: Standalone SoftAP web server reading NPK (RS-485 Modbus RTU), ambient temperature/humidity (SHT20 I2C), and capacitive soil moisture (ADC).
- `npk_modbus_reader.ino`: Dedicated Modbus diagnostic utility.

---

## 8. Authors & Institutional Attribution

This research was conducted at the **Department of Mechatronics Engineering, Rajshahi University of Engineering & Technology (RUET)**, Rajshahi-6204, Bangladesh.

- **Md. Mahbubur Rahman** (Co-first Author; Corresponding Author) — `mahbubur.2008018.ruet.mte@gmail.com` | [![ORCID](https://img.shields.io/badge/ORCID-0009--0004--0252--9140-A6CE39?logo=orcid&logoColor=white)](https://orcid.org/0009-0004-0252-9140)
- **Siam Mridha** (Co-first Author; Equal Contribution) | [![ORCID](https://img.shields.io/badge/ORCID-0009--0003--2850--8076-A6CE39?logo=orcid&logoColor=white)](https://orcid.org/0009-0003-2850-8076)
- **Faisal Rahman Badal** (Co-author) | [![ORCID](https://img.shields.io/badge/ORCID-0000--0002--7463--7675-A6CE39?logo=orcid&logoColor=white)](https://orcid.org/0000-0002-7463-7675)
- **Md Raihanul Haque Rahi** (Co-author) | [![ORCID](https://img.shields.io/badge/ORCID-0000--0002--2936--6263-A6CE39?logo=orcid&logoColor=white)](https://orcid.org/0000-0002-2936-6263)

**Authorship Statement:** Md. Mahbubur Rahman and Siam Mridha contributed equally to this work and share first authorship. Md. Mahbubur Rahman is the corresponding author (`mahbubur.2008018.ruet.mte@gmail.com`).

See [AUTHORS.md](AUTHORS.md) for detailed contribution statements.

---

## 9. License & Limitations

- **Software License:** **Apache License 2.0** (full official text in [LICENSE](LICENSE)). Authorized by the research team for all original LeafCareNet model architectures, training and evaluation scripts, ESP32 firmware, and Krishok Android application source code.
- **Third-Party Notices:** Third-party libraries, frameworks, and dataset attributions are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- **Provenance & Hardware Limitations:** Source-level per-repository image counts and class mappings for Cohort D2 cannot be fully reconstructed because external source pools were merged prior to stratified sampling (see [`datasets/DATASET_SOURCES.md`](datasets/DATASET_SOURCES.md)). Physical ESP32 microcontroller flashing and live sensor bench testing were not executed in this release environment.
