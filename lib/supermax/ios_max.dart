import 'dart:io';

/// iOS MAX 环境。
///
/// - [notJailbroken]：未越狱（App Store / 普通侧载），Super MAX 不可用。
/// - [trollStore]：通过 TrollStore 安装（未越狱）：App 未被沙盒限制，
///   能读写 mobile 用户权限范围内的文件，但没有 root。
/// - [jailbrokenRootless]：已越狱 Rootless（Dopamine / palera1n
///   rootless 等）：系统文件在 /var/jb 前缀下，插件需用 rootless 方案。
/// - [jailbrokenRootful]：已越狱 Rootful（palera1n rootful / checkra1n 等）。
enum IOSMaxEnvironment {
  /// 尚未检测。
  unknown,

  /// 未越狱。
  notJailbroken,

  /// TrollStore 安装（未越狱）。
  trollStore,

  /// 已越狱（Rootless）。
  jailbrokenRootless,

  /// 已越狱（Rootful）。
  jailbrokenRootful,
}

extension IOSMaxEnvironmentX on IOSMaxEnvironment {
  /// 界面显示的中文名。
  String get label => switch (this) {
        IOSMaxEnvironment.unknown => '尚未检测',
        IOSMaxEnvironment.notJailbroken => '未越狱',
        IOSMaxEnvironment.trollStore => 'TrollStore（未越狱）',
        IOSMaxEnvironment.jailbrokenRootless => '已越狱（Rootless）',
        IOSMaxEnvironment.jailbrokenRootful => '已越狱（Rootful）',
      };

  /// 该环境下 Super MAX 开关是否可用。
  ///
  /// TrollStore 安装即算可用（无沙盒限制，能做系统级文件操作）；
  /// 越狱当然可用；未越狱不可用。
  bool get maxAvailable => switch (this) {
        IOSMaxEnvironment.trollStore ||
        IOSMaxEnvironment.jailbrokenRootless ||
        IOSMaxEnvironment.jailbrokenRootful =>
          true,
        _ => false,
      };

  /// 一句话说明（设置页用）。
  String get description => switch (this) {
        IOSMaxEnvironment.unknown => '尚未检测 iOS 环境',
        IOSMaxEnvironment.notJailbroken =>
          '未越狱：Super MAX 需要越狱或通过 TrollStore 安装',
        IOSMaxEnvironment.trollStore =>
          'TrollStore 安装：无沙盒限制，可用 Super MAX（无 root）',
        IOSMaxEnvironment.jailbrokenRootless =>
          '已越狱（Rootless）：可用 Super MAX，插件需用 rootless 方案',
        IOSMaxEnvironment.jailbrokenRootful =>
          '已越狱（Rootful）：可用 Super MAX，配合插件能力最全',
      };
}

/// iOS MAX 环境检测结果。
class IOSMaxStatus {
  /// 检测到的环境。
  final IOSMaxEnvironment environment;

  /// 检测依据（如命中的特征路径、沙盒探测结果），供界面展示与排障。
  final List<String> evidence;

  /// 沙盒探测结果：能否看到 /var/mobile/Library（true 表示未被沙盒限制）。
  final bool unsandboxed;

  /// 本次检测的时间。
  final DateTime checkedAt;

  const IOSMaxStatus({
    required this.environment,
    this.evidence = const [],
    this.unsandboxed = false,
    required this.checkedAt,
  });

  factory IOSMaxStatus.unknown({DateTime? checkedAt}) => IOSMaxStatus(
        environment: IOSMaxEnvironment.unknown,
        checkedAt: checkedAt ?? DateTime.now(),
      );

  /// Super MAX 是否可用（越狱或 TrollStore）。
  bool get maxAvailable => environment.maxAvailable;

  /// 该环境下可用的能力（设置页展示）。
  List<String> get capabilities => switch (environment) {
        IOSMaxEnvironment.jailbrokenRootful => _capabilitiesJailbroken,
        IOSMaxEnvironment.jailbrokenRootless => _capabilitiesJailbroken,
        IOSMaxEnvironment.trollStore => _capabilitiesTrollStore,
        _ => const [],
      };

