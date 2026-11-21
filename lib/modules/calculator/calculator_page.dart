/// 科学计算器页面：表达式输入 + 实时结果 + 5 列按键 + 历史记录。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'calculator_engine.dart';
import 'calculator_prefs.dart';
import 'calculator_settings_page.dart';

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

enum _BtnStyle { number, function, operator, danger, filled }

class _CalculatorPageState extends State<CalculatorPage> {
  final TextEditingController _exprController = TextEditingController();

  bool _isDegrees = true;
  bool _historyEnabled = true;
  List<String> _history = [];
  String _result = '';
  String? _error;

  static const List<List<String>> _rows = [
    ['sin', 'cos', 'tan', '(', ')'],
    ['asin', 'acos', 'atan', 'log', 'ln'],
    ['√', 'x²', 'xʸ', 'n!', 'π'],
    ['7', '8', '9', '÷', 'C'],
    ['4', '5', '6', '×', '⌫'],
    ['1', '2', '3', '−', 'e'],
    ['0', '.', '%', '+', '='],
  ];

  static const Map<String, String> _insertMap = {
    'sin': 'sin(',
    'cos': 'cos(',
    'tan': 'tan(',
    'asin': 'asin(',
    'acos': 'acos(',
    'atan': 'atan(',
    'log': 'log(',
    'ln': 'ln(',
    '√': 'sqrt(',
    'x²': '^2',
    'xʸ': '^',
    'n!': '!',
    'π': 'π',
    'e': 'e',
  };

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _exprController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final degrees = await CalculatorPrefs.isDegrees();
    final historyEnabled = await CalculatorPrefs.historyEnabled();
    final history = await CalculatorPrefs.loadHistory();
    if (!mounted) return;
    setState(() {
      _isDegrees = degrees;
      _historyEnabled = historyEnabled;
      _history = history;
    });
    _onExpressionChanged();
  }

  void _onExpressionChanged() {
    final raw = _exprController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _result = '';
        _error = null;
      });
      return;
    }
    try {
      final value = evaluateExpression(raw, degrees: _isDegrees);
      setState(() {
        _result = formatResult(value);
        _error = null;
      });
    } on CalculatorException catch (e) {
      setState(() {
        _result = '';
        // 还没输完时不显示错误
        _error = looksIncomplete(raw) ? null : e.message;
      });
    }
  }

  void _insert(String text) {
    final selection = _exprController.selection;
    final current = _exprController.text;
    final start = selection.isValid ? selection.start : current.length;
    final end = selection.isValid ? selection.end : current.length;
    final newText = current.replaceRange(start, end, text);
    _exprController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _onExpressionChanged();
  }

  void _backspace() {
    final selection = _exprController.selection;
    final current = _exprController.text;
    if (current.isEmpty) return;
    if (selection.isValid && selection.start != selection.end) {
      final newText = current.replaceRange(selection.start, selection.end, '');
      _exprController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start),
      );
    } else {
      final pos = selection.isValid ? selection.start : current.length;
      if (pos == 0) return;
      final newText = current.replaceRange(pos - 1, pos, '');
      _exprController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: pos - 1),
      );
    }
    _onExpressionChanged();
  }

  void _clear() {
    _exprController.clear();
    _onExpressionChanged();
  }

  Future<void> _onEquals() async {
    final raw = _exprController.text.trim();
    if (raw.isEmpty) return;
    try {
      final value = evaluateExpression(raw, degrees: _isDegrees);
      final formatted = formatResult(value);
      await _addToHistory(raw, formatted);
      _exprController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      setState(() {
        _result = '';
        _error = null;
      });
    } on CalculatorException catch (e) {
      setState(() => _error = e.message);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _addToHistory(String expr, String result) async {
    if (!_historyEnabled) return;
    final entry = '$expr = $result';
    final history = List<String>.from(_history)
      ..remove(entry)
      ..insert(0, entry);
    if (history.length > CalculatorPrefs.maxHistory) {
      history.removeRange(
        CalculatorPrefs.maxHistory,
        history.length,
      );
    }
    setState(() => _history = history);
    await CalculatorPrefs.saveHistory(history);
  }

  Future<void> _clearHistory() async {
    await CalculatorPrefs.clearHistory();
    if (!mounted) return;
    setState(() => _history = []);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('历史记录已清空')));
  }

  void _refillFromHistory(String entry) {
    final expr = entry.split(' = ').first;
    _exprController.value = TextEditingValue(
      text: expr,
      selection: TextSelection.collapsed(offset: expr.length),
    );
    _onExpressionChanged();
  }

  void _onKeyPressed(String label) {
    switch (label) {
      case 'C':
        _clear();
      case '⌫':
        _backspace();
      case '=':
        _onEquals();
      default:
        _insert(_insertMap[label] ?? label);
    }
  }

  _BtnStyle _styleFor(String label) {
    if (label == '=') return _BtnStyle.filled;
    if (label == 'C' || label == '⌫') return _BtnStyle.danger;
    if (label == '÷' || label == '×' || label == '−' || label == '+') {
      return _BtnStyle.operator;
    }
    if (RegExp(r'^[0-9.]$').hasMatch(label)) return _BtnStyle.number;
    return _BtnStyle.function;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('科学计算器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CalculatorSettingsPage(),
                ),
              );
              await _loadPrefs();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 显示区
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('DEG')),
                        ButtonSegment(value: false, label: Text('RAD')),
                      ],
                      selected: {_isDegrees},
                      showSelectedIcon: false,
                      onSelectionChanged: (selected) async {
                        final value = selected.first;
                        setState(() => _isDegrees = value);
                        await CalculatorPrefs.setDegrees(value);
                        _onExpressionChanged();
                      },
                    ),
                    const Spacer(),
                    if (_result.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: '复制结果',
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _result),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('结果已复制')),
                            );
                          }
                        },
                      ),
                  ],
                ),
                TextField(
                  controller: _exprController,
                  readOnly: true,
                  showCursor: true,
                  maxLines: 2,
                  minLines: 1,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 28),
                  decoration: const InputDecoration(
                    hintText: '输入表达式',
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => _onExpressionChanged(),
                ),
                SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _error != null
                        ? Text(
                            _error!,
                            style: TextStyle(
                              fontSize: 16,
                              color: colorScheme.error,
                            ),
                          )
                        : Text(
                            _result.isEmpty ? '' : '= $_result',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 历史记录
          if (_historyEnabled && _history.isNotEmpty)
            SizedBox(
              height: 136,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                    child: Row(
                      children: [
                        Text(
                          '历史记录',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _clearHistory,
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final entry = _history[index];
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(
                            entry,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: '删除这条',
                            onPressed: () async {
                              final history = List<String>.from(_history)
                                ..removeAt(index);
                              setState(() => _history = history);
                              await CalculatorPrefs.saveHistory(history);
                            },
                          ),
                          onTap: () => _refillFromHistory(entry),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          if (_historyEnabled && _history.isNotEmpty)
            const Divider(height: 1),
          // 按键区（5 列）
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: _rows
                    .map(
                      (row) => Expanded(
                        child: Row(
                          children: row
                              .map((label) => _KeyButton(
                                    label: label,
                                    style: _styleFor(label),
                                    onPressed: () => _onKeyPressed(label),
                                  ))
                              .toList(),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final _BtnStyle style;
  final VoidCallback onPressed;

  const _KeyButton({
    required this.label,
    required this.style,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    late final Color background;
    late final Color foreground;
    switch (style) {
      case _BtnStyle.filled:
        background = colorScheme.primary;
        foreground = colorScheme.onPrimary;
      case _BtnStyle.danger:
        background = colorScheme.errorContainer;
        foreground = colorScheme.onErrorContainer;
      case _BtnStyle.operator:
        background = colorScheme.secondaryContainer;
        foreground = colorScheme.onSecondaryContainer;
      case _BtnStyle.function:
        background = colorScheme.surfaceContainer;
        foreground = colorScheme.onSurface;
      case _BtnStyle.number:
        background = colorScheme.surfaceContainerHighest;
        foreground = colorScheme.onSurface;
    }
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: style == _BtnStyle.filled
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
