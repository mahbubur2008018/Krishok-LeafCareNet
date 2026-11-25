# -*- coding: utf-8 -*-
"""
Bootstrap Confidence Interval Generator and Figure 11 Reproducibility Script.

This script reconciles the two bootstrap evaluation protocols:
1. Original Manuscript Protocol (leafcarenet_journal8_worker.py / Cell 7):
   - Non-parametric empirical percentile bootstrap over held-out test cohort (N = 916)
   - RNG: numpy.random.default_rng(42)
   - Resamples: 1,000 repeats
   - Percentiles: 2.5th and 97.5th percentiles
   - Exactly reproduces manuscript Figure 11 bounds:
     * EfficientNet-B3 Flat: [98.47%, 99.56%]
     * FasterNet-M Flat: [97.71%, 99.24%]
     * EfficientNet-B3 Hierarchical: [98.14%, 99.56%]
     * DeiT-Tiny Hierarchical: [94.32%, 96.94%]
     * LeafCareNet Proposed: [98.47%, 99.67%]
2. Extended Class-Stratified Protocol:
   - Resamples within each of the 16 canonical classes separately
   - RNG: numpy.random.default_rng(42)
   - Resamples: 10,000 repeats
"""

import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

BASE_DIR = os.path.dirname(__file__)
BASELINES_DIR = os.path.join(BASE_DIR, "baselines", "predictions")
OUTPUT_CSV = os.path.join(BASE_DIR, "bootstrap_confidence_intervals_summary.csv")
OUTPUT_FIG = os.path.join(BASE_DIR, "fig_11_bootstrap_confidence_intervals.png")

MODELS = [
    ("01_flat_mobilenetv2", "MobileNetV2 Flat", "Flat"),
    ("02_flat_efficientnet_b3", "EfficientNet-B3 Flat", "Flat"),
    ("03_flat_fasternet_m", "FasterNet-M Flat", "Flat"),
    ("04_flat_deit_tiny", "DeiT-Tiny Flat", "Flat"),
    ("06_hier_efficientnet_b3", "EfficientNet-B3 Hierarchical", "Hierarchical"),
    ("07_hier_fasternet_m", "FasterNet-M Hierarchical", "Hierarchical"),
    ("08_hier_deit_tiny", "DeiT-Tiny Hierarchical", "Hierarchical"),
    ("05_leafcarenet", "LeafCareNet (Proposed)", "Proposed Hierarchical"),
]


def original_empirical_bootstrap_ci(y_true: np.ndarray, y_pred: np.ndarray, n_boot: int = 1000, seed: int = 42):
    """
    Original empirical non-parametric bootstrap from leafcarenet_journal8_worker.py:
    rng = np.random.default_rng(42)
    idx = rng.integers(0, n, size=n)
    """
    rng = np.random.default_rng(seed)
    n = len(y_true)
    accuracies = np.empty(n_boot, dtype=np.float64)
    for b in range(n_boot):
        idx = rng.integers(0, n, size=n)
        accuracies[b] = np.mean(y_true[idx] == y_pred[idx]) * 100.0

    mean_val = float(np.mean(accuracies))
    low = float(np.percentile(accuracies, 2.5))
    high = float(np.percentile(accuracies, 97.5))
    return mean_val, low, high


def class_stratified_bootstrap_ci(y_true: np.ndarray, y_pred: np.ndarray, n_boot: int = 10000, seed: int = 42):
    """Class-stratified resampling ensuring exact class proportion balance."""
    rng = np.random.default_rng(seed)
    classes, class_counts = np.unique(y_true, return_counts=True)
    class_indices = {c: np.where(y_true == c)[0] for c in classes}

    accuracies = np.empty(n_boot, dtype=np.float64)
    for b in range(n_boot):
        sample_idx = []
        for c, count in zip(classes, class_counts):
            sample_idx.extend(rng.choice(class_indices[c], size=count, replace=True))
        sample_idx = np.array(sample_idx)
        accuracies[b] = np.mean(y_true[sample_idx] == y_pred[sample_idx]) * 100.0

    mean_val = float(np.mean(accuracies))
    low = float(np.percentile(accuracies, 2.5))
    high = float(np.percentile(accuracies, 97.5))
    return mean_val, low, high


