import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// OfflineKbService — SQLite-backed offline knowledge base
/// Populated from assets/knowledge/agri_knowledge.json on first launch.
/// Provides bilingual (bn / en) advisory responses.
class OfflineKbService {
  static Database? _db;
  static bool _seeded = false;

  // ── Database init ────────────────────────────────────────────────────────────

  static Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final dbPath = p.join(await getDatabasesPath(), 'krishok_kb.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE knowledge_entries (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            crop TEXT,
            disease TEXT,
            text_bn TEXT NOT NULL,
            text_en TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  /// Seeds the SQLite DB from the JSON asset (runs once per install).
  static Future<void> ensureSeeded() async {
    if (_seeded) return;
    final db = await _getDb();
    final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM knowledge_entries')) ??
        0;
    if (count == 0) {
      await _seedFromJson(db);
    }
    _seeded = true;
  }

  static Future<void> _seedFromJson(Database db) async {
    try {
      final raw =
          await rootBundle.loadString('assets/knowledge/agri_knowledge.json');
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final batch = db.batch();
      for (final e in list) {
        final id = e['id'] as String? ?? '';
        final type = e['type'] as String? ?? '';
        final crop = e['crop'] as String? ?? '';
        final disease = e['disease'] as String? ?? '';
        final textBn = e['text'] as String? ?? '';
        final textEn = _translateToEn(id, type, textBn, crop, disease);
        batch.insert(
          'knowledge_entries',
          {
            'id': id,
            'type': type,
            'crop': crop,
            'disease': disease,
            'text_bn': textBn,
            'text_en': textEn,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      // silently ignore seed errors — offline mode will still try
    }
  }

  // ── Disease Advisory ─────────────────────────────────────────────────────────

  static Future<String> getDiseaseAdvisory({
    required String diseaseLabel,
    required double confidence,
    required int npkN,
    required int npkP,
    required int npkK,
    required double soilMoisture,
    required double airTemp,
    required double airHumidity,
    String language = 'bn',
  }) async {
    await ensureSeeded();
    final db = await _getDb();
    // Build the disease id from label: "Potato___Early_blight" → "disease_potato_early_blight"
    final parts = diseaseLabel.split('___');
    final id =
        'disease_${parts.map((part) => part.toLowerCase()).join('_')}';

    final rows = await db.query(
      'knowledge_entries',
      where: 'id = ?',
      whereArgs: [id],
    );

    final isBn = language == 'bn';
    final textField = isBn ? 'text_bn' : 'text_en';
    final kbText = rows.isNotEmpty
        ? (rows.first[textField] as String? ?? '')
        : '';

    // Get NPK + irrigation rules
    final rulesRows = await db.query(
      'knowledge_entries',
      where: "id IN ('npk_irrigation_rules', 'dose_calculation_rules')",
    );
    final rulesText = rulesRows
        .map((r) => (r[textField] as String? ?? ''))
        .where((t) => t.isNotEmpty)
        .join('\n\n');

    return _formatDiseaseAdvisory(
      diseaseLabel: diseaseLabel,
      confidence: confidence,
      npkN: npkN,
      npkP: npkP,
      npkK: npkK,
      soilMoisture: soilMoisture,
      airTemp: airTemp,
      airHumidity: airHumidity,
      kbText: kbText,
      rulesText: rulesText,
      language: language,
    );
  }

  // ── Sensor Advisory ──────────────────────────────────────────────────────────

  static Future<String> getSensorAdvisory({
    required int npkN,
    required int npkP,
    required int npkK,
    required double soilMoisture,
    required double airTemp,
    required double airHumidity,
    String language = 'bn',
  }) async {
    await ensureSeeded();
    final db = await _getDb();
    final isBn = language == 'bn';
    final textField = isBn ? 'text_bn' : 'text_en';

    final rulesRows = await db.query(
      'knowledge_entries',
      where: "id IN ('npk_irrigation_rules', 'spray_timing_rules')",
    );
    final rulesText = rulesRows
        .map((r) => (r[textField] as String? ?? ''))
        .where((t) => t.isNotEmpty)
        .join('\n\n');

    return _formatSensorAdvisory(
      npkN: npkN,
      npkP: npkP,
      npkK: npkK,
      soilMoisture: soilMoisture,
      airTemp: airTemp,
      airHumidity: airHumidity,
      rulesText: rulesText,
      language: language,
    );
  }

  // ── Chat Fallback ────────────────────────────────────────────────────────────

  static Future<String> getChatReply({
    required String userMessage,
    String language = 'bn',
  }) async {
    await ensureSeeded();
    final db = await _getDb();
    final isBn = language == 'bn';
    final textField = isBn ? 'text_bn' : 'text_en';

    final query = userMessage.toLowerCase();

    // Search by crop keyword
    final cropKeywords = {
      'potato': ['আলু', 'potato'],
      'tomato': ['টমেটো', 'tomato'],
      'rice': ['ধান', 'rice', 'paddy'],
    };

    String? matchedCrop;
    for (final entry in cropKeywords.entries) {
      if (entry.value.any((kw) => query.contains(kw))) {
        matchedCrop = entry.key;
        break;
      }
    }

    List<Map<String, dynamic>> rows;
    if (matchedCrop != null) {
      rows = await db.query(
        'knowledge_entries',
        where: "type = 'disease' AND crop = ?",
        whereArgs: [matchedCrop],
        limit: 3,
      );
    } else {
      // General search in rules
      rows = await db.query(
        'knowledge_entries',
        where: "type = 'rules'",
        limit: 3,
      );
    }

    if (rows.isEmpty) {
      return isBn
          ? 'অফলাইন মোডে এই প্রশ্নের উত্তর পাওয়া যায়নি। ইন্টারনেট সংযোগ দিলে সম্পূর্ণ AI পরামর্শ পাবেন।'
          : 'This query could not be answered in offline mode. Please connect to the internet for full AI assistance.';
    }

    final combined = rows
        .map((r) => (r[textField] as String? ?? ''))
        .where((t) => t.isNotEmpty)
        .join('\n\n---\n\n');

    if (isBn) {
      return '📴 অফলাইন মোড — স্থানীয় জ্ঞানভান্ডার থেকে:\n\n$combined';
    } else {
      return '📴 Offline Mode — From local knowledge base:\n\n$combined';
    }
  }

  // ── Response Formatters ──────────────────────────────────────────────────────

  static String _formatDiseaseAdvisory({
    required String diseaseLabel,
    required double confidence,
    required int npkN,
    required int npkP,
    required int npkK,
    required double soilMoisture,
    required double airTemp,
    required double airHumidity,
    required String kbText,
    required String rulesText,
    required String language,
  }) {
    final isBn = language == 'bn';
    String s(int v) => v < 25 ? (isBn ? 'কম' : 'Low') : v < 70 ? (isBn ? 'স্বাভাবিক' : 'Normal') : (isBn ? 'বেশি' : 'High');

    // Parse pesticides from kbText
    final pesticides = _extractPesticides(kbText, isBn);
    final firstPesticide = pesticides.isNotEmpty ? pesticides.first : '';

    // NPK advice
    final npkAdvice = _buildNpkAdvice(npkN, npkP, npkK, isBn);

    // Irrigation advice
    final irrigationAdvice = soilMoisture < 35
        ? (isBn ? 'মাটি শুষ্ক (${soilMoisture.toStringAsFixed(0)}%) — সেচ দিন।' : 'Soil is dry (${soilMoisture.toStringAsFixed(0)}%) — irrigate now.')
        : soilMoisture > 85
            ? (isBn ? 'মাটিতে অতিরিক্ত পানি (${soilMoisture.toStringAsFixed(0)}%) — পানি নিষ্কাশন করুন।' : 'Waterlogged soil (${soilMoisture.toStringAsFixed(0)}%) — improve drainage.')
            : (isBn ? 'মাটির আর্দ্রতা স্বাভাবিক (${soilMoisture.toStringAsFixed(0)}%)।' : 'Soil moisture is optimal (${soilMoisture.toStringAsFixed(0)}%).');

    // Extract disease overview (first two lines of kbText)
    final overview = _extractOverview(kbText, diseaseLabel, isBn);

    // Warning based on air humidity
    final warning = airHumidity > 85
        ? (isBn
            ? 'বায়ু আর্দ্রতা ${airHumidity.toStringAsFixed(0)}% — রোগ ছড়ানোর ঝুঁকি বেশি। আক্রান্ত পাতা সরিয়ে ফেলুন।'
            : 'High humidity ${airHumidity.toStringAsFixed(0)}% — high disease spread risk. Remove infected leaves immediately.')
        : (isBn
            ? 'বালাইনাশক ব্যবহারের আগে লেবেলের নির্দেশ পড়ুন এবং সুরক্ষামূলক পোশাক পরুন।'
            : 'Read pesticide label instructions carefully and wear protective gear before spraying.');

    if (isBn) {
      return '📴 অফলাইন মোড — স্থানীয় জ্ঞানভান্ডার থেকে\n'
          '(${(confidence * 100).toStringAsFixed(1)}% নিশ্চিততা)\n\n'
          '1. রোগের বিবরণ: $overview\n\n'
          '2. বালাইনাশক: ${firstPesticide.isNotEmpty ? firstPesticide : "আপনার নিকটবর্তী কৃষি অফিসে পরামর্শ নিন।"}\n\n'
          '3. সার/NPK: $npkAdvice\n'
          '   (N: $npkN — ${s(npkN)}, P: $npkP — ${s(npkP)}, K: $npkK — ${s(npkK)})\n\n'
          '4. সেচ: $irrigationAdvice\n\n'
          '5. সতর্কতা: $warning';
    } else {
      return '📴 Offline Mode — Local knowledge base\n'
          '(Confidence: ${(confidence * 100).toStringAsFixed(1)}%)\n\n'
          '1. Disease overview: $overview\n\n'
          '2. Pesticide: ${firstPesticide.isNotEmpty ? firstPesticide : "Consult your local agricultural office for pesticide recommendations."}\n\n'
          '3. Fertilizer/NPK: $npkAdvice\n'
          '   (N: $npkN — ${s(npkN)}, P: $npkP — ${s(npkP)}, K: $npkK — ${s(npkK)})\n\n'
          '4. Irrigation: $irrigationAdvice\n\n'
          '5. Warning: $warning';
    }
  }

  static String _formatSensorAdvisory({
    required int npkN,
    required int npkP,
    required int npkK,
    required double soilMoisture,
    required double airTemp,
    required double airHumidity,
    required String rulesText,
    required String language,
  }) {
    final isBn = language == 'bn';

    final tips = <String>[];

    // Tip 1: NPK
    final npkAdvice = _buildNpkAdvice(npkN, npkP, npkK, isBn);
    tips.add('1. ${isBn ? "সার/NPK" : "Fertilizer/NPK"}: $npkAdvice');

    // Tip 2: Irrigation
    if (soilMoisture < 35) {
      tips.add('2. ${isBn ? "সেচ" : "Irrigation"}: ${isBn ? "মাটি শুষ্ক (${soilMoisture.toStringAsFixed(0)}%) — সেচ দিন।" : "Soil is dry (${soilMoisture.toStringAsFixed(0)}%) — irrigate your field."}');
    } else if (soilMoisture > 85) {
      tips.add('2. ${isBn ? "জলাবদ্ধতা" : "Waterlogging"}: ${isBn ? "অতিরিক্ত পানি (${soilMoisture.toStringAsFixed(0)}%) — নিষ্কাশনের ব্যবস্থা করুন।" : "Waterlogged (${soilMoisture.toStringAsFixed(0)}%) — improve drainage immediately."}');
    } else {
      tips.add('2. ${isBn ? "সেচ" : "Irrigation"}: ${isBn ? "মাটির আর্দ্রতা স্বাভাবিক (${soilMoisture.toStringAsFixed(0)}%) — সেচের প্রয়োজন নেই।" : "Soil moisture optimal (${soilMoisture.toStringAsFixed(0)}%) — no irrigation needed."}');
    }

    // Tip 3: Disease risk from humidity
    if (airHumidity > 85) {
      tips.add('3. ${isBn ? "রোগের ঝুঁকি" : "Disease risk"}: ${isBn ? "বায়ু আর্দ্রতা ${airHumidity.toStringAsFixed(0)}% — ছত্রাক রোগের ঝুঁকি বেশি। ক্ষেত পরিদর্শন করুন।" : "Air humidity ${airHumidity.toStringAsFixed(0)}% — high fungal disease risk. Inspect crops."}');
    } else if (airHumidity < 40) {
      tips.add('3. ${isBn ? "পোকার ঝুঁকি" : "Pest risk"}: ${isBn ? "বায়ু আর্দ্রতা কম (${airHumidity.toStringAsFixed(0)}%) — মাকড় পোকার ঝুঁকি বেশি।" : "Low humidity (${airHumidity.toStringAsFixed(0)}%) — higher spider mite risk."}');
    } else {
      tips.add('3. ${isBn ? "আবহাওয়া" : "Weather"}: ${isBn ? "তাপমাত্রা ${airTemp.toStringAsFixed(0)}°C, আর্দ্রতা ${airHumidity.toStringAsFixed(0)}% — স্বাভাবিক।" : "Temperature ${airTemp.toStringAsFixed(0)}°C, humidity ${airHumidity.toStringAsFixed(0)}% — normal conditions."}');
    }

    // Tip 4: Spray timing
    final hour = DateTime.now().hour;
    final goodSprayTime = (hour >= 6 && hour <= 9) || (hour >= 16 && hour <= 18);
    tips.add('4. ${isBn ? "স্প্রে সময়" : "Spray timing"}: ${goodSprayTime ? (isBn ? "এখন স্প্রে করার উপযুক্ত সময়।" : "Good time to spray now.") : (isBn ? "স্প্রে করার উপযুক্ত সময়: সকাল ৬-৯টা বা বিকাল ৪-৬টা।" : "Best spray time: 6-9 AM or 4-6 PM.")}');

    final header = isBn
        ? '📴 অফলাইন মোড — মাঠ ব্যবস্থাপনা পরামর্শ:\n'
        : '📴 Offline Mode — Field management tips:\n';

    return header + tips.join('\n\n');
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static String _extractOverview(String kbText, String diseaseLabel, bool isBn) {
    if (kbText.isEmpty) {
      return isBn
          ? '$diseaseLabel — স্থানীয় তথ্য পাওয়া যায়নি। নিকটবর্তী কৃষি অফিসে যোগাযোগ করুন।'
          : '$diseaseLabel — No local data found. Contact your nearest agricultural office.';
    }
    // Extract disease name and symptoms lines
    final lines = kbText.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final nameLine = lines.firstWhere(
        (l) => l.startsWith('রোগের নাম:') || l.startsWith('Disease name:'),
        orElse: () => lines.isNotEmpty ? lines[0] : '');
    final symptomLine = lines.firstWhere(
        (l) => l.startsWith('লক্ষণ:') || l.startsWith('Symptoms:'),
        orElse: () => lines.length > 1 ? lines[1] : '');
    return '$nameLine. $symptomLine'.trim();
  }

  static List<String> _extractPesticides(String kbText, bool isBn) {
    if (kbText.isEmpty) return [];
    final pesticides = <String>[];
    for (final line in kbText.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('- ') &&
          (trimmed.contains('গ্রাম/লিটার') ||
              trimmed.contains('মিলি/লিটার') ||
              trimmed.contains('g/L') ||
              trimmed.contains('ml/L'))) {
        pesticides.add(trimmed.substring(2));
      }
    }
    return pesticides;
  }

  static String _buildNpkAdvice(int n, int p, int k, bool isBn) {
    final advices = <String>[];
    if (n < 25) {
      advices.add(isBn
          ? 'নাইট্রোজেন (N) কম — ইউরিয়া সার দিন (প্রতি শতকে ২৫০ গ্রাম)।'
          : 'Low Nitrogen (N) — apply Urea (250g per shotok).');
    } else if (n >= 70) {
      advices.add(isBn
          ? 'নাইট্রোজেন (N) অতিরিক্ত — ইউরিয়া বা নাইট্রোজেন সার প্রয়োগ স্থগিত রাখুন।'
          : 'High Nitrogen (N) — withhold nitrogenous fertilizers.');
    }
    if (p < 25) {
      advices.add(isBn
          ? 'ফসফরাস (P) কম — টিএসপি সার দিন (প্রতি শতকে ১৫০ গ্রাম)।'
          : 'Low Phosphorus (P) — apply TSP (150g per shotok).');
    } else if (p >= 70) {
      advices.add(isBn
          ? 'ফসফরাস (P) অতিরিক্ত — টিএসপি সার প্রয়োগ স্থগিত রাখুন।'
          : 'High Phosphorus (P) — withhold TSP.');
    }
    if (k < 25) {
      advices.add(isBn
          ? 'পটাশিয়াম (K) কম — এমওপি সার দিন (প্রতি শতকে ২০০ গ্রাম)।'
          : 'Low Potassium (K) — apply MOP (200g per shotok).');
    } else if (k >= 70) {
      advices.add(isBn
          ? 'পটাশিয়াম (K) অতিরিক্ত — এমওপি সার প্রয়োগ স্থগিত রাখুন।'
          : 'High Potassium (K) — withhold MOP.');
    }
    if (advices.isEmpty) {
      return isBn
          ? 'NPK মাত্রা স্বাভাবিক — অতিরিক্ত সার দেওয়ার প্রয়োজন নেই।'
          : 'NPK levels are normal — no additional fertilizer needed.';
    }
    return advices.join(' ');
  }

  // ── English translation ───────────────────────────────────────────────────────
  // Generates structured English text from the knowledge entry metadata.
  // For disease entries we build a template; for rules we use pre-written English.

  static String _translateToEn(
      String id, String type, String textBn, String crop, String disease) {
    switch (type) {
      case 'disease':
        return _buildEnDiseaseText(id, crop, disease, textBn);
      case 'rules':
        return _buildEnRulesText(id, textBn);
      case 'pesticide':
        return _buildEnPesticideText(id, textBn);
      default:
        return textBn;
    }
  }

  static String _buildEnDiseaseText(
      String id, String crop, String disease, String textBn) {
    // Extract key fields from Bengali text using line prefixes
    String get(String prefix) {
      for (final line in textBn.split('\n')) {
        if (line.startsWith(prefix)) {
          return line.substring(prefix.length).trim();
        }
      }
      return '';
    }

    final diseaseName = get('রোগের নাম:');
    final pathogen = get('রোগের কারণ (pathogen):');
    final symptoms = get('লক্ষণ:');
    final spread = get('ছড়ানোর মাধ্যম:');
    final tempRange = get('রোগ বাড়ার অনুকূল তাপমাত্রা:');
    final humRange = get('রোগ বাড়ার অনুকূল বায়ু আর্দ্রতা:');
    final soilRange = get('রোগ বাড়ার অনুকূল মাটির আর্দ্রতা:');
    final note = get('বিশেষ দ্রষ্টব্য:');

    // Extract pesticides
    final lines = textBn.split('\n');
    final chemical = <String>[];
    final bio = <String>[];
    bool inChem = false, inBio = false;
    for (final line in lines) {
      if (line.contains('রাসায়নিক বালাইনাশক:')) {
        inChem = true;
        inBio = false;
      } else if (line.contains('জৈব বালাইনাশক:')) {
        inChem = false;
        inBio = true;
      } else if (line.trim().startsWith('- ')) {
        if (inChem) chemical.add('  ${line.trim()}');
        if (inBio) bio.add('  ${line.trim()}');
      }
    }

    final sb = StringBuffer();
    sb.writeln('Disease name: $diseaseName');
    sb.writeln('Crop: $crop');
    if (pathogen.isNotEmpty) sb.writeln('Pathogen: $pathogen');
    if (symptoms.isNotEmpty) sb.writeln('Symptoms: $symptoms');
    if (spread.isNotEmpty) sb.writeln('Spread: $spread');
    if (tempRange.isNotEmpty) sb.writeln('Favorable temperature: $tempRange');
    if (humRange.isNotEmpty) sb.writeln('Favorable air humidity: $humRange');
    if (soilRange.isNotEmpty) sb.writeln('Favorable soil moisture: $soilRange');
    if (note.isNotEmpty) sb.writeln('Note: $note');
    if (chemical.isNotEmpty) {
      sb.writeln('Chemical pesticides:');
      sb.writeAll(chemical, '\n');
    }
    if (bio.isNotEmpty) {
      sb.writeln('\nBio pesticides:');
      sb.writeAll(bio, '\n');
    }
    return sb.toString().trim();
  }

  static String _buildEnPesticideText(String id, String textBn) {
    String get(String prefix) {
      for (final line in textBn.split('\n')) {
        if (line.startsWith(prefix)) return line.substring(prefix.length).trim();
      }
      return '';
    }

    final name = get('বালাইনাশকের নাম:');
    final trade = get('ট্রেড নাম:');
    final type = get('ধরন:');
    final action = get('কাজের ধরন:');
    final dose = get('স্বাভাবিক মাত্রা:');
    final interval = get('স্প্রের ব্যবধান:');
    final time = get('স্প্রের সময়:');
    final rainFree = get('বৃষ্টি-মুক্ত সময়:');
    final lastSpray = get('ফসল তোলার আগে শেষ স্প্রে:');
    final cautions = textBn
        .split('\n')
        .where((l) => l.startsWith('সতর্কতা:'))
        .map((l) => l.substring('সতর্কতা:'.length).trim())
        .toList();
    final note = get('বিশেষ দ্রষ্টব্য:');
    final applicable = get('ব্যবহারযোগ্য রোগ:');

    final sb = StringBuffer();
    sb.writeln('Pesticide: $name');
    if (trade.isNotEmpty) sb.writeln('Trade name: $trade');
    if (type.isNotEmpty) sb.writeln('Type: $type');
    if (action.isNotEmpty) sb.writeln('Mode of action: $action');
    if (dose.isNotEmpty) sb.writeln('Normal dose: $dose');
    if (interval.isNotEmpty) sb.writeln('Spray interval: $interval');
    if (time.isNotEmpty) sb.writeln('Spray time: $time');
    if (rainFree.isNotEmpty) sb.writeln('Rain-free period: $rainFree');
    if (lastSpray.isNotEmpty) sb.writeln('Last spray before harvest: $lastSpray');
    for (final c in cautions) {
      sb.writeln('Caution: $c');
    }
    if (note.isNotEmpty) sb.writeln('Note: $note');
    if (applicable.isNotEmpty) sb.writeln('Applicable for: $applicable');
    return sb.toString().trim();
  }

  static String _buildEnRulesText(String id, String textBn) {
    switch (id) {
      case 'npk_irrigation_rules':
        return '''NPK and Irrigation Advice:
Nitrogen (N): Deficient <10, Normal 15-30, Excess >30
Phosphorus (P): Deficient <8, Normal 12-25
Potassium (K): Deficient <12, Normal 15-25
N deficiency: Apply Urea — 250g per shotok, in 2 splits
N deficiency: Apply DAP — 150g per shotok
P deficiency: Apply TSP — 150g per shotok
K deficiency: Apply MOP — 200g per shotok
K deficiency: Apply Compost — 20kg per shotok

Soil moisture:
  - Less than 35%: Soil is dry — irrigate
  - 50%-70%: Ideal condition
  - More than 85%: Waterlogged — drain water

Air humidity and temperature:
  - Air humidity above 85%: Higher risk of fungal diseases
  - Air humidity below 40%: Higher risk of spider mites
  - Temperature above 32°C: Do not spray during noon hours''';

      case 'spray_timing_rules':
        return '''Pesticide Spray Rules and Timing:
Rule R01: Do NOT spray today — high rain probability, pesticide will wash off (condition: rain_prob > 40)
Rule R02: High wind — do NOT spray, drift may cause damage (condition: wind_speed > 15)
Rule R03: Do NOT spray in intense noon heat — leaves may burn (condition: temp > 35, time 10:00-15:00)
Rule R04: Air too dry — pesticide will evaporate quickly, ineffective (condition: humidity < 30)
Rule R05: Good time to spray — morning conditions favorable (condition: 06:00-09:00, rain_prob < 30, wind < 10, temp < 32)
Rule R06: Can spray in evening — conditions favorable (condition: 16:00-18:00, rain_prob < 30, wind < 10)

General rules:
  - Best spray time: 6-9 AM and 4-6 PM
  - Do not spray if rain probability > 40%
  - Do not spray if wind speed > 15 km/h
  - Noon spraying (10 AM - 3 PM) in intense sun may burn leaves
  - Bio-pesticides work best when applied in the evening
  - Do not mix chemical and bio-pesticides — keep at least 7 days gap''';

      case 'dose_calculation_rules':
        return '''Pesticide Dose Calculation by Disease Severity:
Disease severity (by % leaf area affected):
  - Mild (0-20%): Use 75% of normal dose
  - Moderate (20-50%): Use 100% of normal dose
  - Severe (50-80%): Use 125% of normal dose
  - Critical (80%+): Use 150% of normal dose
  - Maximum limit: Do not exceed 150% of label dose

Additional dose adjustments:
  - Air humidity above 85%: Increase dose by 110%
  - Potassium (K) below 12: Increase dose by 110%
  - Soil moisture above 75% (contact pesticide): Slightly increase dose''';

      default:
        return textBn;
    }
  }
}
