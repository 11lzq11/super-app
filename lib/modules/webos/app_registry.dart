import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'webos_paths.dart';

/// WebOS 应用类型：flutter（原生迷你应用）或 html（HTML 应用）。
enum WebOSAppKind { flutter, html }

/// 一个 WebOS 应用的描述。
class WebOSApp {
  final String id;
  final String name;
  final IconData icon;
  final WebOSAppKind kind;
  final String? version;
  final String? description;

  const WebOSApp({
    required this.id,
    required this.name,
    required this.icon,
    required this.kind,
    this.version,
    this.description,
  });
}

/// 应用列表变化通知（安装 / 卸载后触发，桌面与 Dock 监听刷新）。
final ValueNotifier<int> webOSAppsChanged = ValueNotifier<int>(0);

void notifyWebOSAppsChanged() {
  webOSAppsChanged.value++;
}

/// WebOS 应用注册表：内置 Flutter 迷你应用 + 已安装的 HTML 应用。
class WebOSAppRegistry {
  WebOSAppRegistry._();

  /// 内置 Flutter 迷你应用。
  static const List<WebOSApp> builtinApps = [
    WebOSApp(
      id: 'files',
      name: '文件管理器',
      icon: Icons.folder_outlined,
      kind: WebOSAppKind.flutter,
      description: '浏览与管理 WebOS 文件',
    ),
    WebOSApp(
      id: 'notes',
      name: '记事本',
      icon: Icons.note_alt_outlined,
      kind: WebOSAppKind.flutter,
      description: '纯文本笔记，保存在 WebOS 中',
    ),
    WebOSApp(
      id: 'terminal',
      name: '终端',
      icon: Icons.terminal,
      kind: WebOSAppKind.flutter,
      description: '执行命令，Super MAX 下可用 root shell',
    ),
    WebOSApp(
      id: 'calculator',
      name: '计算器',
      icon: Icons.calculate_outlined,
      kind: WebOSAppKind.flutter,
      description: '四则运算与常用科学函数',
    ),
    WebOSApp(
      id: 'store',
      name: '应用市场',
      icon: Icons.store_outlined,
      kind: WebOSAppKind.flutter,
      description: '安装示例应用，导入 .html / .webos 包',
    ),
    WebOSApp(
      id: 'workshop',
      name: '应用工坊',
      icon: Icons.build_outlined,
      kind: WebOSAppKind.flutter,
      description: '自己写一个 WebOS 应用',
    ),
    WebOSApp(
      id: 'settings',
      name: '设置',
      icon: Icons.settings_outlined,
      kind: WebOSAppKind.flutter,
      description: '壁纸、主题与应用管理',
    ),
  ];

  /// 在内置应用里按 id 查找，找不到返回 null。
  static WebOSApp? findBuiltin(String id) {
    for (final app in builtinApps) {
      if (app.id == id) return app;
    }
    return null;
  }

  /// 扫描 webos/apps/，读出已安装的 HTML 应用。
  /// 每个子目录即一个应用，优先读 manifest.json，否则用目录名做名字。
  ///
  /// 容错：目录不可读时返回空列表；单个应用目录损坏（缺 index.html、
  /// manifest 读失败等）时跳过该应用，不影响其他应用和桌面加载。
  static Future<List<WebOSApp>> installedHtmlApps() async {
    final dir = await WebOSPaths.appsDir();
    final result = <WebOSApp>[];
    if (!await dir.exists()) return result;
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list().toList();
    } catch (_) {
      return result;
    }
    for (final entity in entries) {
      if (entity is! Directory) continue;
      try {
        final app = await _readInstalledApp(entity);
        if (app != null) result.add(app);
      } catch (_) {
        // 单个应用损坏：跳过
        continue;
      }
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  /// 读一个已安装应用目录；缺 index.html 或目录名非法时返回 null。
  static Future<WebOSApp?> _readInstalledApp(Directory entity) async {
    final id = entity.path.split(Platform.pathSeparator).last;
    if (id.isEmpty || id.startsWith('.')) return null;
    final index = File(
      '${entity.path}${Platform.pathSeparator}index.html',
    );
    if (!await index.exists()) return null;
    String name = id;
    String? version;
    String? description;
    final manifestFile = File(
      '${entity.path}${Platform.pathSeparator}manifest.json',
    );
    if (await manifestFile.exists()) {
      try {
        final map = jsonDecode(await manifestFile.readAsString())
            as Map<String, dynamic>;
        name = (map['name'] as String?)?.trim().isNotEmpty == true
            ? map['name'] as String
            : id;
        version = map['version'] as String?;
        description = map['description'] as String?;
      } catch (_) {
        // manifest 损坏时仍按目录名展示
      }
    }
    return WebOSApp(
      id: id,
      name: name,
      icon: Icons.web_asset_outlined,
      kind: WebOSAppKind.html,
      version: version,
      description: description,
    );
  }

  /// 全部应用：内置 + 已安装的 HTML 应用。
  /// HTML 应用扫描失败时只返回内置应用，不抛错。
  static Future<List<WebOSApp>> allApps() async {
    List<WebOSApp> installed = [];
    try {
      installed = await installedHtmlApps();
    } catch (_) {
      installed = [];
    }
    return [...builtinApps, ...installed];
  }

  /// 按 id 查找任意应用（先内置，后已安装）。
  static Future<WebOSApp?> findApp(String id) async {
    final builtin = findBuiltin(id);
    if (builtin != null) return builtin;
    final installed = await installedHtmlApps();
    for (final app in installed) {
      if (app.id == id) return app;
    }
    return null;
  }
}
