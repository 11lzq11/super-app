import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 文本工具：实时字数统计 + 大小写转换、反转、清理多余空格。
/// 纯 Dart 实现，不用任何插件。
class TextToolsPage extends StatefulWidget {
  const TextToolsPage({super.key});

  @override
  State<TextToolsPage> createState() => _TextToolsPageState();
}

class _TextToolsPageState extends State<TextToolsPage> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _text => _controller.text;

  /// 词数：按空白切分后的非空段数（中英文都适用）。
  int get _wordCount {
    final trimmed = _text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  int get _lineCount {
    if (_text.isEmpty) return 0;
    return '\n'.allMatches(_text).length + 1;
  }

  void _apply(String Function(String) transform) {
    if (_text.isEmpty) return;
    final selection = _controller.selection;
    _controller.text = transform(_text);
    // 尽量保持光标在原位置附近（不超过新文本长度）。
    final offset = selection.baseOffset.clamp(
      0,
      _controller.text.length,
    );
    _controller.selection = TextSelection.collapsed(offset: offset);
  }

  String _titleCase(String text) {
    return text.replaceAllMapped(
      RegExp(r'\b\w'),
      (m) => m.group(0)!.toUpperCase(),
    );
  }

  Future<void> _copy() async {
    if (_text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  Widget _statCard(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文本工具')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: '在此输入或粘贴文本…',
              alignLabelWithHint: true,
            ),
            minLines: 6,
            maxLines: 12,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statCard('字符', _text.length.toString()),
              const SizedBox(width: 8),
              _statCard('词', _wordCount.toString()),
              const SizedBox(width: 8),
              _statCard('行', _lineCount.toString()),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _text.isEmpty
                    ? null
                    : () => _apply((t) => t.toUpperCase()),
                child: const Text('转大写'),
              ),
              OutlinedButton(
                onPressed: _text.isEmpty
                    ? null
                    : () => _apply((t) => t.toLowerCase()),
                child: const Text('转小写'),
              ),
              OutlinedButton(
                onPressed:
                    _text.isEmpty ? null : () => _apply(_titleCase),
                child: const Text('首字母大写'),
              ),
              OutlinedButton(
                onPressed: _text.isEmpty
                    ? null
                    : () => _apply(
                          (t) => t.split('').reversed.join(),
                        ),
                child: const Text('反转文本'),
              ),
              OutlinedButton(
                onPressed: _text.isEmpty
                    ? null
                    : () => _apply(
                          (t) => t
                              .replaceAll(RegExp(r'[ \t]+'), ' ')
                              .replaceAll(RegExp(r'\n{3,}'), '\n\n')
                              .trim(),
                        ),
                child: const Text('清理多余空格'),
              ),
              TextButton(
                onPressed: _text.isEmpty
                    ? null
                    : () {
                        _controller.clear();
                        setState(() {});
                      },
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('复制全文'),
                onPressed: _text.isEmpty ? null : _copy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
