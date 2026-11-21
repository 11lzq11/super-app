import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'root.dart';
import 'root_shell_page.dart';
import 'supermax_service.dart';

/// Super MAX 设置页。
///
/// - Super MAX 开关（默认关闭）；开启时先弹窗警告，再做 root 检测。
/// - root 状态显示（是否已 root、root 方案、重新检测）。
/// - root 命令执行日志查看 / 清空。
/// - 功能入口：Root Shell、应用管理。
///
/// [service] 不传时从 Provider 里取；Provider 未接入时页面自己建一个实例兜底。
class SuperMaxSettingsPage extends StatefulWidget {
  final SuperMaxService? service;

  const SuperMaxSettingsPage({super.key, this.service});

  @override
  State<SuperMaxSettingsPage> createState() => _SuperMaxSettingsPageState();
}

class _SuperMaxSettingsPageState extends State<SuperMaxSettingsPage> {
  SuperMaxService? _service;
  SuperMaxService? _fallback;
  bool _detecting = false;
  bool _logLoaded = false;
  String _logContent = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_service != null) return;
    if (widget.service != null) {
      _service = widget.service;
    } else {
      try {
        _service = Provider.of<SuperMaxService>(context);
      } catch (_) {
        // Provider 未接入时用页面自己持有的实例兜底。
        _fallback ??= SuperMaxService()..init();
        _service = _fallback;
      }
    }
  }

  SuperMaxService get _sm => _service!;

  Future<void> _onToggle(bool value) async {
    if (value) {
      // 开启前先弹窗警告。
      final confirmed = await _showEnableWarning();
      if (!mounted || !confirmed) return;
      final ok = await _sm.enable();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_sm.lastError ?? '开启失败')),
        );
      }
    } else {
      await _sm.disable();
    }
  }

  Future<bool> _showEnableWarning() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('开启 Super MAX？'),
          ],
        ),
        content: const Text(
          'Super MAX 会使用 root 权限执行命令、管理系统应用、读写真实文件。\n\n'
          '• root 操作有风险，输错命令可能损坏系统或丢失数据；\n'
          '• 每次执行 root 命令都需要你点确认，不会自动执行；\n'
          '• 关闭 Super MAX 后立即收回 root 能力；\n'
          '• 执行记录会保存在本地日志里，可随时查看、清空。\n\n'
          '请确认你清楚自己在做什么。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('我知道了，开启'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _refreshRootStatus() async {
    setState(() => _detecting = true);
    await _sm.refreshRootStatus();
    if (mounted) setState(() => _detecting = false);
  }

  Future<void> _loadLog() async {
    final content = await _sm.readLog();
    if (!mounted) return;
    setState(() {
      _logContent = content;
      _logLoaded = true;
    });
  }

  Future<void> _clearLog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空日志？'),
        content: const Text('将删除全部 root 命令执行记录，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _sm.clearLog();
    if (!mounted) return;
    setState(() {
      _logContent = '';
      _logLoaded = true;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日志已清空')));
  }

  void _openFeature(Widget page) {
    if (!_sm.isEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先开启 Super MAX 模式')),
      );
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final status = service.lastRootStatus;
        return Scaffold(
          appBar: AppBar(title: const Text('Super MAX 设置')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSwitchCard(service),
              const SizedBox(height: 16),
              _buildRootStatusCard(service, status),
              const SizedBox(height: 16),
              _buildFeatureCard(service),
              const SizedBox(height: 16),
              _buildLogCard(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSwitchCard(SuperMaxService service) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Super MAX 模式'),
            subtitle: Text(
              service.isEnabled ? '已开启：root 功能可用' : '默认关闭，在设置里手动启用',
            ),
            secondary: const Icon(Icons.bolt_rounded),
            value: service.isEnabled,
            onChanged: service.isBusy ? null : _onToggle,
          ),
          if (service.isBusy)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('正在检测 root…'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRootStatusCard(SuperMaxService service, RootStatus? status) {
    final isRooted = status?.isRooted ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isRooted ? Icons.verified_user_rounded : Icons.block_rounded,
                  color: isRooted ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Root 状态',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _detecting ? null : _refreshRootStatus,
                  icon: _detecting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重新检测'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _statusRow('是否已 root', isRooted ? '是' : '否'),
            _statusRow('Root 方案', status?.method ?? '—'),
            if (status?.detail != null) _statusRow('检测依据', status!.detail!),
            if (status != null)
              _statusRow(
                '检测时间',
                '${status.checkedAt.year}-${status.checkedAt.month.toString().padLeft(2, '0')}-'
                '${status.checkedAt.day.toString().padLeft(2, '0')} '
                '${status.checkedAt.hour.toString().padLeft(2, '0')}:'
                '${status.checkedAt.minute.toString().padLeft(2, '0')}',
              ),
            if (status == null)
              const Text('尚未检测，点击「重新检测」查看 root 状态。'),
            if (status != null && !isRooted)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '未检测到 root（需要 folkpatch/APatch 等 root 方案）。Super MAX 无法开启。',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 84, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(SuperMaxService service) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Root 功能',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.terminal_rounded),
            title: const Text('Root Shell'),
            subtitle: const Text('以 root 身份执行命令'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openFeature(RootShellPage(service: service)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.apps_rounded),
            title: const Text('应用管理'),
            subtitle: const Text('冻结 / 解冻 / 卸载应用（需要 root）'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openFeature(AppManagerPage(service: service)),
          ),
          if (!service.isEnabled)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '以上功能需要先开启 Super MAX 模式。',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.article_rounded),
                const SizedBox(width: 8),
                const Text(
                  '执行日志',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _loadLog,
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('查看'),
                ),
                TextButton.icon(
                  onPressed: _clearLog,
                  icon: const Icon(Icons.delete_rounded, size: 18),
                  label: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_logLoaded)
              const Text('点击「查看」加载 root 命令执行记录。')
            else if (_logContent.isEmpty)
              const Text('暂无执行记录。')
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _logContent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 应用管理页：列出全部应用，可冻结 / 解冻 / 卸载。
///
/// 全部操作都需要二次确认；卸载是高危操作，会再弹一次确认。
class AppManagerPage extends StatefulWidget {
  final SuperMaxService service;

  const AppManagerPage({super.key, required this.service});

  @override
  State<AppManagerPage> createState() => _AppManagerPageState();
}

class _AppManagerPageState extends State<AppManagerPage> {
  final _searchController = TextEditingController();
  List<String> _packages = [];
  List<String> _filtered = [];
  bool _loading = true;
  String? _error;
  String _busyPackage = '';

  static final _packageNamePattern = RegExp(
    r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$',
  );

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
        _error = '读取应用列表失败：${result.stderr.trim().isEmpty ? '退出码 ${result.exitCode}' : result.stderr.trim()}';
      });
      return;
    }
    final packages = result.stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('package:'))
        .map((line) => line.substring('package:'.length).trim())
        .where((name) => _packageNamePattern.hasMatch(name))
        .toList()
      ..sort();
    setState(() {
      _packages = packages;
      _loading = false;
    });
    _applyFilter();
  }

  Future<void> _runAction({
    required String packageName,
    required String label,
    required String command,
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
            '卸载系统应用可能影响系统功能（卸载仅针对当前用户，'
            '一般可用 pm install-existing 恢复）。',
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

    setState(() => _busyPackage = packageName);
    final result = await widget.service.runRootCommand(command);
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
                        command: 'pm disable-user --user 0 $packageName',
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
                        command: 'pm enable $packageName',
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
                        command: 'pm uninstall --user 0 $packageName',
                        confirmTitle: '卸载应用？',
                        confirmContent:
                            '将为当前用户卸载 $packageName。系统应用卸载后一般可用 '
                            'pm install-existing 恢复，但仍有风险，请谨慎操作。',
                        doubleConfirm: true,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
