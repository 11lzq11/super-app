/// 单位转换纯数据与换算逻辑（不依赖 Flutter，可单独验证）。
///
/// 线性单位：1 个该单位 = [factor] 个基准单位，换算为
/// value * from.factor / to.factor。
/// 温度单独处理（以摄氏度为中转）。货币为离线固定汇率表（以人民币为基准）。
library;

import 'dart:math' as math;

/// 换算结果格式化：按指定小数位截断并去掉无意义的尾随 0。
String formatConverted(double value, {int decimals = 4}) {
  if (value.isNaN) return '—';
  if (value.isInfinite) return '∞';
  if (value == 0) return '0';
  final abs = value.abs();
  if (abs >= 1e12 || (abs < 1e-9 && abs > 0)) {
    final parts = value.toStringAsExponential(6).split('e');
    var mantissa = parts[0];
    if (mantissa.contains('.')) {
      mantissa = mantissa.replaceAll(RegExp(r'0+$'), '');
      mantissa = mantissa.replaceAll(RegExp(r'\.$'), '');
    }
    return '${mantissa}e${parts[1]}';
  }
  var s = value.toStringAsFixed(decimals);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}

class ConvUnit {
  final String id;
  final String name;
  final String symbol;

  /// 1 个该单位 = factor 个基准单位（温度单位不使用该字段，填 1）。
  final double factor;

  const ConvUnit({
    required this.id,
    required this.name,
    required this.symbol,
    required this.factor,
  });
}

class ConvCategory {
  final String id;
  final String name;
  final List<ConvUnit> units;
  final bool isTemperature;
  final bool isCurrency;

  const ConvCategory({
    required this.id,
    required this.name,
    required this.units,
    this.isTemperature = false,
    this.isCurrency = false,
  });
}

const double _mileInMeters = 1609.344;
const double _muInSquareMeters = 2000 / 3;

