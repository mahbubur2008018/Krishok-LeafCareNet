# D2 External Benchmark Reproducibility Guide

To reproduce the exact 2,337-image D2 cohort from raw source repository downloads:

1. Download all eight external datasets listed in `DATASET_DOI_AND_SOURCE_REGISTRY.csv`.
2. Extract the respective folders into the input directory structure:
   `evaluation/Test Dataset 4/Crop_Disease_Dataset/{Crop}/{Disease}/`
3. Execute the reproducible stratified sampling script with fixed random seed 42:
   ```bash
   python datasets/create_stratified_random_test_dataset.py
   ```
4. Verification:
   - The script initializes `numpy.random.PCG64(42)`.
   - Generates exactly 2,337 test images in `Stratified_Random_Test_Dataset/images/` across 16 canonical categories.
   - Generates `sampling_manifest.csv` and `class_distribution.csv` recording each sampled file path.
