import 'dart:io';

import 'package:flutter/material.dart';

import '../supermax_bridge.dart';
import '../webos_paths.dart';

/// WebOS 终端。
///
/// 普通模式：执行 Dart 实现的内置命令（help / echo / date / pwd / ls / cat / clear / about）。
/// Super MAX 开启时：其他命令走 root shell 执行。
class TerminalApp extends StatefulWidget {
  const TerminalApp({super.key});

  @override
  State<TerminalApp> createState() => _TerminalAppState();
}

class _TerminalAppState extends State<TerminalApp> {
  final List<String> _lines = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _supermax = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _supermax = await SuperMaxBridge.isEnabled();
    _print('WebOS 终端 v0.1.0');
    _print('输入 help 查看可用命令。');
    if (_supermax) {
      _print('Super MAX 已开启：可执行 root 命令。');
    } else {
      _print('普通模式：仅支持内置命令（开启 Super MAX 可用 root shell）。');
    }
    setState(() {});
  }

  void _print(String text) {
    setState(() => _lines.add(text));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  String get _prompt => _supermax ? 'root@webos:~# ' : 'webos@superapp:~\$ ';

  Future<void> _run(String raw) async {
    final command = raw.trim();
    _print('$_prompt$raw');
    if (command.isEmpty) return;
    if (_busy) {
      _print('上一条命令还在执行，请稍等。');
      return;
    }
    final parts = command.split(RegExp(r'\s+'));
    final name = parts.first.toLowerCase();
    final args = parts.skip(1).toList();

    switch (name) {
      case 'help':
        _print('内置命令：');
        _print('  help              显示本帮助');
        _print('  echo <内容>       输出内容');
        _print('  date              显示当前日期时间');
        _print('  pwd               显示当前目录');
        _print('  ls [目录]         列出 WebOS 目录内容');
        _print('  cat <文件>        显示文件内容');
        _print('  clear             清空屏幕');
        _print('  about             关于 WebOS 终端');
        if (_supermax) {
          _print('Super MAX：其他命令将以 root 身份执行。');
        }
      case 'echo':
        _print(args.join(' '));
      case 'date':
        _print(DateTime.now().toString());
      case 'pwd':
        final root = await WebOSPaths.root();
        _print(root.path);
      case 'ls':
        await _ls(args.isEmpty ? null : args.first);
      case 'cat':
        if (args.isEmpty) {
          _print('用法：cat <文件>');
        } else {
          await _cat(args.first);
        }
      case 'clear':
        setState(() => _lines.clear());
      case 'about':
        _print('WebOS 终端：在 SuperApp 内运行的迷你 shell。');
      default:
        if (_supermax) {
          await _runRoot(command);
        } else {
          _print('未知命令：$name（输入 help 查看可用命令）');
          _print('需要执行系统命令请开启 Super MAX。');
        }
    }
  }

  Future<void> _ls(String? dirArg) async {
    try {
      final root = await WebOSPaths.root();
      final dir = dirArg == null ? root.path : _resolvePath(dirArg, root.path);
      final entries = await WebOSPaths.listDirectory(dir);
      if (entries.isEmpty) {
        _print('(空目录)');
        return;
      }
      for (final e in entries) {
        _print(e.isDir ? '${e.name}/' : e.name);
      }
    } catch (e) {
      _print('ls 失败：$e');
    }
  }

  Future<void> _cat(String fileArg) async {
    try {
      final root = await WebOSPaths.root();
      final path = _resolvePath(fileArg, root.path);
      final file = File(path);
      if (!await file.exists()) {
        _print('文件不存在：$fileArg');
        return;
      }
      final content = await file.readAsString();
      final lines = content.split('\n');
      if (lines.length > 200) {
        _print('(文件过长，仅显示前 200 行)');
        for (final line in lines.take(200)) {
          _print(line);
        }
      } else {
        for (final line in lines) {
          _print(line);
        }
      }
    } catch (e) {
      _print('cat 失败：$e');
    }
  }

  String _resolvePath(String arg, String base) {
    if (arg.startsWith('/')) return arg;
    if (arg == '~') return base;
    return '$base${Platform.pathSeparator}$arg';
  }

  Future<void> _runRoot(String command) async {
    setState(() => _busy = true);
    try {
      final result = await SuperMaxBridge.runAsRoot(command);
      if (result.output.isNotEmpty) {
        for (final line in result.output.split('\n')) {
          _print(line);
        }
      }
      if (!result.ok) {
        _print('(退出码非 0)');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _lines.length,
              itemBuilder: (context, index) => Text(
                _lines[index],
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFF334155)),
              ),
            ),
            child: Row(
              children: [
                Text(
                  _prompt,
                  style: const TextStyle(
                    color: Color(0xFF4ADE80),
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_busy,
                    autofocus: true,
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '输入命令…',
                      hintStyle: TextStyle(color: Color(0xFF64748B)),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (value) {
                      _input.clear();
                      _run(value);
                    },
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
