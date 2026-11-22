import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';
import '../supermax/ios_max.dart';
import '../supermax/supermax_service.dart';

/// 统一设置页：主题、语言、Super MAX 开关 + root/iOS 环境状态、存储占用、关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const String _repoUrl = 'https://github.com/11lzq11/super-app';
  static const String _version = '0.2.1';

  String _rootStatusText(RootCheckStatus status) {
    return switch (status) {
      RootCheckStatus.rooted => '已检测到 root',
      RootCheckStatus.notRooted => '未检测到 root',
      RootCheckStatus.unknown => '尚未检测',
    };
  }

  String _iosMaxStatusText(IOSMaxStatus? status) {
    final s = status;
    if (s == null) return '尚未检测';
    return '${s.environment.label}：${s.environment.description}';
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
    final unavailableMessage = Platform.isIOS
        ? '需要越狱或通过 TrollStore 安装才能开启 Super MAX'
        : '未检测到 root（需要 folkpatch/APatch 等 root 方案）';
    if (value && !settings.isRooted) {
      _showMessage(context, unavailableMessage);
      return;
    }
    final ok = await settings.setSuperMaxEnabled(value);
    if (!ok && context.mounted) {
      _showMessage(context, unavailableMessage);
    }
  }

  Future<void> _onRecheckRoot(
    BuildContext context,
    SettingsService settings,
    SuperMaxService superMax,
  ) async {
    await settings.refreshRootStatus(force: true);
    if (!context.mounted) return;
    if (Platform.isIOS) {
      final status = superMax.iosMaxStatus;
      if (settings.isRooted) {
        _showMessage(
          context,
          'iOS MAX 可用：${status?.environment.label ?? '已检测'}',
        );
      } else {
        _showMessage(context, '需要越狱或通过 TrollStore 安装才能开启 Super MAX');
      }
      return;
    }
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

  /// iOS MAX 环境详情：可用能力与不可用/受限的能力（仅 iOS 显示）。
  Widget _iosMaxDetails(BuildContext context, IOSMaxStatus status) {
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    final children = <Widget>[
      ListTile(
        leading: const Icon(Icons.phone_iphone),
        title: const Text('iOS MAX 环境'),
        subtitle: Text(
          '${status.environment.label}\n${status.environment.description}',
        ),
      ),
    ];
    if (status.capabilities.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            '可用能力：\n${status.capabilities.map((c) => '• $c').join('\n')}',
            style: textStyle,
          ),
        ),
      );
    }
    if (status.limitations.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            '不可用 / 受限：\n${status.limitations.map((c) => '• $c').join('\n')}',
            style: textStyle,
          ),
        ),
      );
    }
    if (status.evidence.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            '检测依据：\n${status.evidence.map((c) => '• $c').join('\n')}',
            style: textStyle,
          ),
        ),
      );
    }
    return Column(children: children);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final superMax = context.watch<SuperMaxService>();
    final scheme = Theme.of(context).colorScheme;
    final isIOS = Platform.isIOS;

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
            subtitle: Text(
              isIOS
                  ? _iosMaxStatusText(superMax.iosMaxStatus)
                  : _rootStatusText(settings.rootStatus),
            ),
            value: settings.superMaxEnabled,
            // 未检测到 root / iOS 环境不可用时开关不可用。
            onChanged: settings.isRooted
                ? (value) => _onSuperMaxChanged(context, settings, value)
                : null,
          ),
          if (isIOS && superMax.iosMaxStatus != null)
            _iosMaxDetails(context, superMax.iosMaxStatus!),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(isIOS ? '重新检测 iOS 环境' : '重新检测 root'),
            subtitle: Text(
              isIOS
                  ? '检查是否越狱或通过 TrollStore 安装'
                  : '检查设备是否已 root（folkpatch / APatch）',
            ),
            onTap: () => _onRecheckRoot(context, settings, superMax),
          ),
          if (settings.superMaxEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                isIOS
                    ? 'Super MAX 已开启：沙盒外文件读写、系统偏好操作等 iOS MAX '
                        '功能可用（能力范围见上方环境详情），所有系统级操作执行前都会请你确认。'
                    : 'Super MAX 已开启：AI 手机操作、WebOS 真实文件读写等 root 功能可用，'
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
