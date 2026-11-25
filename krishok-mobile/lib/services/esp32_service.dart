import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/sensor_data.dart';

class ESP32Service {
  String baseUrl = 'http://192.168.4.1';

  Future<SensorData> fetchSensorData() async {
    final response = await http.get(Uri.parse('$baseUrl/api/data'));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch sensor data: ${response.statusCode}');
    }

    final Map<String, dynamic> payload =
        jsonDecode(response.body) as Map<String, dynamic>;

    return SensorData.fromJson({
      'npk': {
        'n': _toInt(payload['nitrogen']),
        'p': _toInt(payload['phosphorus']),
        'k': _toInt(payload['potassium']),
      },
      'sht20': {
        'temp': _toDouble(payload['temperature']),
        'hum': _toDouble(payload['humidity']),
      },
      'soil_mosture': {
        'mosture': _toDouble(payload['soilPercent']),
      },
    });
  }

  Future<bool> checkConnection() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/data'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
