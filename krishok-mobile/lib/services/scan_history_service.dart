import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ════════════════════════════════════════════════════════════════════════════════
// SCAN RECORD MODEL
// ════════════════════════════════════════════════════════════════════════════════

class ScanRecord {
  final String id;
  final String cropModel;
  final String cropEmoji;
  final String diseaseName;
  final String diseaseLabel; // raw ML label, e.g. "Potato___Early_blight"
  final double confidence;
  final String? imagePath;
  final DateTime timestamp;
  final bool isHealthy;
  String? aiInsight; // stored after Gemini analysis

  ScanRecord({
    required this.id,
    required this.cropModel,
    required this.cropEmoji,
    required this.diseaseName,
    required this.diseaseLabel,
    required this.confidence,
    this.imagePath,
    required this.timestamp,
    required this.isHealthy,
    this.aiInsight,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'cropModel': cropModel,
    'cropEmoji': cropEmoji,
    'diseaseName': diseaseName,
    'diseaseLabel': diseaseLabel,
    'confidence': confidence,
    'imagePath': imagePath,
    'timestamp': timestamp.toIso8601String(),
    'isHealthy': isHealthy,
    'aiInsight': aiInsight,
  };

  factory ScanRecord.fromJson(Map<String, dynamic> json) {
    return ScanRecord(
      id: json['id'] as String,
      cropModel: json['cropModel'] as String,
      cropEmoji: json['cropEmoji'] as String? ?? '🌱',
      diseaseName: json['diseaseName'] as String,
      diseaseLabel: json['diseaseLabel'] as String? ?? '',
      confidence: (json['confidence'] as num).toDouble(),
      imagePath: json['imagePath'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isHealthy: json['isHealthy'] as bool? ?? false,
      aiInsight: json['aiInsight'] as String?,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// WEEKLY STATS
// ════════════════════════════════════════════════════════════════════════════════

class WeeklyStats {
  final int totalScans;
  final int diseasesFound;
  final int healthyCount;
  final double riskPercent;     // 0–100
  final String riskLevel;       // Low / Moderate / High / Critical
  final List<int> dailyCounts;  // 7 entries, index 0 = 6 days ago, index 6 = today

  const WeeklyStats({
    required this.totalScans,
    required this.diseasesFound,
    required this.healthyCount,
    required this.riskPercent,
    required this.riskLevel,
    required this.dailyCounts,
  });

  static const empty = WeeklyStats(
    totalScans: 0,
    diseasesFound: 0,
    healthyCount: 0,
    riskPercent: 0,
    riskLevel: 'Low',
    dailyCounts: [0, 0, 0, 0, 0, 0, 0],
  );
}

// ════════════════════════════════════════════════════════════════════════════════
// SERVICE
// ════════════════════════════════════════════════════════════════════════════════

class ScanHistoryService {
  static const _key = 'krishok_scan_history';
  static final _uuid = Uuid();

  /// Generate a unique ID for a new scan.
  static String newId() => _uuid.v4();

  /// Persist a scan record.
  Future<void> addScan(ScanRecord record) async {
    final scans = await getScans();
    scans.insert(0, record);
    await _save(scans.take(5).toList()); // keep last 5 only
  }

  /// Retrieve all scan records, newest first.
  Future<List<ScanRecord>> getScans() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ScanRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Delete a scan by ID.
  Future<void> deleteScan(String id) async {
    final scans = await getScans();
    scans.removeWhere((s) => s.id == id);
    await _save(scans);
  }

  /// Update the stored AI insight for a scan.
  Future<void> updateScanInsight(String id, String insight) async {
    final scans = await getScans();
    final idx = scans.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    scans[idx].aiInsight = insight;
    await _save(scans);
  }

  /// Clear all history.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Compute weekly statistics from scan history.
  Future<WeeklyStats> getWeeklyStats() async {
    final scans = await getScans();
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));

    final weekScans = scans.where((s) => s.timestamp.isAfter(weekStart)).toList();

    final totalScans = weekScans.length;
    final diseasesFound = weekScans.where((s) => !s.isHealthy).length;
    final healthyCount = weekScans.where((s) => s.isHealthy).length;

    // Risk = percentage of diseased scans in the week
    final riskPercent = totalScans > 0
        ? (diseasesFound / totalScans * 100).roundToDouble()
        : 0.0;

    final riskLevel = _classifyRisk(riskPercent);

    // Daily counts for chart (7 days, index 0 = 6 days ago)
    final dailyCounts = List.filled(7, 0);
    for (final scan in weekScans) {
      final dayIndex = scan.timestamp
          .difference(weekStart)
          .inDays
          .clamp(0, 6);
      dailyCounts[dayIndex]++;
    }

    return WeeklyStats(
      totalScans: totalScans,
      diseasesFound: diseasesFound,
      healthyCount: healthyCount,
      riskPercent: riskPercent,
      riskLevel: riskLevel,
      dailyCounts: dailyCounts,
    );
  }

  String _classifyRisk(double percent) {
    if (percent < 25) return 'Low';
    if (percent < 50) return 'Moderate';
    if (percent < 75) return 'High';
    return 'Critical';
  }

  Future<void> _save(List<ScanRecord> scans) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(scans.map((s) => s.toJson()).toList());
    await prefs.setString(_key, json);
  }
}
