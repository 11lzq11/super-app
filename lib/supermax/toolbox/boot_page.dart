import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../root_shell.dart';
import '../supermax_service.dart';
import '../toolbox_commands.dart';

/// 开机自启管理：列出声明了 BOOT_COMPLETED 的接收器，可禁止 / 允许。
///
/// 已禁止的接收器 pm query-receivers 查不到，所以单独存在
/// SharedPreferences 里，页面加载时与查询结果合并展示。
class BootManagerPage extends StatefulWidget {
  final SuperMaxService service;

  const BootManagerPage({super.key, required this.service});

  @override
  State<BootManagerPage> createState() => _BootManagerPageState();
}

class _BootManagerPageState extends State<BootManagerPage> {
  static const String _prefsKey = 'toolbox_disabled_boot_receivers';

  bool _loading = true;
  String? _error;
  List<BootReceiver> _queried = [];
  Set<String> _disabledNames = {};
  String _busyName = '';

  @override
  void initState() {
    super.initState();
    _load(showLoading: true);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _failText(RootCommandResult? result) {
    if (result == null) return 'Super MAX 未开启';
    final err = result.stderr.trim();
    return err.isEmpty ? '退出码 ${result.exitCode}' : err;
  }

  /// 仍在生效的接收器：查询结果中去掉已禁止的。
  List<BootReceiver> get _activeReceivers => _queried
      .where((r) => !_disabledNames.contains(r.fullName))
      .toList();

  /// 已禁止的接收器：从 SharedPreferences 存的完整组件名解析回来。
  List<BootReceiver> get _disabledReceivers {
    final list = <BootReceiver>[];
    for (final fullName in _disabledNames) {
      final slash = fullName.indexOf('/');
      if (slash <= 0 || slash == fullName.length - 1) continue;
      list.add(
        BootReceiver(
          packageName: fullName.substring(0, slash),
          componentName: fullName.substring(slash + 1),
        ),
      );
    }
    list.sort((a, b) {
      final byPkg = a.packageName.compareTo(b.packageName);
      if (byPkg != 0) return byPkg;
      return a.componentName.compareTo(b.componentName);
    });
    return list;
  }

  Future<Set<String>> _loadDisabledNames() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveDisabledNames(Set<String> names) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(names.toList()));
    } catch (_) {
      // 保存失败不影响主流程。
    }
  }

  Future<void> _load({bool showLoading = false}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final disabled = await _loadDisabledNames();
    final result =
        await widget.service.runRootCommand(bootReceiversCommand());
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
        _error = '读取开机接收器失败：${_failText(result)}';
      });
      return;
    }
    setState(() {
      _queried = parseBootReceivers(result.stdout);
      _disabledNames = disabled;
      _loading = false;
      _error = null;
    });
  }

  Future<bool> _confirm({
    required String title,
    required String content,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _disable(BootReceiver receiver) async {
    final confirmed = await _confirm(
      title: '禁止开机启动？',
      content: '将禁止 ${receiver.fullName} 接收开机广播，该应用可能无法自启。',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyName = receiver.fullName);
    final result = await widget.service.runRootCommand(
      bootReceiverSet(receiver, false).command,
    );
    if (!mounted) return;
    setState(() => _busyName = '');
    if (result == null || !result.success) {
      _snack('禁止失败：${_failText(result)}');
      return;
    }
    final updated = Set<String>.of(_disabledNames)..add(receiver.fullName);
    await _saveDisabledNames(updated);
    if (!mounted) return;
    setState(() => _disabledNames = updated);
    _snack('已禁止：${receiver.fullName}');
  }

  Future<void> _enable(BootReceiver receiver) async {
    final confirmed = await _confirm(
      title: '允许开机启动？',
      content: '将恢复 ${receiver.fullName} 接收开机广播。',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyName = receiver.fullName);
    final result = await widget.service.runRootCommand(
      bootReceiverSet(receiver, true).command,
    );
    if (!mounted) return;
    setState(() => _busyName = '');
    if (result == null || !result.success) {
      _snack('允许失败：${_failText(result)}');
      return;
    }
    final updated = Set<String>.of(_disabledNames)
      ..remove(receiver.fullName);
    await _saveDisabledNames(updated);
    if (!mounted) return;
    setState(() => _disabledNames = updated);
    _snack('已允许：${receiver.fullName}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('开机自启管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
            onPressed: _loading ? null : () => _load(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => _load(showLoading: true),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final active = _activeReceivers;
    final disabled = _disabledReceivers;
    final grouped = <String, List<BootReceiver>>{};
    for (final receiver in active) {
      grouped.putIfAbsent(receiver.packageName, () => []).add(receiver);
    }
    final packageNames = grouped.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '共 ${active.length + disabled.length} 个开机接收器，'
          '其中已禁止 ${disabled.length} 个。',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        const Text(
          '开机接收器',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (active.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '没有找到声明了开机启动的接收器',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          for (final packageName in packageNames)
            _buildPackageCard(packageName, grouped[packageName]!),
        const SizedBox(height: 16),
        const Text(
          '已禁止',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (disabled.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '暂无已禁止的接收器',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final receiver in disabled)
                  _buildReceiverRow(
                    receiver: receiver,
                    actionLabel: '允许',
                    onAction: () => _enable(receiver),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          '禁用后应用收不到开机广播，可能无法自启；'
          '部分系统应用禁用后可能影响功能。',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildPackageCard(
    String packageName,
    List<BootReceiver> receivers,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              packageName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          for (final receiver in receivers)
            _buildReceiverRow(
              receiver: receiver,
              actionLabel: '禁止',
              onAction: () => _disable(receiver),
            ),
        ],
      ),
    );
  }

  Widget _buildReceiverRow({
    required BootReceiver receiver,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final busy = _busyName == receiver.fullName;
    return ListTile(
      title: Text(
        receiver.fullName,
        style: const TextStyle(fontSize: 13),
      ),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : OutlinedButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
    );
  }
}
