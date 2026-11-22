import 'package:flutter/material.dart';

import '../root_shell.dart';
import '../supermax_service.dart';
import '../toolbox_commands.dart';

/// 广告屏蔽：向 hosts 写入屏蔽规则，支持备份与恢复。
///
/// hosts 位置按以下顺序确定：系统 hosts 可写时直接用它；
/// 否则用 systemless 模块 hosts（存在时无需重新挂载）；
/// 都不满足时仍用系统 hosts，但写操作前需先重新挂载 /system 为可写。
class AdBlockPage extends StatefulWidget {
  final SuperMaxService service;

  const AdBlockPage({super.key, required this.service});

  @override
  State<AdBlockPage> createState() => _AdBlockPageState();
}

class _AdBlockPageState extends State<AdBlockPage> {
  bool _loading = true;
  String? _error;
  bool _busy = false;

  String _hostsPath = hostsSystemPath;
  bool _needsRemount = false;
  bool _writable = false;
  int _blockedCount = 0;
  List<String> _preview = [];
  String? _readError;

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

  Future<void> _load({bool showLoading = false}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final writableResult = await widget.service
        .runRootCommand(hostsWritableCheckCommand(hostsSystemPath));
    if (!mounted) return;
    if (writableResult == null) {
      setState(() {
        _loading = false;
        _error = 'Super MAX 未开启';
      });
      return;
    }
    var path = hostsSystemPath;
    var needsRemount = false;
    var writable = false;
    if (writableResult.success &&
        writableResult.stdout.trim() == 'yes') {
      writable = true;
    } else {
      final moduleResult = await widget.service
          .runRootCommand('ls $hostsModulePath');
      if (moduleResult != null && moduleResult.success) {
        path = hostsModulePath;
        final moduleWritable = await widget.service
            .runRootCommand(hostsWritableCheckCommand(hostsModulePath));
        writable = moduleWritable != null &&
            moduleWritable.success &&
            moduleWritable.stdout.trim() == 'yes';
      } else {
        needsRemount = true;
      }
    }
    final readResult =
        await widget.service.runRootCommand(hostsReadCommand(path));
    if (!mounted) return;
    var blocked = 0;
    var preview = <String>[];
    String? readError;
    if (readResult == null) {
      readError = 'Super MAX 未开启';
    } else if (!readResult.success) {
      readError = '读取 hosts 失败：${_failText(readResult)}';
    } else {
      final lines = readResult.stdout.split('\n');
      blocked = lines
          .where((line) => line.trimLeft().startsWith('0.0.0.0'))
          .length;
      preview = lines.take(50).toList();
    }
    setState(() {
      _hostsPath = path;
      _needsRemount = needsRemount;
      _writable = writable;
      _blockedCount = blocked;
      _preview = preview;
      _readError = readError;
      _loading = false;
      _error = null;
    });
  }

