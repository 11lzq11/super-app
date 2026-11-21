import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// 一次 root 命令的执行结果。
class RootCommandResult {
  /// 退出码；-1 表示超时或启动失败。
  final int exitCode;

  /// 标准输出。
  final String stdout;

  /// 标准错误输出。
  final String stderr;

  /// 是否因超时被终止。
  final bool timedOut;

  /// 本次执行耗时。
  final Duration duration;

  const RootCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
    this.duration = Duration.zero,
  });

  /// 执行成功：未超时且退出码为 0。
  bool get success => !timedOut && exitCode == 0;

  /// 简短摘要（用于日志）：优先取 stdout，截断到 200 字。
  String get summary {
    final out = stdout.trim();
    final err = stderr.trim();
    final text = out.isNotEmpty ? out : err;
    if (text.isEmpty) return timedOut ? '超时' : '（无输出）';
    if (text.length > 200) return '${text.substring(0, 200)}…';
    return text;
  }
}

/// root shell：通过 `su -c <命令>` 执行命令。
///
/// - 真实执行，不做模拟；无 root 或非 Android 设备上调用会返回失败结果，不崩溃。
/// - 一次只跑一条命令：多次调用会自动排队，串行执行。
/// - 高危命令不做硬拦截（用户自己确认），但 [isDangerous] 会标记，
///   调用方应在执行前弹窗二次确认。
class RootShell {
  /// 默认超时：15 秒。
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// 串行队列的尾巴：每次调用都接在上一次后面，保证一次只跑一条命令。
  static Future<void> _tail = Future<void>.value();

