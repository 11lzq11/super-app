/// 科学计算器纯计算逻辑（不依赖 Flutter，可单独验证）。
///
/// 负责：把界面输入的表达式预处理成 math_expressions 认识的形式、
/// 解析求值、结果格式化。
/// 注意 math_expressions 2.7.0 的几个坑（已实测）：
/// - `log` 是二元函数 log(底数, 真数)，单参数 log(x) 需改写为 log(10, x)；
/// - `e` 是前缀函数 e(x)=e^x，欧拉常数需替换为数值；
/// - `pi` 不被识别，需替换为数值；
/// - 反三角函数关键字是 arcsin/arccos/arctan，不是 asin/acos/atan；
/// - `%` 是取模运算符，百分号需改写为 /100。
library;

import 'dart:math' as math;

import 'package:math_expressions/math_expressions.dart';

/// 计算失败时抛出的异常，[message] 为可直接展示的中文提示。
class CalculatorException implements Exception {
  final String message;
  const CalculatorException(this.message);

  @override
  String toString() => message;
}

const String _piDigits = '3.141592653589793';
const String _eDigits = '2.718281828459045';

/// 把用户输入的表达式转成解析器认识的形式。
///
/// [degrees] 为 true 时三角函数按角度制计算（sin(30)=0.5），
/// 为 false 时按弧度制。
String preprocessExpression(String raw, {required bool degrees}) {
  var s = raw.replaceAll(' ', '');
  if (s.isEmpty) {
    throw const CalculatorException('请输入表达式');
  }

  // 界面符号 -> 解析器符号
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

  // log 单参数 -> log(10, x)；已带底数的 log(10, x) 不动
  s = s.replaceAllMapped(RegExp(r'log\((?!10,)'), (_) => 'log(10,');

  // 常量前的隐式乘法：2π -> 2*π，π2 -> π*2，2e -> 2*e，e2 -> e*2
  s = s.replaceAllMapped(RegExp(r'(\d)(π)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(\))(π)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(π)(\d)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(\d)(pi\b)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(\))(pi\b)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(pi)(\d)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(\d)(e)(?![0-9])'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(\))(e)(?![0-9])'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(e)(\d)'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(e)(\()'), (m) => '${m[1]}*${m[2]}');

  // 常量替换为数值
  s = s.replaceAll('π', _piDigits);
  s = s.replaceAllMapped(RegExp(r'\bpi\b'), (_) => _piDigits);
  s = s.replaceAllMapped(RegExp(r'\be\b'), (_) => _eDigits);

  // 百分号：50% -> (50/100)，(a+b)% -> (a+b)/100
  s = s.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)%'),
    (m) => '(${m[1]}/100)',
  );
  s = s.replaceAll(')%', ')/100');

  // 角度制：三角函数按角度算
  if (degrees) {
    s = _applyDegreeMode(s);
  }

  // 括号平衡检查
  var depth = 0;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')') {
      depth--;
      if (depth < 0) {
        throw const CalculatorException('括号不匹配');
      }
    }
  }
  if (depth != 0) {
    throw const CalculatorException('括号不匹配');
  }
  return s;
}

/// 角度制转换：sin/cos/tan 的参数乘 π/180；arcsin 等的结果乘 180/π。
/// 递归处理：先转换最左侧调用的参数（保证嵌套正确，如 sin(cos(30))），
/// 再转换调用后面的部分。
String _applyDegreeMode(String expr) {
  const forward = ['sin', 'cos', 'tan'];
  const inverse = ['arcsin', 'arccos', 'arctan'];
  var bestIndex = -1;
  var bestName = '';
  var bestIsInverse = false;
  for (final name in [...forward, ...inverse]) {
    final idx = _firstIndexOfFunc(expr, name);
    if (idx != -1 && (bestIndex == -1 || idx < bestIndex)) {
      bestIndex = idx;
      bestName = name;
      bestIsInverse = inverse.contains(name);
    }
  }
  if (bestIndex == -1) return expr;
  final openIndex = bestIndex + bestName.length;
  final closeIndex = _matchingParen(expr, openIndex);
  if (closeIndex == -1) return expr; // 括号不匹配，交给后续检查报错
  final arg = _applyDegreeMode(expr.substring(openIndex + 1, closeIndex));
  final suffix = _applyDegreeMode(expr.substring(closeIndex + 1));
  final prefix = expr.substring(0, bestIndex);
  if (bestIsInverse) {
    return '$prefix($bestName($arg)*180/$_piDigits)$suffix';
  }
  return '$prefix$bestName($arg*$_piDigits/180)$suffix';
}

/// 找函数名第一次出现的位置，且前面不能是字母
/// （避免把 arcsin 里的 sin 误当成 sin）。
int _firstIndexOfFunc(String s, String name) {
  final pat = '$name(';
  var idx = s.indexOf(pat);
  while (idx > 0 && RegExp(r'[a-zA-Z]').hasMatch(s[idx - 1])) {
    idx = s.indexOf(pat, idx + 1);
  }
  return idx;
}

/// 找与 openIndex 处的 '(' 配对的 ')' 位置，找不到返回 -1。
int _matchingParen(String s, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// 计算表达式的值，出错时抛出带中文提示的 [CalculatorException]。
double evaluateExpression(String raw, {required bool degrees}) {
  final processed = preprocessExpression(raw, degrees: degrees);
  try {
    final exp = ShuntingYardParser().parse(processed);
    final value = exp.evaluate(EvaluationType.REAL, ContextModel());
    if (value is! num) {
      throw const CalculatorException('表达式错误');
    }
    final d = value.toDouble();
    if (d.isNaN) {
      throw const CalculatorException('结果不是数字');
    }
    if (d.isInfinite) {
      throw const CalculatorException('结果超出范围');
    }
    return d;
  } on CalculatorException {
    rethrow;
  } catch (_) {
    throw const CalculatorException('表达式错误');
  }
}

/// 表达式是否看起来还没输完（以运算符、左括号、函数名结尾），
/// 用于输入过程中不显示错误提示。
bool looksIncomplete(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return true;
  const tails = [
    '+',
    '-',
    '×',
    '÷',
    '*',
    '/',
    '^',
    '.',
    '(',
    '√',
    '%',
  ];
  if (tails.any(s.endsWith)) return true;
  const funcs = ['sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'log', 'ln'];
  return funcs.any(s.endsWith);
}

/// 格式化计算结果：去掉无意义的尾随 0，极大/极小值用科学计数法。
String formatResult(double value) {
  if (value.isNaN || value.isInfinite) return '错误';
  if (value == 0) return '0';
  final abs = value.abs();
  if (abs >= 1e12 || abs < 1e-9) {
    final parts = value.toStringAsExponential(8).split('e');
    var mantissa = parts[0];
    if (mantissa.contains('.')) {
      mantissa = mantissa.replaceAll(RegExp(r'0+$'), '');
      mantissa = mantissa.replaceAll(RegExp(r'\.$'), '');
    }
    return '${mantissa}e${parts[1]}';
  }
  var s = value.toStringAsPrecision(12);
  if (s.contains('e')) return s;
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}

/// 角度转弧度（供外部使用）。
double degreesToRadians(double deg) => deg * math.pi / 180;
