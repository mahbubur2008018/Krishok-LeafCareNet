import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ml_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// GoogleVisionService
// Tier-2 fallback for disease classification when Gemini Vision fails.
//
// Uses Google Cloud Vision API (LABEL_DETECTION + WEB_DETECTION) to identify
// crop + disease from image labels, then maps results to the same
// InferenceResult structure used by Gemini and TFLite.
//
// Setup: Enable "Cloud Vision API" in Google Cloud Console.
//        Use the same API Key as Gemini OR a separate one.
// ════════════════════════════════════════════════════════════════════════════

class GoogleVisionService {
  static const _endpoint =
      'https://vision.googleapis.com/v1/images:annotate';
  static const _apiKeyPref = 'google_vision_api_key';

  // ── Keyword maps ──────────────────────────────────────────────────────────
  // Lower-case keywords that Vision API label/web-entity descriptions
  // typically contain for each crop and disease.

  static const _cropKeywords = <String, List<String>>{
    'potato': ['potato', 'solanum tuberosum'],
    'tomato': ['tomato', 'solanum lycopersicum', 'lycopersicon'],
    'rice':   ['rice', 'oryza sativa', 'paddy', 'paddy field'],
  };

  static const _diseaseKeywords = <String, List<String>>{
    // Potato
    'Potato___Early_blight': [
      'early blight', 'alternaria solani', 'target spot potato',
    ],
    'Potato___Late_blight': [
      'late blight', 'phytophthora infestans', 'water-soaked potato',
    ],
    'Potato___healthy': ['healthy potato', 'normal potato'],

    // Rice
    'Rice___Bacterial_Leaf_Blight': [
      'bacterial blight', 'xanthomonas oryzae', 'kresek', 'blight rice',
    ],
    'Rice___Brown_Spot': [
      'brown spot', 'helminthosporium', 'cochliobolus miyabeanus',
    ],
    'Rice___Healthy_Leaf': ['healthy rice', 'normal rice', 'green rice'],
    'Rice___Leaf_Blast': [
      'blast', 'pyricularia', 'magnaporthe oryzae', 'leaf blast',
    ],
    'Rice___Sheath_Blight': [
      'sheath blight', 'rhizoctonia solani', 'sheath rot',
    ],

    // Tomato
    'Tomato___Bacterial_spot': [
      'bacterial spot', 'xanthomonas campestris tomato',
    ],
    'Tomato___Early_blight': [
      'early blight tomato', 'alternaria tomatophila',
    ],
    'Tomato___Late_blight': [
      'late blight tomato', 'phytophthora tomato',
    ],
    'Tomato___Leaf_Mold': [
      'leaf mold', 'passalora fulva', 'cladosporium fulvum',
    ],
    'Tomato___Spider_mites_Two_spotted_spider_mite': [
      'spider mite', 'tetranychus urticae', 'two-spotted mite',
    ],
    'Tomato___YellowLeaf_Curl_Virus': [
      'yellow leaf curl', 'tylcv', 'begomovirus', 'tomato yellow',
    ],
    'Tomato___mosaic_virus': [
      'mosaic virus', 'tobamovirus', 'tmv', 'tomato mosaic',
    ],
    'Tomato___healthy': ['healthy tomato', 'normal tomato'],
  };

  // ── API Key management ────────────────────────────────────────────────────

  Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyPref) ?? '';
  }

  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPref, key.trim());
  }

  // ── Classification ────────────────────────────────────────────────────────

  /// Calls Google Cloud Vision API and maps labels to an [InferenceResult].
  /// Returns null if the API key is missing, request fails, or crop
  /// cannot be identified — caller should fall back to local TFLite.
  Future<InferenceResult?> classifyFromImage(File imageFile) async {
    final apiKey = await getApiKey();
    if (apiKey.isEmpty) {
      debugPrint('[GoogleVision] No API key — skipping');
      return null;
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http
          .post(
            Uri.parse('$_endpoint?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'requests': [
                {
                  'image': {'content': base64Image},
                  'features': [
                    {'type': 'LABEL_DETECTION', 'maxResults': 30},
                    {'type': 'WEB_DETECTION',   'maxResults': 10},
                  ],
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[GoogleVision] HTTP ${response.statusCode}: ${response.body}');
        return null;
      }

      final json     = jsonDecode(response.body) as Map<String, dynamic>;
      final response0 = (json['responses'] as List?)?.first as Map<String, dynamic>?;
      if (response0 == null) return null;

      // Collect all label descriptions (lower-case)
      final labels = <String>[
        ...((response0['labelAnnotations'] as List?)
                ?.map((l) => ((l as Map)['description'] as String).toLowerCase())
                .toList() ??
            []),
        ...((response0['webDetection']?['webEntities'] as List?)
                ?.map((e) => ((e as Map)['description'] as String? ?? '').toLowerCase())
                .where((s) => s.isNotEmpty)
                .toList() ??
            []),
      ];

      debugPrint('[GoogleVision] labels: $labels');

      if (labels.isEmpty) return null;

      // ── Detect crop ───────────────────────────────────────────────────────
      String? detectedCrop;
      for (final entry in _cropKeywords.entries) {
        if (entry.value.any((kw) => labels.any((l) => l.contains(kw)))) {
          detectedCrop = entry.key;
          break;
        }
      }
      if (detectedCrop == null) {
        debugPrint('[GoogleVision] Could not detect crop from labels');
        return null;
      }

      // ── Detect disease (only among this crop's keys) ──────────────────────
      String? bestDisease;
      for (final entry in _diseaseKeywords.entries) {
        if (!entry.key.toLowerCase().startsWith(detectedCrop)) continue;
        if (entry.value.any((kw) => labels.any((l) => l.contains(kw)))) {
          bestDisease = entry.key;
          break;
        }
      }

      // Default: healthy if no disease keyword matched
      final prefix = _capitalize(detectedCrop);
      bestDisease ??= _healthyLabel(detectedCrop, prefix);

      const cropConf    = 0.80; // Vision API does not give per-crop confidence
      const diseaseConf = 0.72;

      debugPrint('[GoogleVision] crop=$detectedCrop  disease=$bestDisease');

      final krishokModel  = KrishokModel.fromCrop(detectedCrop);
      final topPrediction = PredictionResult(
        label:      bestDisease,
        confidence: diseaseConf,
        isTopResult: true,
      );

      return InferenceResult(
        crop:           krishokModel,
        cropConfidence: cropConf,
        cropProbs: {
          'potato': detectedCrop == 'potato' ? cropConf : 0.0,
          'rice':   detectedCrop == 'rice'   ? cropConf : 0.0,
          'tomato': detectedCrop == 'tomato' ? cropConf : 0.0,
        },
        diseases: [topPrediction],
      );
    } catch (e) {
      debugPrint('[GoogleVision] Error: $e');
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _healthyLabel(String crop, String prefix) {
    return switch (crop) {
      'rice'   => 'Rice___Healthy_Leaf',
      'potato' => 'Potato___healthy',
      'tomato' => 'Tomato___healthy',
      _        => '${prefix}___healthy',
    };
  }
}
