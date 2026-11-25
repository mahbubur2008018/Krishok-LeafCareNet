# -*- coding: utf-8 -*-
"""
Evaluate LeafCareNet Across Three Evaluation Cohorts & Eight Benchmark Models:
- D1 Development Benchmark (N = 916)
- D2 External Public Validation (N = 2,337)
- D3 Authentic Field Smartphone Evaluation (N = 295)

Calculates dynamically:
- Accuracy, Macro-F1, Weighted-F1, MCC, Cohen Kappa
- Stage-1 Coarse Crop-Routing Accuracy from actual predicted class labels
"""

import os
import pandas as pd
import numpy as np
from sklearn.metrics import accuracy_score, f1_score, matthews_corrcoef, cohen_kappa_score

BASE_DIR = os.path.dirname(__file__)
RESULTS_DIR = os.path.join(BASE_DIR, "results")
BASELINES_DIR = os.path.join(BASE_DIR, "baselines", "predictions")


def extract_crop_label(label_val: str) -> str:
    """Dynamically extracts the coarse crop category (potato, rice, tomato)."""
    s = str(label_val).lower().strip()
    if "::" in s:
        return s.split("::")[0].strip()
    if "___" in s:
        return s.split("___")[0].strip()
    if "_" in s:
        return s.split("_")[0].strip()
    return s


def evaluate_cohort(csv_path: str, cohort_name: str):
    if not os.path.exists(csv_path):
        print(f"Prediction file not found: {csv_path}")
        return None

    df = pd.read_csv(csv_path)

    # 1. Identify true and pred columns
    if "true_canonical" in df.columns and "pred_canonical" in df.columns:
        y_true = df["true_canonical"].values
        y_pred = df["pred_canonical"].values
    elif "true_class" in df.columns and "pred_class" in df.columns:
        y_true = df["true_class"].values
        y_pred = df["pred_class"].values
    elif "y_true" in df.columns and "y_pred" in df.columns:
        y_true = df["y_true"].values
        y_pred = df["y_pred"].values
    else:
        cols = df.columns.tolist()
        y_true = df[cols[1]].values
        y_pred = df[cols[2]].values

    n_total = len(y_true)
    n_correct = int(np.sum(y_true == y_pred))
    n_errors = n_total - n_correct
    acc = accuracy_score(y_true, y_pred) * 100.0
    macro_f1 = f1_score(y_true, y_pred, average="macro") * 100.0
    weighted_f1 = f1_score(y_true, y_pred, average="weighted") * 100.0
    mcc = matthews_corrcoef(y_true, y_pred)
    kappa = cohen_kappa_score(y_true, y_pred)

    # 2. Dynamic Stage-1 Crop Routing Calculation
    if "crop" in df.columns and "pred_crop" in df.columns:
        crops_true = df["crop"].astype(str).str.lower().str.strip()
        crops_pred = df["pred_crop"].astype(str).str.lower().str.strip()
    else:
        crops_true = pd.Series(y_true).apply(extract_crop_label)
        crops_pred = pd.Series(y_pred).apply(extract_crop_label)

    crop_matches = (crops_true == crops_pred).sum()
    crop_routing_acc = (crop_matches / n_total) * 100.0

    print(f"=== {cohort_name} (N = {n_total:,}) ===")
    print(f"  Classification: Correct: {n_correct} | Errors: {n_errors}")
    print(f"  Top-1 Accuracy:    {acc:.2f}%")
    print(f"  Macro-Averaged F1: {macro_f1:.2f}%")
    print(f"  Weighted F1:       {weighted_f1:.2f}%")
    print(f"  Matthews CorrCoef: {mcc:.4f}")
    print(f"  Cohen Kappa:       {kappa:.4f}")
    print(f"  Stage-1 Crop Routing: {crop_routing_acc:.2f}% ({crop_matches}/{n_total} samples correctly routed)\n")

    return {
        "cohort": cohort_name,
        "n": n_total,
        "correct": n_correct,
        "errors": n_errors,
        "accuracy": acc,
        "macro_f1": macro_f1,
        "weighted_f1": weighted_f1,
        "mcc": mcc,
        "kappa": kappa,
        "crop_routing_accuracy": crop_routing_acc,
        "crop_matches": crop_matches
    }


def evaluate_eight_model_benchmark():
    print("==================================================================")
    print("Eight-Model D1 Benchmark Recalculation (N = 916)")
    print("==================================================================")

    models = [
        ("01_flat_mobilenetv2", "MobileNetV2 Flat", "Flat", 2244368),
        ("02_flat_efficientnet_b3", "EfficientNet-B3 Flat", "Flat", 10720824),
        ("03_flat_fasternet_m", "FasterNet-M Flat", "Flat", 52258912),
        ("04_flat_deit_tiny", "DeiT-Tiny Flat", "Flat", 5527504),
        ("06_hier_efficientnet_b3", "EfficientNet-B3 Hierarchical", "Hierarchical", 10725435),
        ("07_hier_fasternet_m", "FasterNet-M Hierarchical", "Hierarchical", 52262371),
        ("08_hier_deit_tiny", "DeiT-Tiny Hierarchical", "Hierarchical", 5528083),
        ("05_leafcarenet", "LeafCareNet (Proposed)", "Hierarchical", 2248211),
    ]

    records = []
    for m_id, m_name, paradigm, params in models:
        csv_p = os.path.join(BASELINES_DIR, f"{m_id}_test_predictions.csv")
        if not os.path.exists(csv_p):
            print(f"Missing predictions for {m_id}")
            continue

        df = pd.read_csv(csv_p)
        yt = df["true_global_idx"].values
        yp = df["pred_global_idx"].values
        acc = accuracy_score(yt, yp) * 100.0
        mf1 = f1_score(yt, yp, average="macro") * 100.0
        mcc = matthews_corrcoef(yt, yp)

        records.append({
            "Model": m_name,
            "Paradigm": paradigm,
            "Params": params,
            "Accuracy": acc,
            "Macro_F1": mf1,
            "MCC": mcc
        })
        print(f"  {m_name:<30} | {paradigm:<12} | Params: {params:>10,} | Acc: {acc:.2f}% | F1: {mf1:.2f}% | MCC: {mcc:.4f}")

    print()
    return pd.DataFrame(records)


def main():
    print("==================================================================")
    print("Krishok–LeafCareNet Authentic Evaluation Engine")
    print("Mode: Dynamic Recalculation from Raw Image-Level Prediction Records")
    print("==================================================================\n")

    # Multi-cohort generalization
    d1_csv = os.path.join(RESULTS_DIR, "d1_predictions.csv")
    d2_csv = os.path.join(RESULTS_DIR, "d2_predictions.csv")
    d3_csv = os.path.join(RESULTS_DIR, "d3_predictions.csv")

    evaluate_cohort(d1_csv, "Cohort D1: In-Distribution Benchmark")
    evaluate_cohort(d2_csv, "Cohort D2: External Multi-Source Public Generalization")
    evaluate_cohort(d3_csv, "Cohort D3: Real-World In-Field Smartphone Generalization")

    # Eight-model benchmark
    evaluate_eight_model_benchmark()


if __name__ == "__main__":
    main()