  Future<bool> _backupExists() async {
    final result = await widget.service.runRootCommand(
      'test -f $hostsBackupPath && echo yes || echo no',
    );
    return result != null &&
        result.success &&
        result.stdout.trim() == 'yes';
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

  /// 检查备份是否存在（不存在则先备份）→ 需要时先重新挂载
  /// → 再执行目标命令。任一步失败返回 false 并弹提示。
  Future<bool> _runWithPrereqs(SystemCommand target) async {
    setState(() => _busy = true);
    try {
      if (!await _backupExists()) {
        final backup = hostsBackup(_hostsPath);
        final backupResult =
            await widget.service.runRootCommand(backup.command);
        if (backupResult == null || !backupResult.success) {
          _snack('备份 hosts 失败：${_failText(backupResult)}');
          return false;
        }
      }
      if (_needsRemount) {
        if (!mounted) return false;
        final remount = hostsRemount();
        final confirmed = await showRootCommandConfirmDialog(
          context,
          remount.command,
          dangerous: true,
        );
        if (!confirmed) return false;
        final remountResult =
            await widget.service.runRootCommand(remount.command);
        if (remountResult == null || !remountResult.success) {
          _snack('重新挂载失败：${_failText(remountResult)}');
          return false;
        }
      }
      final result = await widget.service.runRootCommand(target.command);
      if (result == null || !result.success) {
        _snack('执行失败：${_failText(result)}');
        return false;
      }
      return true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 拼确认框里关于备份与重新挂载的补充说明。
  Future<List<String>> _prereqNotes() async {
    final notes = <String>[];
    if (!await _backupExists()) {
      notes.add('当前没有备份，将先备份当前 hosts 到 $hostsBackupPath。');
    }
    if (_needsRemount) {
      notes.add('需要先重新挂载 /system 为可写（高危操作，会再次弹窗确认）。');
    }
    return notes;
  }

  Future<void> _backupHosts() async {
    final confirmed = await _confirm(
      title: '备份 hosts？',
      content: '将当前 hosts（$_hostsPath）备份到 $hostsBackupPath。',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final cmd = hostsBackup(_hostsPath);
    final result = await widget.service.runRootCommand(cmd.command);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == null || !result.success) {
      _snack('备份失败：${_failText(result)}');
      return;
    }
    _snack('hosts 已备份到 $hostsBackupPath');
  }

  Future<void> _applyBlockRules() async {
    final notes = await _prereqNotes();
    if (!mounted) return;
    final confirmed = await _confirm(
      title: '应用屏蔽规则？',
      content: '将向 $_hostsPath 写入 ${adBlockDomains.length} 条屏蔽规则'
          '（已存在的域名会跳过）。\n${notes.join('\n')}',
    );
    if (!confirmed || !mounted) return;
    final ok = await _runWithPrereqs(hostsApply(_hostsPath, adBlockDomains));
    if (!mounted) return;
    if (ok) {
      _snack('屏蔽规则已应用');
      await _load();
    }
  }

  Future<void> _restoreHosts() async {
    if (!await _backupExists()) {
      _snack('暂无备份，请先备份 hosts');
      return;
    }
    if (!mounted) return;
    final notes = await _prereqNotes();
    if (!mounted) return;
    final confirmed = await _confirm(
      title: '恢复备份？',
      content: '将用备份 $hostsBackupPath 覆盖当前 hosts（$_hostsPath）。'
          '\n${notes.join('\n')}',
    );
    if (!confirmed || !mounted) return;
    final ok = await _runWithPrereqs(hostsRestore(_hostsPath));
    if (!mounted) return;
    if (ok) {
      _snack('hosts 已从备份恢复');
      await _load();
    }
  }

  Future<void> _addDomain() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加自定义域名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: '例如 ads.example.com',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) =>
              Navigator.of(dialogContext).pop(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (input == null || !mounted) return;
    final domain = input.trim().toLowerCase();
    if (!isValidDomain(domain)) {
      _snack('域名不合法：$domain');
      return;
    }
    final notes = await _prereqNotes();
    if (!mounted) return;
    final confirmed = await _confirm(
      title: '屏蔽该域名？',
      content: '将向 $_hostsPath 写入屏蔽规则：0.0.0.0 $domain。'
          '\n${notes.join('\n')}',
    );
    if (!confirmed || !mounted) return;
    final ok = await _runWithPrereqs(hostsApply(_hostsPath, [domain]));
    if (!mounted) return;
    if (ok) {
      _snack('已屏蔽 $domain');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('广告屏蔽'),
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
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildStatusCard(),
                    const SizedBox(height: 16),
                    _buildPreviewCard(),
                    const SizedBox(height: 16),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(),
                      ),
                    _buildActionButton(
                      label: '应用屏蔽规则',
                      icon: Icons.block_rounded,
                      onPressed: _applyBlockRules,
                      filled: true,
                    ),
                    const SizedBox(height: 8),
                    _buildActionButton(
                      label: '备份 hosts',
                      icon: Icons.backup_rounded,
                      onPressed: _backupHosts,
                    ),
                    const SizedBox(height: 8),
                    _buildActionButton(
                      label: '恢复备份',
                      icon: Icons.restore_rounded,
                      onPressed: _restoreHosts,
                    ),
                    const SizedBox(height: 8),
                    _buildActionButton(
                      label: '添加自定义域名',
                      icon: Icons.add_rounded,
                      onPressed: _addDomain,
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '当前状态',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _infoRow('hosts 路径', _hostsPath),
            _infoRow('是否可写', _writable ? '是' : '否'),
            _infoRow(
              '重新挂载',
              _needsRemount ? '写入前需要重新挂载 /system' : '不需要',
            ),
            _infoRow('已屏蔽条目', '$_blockedCount 条'),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text(
                  'hosts 内容预览',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '仅预览前 50 行',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _readError ?? _preview.join('\n'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            if (_readError == null && _preview.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'hosts 文件为空。',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Future<void> Function() onPressed,
    bool filled = false,
  }) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton(
              onPressed: _busy ? null : onPressed,
              child: child,
            )
          : OutlinedButton(
              onPressed: _busy ? null : onPressed,
              child: child,
            ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
