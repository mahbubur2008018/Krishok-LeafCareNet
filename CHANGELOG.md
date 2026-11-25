# Changelog: Krishok-LeafCareNet

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-11-22
### Added
- **LeafCareNet Core Architecture:** Hierarchical MobileNetV2 with coarse crop router and disease head in PyTorch.
- **Exported TFLite Model:** Bit-exact Float32 TFLite model (`9e6e7239...`) for edge inference.
- **Krishok Mobile Application:** Complete Flutter 3.x client with on-device camera inference, offline knowledge base, and optional Gemini LLM integration.
- **ESP32 Firmware:** Industrial RS-485 Modbus RTU reader for 7-in-1 NPK probe and local SoftAP REST server (`192.168.4.1/api/data`).
- **Reproducibility Suite:** 8-model comparative benchmark evaluation scripts, 10,000-replicate bootstrap CI generator, and statistical hypothesis tests.
- **Dataset Registry:** Provenance documentation and verified DOIs for all 10 utilized datasets (D1 and D2).
- **Security Audit:** Certified zero hardcoded credentials, API keys, or private tokens in staged repository.