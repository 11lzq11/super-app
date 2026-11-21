/// 函数绘制独立设置页：网格开关、默认 X 轴范围。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plotter_engine.dart';

class PlotterSettingsPage extends StatefulWidget {
  const PlotterSettingsPage({super.key});

  @override
  State<PlotterSettingsPage> createState() => _PlotterSettingsPageState();
}

class _PlotterSettingsPageState extends State<PlotterSettingsPage> {
  final TextEditingController _xMinController = TextEditingController();
  final TextEditingController _xMaxController = TextEditingController();

  bool _showGrid = PlotterPrefs.defaultShowGrid;
  bool _loaded = false;
  String? _rangeError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _xMinController.dispose();
    _xMaxController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showGrid =
          prefs.getBool(PlotterPrefs.showGridKey) ?? PlotterPrefs.defaultShowGrid;
      _xMinController.text =
          (prefs.getDouble(PlotterPrefs.xMinKey) ?? PlotterPrefs.defaultXMin)
              .toString();
      _xMaxController.text =
          (prefs.getDouble(PlotterPrefs.xMaxKey) ?? PlotterPrefs.defaultXMax)
              .toString();
      _loaded = true;
    });
  }

  Future<void> _saveGrid(bool value) async {
    setState(() => _showGrid = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PlotterPrefs.showGridKey, value);
  }

  Future<void> _saveRange() async {
    final min = double.tryParse(_xMinController.text.trim());
    final max = double.tryParse(_xMaxController.text.trim());
    if (min == null || max == null) {
      setState(() => _rangeError = '请输入数字');
      return;
    }
    if (min >= max) {
      setState(() => _rangeError = '最小值必须小于最大值');
      return;
    }
    setState(() => _rangeError = null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(PlotterPrefs.xMinKey, min);
    await prefs.setDouble(PlotterPrefs.xMaxKey, max);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('默认 X 轴范围已保存')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('函数绘制设置')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  title: const Text('显示网格'),
                  subtitle: const Text('画布上显示网格线和刻度'),
                  value: _showGrid,
                  onChanged: _saveGrid,
                ),
                const Divider(height: 32),
                const Text(
                  '默认 X 轴范围',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _xMinController,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.\-]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: '最小值',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _xMaxController,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.\-]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: '最大值',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_rangeError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _rangeError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saveRange,
                  child: const Text('保存范围'),
                ),
                const SizedBox(height: 8),
                const Text(
                  '打开函数绘制或点「重置视图」时按此范围显示。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
    );
  }
}
