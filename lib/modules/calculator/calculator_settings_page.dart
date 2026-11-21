/// 科学计算器独立设置页：角度单位默认、历史记录开关、清空历史。
library;

import 'package:flutter/material.dart';

import 'calculator_prefs.dart';

class CalculatorSettingsPage extends StatefulWidget {
  const CalculatorSettingsPage({super.key});

  @override
  State<CalculatorSettingsPage> createState() =>
      _CalculatorSettingsPageState();
}

class _CalculatorSettingsPageState extends State<CalculatorSettingsPage> {
  bool _isDegrees = true;
  bool _historyEnabled = true;
  int _historyCount = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final degrees = await CalculatorPrefs.isDegrees();
    final historyEnabled = await CalculatorPrefs.historyEnabled();
    final history = await CalculatorPrefs.loadHistory();
    if (!mounted) return;
    setState(() {
      _isDegrees = degrees;
      _historyEnabled = historyEnabled;
      _historyCount = history.length;
      _loaded = true;
    });
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空历史记录'),
        content: const Text('确定要清空全部计算历史记录吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CalculatorPrefs.clearHistory();
    if (!mounted) return;
    setState(() => _historyCount = 0);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('历史记录已清空')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('计算器设置')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '角度单位',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('默认角度单位（三角函数按此计算）'),
                      ),
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
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 32),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '历史记录',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                SwitchListTile(
                  title: const Text('保存计算历史'),
                  subtitle: const Text('关闭后不再记录新的计算历史'),
                  value: _historyEnabled,
                  onChanged: (value) async {
                    setState(() => _historyEnabled = value);
                    await CalculatorPrefs.setHistoryEnabled(value);
                  },
                ),
                ListTile(
                  title: const Text('清空历史记录'),
                  subtitle: Text('当前共 $_historyCount 条'),
                  trailing: TextButton(
                    onPressed: _historyCount == 0
                        ? null
                        : _confirmClearHistory,
                    child: const Text('清空'),
                  ),
                ),
              ],
            ),
    );
  }
}
