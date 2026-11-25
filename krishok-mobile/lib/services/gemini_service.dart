import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connectivity_service.dart';
import 'ml_service.dart';
import 'offline_kb_service.dart';

class GeminiService {
  static const _apiKeyPref = 'gemini_api_key';

  // ── Primary Gemini Model ──────────────────────────────────────────────────
  static const _geminiModel = 'gemini-1.5-flash';

  List<Map<String, dynamic>>? _kb;

  // ── API Key ──────────────────────────────────────────────────────────────────

  Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_apiKeyPref) ?? '';
    if (saved.isNotEmpty) return saved;
    // Runtime configuration or compile-time variable (if configured)
    const envKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
    if (envKey.isNotEmpty) return envKey;
    return '';
  }

  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPref, key.trim());
  }

  // ── Knowledge Base ───────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>?> _loadKb() async {
    if (_kb != null) return _kb;
    try {
      final raw =
          await rootBundle.loadString('assets/knowledge/agri_knowledge.json');
      _kb = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return _kb;
    } catch (_) {
      return null;
    }
  }

  static String labelToKbId(String label) {
    final parts = label.split('___');
    return 'disease_${parts.map((p) => p.toLowerCase()).join('_')}';
  }

  String _diseaseText(String label, List<Map<String, dynamic>> kb) {
    final id = labelToKbId(label);
    final entry = kb.firstWhere(
      (e) => e['id'] == id,
      orElse: () => {},
    );
    return (entry['text'] as String?) ?? '';
  }

  String _rulesText(List<Map<String, dynamic>> kb) {
    final ids = ['npk_irrigation_rules', 'spray_timing_rules'];
    return ids
        .map((id) {
          final e = kb.firstWhere((e) => e['id'] == id, orElse: () => {});
          return (e['text'] as String?) ?? '';
        })
        .where((t) => t.isNotEmpty)
        .join('\n\n');
  }

  String _langInstruction(String language) =>
      language == 'en' ? 'Answer in English.' : 'উত্তর বাংলায় দাও।';

  // ── Gemini Vision — Disease Classification ────────────────────────────────────

  // ── Classification Fallback Chain ─────────────────────────────────────────
  // Tier 1: gemini-3-flash-preview  (primary — fastest)
  // Tier 2: gemini-1.5-pro          (fallback — higher accuracy)
  // Tier 3: gemini-1.5-flash        (last cloud resort — lightweight)
  // Tier 4: local TFLite            — handled by the caller (ai_scan_screen.dart)

  /// Entry point for image-based crop + disease classification.
  /// Tries Gemini Vision first; if it fails, caller uses local TFLite.
  Future<InferenceResult?> classifyDiseaseFromImage(File imageFile) async {
    final result = await _geminiVisionClassify(imageFile, _geminiModel);
    if (result != null) return result;
    debugPrint('[ClassifyChain] Gemini failed → TFLite fallback (caller)');
    return null;
  }

  /// Gemini Vision — structured JSON classification.
  /// [model] selects which Gemini model to use for this attempt.
  Future<InferenceResult?> _geminiVisionClassify(File imageFile, String model) async {
    final apiKey = await getApiKey();
    if (apiKey.isEmpty) return null;

    final bytes = await imageFile.readAsBytes();

    const validCrops = ['potato', 'tomato', 'rice'];
    const knownDiseases = {
      'potato': [
        'Potato___Early_blight',
        'Potato___Late_blight',
        'Potato___healthy',
      ],
      'tomato': [
        'Tomato___Bacterial_spot',
        'Tomato___Early_blight',
        'Tomato___Late_blight',
        'Tomato___Leaf_Mold',
        'Tomato___Spider_mites_Two_spotted_spider_mite',
        'Tomato___YellowLeaf_Curl_Virus',
        'Tomato___healthy',
        'Tomato___mosaic_virus',
      ],
      'rice': [
        'Rice___Bacterial_Leaf_Blight',
        'Rice___Brown_Spot',
        'Rice___Healthy_Leaf',
        'Rice___Leaf_Blast',
        'Rice___Sheath_Blight',
      ],
    };

    final prompt = '''
You are a crop disease classification system. Analyze this plant leaf image.

Your task:
1. Identify the crop — must be exactly one of: potato, tomato, rice
2. Identify the disease from the matching list below

Disease labels for potato:
${knownDiseases['potato']!.join(', ')}

Disease labels for tomato:
${knownDiseases['tomato']!.join(', ')}

Disease labels for rice:
${knownDiseases['rice']!.join(', ')}

Respond ONLY with a valid JSON object, no markdown, no explanation:
{"crop": "<crop>", "disease": "<exact_label_from_list>", "confidence": <0.0-1.0>}

If the image is not a recognisable crop leaf, return:
{"error": "not_a_crop_leaf"}
''';

    try {
      final geminiModel = GenerativeModel(
        model: model,
        apiKey: apiKey,
      );
      final response = await geminiModel.generateContent([
        Content.multi([
          DataPart('image/jpeg', bytes),
          TextPart(prompt),
        ]),
      ]);

      final text = (response.text ?? '').trim();
      debugPrint('[GeminiVision] raw response: $text');

      final cleaned = text
          .replaceAll(RegExp(r'^```[a-z]*\n?', multiLine: true), '')
          .replaceAll(RegExp(r'```$', multiLine: true), '')
          .trim();

      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      if (json.containsKey('error')) return null;

      final crop = (json['crop'] as String?)?.toLowerCase().trim() ?? '';
      final diseaseLabel = (json['disease'] as String?)?.trim() ?? '';
      final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.85;

      if (!validCrops.contains(crop)) return null;
      final cropDiseases = knownDiseases[crop]!;
      if (!cropDiseases.contains(diseaseLabel)) return null;

      final krishokModel = KrishokModel.fromCrop(crop);
      final topPrediction = PredictionResult(
        label: diseaseLabel,
        confidence: confidence,
        isTopResult: true,
      );

      return InferenceResult(
        crop: krishokModel,
        cropConfidence: confidence,
        cropProbs: {
          for (final c in validCrops) c: c == crop ? confidence : 0.0,
        },
        diseases: [topPrediction],
      );
    } catch (e) {
      debugPrint('[GeminiVision][$model] error: $e');
      return null;
    }
  }

  // ── Disease Insight ──────────────────────────────────────────────────────────

  Future<String> getRecommendation({
    required String diseaseLabel,
    required double confidence,
    required int npkN,
    required int npkP,
    required int npkK,
    required double soilMoisture,
    required double airTemp,
    required double airHumidity,
    String weatherSummary = '',
    String language = 'bn',
  }) async {
    final apiKey = await getApiKey();
    if (apiKey.isEmpty) {
      return language == 'en'
          ? '⚠️ API Key not set. Go to Settings and enter your Gemini API Key.'
          : '⚠️ API Key সেট করা নেই। Settings এ গিয়ে Gemini API Key দিন।';
    }

    // Check connectivity first — go offline immediately if no internet
    final online = await ConnectivityService.isOnline();
    if (!online) {
      return OfflineKbService.getDiseaseAdvisory(
        diseaseLabel: diseaseLabel,
        confidence: confidence,
        npkN: npkN,
        npkP: npkP,
        npkK: npkK,
        soilMoisture: soilMoisture,
        airTemp: airTemp,
        airHumidity: airHumidity,
        language: language,
      );
    }

    final kb = await _loadKb();
    final diseaseCtx = kb != null ? _diseaseText(diseaseLabel, kb) : '';
    final rulesCtx = kb != null ? _rulesText(kb) : '';

    String npkLabel(int v) => v < 25 ? 'Low' : v < 70 ? 'Normal' : 'High';
    final hasSensor = airTemp > 0 || airHumidity > 0 || soilMoisture > 0;

    final sensorBlock = hasSensor
        ? '''Sensor data:
N: $npkN mg/kg (${npkLabel(npkN)}), P: $npkP mg/kg (${npkLabel(npkP)}), K: $npkK mg/kg (${npkLabel(npkK)})
Soil moisture: ${soilMoisture.toStringAsFixed(1)}%, Temperature: ${airTemp.toStringAsFixed(1)}°C, Air humidity: ${airHumidity.toStringAsFixed(1)}%${weatherSummary.isNotEmpty ? '\nWeather: $weatherSummary' : ''}'''
        : 'No sensor data available.';

    final prompt = '''Disease: $diseaseLabel (Confidence: ${(confidence * 100).toStringAsFixed(1)}%)
$sensorBlock

${diseaseCtx.isNotEmpty ? '--- Disease Knowledge Base ---\n$diseaseCtx' : ''}
${rulesCtx.isNotEmpty ? '--- Agronomic Rules ---\n$rulesCtx' : ''}

${_langInstruction(language)}
Based on the above, give a concise plain-text advisory with exactly these five sections:
1. Disease overview: two sentences describing the disease and its spread.
2. Pesticide: specific product name and correct dosage.
3. Fertilizer/NPK: recommendation based on current nutrient levels.
4. Irrigation: advice based on current soil moisture reading.
5. Warning: one important precaution the farmer must follow.

Write in plain text only. No emojis, icons, bullet symbols, or markdown formatting.
''';

    return _generate(
      apiKey,
      prompt,
      offlineFallback: () => OfflineKbService.getDiseaseAdvisory(
        diseaseLabel: diseaseLabel,
        confidence: confidence,
        npkN: npkN,
        npkP: npkP,
        npkK: npkK,
        soilMoisture: soilMoisture,
        airTemp: airTemp,
        airHumidity: airHumidity,
        language: language,
      ),
    );
  }

  // ── Dashboard Sensor Suggestion ──────────────────────────────────────────────

  Future<String> getSensorRecommendation({
    required int npkN,
    required int npkP,
    required int npkK,
    required double soilMoisture,
    required double airTemp,
    required double airHumidity,
    String weatherSummary = '',
    String language = 'bn',
  }) async {
    final apiKey = await getApiKey();
    if (apiKey.isEmpty) {
      return language == 'en' ? '⚠️ API Key not set.' : '⚠️ API Key সেট করা নেই।';
    }

    // Offline check
    final online = await ConnectivityService.isOnline();
    if (!online) {
      return OfflineKbService.getSensorAdvisory(
        npkN: npkN,
        npkP: npkP,
        npkK: npkK,
        soilMoisture: soilMoisture,
        airTemp: airTemp,
        airHumidity: airHumidity,
        language: language,
      );
    }

    final kb = await _loadKb();
    final rulesCtx = kb != null ? _rulesText(kb) : '';
    String s(int v) => v < 25 ? 'Low' : v < 70 ? 'Normal' : 'High';

    final prompt = '''Field data: N=$npkN (${s(npkN)}), P=$npkP (${s(npkP)}), K=$npkK (${s(npkK)})
Soil moisture: ${soilMoisture.toStringAsFixed(0)}%, Temperature: ${airTemp.toStringAsFixed(0)}°C, Air humidity: ${airHumidity.toStringAsFixed(0)}%
${weatherSummary.isNotEmpty ? 'Weather: $weatherSummary' : ''}
${rulesCtx.isNotEmpty ? '\n--- Agronomic Rules ---\n$rulesCtx' : ''}

${_langInstruction(language)}
Give 3 to 4 concise field management tips based on this data. Use a numbered list. No emojis, icons, or symbols.
''';

    return _generate(
      apiKey,
      prompt,
      offlineFallback: () => OfflineKbService.getSensorAdvisory(
        npkN: npkN,
        npkP: npkP,
        npkK: npkK,
        soilMoisture: soilMoisture,
        airTemp: airTemp,
        airHumidity: airHumidity,
        language: language,
      ),
    );
  }

  // ── Chat ─────────────────────────────────────────────────────────────────────

  Future<String> chat({
    required String userMessage,
    String context = '',
    String language = 'bn',
  }) async {
    final apiKey = await getApiKey();
    if (apiKey.isEmpty) {
      return language == 'en'
          ? '⚠️ API Key not set. Go to Settings and enter your Gemini API Key.'
          : '⚠️ API Key নেই। Settings এ গিয়ে Gemini API Key দিন।';
    }

    // Offline check
    final online = await ConnectivityService.isOnline();
    if (!online) {
      return OfflineKbService.getChatReply(
        userMessage: userMessage,
        language: language,
      );
    }

    final kb = await _loadKb();
    final kbIndex = kb != null
        ? kb
            .map((e) => e['text'] as String? ?? '')
            .where((t) => t.isNotEmpty)
            .join('\n---\n')
        : '';

    final prompt = '''You are Krishok AI, a crop disease and soil health assistant for Bangladeshi farmers.
Be direct, specific, and practical. Keep answers concise, complete, and grammatically sound. No greetings or filler text. No emojis, icons, or symbols.
When recommending disease treatment or answering treatment-related questions (including spray intervals, dosages, or tank volume mixing), always provide the complete specification: product trade name and active ingredient, standard dosage with units (e.g. g/L or ml/L), application interval, and precaution.
If the farmer asks about tank capacity (e.g. knapsack sprayer), calculate both the per-liter rate and the total product needed for that tank volume.
When asked for agronomic explanations (e.g. why to stop nitrogen fertilizer or why not to spray before rain), state the clear scientific rationale referencing the plant pathology or soil rule from the Knowledge Base.
When advising on soil or irrigation, follow the exact NPK and soil moisture rules provided.
Base your advice strictly on the provided field data and knowledge base.
${_langInstruction(language)}

${context.isNotEmpty ? '--- Field Context ---\n$context' : ''}
${kbIndex.isNotEmpty ? '--- Knowledge Base ---\n$kbIndex' : ''}

User: $userMessage
Answer:''';

    return _generate(
      apiKey,
      prompt,
      offlineFallback: () => OfflineKbService.getChatReply(
        userMessage: userMessage,
        language: language,
      ),
    );
  }

  // ── Shared Generate ──────────────────────────────────────────────────────────

  Future<String> _generate(
    String apiKey,
    String prompt, {
    Future<String> Function()? offlineFallback,
  }) async {
    try {
      final model = GenerativeModel(
        model: _geminiModel,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          maxOutputTokens: 1024,
          temperature: 0.2,
        ),
      );
      final response = await model
          .generateContent([Content.text(prompt)]);
      final text = response.text;
      if (text != null && text.isNotEmpty) return text;
    } on InvalidApiKey {
      return '❌ Invalid API Key. Please update it in Settings.';
    } catch (e) {
      debugPrint('[GeminiGenerate] failed: $e');
      if (ConnectivityService.isNetworkError(e)) {
        if (offlineFallback != null) return offlineFallback();
        return '❌ Gemini connection failed: $e';
      }
    }
    if (offlineFallback != null) return offlineFallback();
    return 'No response received.';
  }
}
