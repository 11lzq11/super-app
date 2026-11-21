import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一款壁纸：纯色渐变。
class WebOSWallpaper {
  final String name;
  final List<Color> colors;
  final Alignment begin;
  final Alignment end;

  const WebOSWallpaper({
    required this.name,
    required this.colors,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  LinearGradient get gradient => LinearGradient(
        colors: colors,
        begin: begin,
        end: end,
      );
}

/// 内置壁纸（克制配色，无 AI 味）。
const List<WebOSWallpaper> webOSWallpapers = [
  WebOSWallpaper(
    name: '石墨蓝',
    colors: [Color(0xFF334155), Color(0xFF0F172A)],
  ),
  WebOSWallpaper(
    name: '青灰',
    colors: [Color(0xFF64748B), Color(0xFF1E293B)],
  ),
  WebOSWallpaper(
    name: '墨绿',
    colors: [Color(0xFF14532D), Color(0xFF052E16)],
  ),
  WebOSWallpaper(
    name: '暖沙',
    colors: [Color(0xFFB45309), Color(0xFF451A03)],
  ),
  WebOSWallpaper(
    name: '雾紫',
    colors: [Color(0xFF6D28D9), Color(0xFF1E1B4B)],
  ),
  WebOSWallpaper(
    name: '浅灰',
    colors: [Color(0xFFE2E8F0), Color(0xFF94A3B8)],
  ),
];

const String _wallpaperKey = 'webos_wallpaper';
const String _darkKey = 'webos_dark_mode';
const String _windowModeKey = 'webos_window_mode';

/// 当前壁纸序号（全局通知，WebOS 桌面与设置页共用）。
final ValueNotifier<int> webOSWallpaperNotifier = ValueNotifier<int>(0);

/// WebOS 深色模式开关（全局通知）。
final ValueNotifier<bool> webOSDarkModeNotifier = ValueNotifier<bool>(false);

Future<int> loadWebOSWallpaper() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_wallpaperKey) ?? 0;
    final safe = index >= 0 && index < webOSWallpapers.length ? index : 0;
    webOSWallpaperNotifier.value = safe;
    return safe;
  } catch (_) {
    return 0;
  }
}

Future<void> setWebOSWallpaper(int index) async {
  if (index < 0 || index >= webOSWallpapers.length) return;
  webOSWallpaperNotifier.value = index;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_wallpaperKey, index);
  } catch (_) {}
}

Future<bool> loadWebOSDarkMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final dark = prefs.getBool(_darkKey) ?? false;
    webOSDarkModeNotifier.value = dark;
    return dark;
  } catch (_) {
    return false;
  }
}

Future<void> setWebOSDarkMode(bool dark) async {
  webOSDarkModeNotifier.value = dark;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkKey, dark);
  } catch (_) {}
}

/// 默认窗口模式：auto（按宽高比自适应）/ desktop（桌面）/ phone（手机）。
Future<String> loadWebOSWindowMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_windowModeKey) ?? 'auto';
    if (mode == 'desktop' || mode == 'phone') return mode;
    return 'auto';
  } catch (_) {
    return 'auto';
  }
}

Future<void> setWebOSWindowMode(String mode) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_windowModeKey, mode);
  } catch (_) {}
}

/// WebOS 窗口配色（跟随深色开关）。
class WebOSColors {
  WebOSColors._();

  static bool get isDark => webOSDarkModeNotifier.value;

  static Color get windowBackground =>
      isDark ? const Color(0xFF1E293B) : Colors.white;

  static Color get titleBarBackground =>
      isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

  static Color get textPrimary =>
      isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

  static Color get textSecondary =>
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  static Color get taskbarBackground =>
      isDark ? const Color(0xCC0F172A) : const Color(0xCCFFFFFF);

  static Color get border =>
      isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
}
