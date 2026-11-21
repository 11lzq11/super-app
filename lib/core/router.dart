import 'package:flutter/material.dart';

import '../modules/aiplat/aiplat_page.dart';
import '../modules/calculator/calculator_page.dart';
import '../modules/converter/converter_page.dart';
import '../modules/plotter/plotter_page.dart';
import '../modules/webos/webos_page.dart';
import '../modules/tools/json_formatter_page.dart';
import '../modules/tools/password_generator_page.dart';
import '../modules/tools/qr_generator_page.dart';
import '../pages/module_placeholder_page.dart';
import '../pages/settings_page.dart';

/// 路由表。
///
/// 各模块页按契约命名（CalculatorPage、ConverterPage、PlotterPage、
/// AiPlatPage、WebOSPage），分别位于
/// lib/modules/calculator/calculator_page.dart 等路径。
/// 模块文件尚未交付、或交付的文件仍有编译错误时，对应路由先用
/// [ModulePlaceholderPage] 顶替，保证编译通过；模块就绪后把下面
/// TODO 处的占位替换为真实页面即可。
class AppRoutes {
  AppRoutes._();

  static const String settings = '/settings';
  static const String calculator = '/calculator';
  static const String converter = '/converter';
  static const String plotter = '/plotter';
  static const String aiplat = '/aiplat';
  static const String webos = '/webos';
  static const String passwordGenerator = '/tools/password';
  static const String jsonFormatter = '/tools/json';
  static const String qrGenerator = '/tools/qr';

  static Map<String, WidgetBuilder> get routes => {
        settings: (_) => const SettingsPage(),
        calculator: (_) => const CalculatorPage(),
        converter: (_) => const ConverterPage(),
        plotter: (_) => const PlotterPage(),
        aiplat: (_) => const AiPlatPage(),
        webos: (_) => const WebOSPage(),
        passwordGenerator: (_) => const PasswordGeneratorPage(),
        jsonFormatter: (_) => const JsonFormatterPage(),
        qrGenerator: (_) => const QrGeneratorPage(),
      };
}