List<ConvCategory> get converterCategories => const [
      ConvCategory(
        id: 'length',
        name: '长度',
        units: [
          ConvUnit(id: 'm', name: '米', symbol: 'm', factor: 1),
          ConvUnit(id: 'km', name: '千米', symbol: 'km', factor: 1000),
          ConvUnit(id: 'cm', name: '厘米', symbol: 'cm', factor: 0.01),
          ConvUnit(id: 'mm', name: '毫米', symbol: 'mm', factor: 0.001),
          ConvUnit(id: 'um', name: '微米', symbol: 'μm', factor: 1e-6),
          ConvUnit(id: 'nm', name: '纳米', symbol: 'nm', factor: 1e-9),
          ConvUnit(id: 'mi', name: '英里', symbol: 'mi', factor: _mileInMeters),
          ConvUnit(id: 'yd', name: '码', symbol: 'yd', factor: 0.9144),
          ConvUnit(id: 'ft', name: '英尺', symbol: 'ft', factor: 0.3048),
          ConvUnit(id: 'in', name: '英寸', symbol: 'in', factor: 0.0254),
          ConvUnit(id: 'nmi', name: '海里', symbol: 'nmi', factor: 1852),
          ConvUnit(id: 'li', name: '里', symbol: '里', factor: 500),
          ConvUnit(id: 'zhang', name: '丈', symbol: '丈', factor: 10 / 3),
          ConvUnit(id: 'chi', name: '尺', symbol: '尺', factor: 1 / 3),
          ConvUnit(id: 'cun', name: '寸', symbol: '寸', factor: 1 / 30),
        ],
      ),
      ConvCategory(
        id: 'mass',
        name: '质量',
        units: [
          ConvUnit(id: 'kg', name: '千克', symbol: 'kg', factor: 1),
          ConvUnit(id: 'g', name: '克', symbol: 'g', factor: 0.001),
          ConvUnit(id: 'mg', name: '毫克', symbol: 'mg', factor: 1e-6),
          ConvUnit(id: 't', name: '吨', symbol: 't', factor: 1000),
          ConvUnit(id: 'jin', name: '斤', symbol: '斤', factor: 0.5),
          ConvUnit(id: 'liang', name: '两', symbol: '两', factor: 0.05),
          ConvUnit(id: 'lb', name: '磅', symbol: 'lb', factor: 0.45359237),
          ConvUnit(id: 'oz', name: '盎司', symbol: 'oz', factor: 0.028349523125),
          ConvUnit(id: 'ct', name: '克拉', symbol: 'ct', factor: 0.0002),
        ],
      ),
      ConvCategory(
        id: 'temperature',
        name: '温度',
        isTemperature: true,
        units: [
          ConvUnit(id: 'c', name: '摄氏度', symbol: '℃', factor: 1),
          ConvUnit(id: 'f', name: '华氏度', symbol: '℉', factor: 1),
          ConvUnit(id: 'k', name: '开尔文', symbol: 'K', factor: 1),
        ],
      ),
      ConvCategory(
        id: 'volume',
        name: '体积',
        units: [
          ConvUnit(id: 'm3', name: '立方米', symbol: 'm³', factor: 1),
          ConvUnit(id: 'l', name: '升', symbol: 'L', factor: 0.001),
          ConvUnit(id: 'ml', name: '毫升', symbol: 'mL', factor: 1e-6),
          ConvUnit(id: 'cm3', name: '立方厘米', symbol: 'cm³', factor: 1e-6),
          ConvUnit(id: 'dm3', name: '立方分米', symbol: 'dm³', factor: 0.001),
          ConvUnit(id: 'gal_us', name: '美制加仑', symbol: 'gal', factor: 0.003785411784),
          ConvUnit(id: 'gal_uk', name: '英制加仑', symbol: 'gal', factor: 0.00454609),
          ConvUnit(id: 'ft3', name: '立方英尺', symbol: 'ft³', factor: 0.028316846592),
          ConvUnit(id: 'in3', name: '立方英寸', symbol: 'in³', factor: 1.6387064e-5),
        ],
      ),
      ConvCategory(
        id: 'area',
        name: '面积',
        units: [
          ConvUnit(id: 'm2', name: '平方米', symbol: 'm²', factor: 1),
          ConvUnit(id: 'km2', name: '平方千米', symbol: 'km²', factor: 1e6),
          ConvUnit(id: 'ha', name: '公顷', symbol: 'ha', factor: 10000),
          ConvUnit(id: 'mu', name: '亩', symbol: '亩', factor: _muInSquareMeters),
          ConvUnit(id: 'cm2', name: '平方厘米', symbol: 'cm²', factor: 1e-4),
          ConvUnit(id: 'ft2', name: '平方英尺', symbol: 'ft²', factor: 0.09290304),
          ConvUnit(id: 'acre', name: '英亩', symbol: 'acre', factor: 4046.8564224),
          ConvUnit(id: 'mi2', name: '平方英里', symbol: 'mi²', factor: 2589988.110336),
        ],
      ),
      ConvCategory(
        id: 'speed',
        name: '速度',
        units: [
          ConvUnit(id: 'ms', name: '米/秒', symbol: 'm/s', factor: 1),
          ConvUnit(id: 'kmh', name: '千米/时', symbol: 'km/h', factor: 1 / 3.6),
          ConvUnit(id: 'mph', name: '英里/时', symbol: 'mph', factor: 0.44704),
          ConvUnit(id: 'kn', name: '节', symbol: 'kn', factor: 0.5144444444444445),
          ConvUnit(id: 'fts', name: '英尺/秒', symbol: 'ft/s', factor: 0.3048),
        ],
      ),
      ConvCategory(
        id: 'time',
        name: '时间',
        units: [
          ConvUnit(id: 's', name: '秒', symbol: 's', factor: 1),
          ConvUnit(id: 'ms', name: '毫秒', symbol: 'ms', factor: 0.001),
          ConvUnit(id: 'us', name: '微秒', symbol: 'μs', factor: 1e-6),
          ConvUnit(id: 'min', name: '分钟', symbol: 'min', factor: 60),
          ConvUnit(id: 'h', name: '小时', symbol: 'h', factor: 3600),
          ConvUnit(id: 'd', name: '天', symbol: 'd', factor: 86400),
          ConvUnit(id: 'week', name: '周', symbol: '周', factor: 604800),
          ConvUnit(id: 'month', name: '月（30天）', symbol: '月', factor: 2592000),
          ConvUnit(id: 'year', name: '年（365天）', symbol: '年', factor: 31536000),
        ],
      ),
      ConvCategory(
        id: 'data',
        name: '数据存储',
        units: [
          ConvUnit(id: 'b', name: '字节', symbol: 'B', factor: 1),
          ConvUnit(id: 'bit', name: '位', symbol: 'bit', factor: 0.125),
          ConvUnit(id: 'kb', name: '千字节', symbol: 'KB', factor: 1000),
          ConvUnit(id: 'mb', name: '兆字节', symbol: 'MB', factor: 1e6),
          ConvUnit(id: 'gb', name: '吉字节', symbol: 'GB', factor: 1e9),
          ConvUnit(id: 'tb', name: '太字节', symbol: 'TB', factor: 1e12),
          ConvUnit(id: 'kib', name: 'Kibibyte', symbol: 'KiB', factor: 1024),
          ConvUnit(id: 'mib', name: 'Mebibyte', symbol: 'MiB', factor: 1048576),
          ConvUnit(id: 'gib', name: 'Gibibyte', symbol: 'GiB', factor: 1073741824),
          ConvUnit(id: 'tib', name: 'Tebibyte', symbol: 'TiB', factor: 1099511627776),
        ],
      ),
      ConvCategory(
        id: 'pressure',
        name: '压力',
        units: [
          ConvUnit(id: 'pa', name: '帕斯卡', symbol: 'Pa', factor: 1),
          ConvUnit(id: 'kpa', name: '千帕', symbol: 'kPa', factor: 1000),
          ConvUnit(id: 'mpa', name: '兆帕', symbol: 'MPa', factor: 1e6),
          ConvUnit(id: 'bar', name: '巴', symbol: 'bar', factor: 100000),
          ConvUnit(id: 'atm', name: '标准大气压', symbol: 'atm', factor: 101325),
          ConvUnit(id: 'mmhg', name: '毫米汞柱', symbol: 'mmHg', factor: 133.322387415),
          ConvUnit(id: 'psi', name: '磅/平方英寸', symbol: 'psi', factor: 6894.757293168),
        ],
      ),
      ConvCategory(
        id: 'energy',
        name: '能量',
        units: [
          ConvUnit(id: 'j', name: '焦耳', symbol: 'J', factor: 1),
          ConvUnit(id: 'kj', name: '千焦', symbol: 'kJ', factor: 1000),
          ConvUnit(id: 'cal', name: '卡路里', symbol: 'cal', factor: 4.184),
          ConvUnit(id: 'kcal', name: '千卡', symbol: 'kcal', factor: 4184),
          ConvUnit(id: 'kwh', name: '千瓦时', symbol: 'kWh', factor: 3600000),
          ConvUnit(id: 'ev', name: '电子伏特', symbol: 'eV', factor: 1.602176634e-19),
          ConvUnit(id: 'btu', name: '英热单位', symbol: 'BTU', factor: 1055.05585262),
        ],
      ),
      ConvCategory(
        id: 'power',
        name: '功率',
        units: [
          ConvUnit(id: 'w', name: '瓦特', symbol: 'W', factor: 1),
          ConvUnit(id: 'kw', name: '千瓦', symbol: 'kW', factor: 1000),
          ConvUnit(id: 'mw', name: '兆瓦', symbol: 'MW', factor: 1e6),
          ConvUnit(id: 'hp', name: '马力（公制）', symbol: 'hp', factor: 735.49875),
        ],
      ),
      ConvCategory(
        id: 'angle',
        name: '角度',
        units: [
          ConvUnit(id: 'deg', name: '度', symbol: '°', factor: 1),
          ConvUnit(
            id: 'rad',
            name: '弧度',
            symbol: 'rad',
            factor: 180 / math.pi,
          ),
          ConvUnit(id: 'turn', name: '圈', symbol: '圈', factor: 360),
          ConvUnit(id: 'grad', name: '梯度', symbol: 'grad', factor: 0.9),
        ],
      ),
      ConvCategory(
        id: 'currency',
        name: '货币',
        isCurrency: true,
        units: [
          ConvUnit(id: 'cny', name: '人民币', symbol: '¥', factor: 1),
          ConvUnit(id: 'usd', name: '美元', symbol: r'$', factor: 7.12),
          ConvUnit(id: 'eur', name: '欧元', symbol: '€', factor: 8.25),
          ConvUnit(id: 'jpy', name: '日元', symbol: '¥', factor: 0.047),
          ConvUnit(id: 'gbp', name: '英镑', symbol: '£', factor: 9.55),
          ConvUnit(id: 'hkd', name: '港币', symbol: r'HK$', factor: 0.915),
          ConvUnit(id: 'aud', name: '澳元', symbol: r'A$', factor: 4.65),
          ConvUnit(id: 'cad', name: '加元', symbol: r'C$', factor: 5.12),
          ConvUnit(id: 'krw', name: '韩元', symbol: '₩', factor: 0.0051),
          ConvUnit(id: 'twd', name: '新台币', symbol: r'NT$', factor: 0.225),
        ],
      ),
    ];

