import 'package:flutter/material.dart';

import '../root_shell.dart';
import '../supermax_service.dart';
import '../toolbox_commands.dart';

/// 应用管理（工具箱增强版）：列出全部应用，可冻结 / 解冻 / 卸载 /
/// 清除数据 / 强制停止。
///
/// 加载用 `pm list packages` + parsePmPackages；全部操作都复用
/// toolbox_commands.dart 里的 pmDisable / pmEnable / pmUninstall /
/// pmClear / pmForceStop。卸载是破坏性操作，需要双重确认。
class ToolboxAppManagerPage extends StatefulWidget {
  final SuperMaxService service;

  const ToolboxAppManagerPage({super.key, required this.service});

  @override
  State<ToolboxAppManagerPage> createState() => _ToolboxAppManagerPageState();
}

class _ToolboxAppManagerPageState extends State<ToolboxAppManagerPage> {
  final _searchController = TextEditingController();
  List<String> _packages = [];
  List<String> _filtered = [];
  bool _loading = true;
  String? _error;
  String _busyPackage = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _loadPackages();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final keyword = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = keyword.isEmpty
          ? List.of(_packages)
          : _packages.where((p) => p.toLowerCase().contains(keyword)).toList();
    });
  }

  Future<void> _loadPackages() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.service.runRootCommand('pm list packages');
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
            '读取应用列表失败：${result.stderr.trim().isEmpty ? '退出码 ${result.exitCode}' : result.stderr.trim()}';
      });
      return;
    }
    setState(() {
      _packages = parsePmPackages(result.stdout);
      _loading = false;
    });
    _applyFilter();
  }

  Future<void> _runAction({
    required String packageName,
    required String label,
    required SystemCommand command,
    required String confirmTitle,
    required String confirmContent,
    bool doubleConfirm = false,
  }) async {
    // 第一次确认。
    final first = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(confirmTitle),
        content: Text(confirmContent),
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
    if (first != true || !mounted) return;

    // 高危操作：再确认一次。
    if (doubleConfirm) {
      final second = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('再次确认'),
            ],
          ),
          content: Text(
            '即将对 $packageName 执行「$label」，请再次确认。\n'
            '卸载仅针对当前用户，系统应用一般可用 pm install-existing 恢复，'
            '但仍有风险，请谨慎操作。',
            style: const TextStyle(color: Colors.red),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认执行'),
            ),
          ],
        ),
      );
      if (second != true || !mounted) return;
    }

    // 高危命令走红色高危确认。
    if (RootShell.isDangerous(command.command)) {
      final confirmed = await showRootCommandConfirmDialog(
        context,
        command.command,
        dangerous: true,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _busyPackage = packageName);
    final result = await widget.service.runRootCommand(command.command);
    if (!mounted) return;
    setState(() => _busyPackage = '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == null
              ? 'Super MAX 未开启'
              : result.success
              ? '$label成功：$packageName'
              : '$label失败：${result.stderr.trim().isEmpty ? '退出码 ${result.exitCode}' : result.stderr.trim()}',
        ),
      ),
    );
    if (result != null && result.success) _loadPackages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新列表',
            onPressed: _loading ? null : _loadPackages,
          ),
        ],
      ),
      body: Column(
        children: [
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
                onPressed: _loadPackages,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_filtered.isEmpty) {
      return const Center(child: Text('没有匹配的应用'));
    }
    return ListView.separated(
      itemCount: _filtered.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final packageName = _filtered[index];
        final busy = _busyPackage == packageName;
        return ListTile(
          title: Text(packageName, style: const TextStyle(fontSize: 13)),
          trailing: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.pause_circle_outline_rounded),
                      tooltip: '冻结',
                      onPressed: () => _runAction(
                        packageName: packageName,
                        label: '冻结',
                        command: pmDisable(packageName),
                        confirmTitle: '冻结应用？',
                        confirmContent:
                            '将冻结 $packageName，应用图标会隐藏且无法运行，可随时解冻恢复。',
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      tooltip: '解冻',
                      onPressed: () => _runAction(
                        packageName: packageName,
                        label: '解冻',
                        command: pmEnable(packageName),
                        confirmTitle: '解冻应用？',
                        confirmContent: '将恢复 $packageName 的运行。',
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                      ),
                      tooltip: '卸载',
                      onPressed: () => _runAction(
                        packageName: packageName,
                        label: '卸载',
                        command: pmUninstall(packageName),
                        confirmTitle: '卸载应用？',
                        confirmContent:
                            '将为当前用户卸载 $packageName。系统应用卸载后一般可用 '
                            'pm install-existing 恢复，但仍有风险，请谨慎操作。',
                        doubleConfirm: true,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cleaning_services_rounded),
                      tooltip: '清除数据',
                      onPressed: () => _runAction(
                        packageName: packageName,
                        label: '清除数据',
                        command: pmClear(packageName),
                        confirmTitle: '清除应用数据？',
                        confirmContent:
                            '将删除 $packageName 的全部应用数据，包括账号、设置和缓存，'
                            '此操作不可恢复。',
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.stop_circle_outlined),
                      tooltip: '强制停止',
                      onPressed: () => _runAction(
                        packageName: packageName,
                        label: '强制停止',
                        command: pmForceStop(packageName),
                        confirmTitle: '强制停止应用？',
                        confirmContent:
                            '将强制停止 $packageName，正在运行的进程会被结束。',
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
