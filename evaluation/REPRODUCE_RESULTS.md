# Reproducing Krishok–LeafCareNet Experimental Results

This guide provides step-by-step instructions for independently validating the experimental findings reported in the manuscript.

---

## 1. Multi-Cohort Performance Validation

Run the automated evaluation benchmark across all three evaluation cohorts:
```bash
python evaluation/evaluate_benchmark.py
```

### Expected Verified Metrics:
- **Cohort D1 (N = 916):**
  - Accuracy: 99.13% (908 correct, 8 errors)
  - Macro-F1: 99.27%
  - Weighted-F1: 99.13%
  - MCC: 0.9903
  - Cohen's Kappa: 0.9902
  - Crop Routing Accuracy: 100.00%
- **Cohort D2 (N = 2,337):**
  - Accuracy: 98.33% (2,298 correct, 39 errors)
  - Macro-F1: 95.09%
  - Weighted-F1: 98.31%
  - MCC: 0.9809
  - Cohen's Kappa: 0.9809
  - Crop Routing Accuracy: 100.00%
- **Cohort D3 (N = 295):**
  - Accuracy: 95.59% (282 correct, 13 errors)
  - Macro-F1: 94.80%
  - Weighted-F1: 95.59%
  - MCC: 0.9526
  - Cohen's Kappa: 0.9526
  - Crop Routing Accuracy: 100.00%

---

## 2. Bootstrap Confidence Intervals & Figure 11 Reproduction

Run the bootstrap generator script:
```bash
python evaluation/generate_bootstrap_ci.py
```

This calculates both statistical protocols and generates the publication-ready Figure 11 (`fig_11_bootstrap_confidence_intervals.png`):

### Protocol 1: Manuscript 10,000 Class-Stratified 95% CI (Figure 11 Generator)
- MobileNetV2 Flat: `[98.36%, 99.56%]`
- EfficientNet-B3 Flat: `[98.36%, 99.56%]`
- FasterNet-M Flat: `[97.60%, 99.24%]`
- DeiT-Tiny Flat: `[95.96%, 98.03%]`
- EfficientNet-B3 Hierarchical: `[98.25%, 99.56%]`
- FasterNet-M Hierarchical: `[97.38%, 99.02%]`
- DeiT-Tiny Hierarchical: `[94.43%, 96.94%]`
- **LeafCareNet (Proposed):** `[98.47%, 99.67%]`

### Protocol 2: Worker Script 1,000 Empirical Non-Stratified 95% CI
- MobileNetV2 Flat: `[98.36%, 99.56%]`
- EfficientNet-B3 Flat: `[98.47%, 99.56%]`
- FasterNet-M Flat: `[97.71%, 99.24%]`
- DeiT-Tiny Flat: `[95.96%, 98.03%]`
- EfficientNet-B3 Hierarchical: `[98.14%, 99.56%]`
- FasterNet-M Hierarchical: `[97.38%, 99.02%]`
- DeiT-Tiny Hierarchical: `[94.32%, 96.94%]`
- **LeafCareNet (Proposed):** `[98.47%, 99.67%]`

Both protocols are saved side-by-side in `evaluation/bootstrap_confidence_intervals_summary.csv`.
