# Krishok-LeafCareNet Evaluation Suite

This directory contains the complete benchmark evaluation suite, statistical scripts, and ground-truth predictions across all eight evaluated models and three evaluation cohorts (D1, D2, D3).

---

## 1. Key Components

- **`BENCHMARK_SUMMARY.csv`**: Consolidated performance metrics across all 8 evaluated model architectures on Cohort D1 ($N = 916$).
- **`MULTI_COHORT_BENCHMARK_SUMMARY.csv`**: Performance metrics for LeafCareNet across Cohort D1 ($N = 916$), Cohort D2 ($N = 2,337$), and Cohort D3 ($N = 295$).
- **`bootstrap_confidence_intervals_summary.csv`**: Full statistical confidence interval table containing both:
  - **Protocol 1 (Manuscript Class-Stratified)**: 10,000 class-stratified resamples (NumPy PCG64, seed 42).
  - **Protocol 2 (Worker Script Empirical)**: 1,000 unstratified resamples (NumPy PCG64, seed 42).
- **`fig_11_bootstrap_confidence_intervals.png`**: High-resolution publication chart depicting 95% Class-Stratified Bootstrap Confidence Intervals across all eight models.
- **`evaluate_benchmark.py`**: Automated metric evaluation engine reproducing Accuracy, Macro-F1, Weighted-F1, MCC, Cohen's Kappa, and Crop Routing Accuracy.
- **`generate_bootstrap_ci.py`**: Bootstrap confidence interval generator implementing both Protocol 1 and Protocol 2, outputting `fig_11_bootstrap_confidence_intervals.png`.
- **`REPRODUCE_RESULTS.md`**: Step-by-step walkthrough to reproduce all benchmark tables and figures.

---

## 2. Statistical Methodology & Bootstrap Protocol Comparison

To ensure complete transparency and scientific rigor, `generate_bootstrap_ci.py` calculates confidence intervals under both the manuscript specification and the historical worker script:

| Model Architecture | Observed Acc (%) | Protocol 1: 10,000 Class-Stratified CI (Manuscript / Fig 11) | Protocol 2: 1,000 Empirical CI (Worker Script) |
|:---|:---:|:---:|:---:|
| MobileNetV2 Flat | 99.02% | [98.36%, 99.56%] | [98.36%, 99.56%] |
| EfficientNet-B3 Flat | 99.02% | [98.36%, 99.56%] | [98.47%, 99.56%] |
| FasterNet-M Flat | 98.47% | [97.60%, 99.24%] | [97.71%, 99.24%] |
| DeiT-Tiny Flat | 97.05% | [95.96%, 98.03%] | [95.96%, 98.03%] |
| EfficientNet-B3 Hierarchical | 98.91% | [98.25%, 99.56%] | [98.14%, 99.56%] |
| FasterNet-M Hierarchical | 98.25% | [97.38%, 99.02%] | [97.38%, 99.02%] |
| DeiT-Tiny Hierarchical | 95.74% | [94.43%, 96.94%] | [94.32%, 96.94%] |
| **LeafCareNet (Proposed)** | **99.13%** | **[98.47%, 99.67%]** | **[98.47%, 99.67%]** |

**Execution:**
```bash
python evaluation/generate_bootstrap_ci.py
```
This recomputes both protocols from the underlying image-level predictions and regenerates Figure 11.
