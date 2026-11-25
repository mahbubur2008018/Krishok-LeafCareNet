import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static const _langKey = 'app_language';
  static const _launchedKey = 'app_launched';

  Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_langKey) ?? 'bn';
  }

  Future<void> setLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, lang);
    await prefs.setBool(_launchedKey, true);
  }

  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_launchedKey) ?? false);
  }
}
