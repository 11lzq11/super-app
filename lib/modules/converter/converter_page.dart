/// 单位转换页面：分类下拉 + 源/目标单位下拉 + 交换按钮 + 实时换算 + 公式展示。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'converter_data.dart';
import 'converter_settings_page.dart';

class ConverterPage extends StatefulWidget {
  const ConverterPage({super.key});

  @override
  State<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends State<ConverterPage> {
  final TextEditingController _inputController = TextEditingController();

  List<ConvCategory> get _categories => converterCategories;

  ConvCategory? _category;
  ConvUnit? _fromUnit;
  ConvUnit? _toUnit;
  int _decimals = ConverterPrefs.defaultDecimals;
  String _result = '';
  String? _hint;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final decimals =
        prefs.getInt(ConverterPrefs.decimalsKey) ??
        ConverterPrefs.defaultDecimals;
    final defaultCategoryId =
        prefs.getString(ConverterPrefs.defaultCategoryKey) ??
        ConverterPrefs.defaultCategoryId;
    if (!mounted) return;
    final category = _categories.firstWhere(
      (c) => c.id == defaultCategoryId,
      orElse: () => _categories.first,
    );
    setState(() {
      _decimals = decimals;
      _selectCategory(category, keepUnits: false);
    });
    _recalculate();
  }

  void _selectCategory(ConvCategory category, {bool keepUnits = false}) {
    _category = category;
    if (!keepUnits || _fromUnit == null || _toUnit == null) {
      _fromUnit = category.units.first;
      _toUnit = category.units.length > 1
          ? category.units[1]
          : category.units.first;
    }
  }

  void _recalculate() {
    final category = _category;
    final from = _fromUnit;
    final to = _toUnit;
    final raw = _inputController.text.trim();
    if (category == null || from == null || to == null) {
      setState(() {
        _result = '';
        _hint = null;
      });
      return;
    }
    if (raw.isEmpty) {
      setState(() {
        _result = '';
        _hint = '请输入数值';
      });
      return;
    }
    final value = double.tryParse(raw);
    if (value == null) {
      setState(() {
        _result = '';
        _hint = '输入无效，请输入数字';
      });
      return;
    }
    try {
      final converted = convertValue(category, from, to, value);
      setState(() {
        _result = formatConverted(converted, decimals: _decimals);
        _hint = null;
      });
    } catch (_) {
      setState(() {
        _result = '';
        _hint = '换算失败';
      });
    }
  }

  void _swapUnits() {
    setState(() {
      final temp = _fromUnit;
      _fromUnit = _toUnit;
      _toUnit = temp;
    });
    _recalculate();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = _category;
    final from = _fromUnit;
    final to = _toUnit;
    return Scaffold(
      appBar: AppBar(
        title: const Text('单位转换'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ConverterSettingsPage(),
                ),
              );
              await _loadPrefs();
            },
          ),
        ],
      ),
      body: category == null || from == null || to == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 分类
                DropdownButtonFormField<ConvCategory>(
                  key: ValueKey(category.id),
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '分类',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectCategory(value));
                    _recalculate();
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // 输入 + 源单位
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _inputController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      signed: true,
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.\-]'),
                                  ),
                                ],
                                style: const TextStyle(fontSize: 24),
                                decoration: InputDecoration(
                                  labelText: '输入数值',
                                  border: const OutlineInputBorder(),
                                  suffixIcon: _inputController.text.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(Icons.clear),
                                          tooltip: '清空',
                                          onPressed: () {
                                            _inputController.clear();
                                            _recalculate();
                                            setState(() {});
                                          },
                                        ),
                                ),
                                onChanged: (_) {
                                  _recalculate();
                                  setState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 132,
                              child: DropdownButtonFormField<ConvUnit>(
                                key: ValueKey('${category.id}:${from.id}'),
                                initialValue: from,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: '从',
                                  border: OutlineInputBorder(),
                                ),
                                items: category.units
                                    .map(
                                      (u) => DropdownMenuItem(
                                        value: u,
                                        child: Text(
                                          '${u.name} (${u.symbol})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _fromUnit = value);
                                  _recalculate();
                                },
                              ),
                            ),
                          ],
                        ),
                        // 交换按钮
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: IconButton(
                            icon: const Icon(Icons.swap_vert),
                            tooltip: '交换单位',
                            onPressed: _swapUnits,
                          ),
                        ),
                        // 结果 + 目标单位
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: colorScheme.outline,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _hint ?? _result,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: _hint != null
                                        ? colorScheme.onSurfaceVariant
                                        : colorScheme.primary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 132,
                              child: DropdownButtonFormField<ConvUnit>(
                                key: ValueKey('${category.id}:${to.id}'),
                                initialValue: to,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: '到',
                                  border: OutlineInputBorder(),
                                ),
                                items: category.units
                                    .map(
                                      (u) => DropdownMenuItem(
                                        value: u,
                                        child: Text(
                                          '${u.name} (${u.symbol})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _toUnit = value);
                                  _recalculate();
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 换算公式
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.functions, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            conversionFormula(
                              category,
                              from,
                              to,
                              decimals: _decimals,
                            ),
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (category.isCurrency) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '汇率仅供参考，更新于 $currencyRateDate',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
