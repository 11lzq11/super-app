import 'package:flutter/material.dart';

import '../root_shell.dart';
import '../supermax_service.dart';
import '../toolbox_commands.dart';

/// 系统设置管理：浏览、修改、新增、删除 settings 表里的键值对。
///
/// 表可选 system / secure / global（默认 system）。
/// 加载用 settingsListCommand + parseSettingsList，
/// 修改、新增用 settingsPut，删除用 settingsDelete。
class SettingsBrowserPage extends StatefulWidget {
  final SuperMaxService service;

  const SettingsBrowserPage({super.key, required this.service});

  @override
  State<SettingsBrowserPage> createState() => _SettingsBrowserPageState();
}

class _SettingsBrowserPageState extends State<SettingsBrowserPage> {
  final _searchController = TextEditingController();

  String _table = 'system';
  Map<String, String> _entries = {};
  List<MapEntry<String, String>> _filtered = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _loadEntries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final keyword = _searchController.text.trim().toLowerCase();
    setState(() {
      final all = _entries.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      _filtered = keyword.isEmpty
          ? all
          : all
                .where((e) => e.key.toLowerCase().contains(keyword))
                .toList();
    });
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.service.runRootCommand(
      settingsListCommand(_table),
    );
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _loading = false;
        _error = 'Super MAX 未开启';
      });
      return;
    }
    if (!result.success) {
      setState(() {
        _loading = false;
        _error =
            '读取设置列表失败：${result.stderr.trim().isEmpty ? '退出码 ${result.exitCode}' : result.stderr.trim()}';
      });
      return;
    }
    setState(() {
      _entries = parseSettingsList(result.stdout);
      _loading = false;
    });
    _applyFilter();
  }

  String _failureMessage(Object? result) {
    if (result == null) return 'Super MAX 未开启';
    final r = result as RootCommandResult;
    return r.stderr.trim().isEmpty
        ? '退出码 ${r.exitCode}'
        : r.stderr.trim();
  }

  /// 执行一条 settings 命令；高危命令先弹窗确认。
  Future<RootCommandResult?> _execute(SystemCommand cmd) async {
    if (RootShell.isDangerous(cmd.command)) {
      final confirmed = await showRootCommandConfirmDialog(
        context,
        cmd.command,
        dangerous: true,
      );
      if (!confirmed || !mounted) return null;
    }
    return widget.service.runRootCommand(cmd.command);
  }

  Future<void> _editEntry(String key, String currentValue) async {
    final valueController = TextEditingController(text: currentValue);
    final newValue = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('修改 $key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (settingsKeyLabel(key) != key) Text(settingsKeyLabel(key)),
            if (settingsKeyLabel(key) != key) const SizedBox(height: 8),
            TextField(
              controller: valueController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '值',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(valueController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    valueController.dispose();
    if (newValue == null || !mounted) return;
    if (newValue == currentValue) return;
    setState(() => _busy = true);
    final cmd = settingsPut(_table, key, newValue);
    final result = await _execute(cmd);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消或 Super MAX 未开启')),
      );
      return;
    }
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('修改失败：${_failureMessage(result)}')),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已将 $key 改为 $newValue')));
    _loadEntries();
  }

  Future<void> _deleteEntry(String key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除设置？'),
        content: Text('将删除 $_table 表里的 $key，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final result = await _execute(settingsDelete(_table, key));
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消或 Super MAX 未开启')),
      );
      return;
    }
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：${_failureMessage(result)}')),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已删除 $key')));
    _loadEntries();
  }

  Future<void> _addEntry() async {
    final keyController = TextEditingController();
    final valueController = TextEditingController();
    String? keyError;
    final values = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('新增设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '键名',
                  hintText: '字母、数字、下划线',
                  errorText: keyError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueController,
                decoration: const InputDecoration(
                  labelText: '值',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final key = keyController.text.trim();
                if (!isValidSettingsKey(key)) {
                  setDialogState(() {
                    keyError = '键名不合法：只允许字母、数字、下划线';
                  });
                  return;
                }
                Navigator.of(
                  dialogContext,
                ).pop((key, valueController.text));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    keyController.dispose();
    valueController.dispose();
    if (values == null || !mounted) return;
    final (key, value) = values;
    setState(() => _busy = true);
    final result = await _execute(settingsPut(_table, key, value));
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消或 Super MAX 未开启')),
      );
      return;
    }
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新增失败：${_failureMessage(result)}')),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已新增 $key')));
    _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统设置管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '新增',
            onPressed: _busy ? null : _addEntry,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新列表',
            onPressed: _loading ? null : _loadEntries,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                DropdownButton<String>(
                  value: _table,
                  items: [
                    for (final table in settingsTables)
                      DropdownMenuItem(value: table, child: Text(table)),
                  ],
                  onChanged: (value) {
                    if (value == null || value == _table) return;
                    setState(() => _table = value);
                    _loadEntries();
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: '搜索设置键名…',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _loadEntries, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('该表里没有任何设置'));
    }
    if (_filtered.isEmpty) {
      return const Center(child: Text('没有匹配的设置'));
    }
    return ListView.separated(
      itemCount: _filtered.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = _filtered[index];
        final label = settingsKeyLabel(entry.key);
        return ListTile(
          title: Text(entry.key, style: const TextStyle(fontSize: 13)),
          subtitle: Text(
            label != entry.key ? '$label：${entry.value}' : entry.value,
            style: const TextStyle(fontSize: 13),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '删除',
            onPressed: _busy
                ? null
                : () => _deleteEntry(entry.key),
          ),
          onTap: _busy ? null : () => _editEntry(entry.key, entry.value),
        );
      },
    );
  }
}
