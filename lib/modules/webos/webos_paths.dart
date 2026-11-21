import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'supermax_bridge.dart';

/// WebOS 沙盒内的一条文件记录。
class WebOSFileEntry {
  final String name;
  final String path;
  final bool isDir;

  const WebOSFileEntry({
    required this.name,
    required this.path,
    required this.isDir,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'isDir': isDir,
      };
}

/// WebOS 数据目录工具。
///
/// 所有 WebOS 数据都在应用文档目录下的 `webos/`：
/// - `apps/`   已安装的 HTML 应用
/// - `notes/`  记事本文件
/// - `files/`  文件管理器的工作区
class WebOSPaths {
  WebOSPaths._();

  /// WebOS 根目录：<文档目录>/webos
  static Future<Directory> root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}webos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> appsDir() async {
    final dir = Directory('${(await root()).path}${Platform.pathSeparator}apps');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> notesDir() async {
    final dir =
        Directory('${(await root()).path}${Platform.pathSeparator}notes');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> filesDir() async {
    final dir =
        Directory('${(await root()).path}${Platform.pathSeparator}files');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 确保 webos/ 及其子目录都存在。
  static Future<void> ensureAll() async {
    await root();
    await appsDir();
    await notesDir();
    await filesDir();
  }

  /// 判断 [path] 是否在 WebOS 沙盒内。
  static Future<bool> isInsideSandbox(String path) async {
    final rootPath = (await root()).path;
    final normalized = File(path).absolute.path;
    return normalized == rootPath || normalized.startsWith('$rootPath${Platform.pathSeparator}');
  }

  /// 列出目录内容。
  ///
  /// 沙盒内目录直接用 Dart IO 列出；沙盒外目录只有 Super MAX 开启时才允许，
  /// 优先用 root shell `ls` 列出，失败时回退到直接列出（桌面平台常用）。
  static Future<List<WebOSFileEntry>> listDirectory(String path) async {
    final inside = await isInsideSandbox(path);
    final maxEnabled = await SuperMaxBridge.isEnabled();
    if (!inside && !maxEnabled) {
      throw StateError('没有权限访问该目录（需要开启 Super MAX）');
    }

    final dir = Directory(path);
    if (!inside && maxEnabled && Platform.isAndroid) {
      // 真实文件系统：先试 root shell，解析失败再回退直接列出。
      try {
        final result = await SuperMaxBridge.runAsRoot(
          'ls -1Ap ${shellEscape(path)}',
        );
        if (result.ok) {
          final entries = <WebOSFileEntry>[];
          for (final line in result.output.split('\n')) {
            final name = line.trim();
            if (name.isEmpty) continue;
            final isDir = name.endsWith('/');
            final clean = isDir ? name.substring(0, name.length - 1) : name;
            entries.add(WebOSFileEntry(
              name: clean,
              path: '$path${Platform.pathSeparator}$clean',
              isDir: isDir,
            ));
          }
          entries.sort((a, b) {
            if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
          return entries;
        }
      } catch (_) {
        // 回退到直接列出
      }
    }

    if (!await dir.exists()) {
      throw StateError('目录不存在：$path');
    }
    final entries = <WebOSFileEntry>[];
    await for (final entity in dir.list()) {
      final name = entity.path.split(Platform.pathSeparator).last;
      entries.add(WebOSFileEntry(
        name: name,
        path: entity.path,
        isDir: entity is Directory,
      ));
    }
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// 计算目录总大小（字节），用于设置页展示存储占用。
  static Future<int> directorySize(Directory dir) async {
    var total = 0;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// 简单的 shell 参数转义（单引号包裹）。
  static String shellEscape(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}
