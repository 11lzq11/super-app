import 'package:flutter/material.dart';

/// 全局尺寸常量：统一间距、圆角，页面都用这套值，别各写各的。
class AppDimens {
  AppDimens._();

  /// 页面左右边距。
  static const double pagePadding = 16;

  /// 列表/卡片之间的间距。
  static const double itemSpacing = 12;

  /// 分区之间的间距。
  static const double sectionSpacing = 20;

  /// 卡片圆角。
  static const double cardRadius = 16;

  /// 输入框/小容器圆角。
  static const double fieldRadius = 12;

  /// 首页模块卡片固定高度：内容（图标 40 + 标题 1 行 + 简介 2 行 +
  /// 内边距与间距）约 132dp，留 16dp 余量，字体放大也不裁简介。
  static const double moduleCardHeight = 148;
}

/// SuperApp 主题：Material 3，中性灰 + 一个克制的主色（深钢蓝）。
/// 浅色 / 深色两套，跟随系统由 SettingsService 控制。
class AppTheme {
  AppTheme._();

  /// 主色：深钢蓝，克制不张扬。
  static const Color _seed = Color(0xFF3A5A7A);

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    // 按钮统一 12dp 圆角，与卡片、输入框对齐（默认是全圆角药丸形）。
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimens.fieldRadius),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.cardRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: buttonShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: buttonShape),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: buttonShape),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.fieldRadius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.fieldRadius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.fieldRadius),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onPrimary;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return null;
        }),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
