import 'package:flutter/material.dart';

import '../root_shell.dart';
import '../supermax_service.dart';
import '../toolbox_commands.dart';

/// 应用备份：备份 APK 与 /data/data 数据，并支持从备份恢复。
class AppBackupPage extends StatefulWidget {
  final SuperMaxService service;

  const AppBackupPage({super.key, required this.service});

  @override
  State<AppBackupPage> createState() => _AppBackupPageState();
}

class _AppBackupPageState extends State<AppBackupPage> {
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<String> _packages = [];
  List<String> _filtered = [];
  List<String> _backedUp = [];
  String _busyPackage = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _load(showLoading: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  void _applyFilter() {
    final keyword = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = keyword.isEmpty
          ? List.of(_packages)
          : _packages
              .where((p) => p.toLowerCase().contains(keyword))
              .toList();
    });
  }

  Future<void> _load({bool showLoading = false}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final pkgResult =
        await widget.service.runRootCommand('pm list packages');
    if (!mounted) return;
    if (pkgResult == null) {
      setState(() {
        _loading = false;
        _error = 'Super MAX 未开启';
      });
      return;
    }
    if (!pkgResult.success) {
      setState(() {
        _loading = false;
        _error = '读取应用列表失败：${_failText(pkgResult)}';
      });
      return;
    }
    final packages = parsePmPackages(pkgResult.stdout);
    final backedUp = await _fetchBackups();
    if (!mounted) return;
    setState(() {
      _packages = packages;
      _backedUp = backedUp;
      _loading = false;
      _error = null;
    });
    _applyFilter();
  }

  Future<List<String>> _fetchBackups() async {
    final result =
        await widget.service.runRootCommand(backupListCommand());
    if (result == null || !result.success) return [];
    final names = result.stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList()
      ..sort();
    return names;
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

  Future<void> _backupApp(String packageName) async {
    final confirmed = await _confirm(
      title: '备份应用？',
      content: '将备份 $packageName 的 APK 和 /data/data 数据，数据可能较大。',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyPackage = packageName);
    String? failedStep;
    String? failedDetail;
    try {
      final pathResult = await widget.service
          .runRootCommand(pmPathCommand(packageName));
      final apkPath = pathResult != null && pathResult.success
          ? parsePmPath(pathResult.stdout)
          : null;
      if (apkPath == null) {
        failedStep = '获取 APK 路径';
        failedDetail = _failText(pathResult);
      } else {
        final apkResult = await widget.service.runRootCommand(
          backupApk(packageName, apkPath).command,
        );
        if (apkResult == null || !apkResult.success) {
          failedStep = '备份 APK';
          failedDetail = _failText(apkResult);
        } else {
          final dataResult = await widget.service.runRootCommand(
            backupData(packageName).command,
          );
          if (dataResult == null || !dataResult.success) {
            failedStep = '备份数据';
            failedDetail = _failText(dataResult);
          }
        }
      }
    } finally {
      if (mounted) setState(() => _busyPackage = '');
    }
    if (!mounted) return;
    if (failedStep == null) {
      _snack('备份成功：$packageName');
      await _load();
    } else {
      _snack('备份失败（$failedStep）：$failedDetail');
    }
  }

  Future<void> _showBackupDetail(String packageName) async {
    final dir = backupDirFor(packageName);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          packageName,
          style: const TextStyle(fontSize: 15),
        ),
        content: Text('备份目录：\n$dir'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _restoreApk(packageName);
            },
            child: const Text('恢复 APK'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _restoreData(packageName);
            },
            child: const Text('恢复数据'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreApk(String packageName) async {
    final confirmed = await _confirm(
      title: '恢复 APK？',
      content: '将从备份重新安装 $packageName 的 APK（pm install -r）。',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyPackage = packageName);
    final result = await widget.service
        .runRootCommand(restoreApk(packageName).command);
    if (!mounted) return;
    setState(() => _busyPackage = '');
    _snack(
      result != null && result.success
          ? 'APK 恢复成功：$packageName'
          : 'APK 恢复失败：${_failText(result)}',
    );
  }

  Future<void> _restoreData(String packageName) async {
    final confirmed = await _confirm(
      title: '恢复数据？',
      content: '将用备份覆盖 $packageName 的当前应用数据，'
          '建议先备份当前状态。恢复前会先强制停止该应用。',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyPackage = packageName);
    String? error;
    try {
      final stopResult = await widget.service
          .runRootCommand(pmForceStop(packageName).command);
      if (stopResult == null || !stopResult.success) {
        error = '强制停止失败：${_failText(stopResult)}';
      } else {
        final dumpsysResult = await widget.service
            .runRootCommand(dumpsysPackageCommand(packageName));
        final uid = dumpsysResult != null && dumpsysResult.success
            ? parseDumpsysUserId(dumpsysResult.stdout)
            : null;
        if (uid == null) {
          error = '无法获取应用 uid，恢复已停止';
        } else {
          final restoreResult = await widget.service.runRootCommand(
            restoreData(packageName, uid).command,
          );
          if (restoreResult == null || !restoreResult.success) {
            error = '恢复数据失败：${_failText(restoreResult)}';
          }
        }
      }
    } finally {
      if (mounted) setState(() => _busyPackage = '');
    }
    if (!mounted) return;
    _snack(error ?? '数据恢复成功：$packageName');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用备份'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
            onPressed: _loading ? null : () => _load(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '备份保存在 $backupRootDir/<包名>/ 下。',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜索应用包名…',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
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
              FilledButton(
                onPressed: () => _load(showLoading: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const _SectionTitle(title: '备份应用'),
        if (_filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '没有匹配的应用',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          for (final packageName in _filtered)
            _buildPackageRow(packageName),
        const SizedBox(height: 16),
        const _SectionTitle(title: '已备份'),
        if (_backedUp.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '暂无备份',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          for (final packageName in _backedUp)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                packageName,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                backupDirFor(packageName),
                style: const TextStyle(fontSize: 11),
              ),
              trailing: _busyPackage == packageName
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _busyPackage == packageName
                  ? null
                  : () => _showBackupDetail(packageName),
            ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPackageRow(String packageName) {
    final busy = _busyPackage == packageName;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(packageName, style: const TextStyle(fontSize: 13)),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : OutlinedButton(
              onPressed: () => _backupApp(packageName),
              child: const Text('备份'),
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}
