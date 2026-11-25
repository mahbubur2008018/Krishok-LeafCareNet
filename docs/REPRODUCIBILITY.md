# Scientific Reproducibility Protocol: Krishok–LeafCareNet

## Research Authorship
- **Co-First Authors:** Md. Mahbubur Rahman & Siam Mridha (Equal Contribution)
- **Co-Authors:** Faisal Rahman Badal & Md Raihanul Haque Rahi
- **Corresponding Author:** Md. Mahbubur Rahman (Email: `mahbubur.2008018.ruet.mte@gmail.com`)
- **Institution:** Department of Mechatronics Engineering, Rajshahi University of Engineering & Technology (RUET), Bangladesh

## Deterministic Verification Gates
1. **Model Checkpoint Parity:** PyTorch checkpoint (`leafcarenet_best.pth`, SHA-256: `8511b9dd...`) and edge Float32 TFLite (`LeafCareNet_final_float32.tflite`, SHA-256: `9e6e7239...`).
2. **D2 Sampling Determinism:** Class-stratified selection via NumPy `PCG64` using fixed seed `42` reproducing the exact 2,337 external field images.
3. **Statistical Confidence Intervals:** 10,000-replicate 16-class-stratified bootstrap confidence intervals matching Figure 11.
