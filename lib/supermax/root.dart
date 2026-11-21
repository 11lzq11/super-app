import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// root 检测结果。
class RootStatus {
  /// 是否已 root。
  final bool isRooted;

  /// root 方案，如 `folkpatch/APatch`、`Magisk`、`KernelSU`、`su`；未 root 时为 null。
  final String? method;

  /// 补充说明，如检测到的 su 路径或守护进程路径。
  final String? detail;

  /// 本次检测的时间。
  final DateTime checkedAt;

  const RootStatus({
    required this.isRooted,
    this.method,
    this.detail,
    required this.checkedAt,
  });

  factory RootStatus.notRooted({DateTime? checkedAt}) => RootStatus(
        isRooted: false,
        checkedAt: checkedAt ?? DateTime.now(),
      );

  @override
  String toString() =>
      'RootStatus(isRooted: $isRooted, method: $method, detail: $detail)';
}

/// root 检测服务。
///
/// 检测策略（按优先级）：
/// 1. 执行 `su -c id`，输出含 `uid=0` 即为已 root（最权威）；
/// 2. 检查 APatch / Magisk / KernelSU 的特征文件与常见 su 路径；
/// 3. `which su` 兜底。
///
/// 非 Android 平台直接返回未 root，不尝试执行任何命令。
class RootService {
  /// `su -c id` 的超时时间。已 root 设备上首次调用可能弹出授权窗口，
  /// 超时后靠路径检查兜底，不会一直卡住。
  static const Duration suTimeout = Duration(seconds: 5);

  /// APatch（folkpatch 是 APatch 分支，共用同一守护进程）的特征路径。
  static const String apatchDaemonPath = '/data/adb/apd';

  /// KernelSU 的特征路径。
  static const String ksuPath = '/data/adb/ksu';

  /// Magisk 的特征路径。
  static const List<String> magiskPaths = [
    '/data/adb/magisk',
    '/system/bin/magisk',
  ];

  /// 常见 su 二进制路径。
  static const List<String> suPaths = [
    '/system/bin/su',
    '/system/xbin/su',
    '/sbin/su',
    '/system/bin/magisk',
    '/data/adb/magisk',
  ];

  RootStatus? _cached;

  /// 上次检测结果（可能为 null，表示尚未检测过）。
  RootStatus? get cachedStatus => _cached;

  /// 清除缓存，下次检测会重新执行。
  void clearCache() => _cached = null;

  /// 检测是否已 root。默认使用缓存，[force] 为 true 时强制重新检测。
  Future<RootStatus> detect({bool force = false}) async {
    if (!force && _cached != null) return _cached!;
    final status = await _detect();
    _cached = status;
    return status;
  }

  /// 快捷判断：是否已 root。
  Future<bool> get isRooted async => (await detect()).isRooted;

  Future<RootStatus> _detect() async {
    final now = DateTime.now();

    // 只在 Android 上做 root 检测；其他平台直接返回未 root。
    // 注意：桌面 Linux 上也有 su，但那不代表本应用拥有 root 权限，
    // 所以必须先按平台拦截，不能只看 su 是否存在。
    bool isAndroid = false;
    try {
      isAndroid = Platform.isAndroid;
    } catch (_) {
      isAndroid = false;
    }
    if (!isAndroid) {
      return RootStatus.notRooted(checkedAt: now);
    }

    // 1) 最权威：执行 su -c id，看 uid 是否为 0。
    final suWorks = await _trySuId();

    // 2) 方案识别：检查各 root 方案的特征文件。
    String? method;
    String? detail;
    if (_pathExists(apatchDaemonPath)) {
      // folkpatch 是 APatch 的分支，守护进程同样是 /data/adb/apd。
      method = 'folkpatch/APatch';
      detail = apatchDaemonPath;
    } else if (_pathExists(ksuPath)) {
      method = 'KernelSU';
      detail = ksuPath;
    } else if (magiskPaths.any(_pathExists)) {
      method = 'Magisk';
      detail = magiskPaths.firstWhere(_pathExists);
    }

    // 3) 常见 su 路径 + which su 兜底。
    String? suPath;
    for (final p in suPaths) {
      if (_pathExists(p)) {
        suPath = p;
        break;
      }
    }
    suPath ??= await _whichSu();

    if (suWorks) {
      return RootStatus(
        isRooted: true,
        method: method ?? 'su',
        detail: detail ?? suPath,
        checkedAt: now,
      );
    }
    // su 命令没跑通（例如用户未在授权弹窗里点允许），但特征文件或
    // su 二进制存在，同样判定为已 root。
    if (method != null || suPath != null) {
      return RootStatus(
        isRooted: true,
        method: method ?? 'su',
        detail: detail ?? suPath,
        checkedAt: now,
      );
    }
    return RootStatus.notRooted(checkedAt: now);
  }

  /// 执行 `su -c id`，输出含 `uid=0` 且退出码为 0 即成功。
  /// 超时或启动失败时返回 false（不抛异常）。
  Future<bool> _trySuId() async {
    Process? process;
    try {
      process = await Process.start('su', ['-c', 'id']);
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(
        suTimeout,
        onTimeout: () {
          process?.kill();
          return -1;
        },
      );
      final output = await stdoutFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () => '',
      );
      return exitCode == 0 && output.contains('uid=0');
    } catch (_) {
      process?.kill();
      return false;
    }
  }

  /// `which su` 兜底：返回 su 的完整路径，找不到返回 null。
  Future<String?> _whichSu() async {
    try {
      final result = await Process.run(
        'which',
        ['su'],
      ).timeout(const Duration(seconds: 3));
      final output = result.stdout.toString().trim();
      if (result.exitCode == 0 && output.isNotEmpty) {
        return output.split('\n').first.trim();
      }
    } catch (_) {
      // which 不存在或超时都视为找不到。
    }
    return null;
  }

  bool _pathExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}
