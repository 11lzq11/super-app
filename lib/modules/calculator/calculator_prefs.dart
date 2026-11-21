/// 科学计算器设置存储（SharedPreferences）。
library;

import 'package:shared_preferences/shared_preferences.dart';

class CalculatorPrefs {
  static const String angleUnitKey = 'calc_angle_unit'; // 'DEG' | 'RAD'
  static const String historyEnabledKey = 'calc_history_enabled';
  static const String historyKey = 'calc_history';

  static const int maxHistory = 50;

  static Future<bool> isDegrees() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(angleUnitKey) ?? 'DEG') == 'DEG';
  }

  static Future<void> setDegrees(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(angleUnitKey, value ? 'DEG' : 'RAD');
  }

  static Future<bool> historyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(historyEnabledKey) ?? true;
  }

  static Future<void> setHistoryEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(historyEnabledKey, value);
  }

  static Future<List<String>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(historyKey) ?? <String>[];
  }

  static Future<void> saveHistory(List<String> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(historyKey, history);
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(historyKey);
  }
}
