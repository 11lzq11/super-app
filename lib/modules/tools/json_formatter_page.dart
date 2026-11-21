import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// JSON 格式化 / 校验：输入框 + 格式化按钮 + 错误提示。
class JsonFormatterPage extends StatefulWidget {
  const JsonFormatterPage({super.key});

  @override
  State<JsonFormatterPage> createState() => _JsonFormatterPageState();
}

class _JsonFormatterPageState extends State<JsonFormatterPage> {
  final TextEditingController _inputController = TextEditingController();
  String _output = '';
  String? _error;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _format({required bool minify}) {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output = '';
        _error = '请先输入 JSON 内容';
      });
      return;
    }
    try {
      final decoded = jsonDecode(text);
      final encoder = minify
          ? const JsonEncoder()
          : const JsonEncoder.withIndent('  ');
      setState(() {
        _output = encoder.convert(decoded);
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _output = '';
        _error = 'JSON 格式错误：${e.message}';
      });
    }
  }

  void _clear() {
    _inputController.clear();
    setState(() {
      _output = '';
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    if (_output.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _output));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('JSON 格式化')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _inputController,
            decoration: const InputDecoration(
              hintText: '在此粘贴 JSON 内容…',
              alignLabelWithHint: true,
            ),
            style: const TextStyle(fontFamily: 'monospace'),
            minLines: 6,
            maxLines: 10,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () => _format(minify: false),
                child: const Text('格式化'),
              ),
              OutlinedButton(
                onPressed: () => _format(minify: true),
                child: const Text('压缩'),
              ),
              TextButton(
                onPressed: _clear,
                child: const Text('清空'),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                error,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
          if (_output.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '结果',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: '复制结果',
                  onPressed: _copyOutput,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: SelectableText(
                _output,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
