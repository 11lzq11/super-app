/// 函数绘制纯逻辑（不依赖 Flutter，可单独验证）。
///
/// 负责：把用户输入的 y=f(x) 预处理成 math_expressions 认识的形式、
/// 解析、求值、数值求零点。
/// 与计算器引擎共享同一套 math_expressions 2.7.0 适配：
/// log 单参数需改写为 log(10, x)；e / pi 需替换为数值；
/// 反三角函数关键字是 arcsin/arccos/arctan。
library;

import 'dart:math' as math;

import 'package:math_expressions/math_expressions.dart';

/// 函数表达式错误，[message] 为可直接展示的中文提示。
class PlotParseException implements Exception {
  final String message;
  const PlotParseException(this.message);

  @override
  String toString() => message;
}

const String _piDigits = '3.141592653589793';
const String _eDigits = '2.718281828459045';

/// 预处理绘图表达式：符号转换、常量替换、隐式乘法补全。
String preprocessPlotExpression(String raw) {
  var s = raw.replaceAll(' ', '');
  if (s.isEmpty) {
    throw const PlotParseException('请输入函数表达式');
  }

  s = s.replaceAll('×', '*');
  s = s.replaceAll('÷', '/');
  s = s.replaceAll('−', '-');
  s = s.replaceAll('–', '-');

  // √：√( -> sqrt( ；√9 -> sqrt(9)
  s = s.replaceAllMapped(RegExp(r'√\s*\('), (_) => 'sqrt(');
  s = s.replaceAllMapped(
    RegExp(r'√\s*(\d+(?:\.\d+)?)'),
    (m) => 'sqrt(${m[1]})',
  );

  // 科学计数法 1.23e+10 -> (1.23*10^10)
  s = s.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)[eE]([+-]?\d+)'),
    (m) => '(${m[1]}*10^${m[2]})',
  );

  // 反三角函数名
  s = s.replaceAllMapped(RegExp(r'\basin\('), (_) => 'arcsin(');
  s = s.replaceAllMapped(RegExp(r'\bacos\('), (_) => 'arccos(');
  s = s.replaceAllMapped(RegExp(r'\batan\('), (_) => 'arctan(');

  // log 单参数 -> log(10, x)
  s = s.replaceAllMapped(RegExp(r'log\((?!10,)'), (_) => 'log(10,');

  // 常量前的隐式乘法（必须在替换为数值之前做，否则 2π 会变成 23.14…）
  s = s.replaceAllMapped(RegExp(r'(\d)(π)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(\))(π)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(x)(π)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(π)(\d)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(\d)(pi\b)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(\))(pi\b)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(x)(pi\b)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(pi)(\d)'), (m) => '${m[1]}*${m[2]}');

  // 常量替换为数值
  s = s.replaceAll('π', _piDigits);
  s = s.replaceAllMapped(RegExp(r'\bpi\b'), (_) => _piDigits);

  // 其余隐式乘法：2x、2(、x(、)(、2sin(x)、xsin(x)、2e、xe、ex、e(
  s = _insertImplicitMultiplication(s);

  // 欧拉常数替换为数值
  s = s.replaceAllMapped(RegExp(r'\be\b'), (_) => _eDigits);

  // 括号平衡检查
  var depth = 0;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')') {
      depth--;
      if (depth < 0) {
        throw const PlotParseException('括号不匹配');
      }
    }
  }
  if (depth != 0) {
    throw const PlotParseException('括号不匹配');
  }
  return s;
}

