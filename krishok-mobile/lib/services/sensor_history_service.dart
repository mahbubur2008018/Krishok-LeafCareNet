import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sensor_data.dart';

class DailySensorSnapshot {
  final DateTime date;
  final int n, p, k;
  final double temp, hum, moisture;

  const DailySensorSnapshot({
    required this.date,
    required this.n,
    required this.p,
    required this.k,
    required this.temp,
    required this.hum,
    required this.moisture,
  });

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'n': n, 'p': p, 'k': k,
    'temp': temp, 'hum': hum, 'moisture': moisture,
  };

  factory DailySensorSnapshot.fromJson(Map<String, dynamic> json) {
    return DailySensorSnapshot(
      date: DateTime.parse(json['date'] as String),
      n: (json['n'] as num?)?.toInt() ?? 0,
      p: (json['p'] as num?)?.toInt() ?? 0,
      k: (json['k'] as num?)?.toInt() ?? 0,
      temp: (json['temp'] as num?)?.toDouble() ?? 0.0,
      hum: (json['hum'] as num?)?.toDouble() ?? 0.0,
      moisture: (json['moisture'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SensorHistoryService {
  static const _key = 'sensor_daily_history';
  static const _maxDays = 5;

  Future<List<DailySensorSnapshot>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => DailySensorSnapshot.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSnapshot(SensorData data) async {
    final history = await getHistory();
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final snapshot = DailySensorSnapshot(
      date: todayDate,
      n: data.npk.n,
      p: data.npk.p,
      k: data.npk.k,
      temp: data.sht20.temp,
      hum: data.sht20.hum,
      moisture: data.soilMoisture.moisture,
    );

    // Replace today's entry with latest reading
    history.removeWhere((s) {
      final d = DateTime(s.date.year, s.date.month, s.date.day);
      return d.isAtSameMomentAs(todayDate);
    });
    history.insert(0, snapshot);

    // Keep only the most recent _maxDays days
    final trimmed = history.take(_maxDays).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(trimmed.map((s) => s.toJson()).toList()),
    );
  }
}
