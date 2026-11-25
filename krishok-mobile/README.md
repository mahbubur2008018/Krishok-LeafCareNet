# Krishok Mobile Application (Flutter)

**Krishok** (কৃষক) is a smart agricultural decision-support application built with Flutter 3.x.

## Three-Tier Architecture
1. **Tier I (Edge Vision):** On-device leaf disease recognition powered by `hierarchical_float32.tflite` (100% offline).
2. **Tier II (Deterministic Advisory):** Rule-based treatment and fertilizer guidelines in Bengali and English (100% offline).
3. **Tier III (Interactive Advisory):** Conversational agricultural assistance via Google Gemini (Online, user-supplied key).

## Build Instructions
```bash
# 1. Install dependencies
flutter pub get

# 2. Run on connected Android device
flutter run --dart-define=GEMINI_API_KEY=YOUR_KEY

# 3. Build standalone debug APK
flutter build apk --debug --dart-define=GEMINI_API_KEY=YOUR_KEY
```