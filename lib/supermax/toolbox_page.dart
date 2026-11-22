import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'supermax_service.dart';
import 'supermax_settings_page.dart';
import 'toolbox/adblock_page.dart';
import 'toolbox/ai_settings_page.dart';
import 'toolbox/app_manager_page.dart';
import 'toolbox/backup_page.dart';
import 'toolbox/boot_page.dart';
import 'toolbox/file_manager_page.dart';
import 'toolbox/performance_page.dart';
import 'toolbox/settings_browser_page.dart';

/// Super MAX 工具箱：系统级 root 功能入口。
///
/// 仅在 Super MAX 开启（即已 root）时可用；未开启时显示锁定状态，
/// 可一键跳转到 Super MAX 设置页开启。
/// 每个功能都是独立页面，全部走 SuperMaxService.runRootCommand 执行，
/// 高危操作先弹窗确认，执行记录写入 root 日志。
///
/// [service] 不传时从 Provider 里取；Provider 未接入时页面自己建一个实例兜底。
class ToolboxPage extends StatefulWidget {
  final SuperMaxService? service;

  const ToolboxPage({super.key, this.service});

  @override
  State<ToolboxPage> createState() => _ToolboxPageState();
}

class _ToolboxPageState extends State<ToolboxPage> {
  SuperMaxService? _service;
  SuperMaxService? _fallback;

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
        _fallback ??= SuperMaxService()..init();
        _service = _fallback;
      }
    }
  }

  SuperMaxService get _sm => _service!;

  void _openFeature(Widget page) {
    if (!_sm.isEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先开启 Super MAX 模式')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _openSuperMaxSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SuperMaxSettingsPage(service: _sm),
      ),
    );
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
        final enabled = service.isEnabled;
        return Scaffold(
          appBar: AppBar(title: const Text('Super MAX 工具箱')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!enabled) _buildLockedCard(),
              _buildFeatureTile(
                icon: Icons.auto_awesome_rounded,
                title: 'AI 调设置',
                subtitle: '说一句话，让 AI 帮你改系统设置',
                page: AiSettingsPage(service: service),
              ),
              _buildFeatureTile(
                icon: Icons.tune_rounded,
                title: '系统设置管理',
                subtitle: '浏览、修改 settings 表（system / secure / global）',
                page: SettingsBrowserPage(service: service),
              ),
              _buildFeatureTile(
                icon: Icons.apps_rounded,
                title: '应用管理',
                subtitle: '冻结 / 解冻 / 卸载 / 清除数据 / 强制停止',
                page: ToolboxAppManagerPage(service: service),
              ),
              _buildFeatureTile(
                icon: Icons.folder_rounded,
                title: 'Root 文件管理',
                subtitle: '浏览 /system、/data，查看、删除文件',
                page: RootFileManagerPage(service: service),
              ),
              _buildFeatureTile(
                icon: Icons.speed_rounded,
                title: '性能调节',
                subtitle: 'CPU 调速器、屏幕刷新率、省电模式',
                page: PerformancePage(service: service),
              ),
              _buildFeatureTile(
                icon: Icons.block_rounded,
                title: '广告屏蔽',
                subtitle: 'hosts 屏蔽规则、备份与恢复',
                page: AdBlockPage(service: service),
              ),
              _buildFeatureTile(
                icon: Icons.backup_rounded,
                title: '应用备份',
                subtitle: '备份 APK 与应用数据，支持恢复',
                page: AppBackupPage(service: service),
              ),
              _buildFeatureTile(
                icon: Icons.power_settings_new_rounded,
                title: '开机自启管理',
                subtitle: '管理声明了开机启动的应用',
                page: BootManagerPage(service: service),
              ),
              const SizedBox(height: 16),
              const Text(
                '所有操作都通过 root 执行，执行前会弹窗确认，'
                '记录保存在 Super MAX 执行日志里。',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLockedCard() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lock_rounded),
                SizedBox(width: 8),
                Text(
                  'Super MAX 未开启',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('工具箱里的功能都需要 root 权限。请先开启 Super MAX 模式（需要设备已 root）。'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _openSuperMaxSettings,
              child: const Text('去开启 Super MAX'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _openFeature(page),
      ),
    );
  }
}