  /// 该环境下不可用 / 受限的能力（设置页展示）。
  List<String> get limitations => switch (environment) {
        IOSMaxEnvironment.jailbrokenRootful => _limitationsJailbroken,
        IOSMaxEnvironment.jailbrokenRootless => _limitationsJailbrokenRootless,
        IOSMaxEnvironment.trollStore => _limitationsTrollStore,
        IOSMaxEnvironment.notJailbroken => _limitationsNotJailbroken,
        _ => const [],
      };

  static const List<String> _capabilitiesJailbroken = [
    '系统偏好读写（经 SuperAppMax 插件 IPC，AI 调设置）',
    '沙盒外文件读写，WebOS 文件管理器访问真实文件系统',
    'respring 与系统守护进程管理（需安装插件）',
    '配合插件注入其他 App、Hook SpringBoard',
  ];

  static const List<String> _limitationsJailbroken = [
    '需要安装 SuperAppMax 插件（见 ios-max/README.md），否则只有检测，没有系统级能力',
  ];

  static const List<String> _limitationsJailbrokenRootless = [
    'Rootless 越狱：插件需用 rootless 方案编译，root 写操作需 root 守护进程配合（待实现）',
    '需要安装 SuperAppMax 插件（见 ios-max/README.md），否则只有检测，没有系统级能力',
  ];

  static const List<String> _capabilitiesTrollStore = [
    '沙盒外文件读写（mobile 用户权限），WebOS 文件管理器访问真实文件系统',
    '读取系统偏好设置文件',
    '运行自带辅助工具，无需越狱注入',
  ];

  static const List<String> _limitationsTrollStore = [
    '无 root 权限：不能修改 root 拥有的系统文件与设置',
    '不能注入其他 App、Hook SpringBoard（需越狱 + 安装插件）',
    '修改系统偏好仅限 mobile 用户可写的域',
  ];

  static const List<String> _limitationsNotJailbroken = [
    'Super MAX 不可用：需要越狱，或通过 TrollStore 安装（见 ios-max/README.md）',
    '只能用应用内功能：计算器、AiPlat、WebOS 内置应用等',
  ];

  @override
  String toString() =>
      'IOSMaxStatus(environment: $environment, unsandboxed: $unsandboxed)';
}

/// iOS MAX 环境检测器。
///
/// 检测策略（全部是 best-effort，任何一步抛异常都视为“没看到”，绝不崩溃）：
/// 1. 越狱特征路径（Rootful 的 Cydia / MobileSubstrate 等，Rootless 的 /var/jb）；
/// 2. `DYLD_INSERT_LIBRARIES` 环境变量（有代码注入时存在）；
/// 3. TrollStore 特征路径；
/// 4. 沙盒探测：能否看到 /var/mobile/Library（沙盒内的 App 看不到）。
///
/// 注意：这只是环境检测，不是安全判定；结果仅供开关与界面展示用。
/// 越狱检测本身存在误报/漏报可能（例如用户手动创建了同名文件），
/// 不要把它当作鉴权依据。
class IOSMaxDetector {
  /// Rootful 越狱特征路径（Cydia / MobileSubstrate 等）。
  static const List<String> jailbreakPaths = [
    '/Applications/Cydia.app',
    '/Library/MobileSubstrate/MobileSubstrate.dylib',
    '/Library/MobileSubstrate/DynamicLibraries',
    '/Library/PreferenceBundles/CydiaSettings.bundle',
    '/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist',
    '/usr/sbin/sshd',
    '/usr/bin/ssh',
    '/usr/lib/libsubstrate.dylib',
    '/etc/apt',
    '/bin/bash',
    '/private/var/lib/apt',
    '/private/var/lib/cydia',
    '/private/var/tmp/cydia.log',
    '/var/cache/apt',
    '/var/mobile/Library/Caches/com.saurik.Cydia',
  ];

