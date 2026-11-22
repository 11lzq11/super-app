/// Super MAX 工具箱的命令库。
///
/// 纯 Dart，无 Flutter 依赖，可单元测试。所有 root 命令的构建、
/// AI 返回的 JSON 命令解析、命令输出的解析都在这里；
/// UI 层只负责展示、确认、执行（走 SuperMaxService.runRootCommand，
/// 高危命令先用 RootShell.isDangerous 判断并弹窗确认）。
///
/// 命令映射约定（Android）：
/// - 系统设置：`settings get/put/list/delete <表> <键> [值]`，
///   表只能是 system / secure / global；
/// - 服务开关：`svc wifi|bluetooth|data|nfc enable|disable`；
/// - 应用：`pm disable-user/enable/uninstall/clear` + `am force-stop`；
/// - 其他见各段注释。
library;

import 'dart:convert';

/// 一条待执行的系统命令。
class SystemCommand {
  const SystemCommand({
    required this.command,
    required this.description,
  });

  /// 实际执行的 shell 命令。
  final String command;

  /// 给用户看的中文说明（确认框里展示）。
  final String description;

  @override
  String toString() => '$description：$command';
}

/// 给 shell 用的单引号转义：`'` → `'\''`，外面包一层单引号。
/// 用于用户输入的路径、文件名等，避免注入。
String shellQuote(String value) {
  return "'${value.replaceAll("'", "'\\''")}'";
}

/// 包名校验（与应用管理页一致）：`com.example.app` 形式。
bool isValidPackageName(String name) {
  return RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$').hasMatch(name);
}

/// 域名校验（广告屏蔽用）。
bool isValidDomain(String domain) {
  return RegExp(
    r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$',
  ).hasMatch(domain);
}

// ---------------------------------------------------------------------------
// 系统设置：settings 表
// ---------------------------------------------------------------------------

/// settings 表名白名单。
const List<String> settingsTables = ['system', 'secure', 'global'];

bool isValidSettingsTable(String table) => settingsTables.contains(table);

/// settings 键名白名单格式：字母数字下划线。
bool isValidSettingsKey(String key) {
  return RegExp(r'^[A-Za-z0-9_]+$').hasMatch(key);
}

/// 常用设置键的中文名（用于命令说明；不在表里的键直接显示键名）。
const Map<String, String> knownSettingsKeys = {
  'screen_brightness': '屏幕亮度',
  'screen_brightness_mode': '亮度模式',
  'screen_off_timeout': '屏幕超时',
  'window_animation_scale': '窗口动画速度',
  'transition_animation_scale': '过渡动画速度',
  'animator_duration_scale': '动画时长缩放',
  'font_scale': '字体大小',
  'zen_mode': '勿扰模式',
  'accelerometer_rotation': '自动旋转',
  'low_power': '省电模式',
  'peak_refresh_rate': '最高刷新率',
  'min_refresh_rate': '最低刷新率',
  'airplane_mode_on': '飞行模式',
  'wifi_on': 'WiFi 开关',
  'bluetooth_on': '蓝牙开关',
};

String settingsKeyLabel(String key) => knownSettingsKeys[key] ?? key;

/// 读一条设置：`settings get <表> <键>`。
SystemCommand settingsGet(String table, String key) {
  return SystemCommand(
    command: 'settings get $table $key',
    description: '读取设置 ${settingsKeyLabel(key)}',
  );
}

/// 写一条设置：`settings put <表> <键> <值>`。
SystemCommand settingsPut(String table, String key, String value) {
  return SystemCommand(
    command: 'settings put $table $key ${shellQuote(value)}',
    description: '设置 ${settingsKeyLabel(key)} 为 $value',
  );
}

/// 删除一条设置：`settings delete <表> <键>`。
SystemCommand settingsDelete(String table, String key) {
  return SystemCommand(
    command: 'settings delete $table $key',
    description: '删除设置 ${settingsKeyLabel(key)}',
  );
}

