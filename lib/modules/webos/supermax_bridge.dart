import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../supermax/root.dart';
import '../../supermax/root_shell.dart';

/// Super MAX 桥接：WebOS 侧读取 Super MAX 状态、执行 root 命令的统一入口。
///
/// 直接对接 supermax 模块的真实实现：
/// - 开关位：读 SharedPreferences 的 `supermax_enabled`，
///   与 [SuperMaxService.prefKeyEnabled] 是同一个 key；
/// - root 执行：走 [RootShell.runAsRoot]（串行队列 + 超时 + 日志由
///   SuperMaxService.runRootCommand 记，本桥接只做直接执行）。
///
/// supermax 模块不存在时本文件无法编译；当前它已存在（lib/supermax/）。
class SuperMaxBridge {
  SuperMaxBridge._();

  /// SuperMaxService 保存开关的 key（与 supermax_service.dart 一致）。
  static const String enabledKey = 'supermax_enabled';

  static const List<String> _enabledKeys = [
    enabledKey,
    'super_max_enabled',
    'supermaxEnabled',
    'superMaxEnabled',
  ];

  /// Super MAX 是否开启。读不到时返回 false。
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _enabledKeys) {
        if (prefs.getBool(key) == true) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 以 root 身份执行一条 shell 命令（仅 Android）。
  ///
  /// 返回 (ok, output)：ok 表示退出码为 0，output 为 stdout + stderr。
  /// 未开启 Super MAX / 非 Android / su 不可用时 ok 为 false 并附原因。
  static Future<({bool ok, String output})> runAsRoot(String command) async {
    if (!Platform.isAndroid) {
      return (ok: false, output: '当前平台不支持 root');
    }
    if (!await isEnabled()) {
      return (ok: false, output: 'Super MAX 未开启');
    }
    try {
      final result = await RootShell.runAsRoot(
        command,
        timeout: const Duration(seconds: 30),
      );
      final out = [
        result.stdout.trim(),
        result.stderr.trim(),
      ].where((s) => s.isNotEmpty).join('\n');
      return (
        ok: result.success,
        output: out.isEmpty ? '(无输出)' : out,
      );
    } catch (e) {
      return (ok: false, output: '执行失败：$e');
    }
  }

  /// 检测设备是否真的有 root（走 RootService，与设置页同一份逻辑）。
  static Future<bool> detectRoot() async {
    if (!Platform.isAndroid) return false;
    try {
      return await RootService().isRooted;
    } catch (_) {
      return false;
    }
  }
}
