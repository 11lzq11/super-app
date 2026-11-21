/// 单位转换独立设置页：结果小数位数、默认分类。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'converter_data.dart';

class ConverterSettingsPage extends StatefulWidget {
  const ConverterSettingsPage({super.key});

  @override
  State<ConverterSettingsPage> createState() => _ConverterSettingsPageState();
}

class _ConverterSettingsPageState extends State<ConverterSettingsPage> {
  int _decimals = ConverterPrefs.defaultDecimals;
  String _defaultCategoryId = ConverterPrefs.defaultCategoryId;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _decimals =
          prefs.getInt(ConverterPrefs.decimalsKey) ??
          ConverterPrefs.defaultDecimals;
      _defaultCategoryId =
          prefs.getString(ConverterPrefs.defaultCategoryKey) ??
          ConverterPrefs.defaultCategoryId;
      _loaded = true;
    });
  }

  Future<void> _saveDecimals(int value) async {
    setState(() => _decimals = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(ConverterPrefs.decimalsKey, value);
  }

  Future<void> _saveDefaultCategory(String value) async {
    setState(() => _defaultCategoryId = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ConverterPrefs.defaultCategoryKey, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('单位转换设置')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '显示',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Expanded(child: Text('结果小数位数')),
                      DropdownButton<int>(
                        value: _decimals,
                        items: List.generate(
                          11,
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text('$i 位'),
                          ),
                        ),
                        onChanged: (value) {
                          if (value != null) _saveDecimals(value);
                        },
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    '超出位数时截断显示，尾随的 0 会自动去掉。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                const Divider(height: 32),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '默认分类',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_defaultCategoryId),
                    initialValue: _defaultCategoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '打开单位转换时默认显示的分类',
                      border: OutlineInputBorder(),
                    ),
                    items: converterCategories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) _saveDefaultCategory(value);
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
