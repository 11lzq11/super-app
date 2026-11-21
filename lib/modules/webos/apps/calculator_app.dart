import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';

/// WebOS 内置迷你计算器：四则运算 + 常用科学函数（用 math_expressions 解析）。
class CalculatorApp extends StatefulWidget {
  const CalculatorApp({super.key});

  @override
  State<CalculatorApp> createState() => _CalculatorAppState();
}

class _CalculatorAppState extends State<CalculatorApp> {
  String _expression = '';
  String _result = '';
  bool _degrees = true;

  void _onKey(String key) {
    setState(() {
      switch (key) {
        case 'C':
          _expression = '';
          _result = '';
        case '⌫':
          if (_expression.isNotEmpty) {
            _expression = _expression.substring(0, _expression.length - 1);
          }
        case '=':
          _evaluate();
        case 'DEG':
        case 'RAD':
          _degrees = !_degrees;
        default:
          // 刚算完又按数字/函数：从新表达式开始
          if (_result.isNotEmpty &&
              _expression.isNotEmpty &&
              (key == '(' || _isDigitOrDot(key))) {
            _expression = key;
            _result = '';
          } else {
            _expression += key;
          }
      }
    });
  }

  bool _isDigitOrDot(String key) {
    return key.length == 1 && '0123456789.'.contains(key);
  }

  void _evaluate() {
    if (_expression.trim().isEmpty) return;
    try {
      var expr = _expression
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll('−', '-')
          .replaceAll('π', 'pi');
      // 角度制：sin/cos/tan 的参数从度转弧度（仅处理无嵌套括号的简单情形）
      if (_degrees) {
        expr = expr.replaceAllMapped(
          RegExp(r'(sin|cos|tan)\(([^()]*)\)'),
          (m) => '${m[1]}((${m[2]})*pi/180)',
        );
      }
      final parser = ShuntingYardParser();
      final parsed = parser.parse(expr);
      final value = parsed.evaluate(EvaluationType.REAL, ContextModel());
      _result = _format(value);
    } catch (_) {
      _result = '错误';
    }
  }

  String _format(double value) {
    if (value.isNaN || value.isInfinite) return '错误';
    if (value == value.truncateToDouble() && value.abs() < 1e15) {
      return value.truncate().toString();
    }
    var text = value.toStringAsPrecision(10);
    // 去掉多余的尾零
    if (text.contains('.')) {
      text = text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            alignment: Alignment.bottomRight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Text(
                    _expression.isEmpty ? '0' : _expression,
                    style: const TextStyle(fontSize: 22, color: Colors.grey),
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Text(
                    _result.isEmpty ? '' : '= $_result',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            children: [
              _buildRow(['sin(', 'cos(', 'tan(', 'log(', 'ln(']),
              _buildRow(['√(', 'x²', 'xʸ', '(', ')']),
              _buildRow([_degrees ? 'DEG' : 'RAD', 'π', 'e', '!', '%']),
              _buildRow(['7', '8', '9', '÷', '⌫']),
              _buildRow(['4', '5', '6', '×', 'C']),
              _buildRow(['1', '2', '3', '−', '']),
              _buildRow(['0', '.', '+', '=', '']),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      children: keys.map((key) {
        if (key.isEmpty) return const Expanded(child: SizedBox());
        return Expanded(child: _buildKey(key));
      }).toList(),
    );
  }

  Widget _buildKey(String key) {
    final isOperator = ['÷', '×', '−', '+', '='].contains(key);
    final isAction = ['C', '⌫', 'DEG', 'RAD'].contains(key);
    return Padding(
      padding: const EdgeInsets.all(3),
      child: FilledButton(
        onPressed: () => _onKey(_keyValue(key)),
        style: FilledButton.styleFrom(
          backgroundColor: isOperator
              ? const Color(0xFF0F172A)
              : isAction
                  ? const Color(0xFFE2E8F0)
                  : const Color(0xFFF1F5F9),
          foregroundColor: isOperator
              ? Colors.white
              : const Color(0xFF0F172A),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(key, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  /// 按钮显示文本 -> 表达式文本。
  String _keyValue(String key) {
    switch (key) {
      case '√(':
        return 'sqrt(';
      case 'x²':
        return '^2';
      case 'xʸ':
        return '^';
      case '!':
        return '!';
      case 'DEG':
      case 'RAD':
        return key;
      default:
        return key;
    }
  }
}
