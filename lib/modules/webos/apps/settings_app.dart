import 'package:flutter/material.dart';

import '../app_registry.dart';
import '../app_store.dart';
import '../webos_theme.dart';

/// WebOS 设置（窗口内应用）：壁纸、主题、应用管理。
class SettingsApp extends StatefulWidget {
  const SettingsApp({super.key});

  @override
  State<SettingsApp> createState() => _SettingsAppState();
}

class _SettingsAppState extends State<SettingsApp> {
  List<WebOSApp> _installed = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInstalled();
  }

  Future<void> _loadInstalled() async {
    final apps = await WebOSAppRegistry.installedHtmlApps();
    if (mounted) {
      setState(() {
        _installed = apps;
        _loading = false;
      });
    }
  }

  Future<void> _uninstall(WebOSApp app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卸载应用'),
        content: Text('确定卸载「${app.name}」吗？应用文件将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AppStoreService.uninstall(app.id);
    await _loadInstalled();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已卸载 ${app.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '壁纸',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<int>(
          valueListenable: webOSWallpaperNotifier,
          builder: (context, current, _) {
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < webOSWallpapers.length; i++)
                  InkWell(
                    onTap: () => setWebOSWallpaper(i),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 72,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: webOSWallpapers[i].gradient,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: current == i
                              ? Colors.blue
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        webOSWallpapers[i].name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          shadows: [
                            Shadow(color: Colors.black45, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        const Text(
          '外观',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<bool>(
          valueListenable: webOSDarkModeNotifier,
          builder: (context, dark, _) {
            return SwitchListTile(
              title: const Text('深色模式'),
              subtitle: const Text('窗口与任务栏使用深色'),
              value: dark,
              onChanged: (value) => setWebOSDarkMode(value),
              contentPadding: EdgeInsets.zero,
            );
          },
        ),
        const SizedBox(height: 16),
        const Text(
          '已安装的应用',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_installed.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('还没有安装 HTML 应用，去应用市场看看吧。'),
          )
        else
          for (final app in _installed)
            ListTile(
              leading: Icon(app.icon),
              title: Text(app.name),
              subtitle: Text(app.version ?? ''),
              trailing: TextButton(
                onPressed: () => _uninstall(app),
                child: const Text('卸载'),
              ),
              contentPadding: EdgeInsets.zero,
            ),
        const SizedBox(height: 16),
        const Text(
          '关于',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text('WebOS v0.1.0 — 在 SuperApp 内运行的桌面操作系统环境。'),
        const Text('HTML 应用通过内置 localhost 服务运行，支持应用互联。'),
      ],
    );
  }
}
