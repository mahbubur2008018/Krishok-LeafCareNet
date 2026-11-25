import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sensor_data.dart';
import '../services/esp32_service.dart';
import '../services/language_service.dart';
import '../services/scan_history_service.dart';
import '../services/sensor_history_service.dart';

class AppState with ChangeNotifier {
  final ESP32Service _esp32Service = ESP32Service();
  final ScanHistoryService _scanHistoryService = ScanHistoryService();
  final LanguageService _languageService = LanguageService();
  final SensorHistoryService _sensorHistoryService = SensorHistoryService();

  static const _sensorCacheKey = 'last_sensor_data';

  bool isConnected = false;
  SensorData? currentData;
  Timer? _pollingTimer;
  DateTime? lastDataTimestamp;

  List<ScanRecord> scanHistory = [];
  WeeklyStats weeklyStats = WeeklyStats.empty;
  List<DailySensorSnapshot> sensorHistory = [];

  String _language = 'bn';
  String get language => _language;

  bool get isShowingStaleData => !isConnected && currentData != null;

  String get staleSinceLabel {
    if (lastDataTimestamp == null) return 'unknown';
    final diff = DateTime.now().difference(lastDataTimestamp!);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  String get serverUrl => _esp32Service.baseUrl;

  AppState() {
    _init();
  }

  Future<void> _init() async {
    await Future.wait([
      _loadLanguage(),
      _loadLastSensorData(),
      _loadSensorHistory(),
    ]);
    _startPolling();
    _loadScanHistory();
  }

  Future<void> _loadLanguage() async {
    _language = await _languageService.getLanguage();
  }

  Future<void> setLanguage(String lang) async {
    await _languageService.setLanguage(lang);
    _language = lang;
    notifyListeners();
  }

  Future<void> _loadLastSensorData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sensorCacheKey);
      if (raw != null && raw.isNotEmpty) {
        currentData = SensorData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _loadSensorHistory() async {
    try {
      sensorHistory = await _sensorHistoryService.getHistory();
    } catch (_) {}
  }

  Future<void> _saveSensorData(SensorData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sensorCacheKey, jsonEncode(data.toJson()));
      await _sensorHistoryService.saveSnapshot(data);
      sensorHistory = await _sensorHistoryService.getHistory();
    } catch (_) {}
  }

  void setServerUrl(String url) {
    _esp32Service.baseUrl = url;
    _startPolling();
  }

  void forceReconnect() => _startPolling();

  void _startPolling() {
    _pollingTimer?.cancel();
    _fetchData();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchData();
    });
  }

  void _fetchData() async {
    try {
      final data = await _esp32Service.fetchSensorData();
      currentData = data;
      lastDataTimestamp = DateTime.now();
      if (!isConnected) isConnected = true;
      await _saveSensorData(data);
      notifyListeners();
    } catch (_) {
      if (isConnected) {
        isConnected = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadScanHistory() async {
    final scans = await _scanHistoryService.getScans();
    final stats = await _scanHistoryService.getWeeklyStats();
    scanHistory = scans;
    weeklyStats = stats;
    notifyListeners();
  }

  Future<void> addScan(ScanRecord record) async {
    await _scanHistoryService.addScan(record);
    await _loadScanHistory();
  }

  Future<void> deleteScan(String id) async {
    await _scanHistoryService.deleteScan(id);
    await _loadScanHistory();
  }

  Future<void> updateScanInsight(String id, String insight) async {
    await _scanHistoryService.updateScanInsight(id, insight);
    await _loadScanHistory();
  }

  Future<void> clearScanHistory() async {
    await _scanHistoryService.clearAll();
    await _loadScanHistory();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}