/// 列出整个表：`settings list <表>`。
String settingsListCommand(String table) => 'settings list $table';

/// 解析 `settings list` 输出：每行 `键=值`，值里可能含 `=`。
/// 忽略空行与不含 `=` 的行。
Map<String, String> parseSettingsList(String output) {
  final result = <String, String>{};
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    if (!isValidSettingsKey(key)) continue;
    result[key] = line.substring(eq + 1);
  }
  return result;
}

// ---------------------------------------------------------------------------
// AI 调设置：JSON 命令解析
// ---------------------------------------------------------------------------

/// AI 返回的 JSON 解析结果。
class AiCommandParseResult {
  const AiCommandParseResult({
    required this.commands,
    required this.ignored,
    this.error,
  });

  /// 通过白名单校验、可执行的命令。
  final List<SystemCommand> commands;

  /// 被忽略的条目及原因（如 action 不在白名单、参数非法）。
  final List<String> ignored;

  /// 整体解析失败时的原因（如不是 JSON）；失败时 commands 为空。
  final String? error;

  bool get success => error == null;
}

/// AI 命令的 action 白名单。
const List<String> aiAllowedActions = [
  'settings_put',
  'svc',
  'wm',
  'night',
  'input',
];

const List<String> _svcServices = ['wifi', 'bluetooth', 'data', 'nfc'];
const Map<String, String> _svcServiceLabels = {
  'wifi': 'WiFi',
  'bluetooth': '蓝牙',
  'data': '移动数据',
  'nfc': 'NFC',
};

