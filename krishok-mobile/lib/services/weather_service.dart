import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  static const double _lat = 24.363588; // Rajshahi, Bangladesh
  static const double _lon = 88.624138;

  /// Full weather data for [lat]/[lon] — used by the Weather tab.
  Future<Map<String, dynamic>> fetchWeather(double lat, double lon) async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&current=temperature_2m,relative_humidity_2m,weather_code'
      '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,time'
      '&timezone=auto',
    );
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Weather fetch failed (${response.statusCode})');
  }

  /// Returns the current hour's precipitation probability (0–100) for Rajshahi.
  Future<int?> fetchRainProbability() async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$_lat&longitude=$_lon'
      '&hourly=temperature_2m,precipitation_probability'
      '&forecast_days=1'
      '&timezone=auto',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Weather fetch failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final probs =
        (data['hourly']?['precipitation_probability']) as List?;
    if (probs == null || probs.isEmpty) return null;
    final idx = DateTime.now().hour.clamp(0, probs.length - 1);
    return (probs[idx] as num?)?.toInt();
  }
}
