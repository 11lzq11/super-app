import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';

/// 统一设置页：主题、语言、Super MAX 开关 + root 状态、存储占用、关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const String _repoUrl = 'https://github.com/11lzq11/super-app';
  static const String _version = '0.1.0';

  String _rootStatusText(RootCheckStatus status) {
    return switch (status) {
      RootCheckStatus.rooted => '已检测到 root',
      RootCheckStatus.notRooted => '未检测到 root',
      RootCheckStatus.unknown => '尚未检测',
    };
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _onSuperMaxChanged(
    BuildContext context,
    SettingsService settings,
    bool value,
  ) async {
    if (value && !settings.isRooted) {
      _showMessage(context, '未检测到 root（需要 folkpatch/APatch 等 root 方案）');
      return;
    }
    final ok = await settings.setSuperMaxEnabled(value);
    if (!ok && context.mounted) {
      _showMessage(context, '未检测到 root（需要 folkpatch/APatch 等 root 方案）');
    }
  }

  Future<void> _onRecheckRoot(
    BuildContext context,
    SettingsService settings,
  ) async {
    await settings.refreshRootStatus(force: true);
    if (!context.mounted) return;
    if (settings.isRooted) {
      _showMessage(context, '已检测到 root');
    } else {
      _showMessage(context, '未检测到 root（需要 folkpatch/APatch 等 root 方案）');
    }
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _sectionTitle(context, '外观'),
          RadioGroup<ThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (mode) {
              if (mode != null) settings.setThemeMode(mode);
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: Text('跟随系统'),
                  value: ThemeMode.system,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('浅色'),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('深色'),
                  value: ThemeMode.dark,
                ),
              ],
            ),
          ),
          const ListTile(
            title: Text('语言'),
            trailing: Text('简体中文'),
          ),
          _sectionTitle(context, 'Super MAX'),
          SwitchListTile(
            title: const Text('Super MAX 模式'),
            subtitle: Text(_rootStatusText(settings.rootStatus)),
            value: settings.superMaxEnabled,
            // 未检测到 root 时开关不可用。
            onChanged: settings.isRooted
                ? (value) => _onSuperMaxChanged(context, settings, value)
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('重新检测 root'),
            subtitle: const Text('检查设备是否已 root（folkpatch / APatch）'),
            onTap: () => _onRecheckRoot(context, settings),
          ),
          if (settings.superMaxEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Super MAX 已开启：AI 手机操作、WebOS 真实文件读写等 root 功能可用，'
                '所有 root 操作执行前都会请你确认。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          _sectionTitle(context, '存储'),
          const ListTile(
            title: Text('存储占用'),
            subtitle: Text('暂未统计'),
          ),
          _sectionTitle(context, '关于'),
          const ListTile(
            title: Text('版本'),
            trailing: Text(_version),
          ),
          const ListTile(
            title: Text('仓库地址'),
            subtitle: Text(_repoUrl),
          ),
          ListTile(
            leading: const Icon(Icons.info_outlined),
            title: const Text('关于 SuperApp'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'SuperApp',
                applicationVersion: _version,
                children: [
                  const SizedBox(height: 8),
                  const SelectableText(_repoUrl),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
