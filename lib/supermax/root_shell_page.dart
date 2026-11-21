import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'root_shell.dart';
import 'supermax_service.dart';
import 'supermax_settings_page.dart';

/// 一条已执行命令的记录（命令 + 输出）。
class _ShellEntry {
  final String command;
  final RootCommandResult result;

  const _ShellEntry({required this.command, required this.result});
}

/// Root Shell 页：仅 Super MAX 开启时可用。
///
/// - 命令输入框 + 执行按钮；输出区显示 stdout / stderr 与退出码。
/// - 高危命令执行前弹窗确认（[RootShell.isDangerous] 判断）。
/// - 常用命令快捷按钮。
class RootShellPage extends StatefulWidget {
  final SuperMaxService? service;

  const RootShellPage({super.key, this.service});

  @override
  State<RootShellPage> createState() => _RootShellPageState();
}

class _RootShellPageState extends State<RootShellPage> {
  final _commandController = TextEditingController();
  final _outputScrollController = ScrollController();
  final List<_ShellEntry> _history = [];
  SuperMaxService? _service;
  SuperMaxService? _fallback;
  bool _running = false;

  /// 常用命令快捷按钮。
  static const List<(String, String)> _quickCommands = [
    ('id', '查看身份'),
    ('ls /sdcard', '列出存储'),
    ('pm list packages', '应用列表'),
    ('df -h', '磁盘空间'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_service != null) return;
    if (widget.service != null) {
      _service = widget.service;
    } else {
      try {
        _service = Provider.of<SuperMaxService>(context);
      } catch (_) {
        _fallback ??= SuperMaxService()..init();
        _service = _fallback;
      }
    }
  }

  @override
  void dispose() {
    _commandController.dispose();
    _outputScrollController.dispose();
    super.dispose();
  }

  SuperMaxService get _sm => _service!;

  Future<void> _execute(String command) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty || _running) return;
    if (!_sm.isEnabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先开启 Super MAX 模式')));
      return;
    }
    // 高危命令先弹窗确认。
    if (RootShell.isDangerous(trimmed)) {
      final confirmed = await showRootCommandConfirmDialog(
        context,
        trimmed,
        dangerous: true,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _running = true);
    final result = await _sm.runRootCommand(trimmed);
    if (!mounted) return;
    setState(() {
      _running = false;
      if (result != null) {
        _history.add(_ShellEntry(command: trimmed, result: result));
      }
      _commandController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_outputScrollController.hasClients) {
        _outputScrollController.animateTo(
          _outputScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SuperMaxSettingsPage(service: _sm),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        if (!service.isEnabled) {
          return Scaffold(
            appBar: AppBar(title: const Text('Root Shell')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_rounded,
                      size: 48,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Super MAX 未开启',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Root Shell 需要先开启 Super MAX 模式（设置里手动启用）。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _openSettings,
                      child: const Text('去设置开启'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Root Shell'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_sweep_rounded),
                tooltip: '清空输出',
                onPressed: _history.isEmpty
                    ? null
                    : () => setState(_history.clear),
              ),
            ],
          ),
          body: Column(
            children: [
              _buildQuickCommands(),
              Expanded(child: _buildOutput()),
              _buildInputBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickCommands() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (command, label) in _quickCommands)
            ActionChip(
              label: Text(label),
              avatar: const Icon(Icons.terminal_rounded, size: 16),
              onPressed: _running ? null : () => _execute(command),
            ),
        ],
      ),
    );
  }

  Widget _buildOutput() {
    if (_history.isEmpty) {
      return const Center(
        child: Text(
          '输入命令或点上方快捷按钮开始执行。\n高危命令执行前会弹窗确认。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      controller: _outputScrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final entry = _history[index];
        final result = entry.result;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Colors.green,
                    ),
                    Expanded(
                      child: SelectableText(
                        entry.command,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      result.timedOut
                          ? '超时'
                          : 'exit=${result.exitCode}',
                      style: TextStyle(
                        fontSize: 12,
                        color: result.success ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (result.stdout.trim().isNotEmpty)
                  SelectableText(
                    result.stdout.trimRight(),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                if (result.stderr.trim().isNotEmpty)
                  SelectableText(
                    result.stderr.trimRight(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.red,
                    ),
                  ),
                if (result.stdout.trim().isEmpty &&
                    result.stderr.trim().isEmpty)
                  const Text(
                    '（无输出）',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commandController,
                enabled: !_running,
                onSubmitted: _execute,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: '输入命令，如 id',
                  prefixIcon: Icon(Icons.terminal_rounded),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _running
                  ? null
                  : () => _execute(_commandController.text),
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: const Text('执行'),
            ),
          ],
        ),
      ),
    );
  }
}
