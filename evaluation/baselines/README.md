# Evaluated Baseline Architectures

The Krishok–LeafCareNet benchmark includes eight (8) standardized deep learning architectures evaluated across flat and hierarchical paradigms under identical training protocols:

1. **MobileNetV2 Flat:** Same-backbone flat baseline (2,244,368 params, D1 Acc: 99.02%, Macro-F1: 98.53%)
2. **EfficientNet-B3 Flat:** Standard convolutional baseline (10,720,824 params, D1 Acc: 99.02%, Macro-F1: 98.28%)
3. **FasterNet-M Flat:** High-throughput PConv CNN baseline (52,258,912 params, D1 Acc: 98.47%, Macro-F1: 98.40%)
4. **DeiT-Tiny Flat:** Compact Vision Transformer baseline (5,527,504 params, D1 Acc: 97.05%, Macro-F1: 95.88%)
5. **EfficientNet-B3 Hierarchical:** Hierarchical decoupled CNN control (10,725,435 params, D1 Acc: 98.91%, Macro-F1: 98.51%)
6. **FasterNet-M Hierarchical:** Hierarchical decoupled CNN control (52,262,371 params, D1 Acc: 98.25%, Macro-F1: 96.86%)
7. **DeiT-Tiny Hierarchical:** Hierarchical decoupled Transformer control (5,528,083 params, D1 Acc: 95.74%, Macro-F1: 93.81%)
8. **LeafCareNet (Proposed):** Lightweight Hierarchical MobileNetV2 (2,248,211 params, D1 Acc: 99.13%, Macro-F1: 99.27%)

Summary metrics and latency profiles are recorded in `evaluation/BENCHMARK_SUMMARY.csv`.