/// 货币汇率表更新日期（离线固定汇率，仅供参考）。
const String currencyRateDate = '2026-11-22';

/// 温度换算（以摄氏度为中转）。
double convertTemperature(double value, String fromId, String toId) {
  double celsius;
  switch (fromId) {
    case 'c':
      celsius = value;
    case 'f':
      celsius = (value - 32) * 5 / 9;
    case 'k':
      celsius = value - 273.15;
    default:
      throw ArgumentError('未知温度单位：$fromId');
  }
  switch (toId) {
    case 'c':
      return celsius;
    case 'f':
      return celsius * 9 / 5 + 32;
    case 'k':
      return celsius + 273.15;
    default:
      throw ArgumentError('未知温度单位：$toId');
  }
}

/// 通用换算入口。
double convertValue(
  ConvCategory category,
  ConvUnit from,
  ConvUnit to,
  double value,
) {
  if (category.isTemperature) {
    return convertTemperature(value, from.id, to.id);
  }
  return value * from.factor / to.factor;
}

/// 温度换算公式文本，如 ℉ = ℃ × 9/5 + 32。
String temperatureFormula(String fromId, String toId) {
  const formulas = {
    'c_f': '℉ = ℃ × 9/5 + 32',
    'f_c': '℃ = (℉ − 32) × 5/9',
    'c_k': 'K = ℃ + 273.15',
    'k_c': '℃ = K − 273.15',
    'f_k': 'K = (℉ − 32) × 5/9 + 273.15',
    'k_f': '℉ = (K − 273.15) × 9/5 + 32',
  };
  return formulas['${fromId}_$toId'] ?? '';
}

/// 换算公式展示，如「1 千米 = 1000 米」。
String conversionFormula(
  ConvCategory category,
  ConvUnit from,
  ConvUnit to, {
  int decimals = 4,
}) {
  if (from.id == to.id) {
    return '1 ${from.name} = 1 ${to.name}';
  }
  if (category.isTemperature) {
    final value = convertTemperature(1, from.id, to.id);
    final formula = temperatureFormula(from.id, to.id);
    return '1 ${from.name} = ${formatConverted(value, decimals: decimals)} '
        '${to.name}（$formula）';
  }
  final value = from.factor / to.factor;
  return '1 ${from.name} = ${formatConverted(value, decimals: decimals)} '
      '${to.name}';
}

/// 设置存储键。
class ConverterPrefs {
  static const String decimalsKey = 'conv_decimals';
  static const String defaultCategoryKey = 'conv_default_category';
  static const int defaultDecimals = 4;
  static const String defaultCategoryId = 'length';
}
