import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 密码生成器：长度滑块、字符集开关、生成 + 复制。
class PasswordGeneratorPage extends StatefulWidget {
  const PasswordGeneratorPage({super.key});

  @override
  State<PasswordGeneratorPage> createState() => _PasswordGeneratorPageState();
}

class _PasswordGeneratorPageState extends State<PasswordGeneratorPage> {
  static const String _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const String _digits = '0123456789';
  static const String _symbols = '!@#\$%^&*()-_=+[]{};:,.<>?/';

  double _length = 16;
  bool _useUpper = true;
  bool _useLower = true;
  bool _useDigits = true;
  bool _useSymbols = true;
  String _password = '';

  @override
  void initState() {
    super.initState();
    _generate();
  }

  String get _charset {
    final buffer = StringBuffer();
    if (_useUpper) buffer.write(_upper);
    if (_useLower) buffer.write(_lower);
    if (_useDigits) buffer.write(_digits);
    if (_useSymbols) buffer.write(_symbols);
    return buffer.toString();
  }

  /// 熵（bit）= 长度 × log2(字符集大小)，用于强度提示。
  double get _entropy {
    final size = _charset.length;
    if (size <= 1 || _password.isEmpty) return 0;
    return _length * (log(size) / log(2));
  }

  String get _strengthLabel {
    final entropy = _entropy;
    if (entropy < 40) return '弱';
    if (entropy < 64) return '一般';
    if (entropy < 100) return '强';
    return '很强';
  }

  Color _strengthColor(BuildContext context) {
    final entropy = _entropy;
    final scheme = Theme.of(context).colorScheme;
    if (entropy < 40) return scheme.error;
    if (entropy < 64) return Colors.orange;
    return Colors.green;
  }

  void _generate() {
    final charset = _charset;
    if (charset.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一种字符')),
      );
      return;
    }
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < _length.round(); i++) {
      buffer.write(charset[random.nextInt(charset.length)]);
    }
    setState(() => _password = buffer.toString());
  }

  Future<void> _copy() async {
    if (_password.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _password));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('密码生成器')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _password,
                          style: const TextStyle(
                            fontSize: 18,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: '复制',
                        onPressed: _copy,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '强度：$_strengthLabel',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '约 ${_entropy.toStringAsFixed(0)} bit',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (_entropy / 128).clamp(0.0, 1.0),
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: _strengthColor(context),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('长度'),
              Text(
                _length.round().toString(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          Slider(
            value: _length,
            min: 8,
            max: 64,
            divisions: 56,
            label: _length.round().toString(),
            onChanged: (value) {
              setState(() => _length = value);
              _generate();
            },
          ),
          SwitchListTile(
            title: const Text('大写字母 (A-Z)'),
            value: _useUpper,
            onChanged: (value) {
              setState(() => _useUpper = value);
              _generate();
            },
          ),
          SwitchListTile(
            title: const Text('小写字母 (a-z)'),
            value: _useLower,
            onChanged: (value) {
              setState(() => _useLower = value);
              _generate();
            },
          ),
          SwitchListTile(
            title: const Text('数字 (0-9)'),
            value: _useDigits,
            onChanged: (value) {
              setState(() => _useDigits = value);
              _generate();
            },
          ),
          SwitchListTile(
            title: const Text('符号 (!@#...)'),
            value: _useSymbols,
            onChanged: (value) {
              setState(() => _useSymbols = value);
              _generate();
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('重新生成'),
            onPressed: _generate,
          ),
        ],
      ),
    );
  }
}
