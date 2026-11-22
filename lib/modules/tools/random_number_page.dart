import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 随机数：指定范围生成若干随机整数，附带掷骰子、抛硬币快捷方式。
/// 纯 Dart 实现（dart:math），不用任何插件。
class RandomNumberPage extends StatefulWidget {
  const RandomNumberPage({super.key});

  @override
  State<RandomNumberPage> createState() => _RandomNumberPageState();
}

class _RandomNumberPageState extends State<RandomNumberPage> {
  final TextEditingController _minController =
      TextEditingController(text: '1');
  final TextEditingController _maxController =
      TextEditingController(text: '100');
  double _count = 1;
  List<int> _results = [];
  String? _error;

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  int? _parse(TextEditingController controller) {
    return int.tryParse(controller.text.trim());
  }

  void _generate({int? min, int? max, int? count}) {
    final lo = min ?? _parse(_minController);
    final hi = max ?? _parse(_maxController);
    if (lo == null || hi == null) {
      setState(() => _error = '请输入有效的整数范围');
      return;
    }
    if (lo > hi) {
      setState(() => _error = '最小值不能大于最大值');
      return;
    }
    final n = count ?? _count.round();
    final random = Random();
    setState(() {
      _error = null;
      _results = List.generate(n, (_) => lo + random.nextInt(hi - lo + 1));
    });
  }

  void _quickDice() {
    _minController.text = '1';
    _maxController.text = '6';
    setState(() => _count = 1);
    _generate(min: 1, max: 6, count: 1);
  }

  void _quickCoin() {
    final heads = Random().nextBool();
    setState(() {
      _error = null;
      _results = [];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(heads ? '正面' : '反面')),
    );
  }

  Future<void> _copyAll() async {
    if (_results.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: _results.join(', ')),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasResults = _results.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('随机数')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minController,
                  decoration: const InputDecoration(labelText: '最小值'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'-?\d*')),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxController,
                  decoration: const InputDecoration(labelText: '最大值'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'-?\d*')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('生成个数'),
              Text(
                _count.round().toString(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          Slider(
            value: _count,
            min: 1,
            max: 20,
            divisions: 19,
            label: _count.round().toString(),
            onChanged: (value) => setState(() => _count = value),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.casino_outlined),
                label: const Text('生成'),
                onPressed: () => _generate(),
              ),
              OutlinedButton(
                onPressed: _quickDice,
                child: const Text('掷骰子'),
              ),
              OutlinedButton(
                onPressed: _quickCoin,
                child: const Text('抛硬币'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
          if (hasResults) ...[
            const SizedBox(height: 24),
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
                  tooltip: '复制全部',
                  onPressed: _copyAll,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in _results)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      value.toString(),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 24),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.casino_outlined,
                      size: 48,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '设置范围后点「生成」',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