def plot_figure_11(df_results):
    """
    Generates Figure 11 publication plot consistent with the latest manuscript:
    - 10,000 Class-Stratified Bootstrap Resamples
    - Seed 42, NumPy PCG64
    - 95% Confidence Interval (2.5th and 97.5th percentiles)
    """
    plt.figure(figsize=(10, 6), dpi=300)
    
    y_pos = np.arange(len(df_results))
    means = df_results["Observed_Accuracy"].values
    lows = df_results["Class_Stratified_10k_CI_Low"].values
    highs = df_results["Class_Stratified_10k_CI_High"].values
    labels = df_results["Model"].values
    
    # Calculate asymmetric error bar lengths
    xerr = [means - lows, highs - means]
    
    colors = []
    for m in df_results["Model"]:
        if "LeafCareNet" in m:
            colors.append("#2e7d32")  # Distinctive green for proposed model
        elif "Hierarchical" in m:
            colors.append("#1565c0")  # Blue for hierarchical controls
        else:
            colors.append("#546e7a")  # Slate gray for flat controls

    bars = plt.barh(y_pos, means, xerr=xerr, align="center", color=colors, alpha=0.85, 
                     capsize=5, edgecolor="black", linewidth=0.8, height=0.6)
    
    plt.yticks(y_pos, labels, fontsize=10, fontweight="bold")
    plt.xlabel("Top-1 Classification Accuracy (%)", fontsize=11, fontweight="bold")
    plt.title("Figure 11: 95% Class-Stratified Bootstrap Confidence Intervals (N = 10,000 Resamples, Seed 42)", 
              fontsize=12, fontweight="bold", pad=15)
    plt.xlim(93.0, 100.0)
    plt.grid(axis="x", linestyle="--", alpha=0.6)
    
    # Value annotations
    for i, bar in enumerate(bars):
        m = means[i]
        lo = lows[i]
        hi = highs[i]
        plt.text(m + 0.15, bar.get_y() + bar.get_height()/2.0, 
                 f"{m:.2f}% [{lo:.2f}%, {hi:.2f}%]", 
                 va="center", fontsize=8.5, fontweight="bold", color="#212121")

    plt.tight_layout()
    plt.savefig(OUTPUT_FIG, dpi=300)
    plt.close()
    print(f"Saved Figure 11 publication plot to {OUTPUT_FIG}")


def main():
    print("=" * 80)
    print("BOOTSTRAP CONFIDENCE INTERVAL GENERATION & RECONCILIATION")
    print("Protocol 1 (Manuscript Specification): 10,000 Class-Stratified Resamples (Seed 42)")
    print("Protocol 2 (Original Worker Script):   1,000 Unstratified Resamples (Seed 42)")
    print("=" * 80)

    results = []
    for prefix, model_name, category in MODELS:
        fname = f"{prefix}_test_predictions.csv"
        csv_path = os.path.join(BASELINES_DIR, fname)
        if not os.path.exists(csv_path):
            print(f"Warning: File {csv_path} not found. Skipping.")
            continue

        df = pd.read_csv(csv_path)
        
        # Load true and predicted classes
        if "true_class" in df.columns and "pred_class" in df.columns:
            y_true = df["true_class"].values
            y_pred = df["pred_class"].values
        elif "true_canonical" in df.columns and "pred_canonical" in df.columns:
            y_true = df["true_canonical"].values
            y_pred = df["pred_canonical"].values
        else:
            y_true = df.iloc[:, 1].values
            y_pred = df.iloc[:, 2].values

        observed_acc = float(np.mean(y_true == y_pred) * 100.0)

        # 1. Class-Stratified Protocol (10,000 resamples, default_rng(42)) - Primary Manuscript Protocol
        strat_mean, strat_low, strat_high = class_stratified_bootstrap_ci(y_true, y_pred, n_boot=10000, seed=42)

        # 2. Original Protocol (1,000 empirical unstratified resamples, default_rng(42))
        orig_mean, orig_low, orig_high = original_empirical_bootstrap_ci(y_true, y_pred, n_boot=1000, seed=42)

        results.append({
            "Model": model_name,
            "Category": category,
            "Observed_Accuracy": round(observed_acc, 2),
            "Class_Stratified_10k_CI_Low": round(strat_low, 2),
            "Class_Stratified_10k_CI_High": round(strat_high, 2),
            "Class_Stratified_10k_CI": f"[{strat_low:.2f}%, {strat_high:.2f}%]",
            "Original_Unstratified_1k_CI_Low": round(orig_low, 2),
            "Original_Unstratified_1k_CI_High": round(orig_high, 2),
            "Original_Unstratified_1k_CI": f"[{orig_low:.2f}%, {orig_high:.2f}%]"
        })

        print(f"{model_name:30s}: Observed={observed_acc:.2f}% | "
              f"Manuscript Stratified CI: [{strat_low:.2f}%, {strat_high:.2f}%] | "
              f"Original Unstratified CI: [{orig_low:.2f}%, {orig_high:.2f}%]")

    df_out = pd.DataFrame(results)
    df_out.to_csv(OUTPUT_CSV, index=False)
    print(f"\nSaved reconciled bootstrap summary to {OUTPUT_CSV}")

    plot_figure_11(df_out)


if __name__ == "__main__":
    main()

