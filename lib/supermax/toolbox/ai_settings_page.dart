import 'package:flutter/material.dart';

import '../../core/router.dart';
import '../../modules/aiplat/api_client.dart';
import '../ai_settings_assistant.dart';
import '../root_shell.dart';
import '../supermax_service.dart';
import '../toolbox_commands.dart';
import 'settings_browser_page.dart';

/// AI 调设置：用自然语言说需求，AI 翻译成系统命令，确认后执行。
///
/// 流程：输入需求 → 调用已配置的 AiPlat API 翻译 → 展示待执行命令清单
/// （白名单校验后）→ 用户确认 → 逐条执行并显示结果。
/// 未配置 API Key 时显示手动兜底（去配置 / 手动浏览设置）。
class AiSettingsPage extends StatefulWidget {
  final SuperMaxService service;

  const AiSettingsPage({super.key, required this.service});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _inputController = TextEditingController();
  final _assistant = AiSettingsAssistant();

  bool _translating = false;
  bool _executing = false;
  bool _noKey = false;
  String? _error;
  AiCommandParseResult? _result;
  List<_ExecutedCommand>? _executed;

  static const List<String> _examples = [
    '把亮度调到最低',
    '关闭蓝牙',
    '动画速度 0.5x',
    '屏幕 10 分钟不锁屏',
    '开启深色模式',
    '关闭所有动画',
  ];

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    final request = _inputController.text.trim();
    if (request.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先说说你想改什么设置')),
      );
      return;
    }
    setState(() {
      _translating = true;
      _error = null;
      _noKey = false;
      _result = null;
      _executed = null;
    });
    try {
      final result = await _assistant.translate(request);
      if (!mounted) return;
      setState(() {
        _result = result;
        _error = result.error;
      });
    } on AiSettingsNoKeyException {
      if (!mounted) return;
      setState(() => _noKey = true);
    } on AiPlatException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '翻译失败：$e');
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _executeAll() async {
    final commands = _result?.commands;
    if (commands == null || commands.isEmpty) return;
    final hasDangerous =
        commands.any((c) => RootShell.isDangerous(c.command));
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              hasDangerous
                  ? Icons.warning_amber_rounded
                  : Icons.playlist_add_check_rounded,
              color: hasDangerous ? Colors.red : null,
            ),
            const SizedBox(width: 8),
            Text('执行 ${commands.length} 条命令？'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasDangerous)
                  const Text(
                    '其中包含高危命令，请确认你清楚每条命令在做什么。',
                    style: TextStyle(color: Colors.red),
                  ),
                if (hasDangerous) const SizedBox(height: 12),
                for (final cmd in commands) ...[
                  Text(
                    '• ${cmd.description}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SelectableText(
                    cmd.command,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: hasDangerous
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认执行'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _executing = true;
      _executed = [];
    });
    final results = <_ExecutedCommand>[];
    for (final cmd in commands) {
      final result = await widget.service.runRootCommand(cmd.command);
      if (!mounted) return;
      results.add(
        _ExecutedCommand(
          command: cmd,
          success: result != null && result.success,
          output: result == null
              ? 'Super MAX 未开启'
              : result.success
              ? (result.stdout.trim().isEmpty ? '执行成功' : result.stdout.trim())
              : (result.stderr.trim().isEmpty
                  ? '退出码 ${result.exitCode}'
                  : result.stderr.trim()),
        ),
      );
      setState(() => _executed = List.of(results));
    }
    if (mounted) setState(() => _executing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 调设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '用一句话说出你想改的设置，AI 会翻译成系统命令，'
            '确认后才会执行。每条命令都会记入 root 执行日志。',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _inputController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '例如：把亮度调到最低、关闭蓝牙…',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _translate(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final example in _examples)
                ActionChip(
                  label: Text(example),
                  onPressed: () {
                    _inputController.text = example;
                    _translate();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _translating ? null : _translate,
              icon: _translating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_translating ? '翻译中…' : '翻译成命令'),
            ),
          ),
          const SizedBox(height: 16),
          if (_noKey) _buildNoKeyCard(),
          if (_error != null) _buildErrorCard(_error!),
          if (_result != null) _buildResultCard(),
          if (_executed != null && _executed!.isNotEmpty) _buildExecutedCard(),
        ],
      ),
    );
  }

  Widget _buildNoKeyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.key_off_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  '未配置 AiPlat API Key',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('AI 调设置需要先在 AiPlat 里配置 API Key（DeepSeek / OpenAI 等）。也可以直接手动浏览、修改系统设置。'),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.aiplat,
                  ),
                  child: const Text('去配置 API Key'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SettingsBrowserPage(service: widget.service),
                    ),
                  ),
                  child: const Text('手动浏览设置'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(error),
      ),
    );
  }

  Widget _buildResultCard() {
    final result = _result!;
    final commands = result.commands;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.list_alt_rounded),
                const SizedBox(width: 8),
                Text(
                  commands.isEmpty ? '没有可执行的命令' : '待执行命令（${commands.length} 条）',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (commands.isEmpty)
              const Text('AI 没能把这句话翻译成已知的系统命令，换个说法试试（例如「关闭蓝牙」「亮度调到最低」）。')
            else
              for (final cmd in commands) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      RootShell.isDangerous(cmd.command)
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 18,
                      color: RootShell.isDangerous(cmd.command)
                          ? Colors.red
                          : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cmd.description,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SelectableText(
                            cmd.command,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            if (result.ignored.isNotEmpty) ...[
              const Divider(),
              for (final ignored in result.ignored)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '已忽略：$ignored',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
            ],
            if (commands.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _executing ? null : _executeAll,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(_executing ? '执行中…' : '确认执行'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExecutedCard() {
    final executed = _executed!;
    final okCount = executed.where((e) => e.success).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '执行结果：$okCount/${executed.length} 成功',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (final item in executed) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.success
                        ? Icons.check_circle_rounded
                        : Icons.error_rounded,
                    size: 18,
                    color: item.success ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.command.description,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          item.output,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExecutedCommand {
  const _ExecutedCommand({
    required this.command,
    required this.success,
    required this.output,
  });

  final SystemCommand command;
  final bool success;
  final String output;
}
