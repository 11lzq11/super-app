import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/settings.dart';
import 'root.dart';
import 'root_shell.dart';

/// Super MAX 模式服务：开关 + root 检测 + root 命令执行 + 执行日志。
///
/// - 默认关闭（[isEnabled] 初始为 false），开启时先做 root 检测，
///   未 root 则拒绝开启并把原因写进 [lastError]。
/// - 关闭后立即收回 root 能力：[runRootCommand] 会直接返回 null。
/// - 其他模块（WebOS 文件管理器/终端、AiPlat 手机操作）通过它查询状态、
///   执行 root 命令；执行记录自动写入本地日志文件。
///
/// 最简接口（给 WebOS / AiPlat 用）：
/// - `isEnabled`：Super MAX 是否开启；
/// - `runRootCommand(command, confirm: ...)`：执行 root 命令并记日志；
/// - `RootShell.isDangerous(command)`：判断命令是否高危（root_shell.dart）。
///
/// 它还实现核心壳的 [SuperMaxController] 接口，是 Super MAX 开关的
/// 唯一事实源；[SettingsService] 绑定它之后只做委托转发。
class SuperMaxService extends ChangeNotifier implements SuperMaxController {
  /// shared_preferences 里保存开关的 key。
  static const String prefKeyEnabled = 'supermax_enabled';

  /// 日志文件超过该大小时截断，只保留后半部分。
  static const int _maxLogBytes = 512 * 1024;

  final RootService rootService;

  SuperMaxService({RootService? rootService})
      : rootService = rootService ?? RootService();

  bool _isEnabled = false;

  /// Super MAX 是否开启（默认 false）。
  @override
  bool get isEnabled => _isEnabled;

  /// 是否已检测到 root（缓存的检测结果，未检测过时为 false）。
  @override
  bool get isRooted => lastRootStatus?.isRooted ?? false;

  /// 上次 root 检测结果（可能为 null，表示尚未检测过）。
  RootStatus? get lastRootStatus => rootService.cachedStatus;

  /// 开启失败时的原因（如「未检测到 root」），成功时为 null。
  String? lastError;

  /// 是否正在检测 root（开启过程中）。
  bool _isBusy = false;
  bool get isBusy => _isBusy;

  /// 从本地存储加载开关状态。
  ///
  /// 如果本地保存的是开启状态，会重新检测 root；检测不到 root 时
  /// 自动关闭（设备可能已失去 root），避免开关与实际能力不一致。
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(prefKeyEnabled) ?? false;
      if (!saved) {
        _isEnabled = false;
        return;
      }
      final status = await rootService.detect(force: true);
      _isEnabled = status.isRooted;
      if (!_isEnabled) {
        await prefs.setBool(prefKeyEnabled, false);
      }
      notifyListeners();
    } catch (_) {
      _isEnabled = false;
    }
  }

  /// 重新检测 root 状态（强制重新检测，不用缓存）。
  Future<RootStatus> refreshRootStatus() async {
    final status = await rootService.detect(force: true);
    notifyListeners();
    return status;
  }

  /// 重新检测 root，返回是否已 root（供 [SuperMaxController] 用）。
  @override
  Future<bool> refreshRoot() async {
    final status = await refreshRootStatus();
    return status.isRooted;
  }

  /// 开启 Super MAX：先检测 root，未 root 则返回 false 并设置 [lastError]。
  @override
  Future<bool> enable() async {
    if (_isEnabled) return true;
    _isBusy = true;
    lastError = null;
    notifyListeners();
    try {
      final status = await rootService.detect(force: true);
      if (!status.isRooted) {
        lastError = '未检测到 root（需要 folkpatch/APatch 等 root 方案）';
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefKeyEnabled, true);
      _isEnabled = true;
      return true;
    } catch (e) {
      lastError = '开启失败：$e';
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// 关闭 Super MAX：立即生效，并持久化。
  @override
  Future<void> disable() async {
    if (!_isEnabled) return;
    _isEnabled = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefKeyEnabled, false);
    } catch (_) {
      // 持久化失败不影响关闭本身。
    }
    notifyListeners();
  }

  /// 执行一条 root 命令并记日志。
  ///
  /// - 未开启 Super MAX 时直接返回 null（不执行、不记日志）。
  /// - [confirm] 传入时，每次执行前都会调用它让用户确认；
  ///   不传时不弹窗——调用方应自行用 [RootShell.isDangerous] 判断，
  ///   高危命令先用 [showRootCommandConfirmDialog] 确认。
  /// - 用户在确认框里点取消时返回 null。
  Future<RootCommandResult?> runRootCommand(
    String command, {
    Future<bool> Function(String command)? confirm,
    Duration timeout = RootShell.defaultTimeout,
  }) async {
    if (!_isEnabled) return null;
    final RootCommandResult? result;
    if (confirm != null) {
      result = await RootShell.runAsRootWithConfirm(
        command,
        confirm: confirm,
        timeout: timeout,
      );
    } else {
      result = await RootShell.runAsRoot(command, timeout: timeout);
    }
    if (result != null) {
      await _appendLog(command, result);
    }
    return result;
  }

  /// root 命令执行日志文件路径（应用文档目录 supermax/root_log.txt）。
  Future<String> logFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/supermax/root_log.txt';
  }

  /// 读取全部日志内容；无日志时返回空字符串。
  Future<String> readLog() async {
    try {
      final file = File(await logFilePath());
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  /// 清空日志。
  Future<void> clearLog() async {
    try {
      final file = File(await logFilePath());
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 删不掉也不影响使用。
    }
  }

  Future<void> _appendLog(String command, RootCommandResult result) async {
    try {
      final path = await logFilePath();
      final file = File(path);
      await file.parent.create(recursive: true);
      final now = DateTime.now();
      final time =
          '${now.year}-${_two(now.month)}-${_two(now.day)} '
          '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';
      final line =
          '[$time] \$ $command\n'
          '  exit=${result.exitCode}'
          '${result.timedOut ? '（超时）' : ''} '
          '耗时=${result.duration.inMilliseconds}ms\n'
          '  ${result.summary.replaceAll('\n', '\n  ')}\n';
      // 日志过大时先截断，只保留后半部分。
      if (await file.exists() && await file.length() > _maxLogBytes) {
        final content = await file.readAsString();
        final keepFrom = content.length ~/ 2;
        await file.writeAsString(content.substring(keepFrom));
      }
      await file.writeAsString(line, mode: FileMode.append);
    } catch (_) {
      // 日志写失败不影响命令执行本身。
    }
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
