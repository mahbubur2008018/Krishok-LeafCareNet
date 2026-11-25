# Krishok-LeafCareNet: Dataset Sources & Provenance Registry

## 1. Overview
This directory contains documentation, source provenance, and verified Digital Object Identifiers (DOIs) for all datasets utilized in the Krishok-LeafCareNet research project.

The experimental evaluation benchmarks models across three distinct cohorts:
1. **Cohort D1 (Development & Internal Benchmark):** Exactly 18,296 clean laboratory images split into:
   - **Training Set:** 13,720 images (75.0%)
   - **Validation Set:** 3,660 images (20.0%)
   - **Test Set:** 916 images (5.0%)
   - **Sources:**
     - **Potato & Tomato (16,555 images across 11 classes):** New Plant Diseases Dataset (`https://www.kaggle.com/datasets/vipoooool/new-plant-diseases-dataset`), derived from PlantVillage (`10.17632/tywbtsjrjv.1` / `10.48550/arXiv.1511.08060`). Covers Potato (3 classes: 2,600 images) and Tomato (8 classes: 13,955 images).
     - **Rice (1,741 images across 5 classes):** Mendeley Data *"Rice Leaf Bacterial and Fungal Disease Dataset"* by **Mehedi Hasan, Sonia Khatun, Md. Abu Raihan, Abdul Hasib Uddin** (`https://data.mendeley.com/datasets/hx6f852hw4/2`, Dataset DOI: `10.17632/hx6f852hw4.2`). Five target classes (`Bacterial Leaf Blight`, `Brown Spot`, `Healthy Leaf`, `Leaf Blast`, `Sheath Blight`) were selected from the original eight-class collection.
2. **Cohort D2 (External Generalization Benchmark):** Exactly 2,337 real-world field images sampled from eight (8) independent public repositories using class-size-adaptive stratified sampling without replacement (`create_stratified_random_test_dataset.py`, NumPy PCG64, fixed seed 42).
   - **Verified Ground-Truth Crop Breakdown:**
     - **Potato (3 Classes):** Exactly 1,044 images (Early Blight: 222, Late Blight: 238, Healthy: 584)
     - **Rice (5 Classes):** Exactly 884 images (Bacterial Leaf Blight: 68, Brown Spot: 226, Healthy Leaf: 294, Leaf Blast: 49, Sheath Blight: 247)
     - **Tomato (8 Classes):** Exactly 409 images (Bacterial Spot: 29, Early Blight: 72, Late Blight: 170, Leaf Mold: 20, Spider Mites: 31, Yellow Leaf Curl: 22, Mosaic Virus: 21, Healthy: 44)
     - **Total:** Exactly 2,337 field images across all 16 canonical categories.
   - **Contributing Repositories & Official Attributions:**
     1. **BanglaRiceLeaf Dataset:** Md. Al-Amin, Md. Abu Bakr Siddique, Md. Shahin Ali (Harvard Dataverse DOI: `10.7910/DVN/XAOBYW`, CC0 1.0 Universal, 5 native classes: Bacterial Leaf Blight, Bacterial Leaf Streak, Sheath Blight, Leaf Blast, Healthy Leaf).
     2. **Irish Potato Leaf Disease Dataset:** Hudson Laizer, Neema Mduma, Dina Machuve, Tumaini Lyimo, Claire Babirye, Jenifa Swai, Adam Siwingwa (Zenodo DOI: `10.5281/zenodo.8286529`, CC BY 4.0).
     3. **Paddy Doctor Challenge Dataset:** P. Petchiammal, D. Murugan et al. (`https://www.kaggle.com/competitions/paddy-disease-classification`).
     4. **High-Resolution Tomato Leaf Disease Dataset:** Puja Bapari, Md Zinnahtur Rahman Zitu, Mst Ummehani (Mendeley Data DOI: `10.17632/74zvtzx9pr.1`).
     5. **Tomato Leaf Diseases Detect:** Mohamed Traore (Roboflow Universe: `https://universe.roboflow.com/mohamed-traore-2ekkp/tomato-leaf-diseases-detect`).
     6. **Tomato Leaf Disease Classification Dataset (Mendeley Tomato v1):** Nure Alam Siddiki Rachin, Nasim Mahmud Likhon, Md Abdullah Hel Baki (Mendeley Data DOI: `10.17632/jttrv2w27r.1`).
     7. **Tomato Leaf Disease Classification Dataset in Pakistan:** Mohammad Naeem Malik, Syed Hashir Ali, Hamid Ali (Mendeley Data DOI: `10.17632/3mbnb82mxd.1`; official source contains 7,200 tomato images).
     8. **Tomato Leaf Image Dataset for Disease Analysis in Real-World Environment:** Mangsura Kabir Oni, Tabia Tanzin Prama (Mendeley Data DOI: `10.17632/rnbsw72zb5.1`; original annotation is `Healthy`/`Diseased`).
3. **Cohort D3 (Field Smartphone Evaluation):** Exactly 295 genuine field images captured by smallholder farmers using low-cost Android smartphones under unconstrained natural illumination in Rajshahi Agricultural Division, Bangladesh.
   - **Distribution:** Potato (68 images: Early Blight 26, Late Blight 22, Healthy 20), Rice (92 images: BLB 17, Brown Spot 20, Healthy 24, Leaf Blast 14, Sheath Blight 17), Tomato (135 images across 8 classes).
   - **Public Archive Status:** Pending publication in private author archive (no public DOI assigned yet).

## 2. Canonical 16-Class Hierarchy
- **Potato (3 Classes):** `Potato___Early_blight`, `Potato___Late_blight`, `Potato___healthy`
- **Rice (5 Classes):** `Rice___Bacterial_Leaf_Blight`, `Rice___Brown_Spot`, `Rice___Healthy_Leaf`, `Rice___Leaf_Blast`, `Rice___Sheath_Blight`
- **Tomato (8 Classes):** `Tomato___Bacterial_spot`, `Tomato___Early_blight`, `Tomato___Late_blight`, `Tomato___Leaf_Mold`, `Tomato___Spider_mites_Two_spotted_spider_mite`, `Tomato___Tomato_YellowLeaf_Curl_Virus`, `Tomato___Tomato_mosaic_virus`, `Tomato___healthy`

## 3. Provenance Limitations & Licensing Notice
- **Unavailable Source-Level Provenance (D2):** While crop-level counts (Potato: 1,044, Rice: 884, Tomato: 409; total = 2,337) and 16-class frequencies are 100% mathematically verified from ground truth prediction records, exact per-repository image counts and per-source class mappings cannot be exhaustively reconstructed because source folders were consolidated prior to stratified sampling. Specifically, for `D2-8` (Real-World Tomato, `10.17632/rnbsw72zb5.1`), the original source annotation is `Healthy`/`Diseased`, and no documented mapping evidence to specific tomato disease subclasses is available in the release archive.
- **Unverified Licenses & Links:** Third-party dataset licenses that were not explicitly verified on the canonical landing pages (e.g., Kaggle compilations, Roboflow community projects, and certain Mendeley releases) are marked as unverified in `DATASET_DOI_AND_SOURCE_REGISTRY.csv`. Third-party redistribution compatibility remains pending explicit owner verification.