/// 解析 AI 返回的文本，提取 JSON 命令列表并做白名单校验。
///
/// - 兼容 ```json 代码块包裹；
/// - 找不到 JSON 对象或 JSON 非法时返回 error；
/// - action 不在白名单、参数不合法的条目会被忽略并记录原因，
///   其余合法命令正常返回。
AiCommandParseResult parseAiCommandList(String text) {
  // 去掉 ```json 代码块包裹。
  var cleaned = text.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
  final fenceMatch = fence.firstMatch(cleaned);
  if (fenceMatch != null) {
    cleaned = fenceMatch.group(1)!.trim();
  }
  // 取第一个 { 到最后一个 } 之间的内容（容忍前后多余文字）。
  final start = cleaned.indexOf('{');
  final end = cleaned.lastIndexOf('}');
  if (start < 0 || end < 0 || end <= start) {
    return const AiCommandParseResult(
      commands: [],
      ignored: [],
      error: 'AI 没有返回有效的 JSON 命令',
    );
  }
  dynamic decoded;
  try {
    decoded = jsonDecode(cleaned.substring(start, end + 1));
  } catch (_) {
    return const AiCommandParseResult(
      commands: [],
      ignored: [],
      error: 'AI 返回的 JSON 无法解析',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    return const AiCommandParseResult(
      commands: [],
      ignored: [],
      error: 'AI 返回的 JSON 不是对象',
    );
  }
  final rawList = decoded['commands'];
  if (rawList == null) {
    return const AiCommandParseResult(
      commands: [],
      ignored: [],
      error: 'AI 返回的 JSON 里没有 commands 列表',
    );
  }
  if (rawList is! List) {
    return const AiCommandParseResult(
      commands: [],
      ignored: [],
      error: 'commands 不是列表',
    );
  }
  final commands = <SystemCommand>[];
  final ignored = <String>[];
  for (var i = 0; i < rawList.length; i++) {
    final item = rawList[i];
    final parsed = _parseOneAiCommand(item);
    if (parsed != null) {
      commands.add(parsed);
    } else {
      ignored.add('第 ${i + 1} 条命令无法识别或参数不合法，已忽略');
    }
  }
  return AiCommandParseResult(commands: commands, ignored: ignored);
}

/// 解析 AI 命令列表里的一条；不合法返回 null。
SystemCommand? _parseOneAiCommand(dynamic item) {
  if (item is! Map<String, dynamic>) return null;
  final action = item['action'];
  if (action is! String) return null;
  switch (action) {
    case 'settings_put':
      final table = item['table'];
      final key = item['key'];
      final value = item['value'];
      if (table is! String ||
          key is! String ||
          value == null ||
          !isValidSettingsTable(table) ||
          !isValidSettingsKey(key)) {
        return null;
      }
      final valueStr = value.toString();
      if (valueStr.isEmpty || valueStr.length > 256) return null;
      return settingsPut(table, key, valueStr);
    case 'svc':
      final service = item['service'];
      final state = item['state'];
      if (service is! String ||
          state is! String ||
          !_svcServices.contains(service) ||
          (state != 'enable' && state != 'disable')) {
        return null;
      }
      final label = _svcServiceLabels[service] ?? service;
      return SystemCommand(
        command: 'svc $service $state',
        description: state == 'enable' ? '开启$label' : '关闭$label',
      );
    case 'wm':
      final size = item['size'];
      final density = item['density'];
      if (size is String && size.isNotEmpty) {
        if (size != 'reset' && !RegExp(r'^\d+x\d+$').hasMatch(size)) {
          return null;
        }
        return SystemCommand(
          command: 'wm size $size',
          description: size == 'reset' ? '恢复默认屏幕尺寸' : '设置屏幕尺寸为 $size',
        );
      }
      if (density is String && density.isNotEmpty) {
        if (density != 'reset' && !RegExp(r'^\d{2,4}$').hasMatch(density)) {
          return null;
        }
        return SystemCommand(
          command: 'wm density $density',
          description: density == 'reset' ? '恢复默认屏幕密度' : '设置屏幕密度为 $density',
        );
      }
      return null;
    case 'night':
      final value = item['value'];
      if (value != 'yes' && value != 'no') return null;
      return SystemCommand(
        command: 'cmd uimode night $value',
        description: value == 'yes' ? '开启深色模式' : '关闭深色模式',
      );
    case 'input':
      final keycode = item['keycode'];
      final code = keycode is int
          ? keycode
          : (keycode is String ? int.tryParse(keycode) : null);
      if (code == null || code < 0 || code > 1000) return null;
      return SystemCommand(
        command: 'input keyevent $code',
        description: '模拟按键 $code',
      );
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// 应用管理：pm / am
// ---------------------------------------------------------------------------

/// 冻结应用（仅当前用户）：`pm disable-user --user 0 <包名>`。
SystemCommand pmDisable(String packageName) {
  _requirePackage(packageName);
  return SystemCommand(
    command: 'pm disable-user --user 0 $packageName',
    description: '冻结应用 $packageName',
  );
}

/// 解冻应用：`pm enable <包名>`。
SystemCommand pmEnable(String packageName) {
  _requirePackage(packageName);
  return SystemCommand(
    command: 'pm enable $packageName',
    description: '解冻应用 $packageName',
  );
}

/// 卸载应用（仅当前用户，系统应用一般可用 pm install-existing 恢复）：
/// `pm uninstall --user 0 <包名>`。
SystemCommand pmUninstall(String packageName) {
  _requirePackage(packageName);
  return SystemCommand(
    command: 'pm uninstall --user 0 $packageName',
    description: '卸载应用 $packageName',
  );
}

/// 清除应用数据：`pm clear <包名>`。
SystemCommand pmClear(String packageName) {
  _requirePackage(packageName);
  return SystemCommand(
    command: 'pm clear $packageName',
    description: '清除应用数据 $packageName',
  );
}

/// 强制停止应用：`am force-stop <包名>`。
SystemCommand pmForceStop(String packageName) {
  _requirePackage(packageName);
  return SystemCommand(
    command: 'am force-stop $packageName',
    description: '强制停止 $packageName',
  );
}

/// 取应用 APK 路径：`pm path <包名>`。
String pmPathCommand(String packageName) {
  _requirePackage(packageName);
  return 'pm path $packageName';
}

void _requirePackage(String packageName) {
  if (!isValidPackageName(packageName)) {
    throw ArgumentError('包名不合法：$packageName');
  }
}

/// 解析 `pm list packages` 输出：每行 `package:<包名>`。
List<String> parsePmPackages(String output) {
  final packages = <String>[];
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (!line.startsWith('package:')) continue;
    final name = line.substring('package:'.length).trim();
    if (isValidPackageName(name)) packages.add(name);
  }
  packages.sort();
  return packages;
}

/// 解析 `pm path` 输出：`package:/data/app/.../base.apk` → APK 路径。
String? parsePmPath(String output) {
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (!line.startsWith('package:')) continue;
    final path = line.substring('package:'.length).trim();
    if (path.isNotEmpty) return path;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Root 文件管理：ls / cat / rm
// ---------------------------------------------------------------------------

/// `ls -la` 的一条记录。
class RootFileEntry {
  const RootFileEntry({
    required this.name,
    required this.isDirectory,
    required this.isSymlink,
    required this.size,
    required this.permissions,
    this.linkTarget,
  });

  final String name;
  final bool isDirectory;
  final bool isSymlink;

  /// 文件大小（字节）；目录为 4096 等占位值。
  final int size;

  /// 如 `drwxr-xr-x`。
  final String permissions;

  /// 软链接指向的目标（非链接时为 null）。
  final String? linkTarget;

  /// 展示用大小：B / KB / MB / GB。
  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// 列目录：`ls -la <路径>`。
String lsCommand(String path) => 'ls -la ${shellQuote(path)}';

/// 解析 `ls -la` 输出。跳过 total 行与 . / ..，目录排前面再按名字排序。
List<RootFileEntry> parseLsLa(String output) {
  final entries = <RootFileEntry>[];
  final linePattern = RegExp(
    r'^([dlbcps-][rwxst-]{9})\s+\d+\s+\S+\s+\S+\s+(\d+)\s+'
    r'[A-Za-z]{3}\s+\d+\s+(?:\d{2}:\d{2}|\d{4})\s+(.+)$',
  );
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty || line.startsWith('total ')) continue;
    final match = linePattern.firstMatch(line);
    if (match == null) continue;
    final perms = match.group(1)!;
    final size = int.tryParse(match.group(2)!) ?? 0;
    var name = match.group(3)!;
    String? linkTarget;
    if (perms.startsWith('l') && name.contains(' -> ')) {
      final parts = name.split(' -> ');
      name = parts.first;
      linkTarget = parts.sublist(1).join(' -> ');
    }
    if (name == '.' || name == '..') continue;
    entries.add(
      RootFileEntry(
        name: name,
        isDirectory: perms.startsWith('d'),
        isSymlink: perms.startsWith('l'),
        size: size,
        permissions: perms,
        linkTarget: linkTarget,
      ),
    );
  }
  entries.sort((a, b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return entries;
}

/// 文本文件后缀白名单（用于决定是否提供「查看」）。
const List<String> textFileExtensions = [
  '.txt', '.log', '.json', '.xml', '.prop', '.conf', '.cfg', '.ini',
  '.sh', '.rc', '.md', '.csv', '.html', '.css', '.js', '.py', '.java',
  '.kt', '.gradle', '.yaml', '.yml', '.toml',
];

/// 按后缀判断文件是否大概率是文本（可预览）。
bool isTextFile(String name) {
  final lower = name.toLowerCase();
  return textFileExtensions.any(lower.endsWith);
}

/// 查看文本文件前 64KB：`head -c 65536 <路径>`。
String catCommand(String path, {int maxBytes = 65536}) {
  return 'head -c $maxBytes ${shellQuote(path)}';
}

/// 删除文件/空目录：`rm <路径>`；目录用 `rm -rf`（高危，走确认）。
SystemCommand rmCommand(String path, {required bool isDirectory}) {
  if (isDirectory) {
    return SystemCommand(
      command: 'rm -rf ${shellQuote(path)}',
      description: '删除目录 $path（递归）',
    );
  }
  return SystemCommand(
    command: 'rm ${shellQuote(path)}',
    description: '删除文件 $path',
  );
}

/// 根目录快捷入口。
const List<String> rootQuickPaths = [
  '/',
 '/system',
  '/data',
  '/data/data',
  '/data/app',
  '/sdcard',
];

// ---------------------------------------------------------------------------
// 性能调节：CPU 调速器 / 刷新率 / 省电
// ---------------------------------------------------------------------------

const String _cpuFreqDir = '/sys/devices/system/cpu/cpu0/cpufreq';

/// 读当前调速器。
String governorGetCommand() => 'cat $_cpuFreqDir/scaling_governor';

/// 读可用调速器列表。
String governorListCommand() => 'cat $_cpuFreqDir/scaling_available_governors';

/// 读当前频率（KHz）。
String cpuFreqGetCommand() => 'cat $_cpuFreqDir/scaling_cur_freq';

/// 读最高频率（KHz）。
String cpuMaxFreqGetCommand() => 'cat $_cpuFreqDir/scaling_max_freq';

/// 设置全部 CPU 核心的调速器。
SystemCommand governorSet(String governor) {
  if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(governor)) {
    throw ArgumentError('调速器名不合法：$governor');
  }
  return SystemCommand(
    command:
        'for c in /sys/devices/system/cpu/cpu[0-9]*; do '
        'echo $governor > \$c/cpufreq/scaling_governor; done',
    description: '设置 CPU 调速器为 $governor',
  );
}

/// 读最高/最低刷新率设置。
String refreshRateGetCommand({required bool peak}) {
  return 'settings get system ${peak ? 'peak_refresh_rate' : 'min_refresh_rate'}';
}

/// 设置最高/最低刷新率（Hz）。
SystemCommand refreshRateSet(int hz, {required bool peak}) {
  if (hz < 30 || hz > 240) {
    throw ArgumentError('刷新率超出范围：$hz');
  }
  return SystemCommand(
    command:
        'settings put system ${peak ? 'peak_refresh_rate' : 'min_refresh_rate'} $hz',
    description: '设置${peak ? '最高' : '最低'}刷新率为 ${hz}Hz',
  );
}

/// 省电模式开关：`settings put global low_power 1/0`。
SystemCommand powerSaveSet(bool on) {
  return SystemCommand(
    command: 'settings put global low_power ${on ? 1 : 0}',
    description: on ? '开启省电模式' : '关闭省电模式',
  );
}

/// 读省电模式状态。
String powerSaveGetCommand() => 'settings get global low_power';

// ---------------------------------------------------------------------------
// 广告屏蔽：hosts
// ---------------------------------------------------------------------------

/// 系统 hosts 文件。
const String hostsSystemPath = '/system/etc/hosts';

/// Magisk/APatch systemless hosts 模块的 hosts 文件（存在时优先用它，
/// 无需重新挂载 /system）。
const String hostsModulePath = '/data/adb/modules/hosts/system/etc/hosts';

/// hosts 备份位置（用户可访问的存储）。
const String hostsBackupPath = '/sdcard/SuperApp/hosts.bak';

/// 内置屏蔽域名（常见广告/统计域名）。
const List<String> adBlockDomains = [
  'doubleclick.net',
  'googleadservices.com',
  'googlesyndication.com',
  'googletagmanager.com',
  'google-analytics.com',
  'analytics.google.com',
  'ads.google.com',
  'adservice.google.com',
  'pagead2.googlesyndication.com',
  'admob.com',
  'ads.yahoo.com',
  'adsystem.com',
  'advertising.com',
  'adnxs.com',
  'adsrvr.org',
  'criteo.com',
  'moatads.com',
  'scorecardresearch.com',
  'quantserve.com',
  'connect.facebook.net',
  'graph.facebook.com',
  'umeng.com',
  'umengcloud.com',
  'admobile.top',
  'ad.sogou.com',
  'pos.baidu.com',
  'hm.baidu.com',
  'ad.baidu.com',
  'union.baidu.com',
];

/// 备份当前 hosts：`cp <源> <备份>`。
SystemCommand hostsBackup(String sourcePath) {
  return SystemCommand(
    command: 'cp ${shellQuote(sourcePath)} ${shellQuote(hostsBackupPath)}',
    description: '备份 hosts 到 $hostsBackupPath',
  );
}

/// 从备份恢复 hosts。
SystemCommand hostsRestore(String targetPath) {
  return SystemCommand(
    command: 'cp ${shellQuote(hostsBackupPath)} ${shellQuote(targetPath)}',
    description: '从备份恢复 hosts',
  );
}

/// 重新挂载 /system 为可写（高危，执行前必须弹窗确认）。
SystemCommand hostsRemount() {
  return const SystemCommand(
    command: 'mount -o remount,rw /system',
    description: '重新挂载 /system 为可写',
  );
}

/// 向 hosts 追加屏蔽条目（已存在的域名跳过）。
/// 用 shell 循环逐条检查，避免重复写入。
SystemCommand hostsApply(String hostsPath, List<String> domains) {
  final valid = domains.where(isValidDomain).toList();
  if (valid.isEmpty) {
    throw ArgumentError('没有有效的屏蔽域名');
  }
  final list = valid.join(' ');
  return SystemCommand(
    command:
        'for d in $list; do '
        'grep -q " \$d\$" ${shellQuote(hostsPath)} || '
        'echo "0.0.0.0 \$d" >> ${shellQuote(hostsPath)}; done',
    description: '向 hosts 写入 ${valid.length} 条屏蔽规则',
  );
}

/// 读 hosts 文件内容。
String hostsReadCommand(String path) => 'cat ${shellQuote(path)}';

/// 检查文件是否可写：`test -w <路径> && echo yes || echo no`。
String hostsWritableCheckCommand(String path) {
  return 'test -w ${shellQuote(path)} && echo yes || echo no';
}

// ---------------------------------------------------------------------------
// 应用备份：APK + 数据
// ---------------------------------------------------------------------------

/// 备份根目录（用户可访问的存储）。
const String backupRootDir = '/sdcard/SuperApp/backup';

/// 某应用的备份目录。
String backupDirFor(String packageName) => '$backupRootDir/$packageName';

/// 备份 APK：`cp <APK路径> <备份目录>/base.apk`。
SystemCommand backupApk(String packageName, String apkPath) {
  _requirePackage(packageName);
  final dir = backupDirFor(packageName);
  return SystemCommand(
    command:
        'mkdir -p ${shellQuote(dir)} && cp ${shellQuote(apkPath)} ${shellQuote('$dir/base.apk')}',
    description: '备份 $packageName 的 APK',
  );
}

/// 备份应用数据：`tar -czf <备份目录>/data.tar.gz -C /data/data <包名>`。
SystemCommand backupData(String packageName) {
  _requirePackage(packageName);
  final dir = backupDirFor(packageName);
  return SystemCommand(
    command:
        'mkdir -p ${shellQuote(dir)} && '
        'tar -czf ${shellQuote('$dir/data.tar.gz')} -C /data/data $packageName',
    description: '备份 $packageName 的数据（/data/data）',
  );
}

/// 恢复 APK：`pm install -r <备份目录>/base.apk`。
SystemCommand restoreApk(String packageName) {
  _requirePackage(packageName);
  final dir = backupDirFor(packageName);
  return SystemCommand(
    command: 'pm install -r ${shellQuote('$dir/base.apk')}',
    description: '恢复 $packageName 的 APK',
  );
}

/// 恢复应用数据：解压 + 修正属主 + 恢复 SELinux 标签。
/// 必须在应用已安装且已停止的状态下执行；[uid] 从 dumpsys 取。
SystemCommand restoreData(String packageName, String uid) {
  _requirePackage(packageName);
  if (!RegExp(r'^\d+$').hasMatch(uid)) {
    throw ArgumentError('uid 不合法：$uid');
  }
  final dir = backupDirFor(packageName);
  return SystemCommand(
    command:
        'tar -xzf ${shellQuote('$dir/data.tar.gz')} -C /data/data && '
        'chown -R $uid:$uid /data/data/$packageName && '
        'restorecon -R /data/data/$packageName',
    description: '恢复 $packageName 的数据',
  );
}

/// 取应用 uid：`dumpsys package <包名>`。
String dumpsysPackageCommand(String packageName) {
  _requirePackage(packageName);
  return 'dumpsys package $packageName';
}

/// 解析 `dumpsys package` 输出里的 `userId=数字`。
String? parseDumpsysUserId(String output) {
  final match = RegExp(r'userId=(\d+)').firstMatch(output);
  return match?.group(1);
}

/// 列出备份目录：`ls <备份根目录>`。
String backupListCommand() => 'ls $backupRootDir';

// ---------------------------------------------------------------------------
// 开机自启管理：BOOT_COMPLETED 接收器
// ---------------------------------------------------------------------------

/// 一个开机启动接收器。
class BootReceiver {
  const BootReceiver({
    required this.packageName,
    required this.componentName,
  });

  /// 应用包名。
  final String packageName;

  /// 组件名（可能以 `.` 开头，如 `.BootReceiver`）。
  final String componentName;

  /// 完整组件名：`包名/组件名`，用于 pm disable/enable。
  String get fullName => '$packageName/$componentName';

  /// 显示用：`包名/组件名`。
  @override
  String toString() => fullName;

  @override
  bool operator ==(Object other) =>
      other is BootReceiver &&
      other.packageName == packageName &&
      other.componentName == componentName;

  @override
  int get hashCode => Object.hash(packageName, componentName);
}

/// 列出声明了 BOOT_COMPLETED 的接收器（组件形式）。
String bootReceiversCommand() {
  return 'pm query-receivers --components -a android.intent.action.BOOT_COMPLETED';
}

/// 解析 `pm query-receivers --components` 输出。
///
/// 兼容两种格式：
/// - 组件行：`com.example/.BootReceiver`；
/// - 键值行：`packageName=com.example` 后跟 `name=.BootReceiver`。
/// 去重后按包名排序。
List<BootReceiver> parseBootReceivers(String output) {
  final found = <BootReceiver>{};
  final componentPattern = RegExp(
    r'^\s*([a-zA-Z][a-zA-Z0-9_.]*)/([a-zA-Z0-9_.$]+)\s*$',
  );
  String? pendingPackage;
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('Receiver #')) continue;
    final componentMatch = componentPattern.firstMatch(line);
    if (componentMatch != null) {
      final pkg = componentMatch.group(1)!;
      final comp = componentMatch.group(2)!;
      if (isValidPackageName(pkg)) {
        found.add(BootReceiver(packageName: pkg, componentName: comp));
      }
      pendingPackage = null;
      continue;
    }
    if (line.startsWith('packageName=')) {
      pendingPackage = line.substring('packageName='.length).trim();
      continue;
    }
    if (line.startsWith('name=') && pendingPackage != null) {
      final comp = line.substring('name='.length).trim();
      if (comp.isNotEmpty && isValidPackageName(pendingPackage)) {
        found.add(
          BootReceiver(packageName: pendingPackage, componentName: comp),
        );
      }
      pendingPackage = null;
      continue;
    }
    // 其他行不影响 pendingPackage（name 可能隔几行才出现）。
  }
  final list = found.toList()
    ..sort((a, b) {
      final byPkg = a.packageName.compareTo(b.packageName);
      if (byPkg != 0) return byPkg;
      return a.componentName.compareTo(b.componentName);
    });
  return list;
}

/// 开关一个开机启动接收器：`pm disable/enable <包名/组件名>`。
SystemCommand bootReceiverSet(BootReceiver receiver, bool enable) {
  return SystemCommand(
    command: 'pm ${enable ? 'enable' : 'disable'} ${receiver.fullName}',
    description: '${enable ? '允许' : '禁止'} ${receiver.fullName} 开机启动',
  );
}