String _insertImplicitMultiplication(String s) {
  const funcs = r'sin|cos|tan|arcsin|arccos|arctan|log|ln|sqrt|abs';
  s = s.replaceAllMapped(RegExp(r'(\d)(x)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(\d)(\()'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(x)(\()'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(\))(x|\()'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(
    RegExp('(\\d)($funcs)'),
    (m) => '${m[1]}*${m[2]}',
  );
  s = s.replaceAllMapped(
    RegExp('(x)($funcs)'),
    (m) => '${m[1]}*${m[2]}',
  );
  s = s.replaceAllMapped(
    RegExp('(\\))($funcs)'),
    (m) => '${m[1]}*${m[2]}',
  );
  s = s.replaceAllMapped(
    RegExp(r'(\d)(e)(?![0-9])'),
    (m) => '${m[1]}*${m[2]}',
  );
  s = s.replaceAllMapped(
    RegExp(r'(x)(e)(?![0-9a-zA-Z])'),
    (m) => '${m[1]}*${m[2]}',
  );
  s = s.replaceAllMapped(RegExp(r'(e)(x)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(e)(\()'), (m) => '${m[1]}*${m[2]}');
  return s;
}

/// 解析函数表达式，出错时抛出中文提示的 [PlotParseException]。
Expression parsePlotFunction(String raw) {
  final processed = preprocessPlotExpression(raw);
  try {
    return ShuntingYardParser().parse(processed);
  } catch (_) {
    throw const PlotParseException('函数表达式错误，请检查输入');
  }
}

/// 计算 f(x)，无定义或超出范围时返回 null。
double? evaluateAt(Expression exp, double x) {
  try {
    final cm = ContextModel()..bindVariable(Variable('x'), Number(x));
    final value = exp.evaluate(EvaluationType.REAL, cm);
    if (value is! num) return null;
    final d = value.toDouble();
    if (d.isNaN || d.isInfinite) return null;
    return d;
  } catch (_) {
    return null;
  }
}

/// 在 [xMin, xMax] 内数值求零点：采样找变号区间再二分精化。
/// 渐近线处的假变号会被 |f(零点)| 检查过滤掉。
List<double> findZeros(
  Expression exp,
  double xMin,
  double xMax, {
  int samples = 400,
}) {
  final zeros = <double>[];
  if (xMax <= xMin) return zeros;
  final step = (xMax - xMin) / samples;
  double? prevX;
  double? prevY;
  for (var i = 0; i <= samples; i++) {
    final x = xMin + step * i;
    final y = evaluateAt(exp, x);
    if (y == null) continue;
    if (y == 0) {
      if (zeros.isEmpty || (x - zeros.last).abs() > 1e-6) {
        zeros.add(x);
      }
    } else if (prevY != null &&
        prevY != 0 &&
        prevX != null &&
        y.sign != prevY.sign) {
      var a = prevX;
      var b = x;
      var fa = prevY;
      for (var k = 0; k < 50; k++) {
        final m = (a + b) / 2;
        final fm = evaluateAt(exp, m);
        if (fm == null) break;
        if (fm == 0) {
          a = m;
          b = m;
          break;
        }
        if (fm.sign == fa.sign) {
          a = m;
          fa = fm;
        } else {
          b = m;
        }
      }
      final z = (a + b) / 2;
      final fz = evaluateAt(exp, z);
      if (fz != null && fz.abs() < 1e-6) {
        if (zeros.isEmpty || (z - zeros.last).abs() > 1e-6) {
          zeros.add(z);
        }
      }
    }
    prevX = x;
    prevY = y;
  }
  return zeros;
}

/// 检查表达式在几个采样点上是否至少有一个有效值。
bool hasAnyValidValue(Expression exp, {double xMin = -10, double xMax = 10}) {
  for (final x in [0.0, 1.0, -1.0, 0.5, -0.5, 2.0, -2.0, 5.0, -5.0]) {
    if (x < xMin || x > xMax) continue;
    if (evaluateAt(exp, x) != null) return true;
  }
  return false;
}

/// 设置存储键（字符串常量，供页面与设置页共用）。
class PlotterPrefs {
  static const String showGridKey = 'plot_show_grid';
  static const String xMinKey = 'plot_x_min';
  static const String xMaxKey = 'plot_x_max';
  static const bool defaultShowGrid = true;
  static const double defaultXMin = -10;
  static const double defaultXMax = 10;
}

/// 坐标换算：屏幕坐标 -> 数学坐标。
({double x, double y}) screenToMath({
  required double sx,
  required double sy,
  required double width,
  required double height,
  required double centerX,
  required double centerY,
  required double scale,
}) {
  return (
    x: centerX + (sx - width / 2) / scale,
    y: centerY - (sy - height / 2) / scale,
  );
}

/// 坐标换算：数学坐标 -> 屏幕坐标。
({double x, double y}) mathToScreen({
  required double mx,
  required double my,
  required double width,
  required double height,
  required double centerX,
  required double centerY,
  required double scale,
}) {
  return (
    x: width / 2 + (mx - centerX) * scale,
    y: height / 2 - (my - centerY) * scale,
  );
}

/// 网格步长：取 1/2/5×10^n 中大于等于目标值（约 60 像素一格）的最小值。
double niceGridStep(double pixelsPerUnit, {double targetPixels = 60}) {
  final target = targetPixels / pixelsPerUnit;
  final magnitude = math.pow(10, (math.log(target) / math.ln10).floor());
  for (final mult in [1, 2, 5, 10]) {
    final step = mult * magnitude;
    if (step >= target) return step.toDouble();
  }
  return (10 * magnitude).toDouble();
}

/// 格式化刻度数字。
String formatTick(double value) {
  if (value == value.truncateToDouble() && value.abs() < 1e12) {
    return value.toInt().toString();
  }
  var s = value.toStringAsPrecision(4);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}