  /// Rootless 越狱特征路径（Dopamine / palera1n rootless 等）。
  static const List<String> rootlessPaths = [
    '/var/jb',
    '/var/jb/usr/lib/libsubstrate.dylib',
    '/var/jb/Applications',
    '/var/jb/Library/MobileSubstrate',
    '/var/jb/bin/bash',
  ];

  /// TrollStore 特征路径。
  static const List<String> trollStorePaths = [
    '/Applications/TrollStore.app',
    '/var/mobile/Library/TrollStore',
    '/private/var/mobile/Library/TrollStore',
  ];

  IOSMaxStatus? _cached;

  /// 上次检测结果（可能为 null，表示尚未检测过）。
  IOSMaxStatus? get cachedStatus => _cached;

  /// 清除缓存，下次检测会重新执行。
  void clearCache() => _cached = null;

  /// 检测 iOS MAX 环境。默认使用缓存，[force] 为 true 时强制重新检测。
  Future<IOSMaxStatus> detect({bool force = false}) async {
    if (!force && _cached != null) return _cached!;
    final status = _detect();
    _cached = status;
    return status;
  }

  IOSMaxStatus _detect() {
    final now = DateTime.now();
    bool isIOS = false;
    try {
      isIOS = Platform.isIOS;
    } catch (_) {
      isIOS = false;
    }
    if (!isIOS) {
      return IOSMaxStatus.unknown(checkedAt: now);
    }

    final evidence = <String>[];

    // 1) 越狱特征路径。
    final jbHits = jailbreakPaths.where(_pathExists).toList();
    final rootlessHits = rootlessPaths.where(_pathExists).toList();
    for (final p in [...jbHits, ...rootlessHits]) {
      evidence.add('发现越狱特征路径：$p');
    }

    // 2) 代码注入环境变量。
    final dyldInsert = _hasDyldInsertLibraries();
    if (dyldInsert) {
      evidence.add('检测到 DYLD_INSERT_LIBRARIES（有代码注入）');
    }

    // 3) TrollStore 特征路径。
    final tsHits = trollStorePaths.where(_pathExists).toList();
    for (final p in tsHits) {
      evidence.add('发现 TrollStore 特征路径：$p');
    }

    // 4) 沙盒探测。
    final unsandboxed = _probeUnsandboxed();
    if (unsandboxed) {
      evidence.add('沙盒探测：可访问 /var/mobile/Library（未被沙盒限制）');
    }

    // 分类：越狱优先于 TrollStore（越狱设备也可能装了 TrollStore）。
    IOSMaxEnvironment environment;
    if (jbHits.isNotEmpty || rootlessHits.isNotEmpty || dyldInsert) {
      environment = rootlessHits.isNotEmpty
          ? IOSMaxEnvironment.jailbrokenRootless
          : IOSMaxEnvironment.jailbrokenRootful;
    } else if (tsHits.isNotEmpty || unsandboxed) {
      environment = IOSMaxEnvironment.trollStore;
    } else {
      environment = IOSMaxEnvironment.notJailbroken;
    }

    return IOSMaxStatus(
      environment: environment,
      evidence: evidence,
      unsandboxed: unsandboxed,
      checkedAt: now,
    );
  }

  bool _pathExists(String path) {
    try {
      return File(path).existsSync() || Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  bool _hasDyldInsertLibraries() {
    try {
      final value = Platform.environment['DYLD_INSERT_LIBRARIES'];
      return value != null && value.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 沙盒探测：沙盒内的 App 无法看到 /var/mobile/Library；
  /// 能看到（目录存在或系统偏好文件存在）即未被沙盒限制。
  /// 只读探测，不写任何文件。
  bool _probeUnsandboxed() {
    try {
      if (Directory('/var/mobile/Library/Preferences').existsSync()) {
        return true;
      }
    } catch (_) {
      // 看不到就当作仍在沙盒里。
    }
    try {
      if (File('/var/mobile/Library/Preferences/com.apple.springboard.plist')
          .existsSync()) {
        return true;
      }
    } catch (_) {
      // 同上。
    }
    return false;
  }
}