  /// 以 root 身份执行 [command]，返回执行结果。
  /// [timeout] 超时后会杀掉进程并返回 timedOut 为 true 的结果。
  static Future<RootCommandResult> runAsRoot(
    String command, {
    Duration timeout = defaultTimeout,
  }) {
    final completer = Completer<RootCommandResult>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await _runOnce(command, timeout: timeout));
      } catch (e) {
        completer.complete(
          RootCommandResult(
            exitCode: -1,
            stdout: '',
            stderr: '执行失败：$e',
          ),
        );
      }
    });
    return completer.future;
  }

  /// 以 root 身份执行 [command]，执行前先调用 [confirm] 让用户确认。
  ///
  /// - [confirm] 是 UI 弹窗回调（由调用方传入，例如 [showRootCommandConfirmDialog]），
  ///   返回 true 才执行，false 则取消并返回 null。
  /// - 这是给 AiPlat「手机操作」等场景用的：每次执行都必须用户点确认。
  /// - 如果调用方只想在危险命令时确认，请自行先调 [isDangerous] 判断，
  ///   再决定是否弹窗；或直接用 [runAsRoot]。
  static Future<RootCommandResult?> runAsRootWithConfirm(
    String command, {
    required Future<bool> Function(String command) confirm,
    Duration timeout = defaultTimeout,
  }) async {
    final ok = await confirm(command);
    if (!ok) return null;
    return runAsRoot(command, timeout: timeout);
  }

  /// 判断 [command] 是否为高危命令。
  ///
  /// 匹配以下模式（任一命中即为高危）：
  /// - `rm -rf /`、`rm -rf /system`、`rm -rf /data` 等（递归强制删除根目录或系统目录）
  /// - `dd if=...`（直接写磁盘）
  /// - `mkfs...`（格式化文件系统）
  /// - `:(){:|:&};:`（fork 炸弹）
  /// - `> /dev/block/...` 等向块设备重定向写入
  /// - `chmod 777 /`（根目录权限放开）
  /// - `mount ... remount`（重新挂载系统分区）
  /// - `reboot`（重启设备）
  static bool isDangerous(String command) {
    final cmd = command.trim();
    if (cmd.isEmpty) return false;
    for (final pattern in _dangerousPatterns) {
      if (pattern.hasMatch(cmd)) return true;
    }
    return _isRmRfCritical(cmd);
  }

  static final List<RegExp> _dangerousPatterns = [
    // dd if=...：直接读写磁盘
    RegExp(r'\bdd\s+[^|;&]*\bif\s*='),
    // mkfs / mkfs.ext4 等：格式化
    RegExp(r'\bmkfs(\.\w+)?\b'),
    // fork 炸弹
    RegExp(r':\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;?\s*:'),
    // 向块设备重定向写入，如 > /dev/block/sda
    RegExp(r'>\s*/dev/(block/|sd[a-z]+|mmcblk|loop|nvme)'),
    // chmod 777 /：根目录权限放开
    RegExp(r'\bchmod\s+(-R\s+)?777\s+/\s*(?:$|[|;&])'),
    // 重新挂载分区
    RegExp(r'\bmount\b[^|;&]*\bremount\b'),
    // 重启设备
    RegExp(r'\breboot\b'),
  ];

  /// `rm` 带 -r 和 -f 且目标是根目录或系统关键目录时为高危。
  static bool _isRmRfCritical(String command) {
    // 只看第一个命令段（;、&&、|| 之前），避免误判管道后的内容。
    final first = command.split(RegExp(r'[;&|]')).first;
    final tokens = first.trim().split(RegExp(r'\s+'));
    if (tokens.isEmpty || tokens.first != 'rm') return false;

    var hasRecursive = false;
    var hasForce = false;
    final targets = <String>[];
    for (final token in tokens.skip(1)) {
      if (token.startsWith('-') && !token.startsWith('--')) {
        if (token.contains('r')) hasRecursive = true;
        if (token.contains('f')) hasForce = true;
      } else if (token == '--recursive') {
        hasRecursive = true;
      } else if (token == '--force') {
        hasForce = true;
      } else if (!token.startsWith('-')) {
        targets.add(token);
      }
    }
    if (!hasRecursive || !hasForce) return false;

    const critical = [
      '/system',
      '/data',
      '/vendor',
      '/product',
      '/sdcard',
      '/storage',
    ];
    return targets.any((target) {
      if (target == '/' || target == '/*') return true;
      return critical.any(
        (dir) => target == dir || target.startsWith('$dir/'),
      );
    });
  }

  static Future<RootCommandResult> _runOnce(
    String command, {
    required Duration timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    Process? process;
    try {
      process = await Process.start('su', ['-c', command]);
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process?.kill();
          return -1;
        },
      );
      final timedOut = exitCode == -1;
      final stdout = await stdoutFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () => '',
      );
      final stderr = await stderrFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () => '',
      );
      stopwatch.stop();
      return RootCommandResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        timedOut: timedOut,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      // su 不存在、没有执行权限等情况都会走到这里。
      process?.kill();
      stopwatch.stop();
      return RootCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: '无法执行 root 命令：$e',
        duration: stopwatch.elapsed,
      );
    }
  }
}

/// 默认的 root 命令确认对话框（供调用方直接使用）。
///
/// [command] 为待执行命令；[dangerous] 为 true 时用红色警示样式。
/// 返回 true 表示用户确认执行，false 表示取消。
Future<bool> showRootCommandConfirmDialog(
  BuildContext context,
  String command, {
  bool dangerous = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          Icon(
            dangerous ? Icons.warning_amber_rounded : Icons.terminal_rounded,
            color: dangerous ? Colors.red : null,
          ),
          const SizedBox(width: 8),
          Text(dangerous ? '确认执行高危命令？' : '确认执行命令？'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dangerous)
            const Text(
              '这条命令可能损坏系统或删除数据，请确认你清楚它在做什么。',
              style: TextStyle(color: Colors.red),
            ),
          if (dangerous) const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              command,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: dangerous
              ? FilledButton.styleFrom(backgroundColor: Colors.red)
              : null,
          child: const Text('确认执行'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
