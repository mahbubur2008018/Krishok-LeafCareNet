import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  /// Returns true if the device has a working internet connection.
  /// Checks both network type (wifi/mobile) and actual reachability.
  static Future<bool> isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.none)) return false;

      // Verify actual internet by doing a quick DNS lookup
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Checks if a Gemini error is due to connectivity/availability issues.
  static bool isNetworkError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('socket') ||
        msg.contains('host lookup') ||
        msg.contains('connection') ||
        msg.contains('timeout') ||
        msg.contains('network') ||
        msg.contains('unavailable') ||
        msg.contains('errno = 7');
  }
}
