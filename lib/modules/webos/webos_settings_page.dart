import 'dart:io';

import 'package:flutter/material.dart';

import 'app_registry.dart';
import 'app_store.dart';
import 'local_server.dart';
import 'webos_paths.dart';
import 'webos_theme.dart';

/// WebOS 设置页（独立页面，供 SuperApp 统一设置页跳转进入）。
///
/// 壁纸、默认窗口模式、应用管理、localhost 端口与存储占用。
class WebOSSettingsPage extends StatefulWidget {
  const WebOSSettingsPage({super.key});

  @override
  State<WebOSSettingsPage> createState() => _WebOSSettingsPageState();
}

class _WebOSSettingsPageState extends State<WebOSSettingsPage> {
  String _windowMode = 'auto';
  List<WebOSApp> _installed = [];
  int _storageBytes = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mode = await loadWebOSWindowMode();
    final apps = await WebOSAppRegistry.installedHtmlApps();
    var size = 0;
    try {
      size = await WebOSPaths.directorySize(await WebOSPaths.root());
    } catch (_) {}
    if (mounted) {
      setState(() {
        _windowMode = mode;
        _installed = apps;
        _storageBytes = size;
        _loading = false;
      });
    }
  }

  Future<void> _setWindowMode(String mode) async {
    await setWebOSWindowMode(mode);
    setState(() => _windowMode = mode);
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
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已卸载 ${app.name}')),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final server = WebOSLocalServer.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('WebOS 设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                              width: 84,
                              height: 56,
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
                                  fontSize: 12,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black45,
                                      blurRadius: 4,
                                    ),
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
                  '默认窗口模式',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                RadioGroup<String>(
                  groupValue: _windowMode,
                  onChanged: (value) {
                    if (value != null) _setWindowMode(value);
                  },
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        title: const Text('自动'),
                        subtitle: const Text(
                          '按屏幕宽高比自适应（宽屏桌面，窄屏手机）',
                        ),
                        value: 'auto',
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<String>(
                        title: const Text('桌面模式'),
                        subtitle: const Text('浮动窗口，可拖动、缩放'),
                        value: 'desktop',
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<String>(
                        title: const Text('手机模式'),
                        subtitle: const Text('窗口全屏，底部 Dock 切换'),
                        value: 'phone',
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '本地服务',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Icon(
                    server.isRunning
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                  ),
                  title: Text(server.isRunning ? '运行中' : '未启动'),
                  subtitle: Text(
                    server.isRunning
                        ? '地址：${server.baseUrl}\n打开 WebOS 时自动启动，退出时关闭。'
                        : '打开 WebOS 后自动启动，退出时关闭。',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                const Text(
                  '存储',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('WebOS 数据占用'),
                  subtitle: Text(_formatBytes(_storageBytes)),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                const Text(
                  '应用管理',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (_installed.isEmpty)
                  const Text('还没有安装 HTML 应用，去应用市场看看吧。')
                else
                  for (final app in _installed)
                    ListTile(
                      leading: Icon(app.icon),
                      title: Text(app.name),
                      subtitle: Text(
                        [if (app.version != null) 'v${app.version}']
                            .join(' · '),
                      ),
                      trailing: TextButton(
                        onPressed: () => _uninstall(app),
                        child: const Text('卸载'),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                const SizedBox(height: 16),
                Text(
                  'WebOS 数据保存在应用文档目录下的 webos/（应用：apps/，笔记：notes/，文件：files/）。',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
                if (Platform.isLinux) ...[
                  const SizedBox(height: 8),
                  Text(
                    '提示：当前平台不支持 WebView，HTML 应用无法运行。',
                    style: TextStyle(color: Colors.orange[800], fontSize: 13),
                  ),
                ],
              ],
            ),
    );
  }
}
