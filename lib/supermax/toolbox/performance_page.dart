import 'package:flutter/material.dart';

import '../root_shell.dart';
import '../supermax_service.dart';
import '../toolbox_commands.dart';

/// 性能调节：CPU 调速器、屏幕刷新率、省电模式。
class PerformancePage extends StatefulWidget {
  final SuperMaxService service;

  const PerformancePage({super.key, required this.service});

  @override
  State<PerformancePage> createState() => _PerformancePageState();
}

class _PerformancePageState extends State<PerformancePage> {
  final _peakCustomController = TextEditingController();
  final _minCustomController = TextEditingController();

  bool _loading = true;
  String? _error;
  bool _busy = false;

  bool _governorUnsupported = false;
  String? _governor;
  List<String> _governors = [];
  int? _curFreqKhz;
  int? _maxFreqKhz;

  int? _peakRate;
  int? _minRate;
  bool? _powerSave;

  static const List<int> _ratePresets = [60, 90, 120, 144];

  @override
  void initState() {
    super.initState();
    _load(showLoading: true);
  }

  @override
  void dispose() {
    _peakCustomController.dispose();
    _minCustomController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _failText(RootCommandResult? result) {
    if (result == null) return 'Super MAX 未开启';
    final err = result.stderr.trim();
    return err.isEmpty ? '退出码 ${result.exitCode}' : err;
  }

  Future<void> _load({bool showLoading = false}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final govResult =
        await widget.service.runRootCommand(governorGetCommand());
    if (!mounted) return;
    if (govResult == null) {
      setState(() {
        _loading = false;
        _error = 'Super MAX 未开启';
      });
      return;
    }
    var governorUnsupported = false;
    String? governor;
    var governors = <String>[];
    int? curFreq;
    int? maxFreq;
    if (!govResult.success || govResult.stdout.trim().isEmpty) {
      governorUnsupported = true;
    } else {
      governor = govResult.stdout.trim();
      final listResult =
          await widget.service.runRootCommand(governorListCommand());
      if (listResult != null && listResult.success) {
        governors = listResult.stdout
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toList();
      }
      final curResult =
          await widget.service.runRootCommand(cpuFreqGetCommand());
      if (curResult != null && curResult.success) {
        curFreq = int.tryParse(curResult.stdout.trim());
      }
      final maxResult =
          await widget.service.runRootCommand(cpuMaxFreqGetCommand());
      if (maxResult != null && maxResult.success) {
        maxFreq = int.tryParse(maxResult.stdout.trim());
      }
    }
    final peakResult = await widget.service
        .runRootCommand(refreshRateGetCommand(peak: true));
    final minResult = await widget.service
        .runRootCommand(refreshRateGetCommand(peak: false));
    final powerResult =
        await widget.service.runRootCommand(powerSaveGetCommand());
    if (!mounted) return;
    setState(() {
      _governorUnsupported = governorUnsupported;
      _governor = governor;
      _governors = governors;
      _curFreqKhz = curFreq;
      _maxFreqKhz = maxFreq;
      _peakRate = peakResult != null && peakResult.success
          ? int.tryParse(peakResult.stdout.trim())
          : null;
      _minRate = minResult != null && minResult.success
          ? int.tryParse(minResult.stdout.trim())
          : null;
      final powerText = powerResult != null && powerResult.success
          ? powerResult.stdout.trim()
          : '';
      _powerSave = powerText == '1'
          ? true
          : powerText == '0'
              ? false
              : null;
      _loading = false;
      _error = null;
    });
  }

  /// 确认并执行一条写命令；高危命令走红色高危确认框。
  /// 返回是否执行成功。
  Future<bool> _runWrite(SystemCommand cmd) async {
    final bool confirmed;
    if (RootShell.isDangerous(cmd.command)) {
      confirmed = await showRootCommandConfirmDialog(
        context,
        cmd.command,
        dangerous: true,
      );
    } else {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(cmd.description),
          content: SelectableText(
            cmd.command,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认执行'),
            ),
          ],
        ),
      );
      confirmed = result ?? false;
    }
    if (!confirmed || !mounted) return false;
    setState(() => _busy = true);
    final execResult = await widget.service.runRootCommand(cmd.command);
    if (!mounted) return false;
    setState(() => _busy = false);
    if (execResult == null || !execResult.success) {
      _snack('执行失败：${_failText(execResult)}');
      return false;
    }
    return true;
  }

  Future<void> _onSelectGovernor(String name) async {
    if (name == _governor || _busy) return;
    final ok = await _runWrite(governorSet(name));
    if (!mounted) return;
    if (ok) {
      _snack('调速器已切换为 $name');
      await _load();
    }
  }

  Future<void> _onSetRefreshRate(int hz, {required bool peak}) async {
    if (hz < 30 || hz > 240) {
      _snack('刷新率请输入 30-240 之间的整数');
      return;
    }
    final ok = await _runWrite(refreshRateSet(hz, peak: peak));
    if (!mounted) return;
    if (ok) {
      _snack('${peak ? '最高' : '最低'}刷新率已设为 ${hz}Hz');
      await _load();
    }
  }

  void _onApplyCustomRate({required bool peak}) {
    final text =
        (peak ? _peakCustomController : _minCustomController).text.trim();
    final hz = int.tryParse(text);
    if (hz == null) {
      _snack('请输入整数刷新率');
      return;
    }
    _onSetRefreshRate(hz, peak: peak);
  }

  Future<void> _onTogglePowerSave(bool value) async {
    final ok = await _runWrite(powerSaveSet(value));
    if (!mounted) return;
    if (ok) {
      _snack(value ? '省电模式已开启' : '省电模式已关闭');
      await _load();
    }
  }

  String _freqLabel(int? khz) {
    if (khz == null) return '—';
    final mhz = khz / 1000;
    final text = mhz % 1 == 0
        ? mhz.toStringAsFixed(0)
        : mhz.toStringAsFixed(1);
    return '$text MHz';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('性能调节'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
            onPressed: _loading ? null : () => _load(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => _load(showLoading: true),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildGovernorCard(),
                    const SizedBox(height: 16),
                    _buildRefreshCard(),
                    const SizedBox(height: 16),
                    _buildPowerSaveCard(),
                  ],
                ),
    );
  }

  Widget _buildGovernorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CPU 调速器',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_governorUnsupported)
              const Text('当前设备不支持读取 CPU 调速器')
            else ...[
              _infoRow('当前调速器', _governor ?? '—'),
              _infoRow('当前频率', _freqLabel(_curFreqKhz)),
              _infoRow('最高频率', _freqLabel(_maxFreqKhz)),
              const SizedBox(height: 12),
              if (_governors.isEmpty)
                const Text(
                  '无法读取可用调速器列表',
                  style: TextStyle(color: Colors.grey),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in _governors)
                      ChoiceChip(
                        label: Text(name),
                        selected: name == _governor,
                        onSelected: _busy
                            ? null
                            : (_) => _onSelectGovernor(name),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRefreshCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '屏幕刷新率',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildRefreshGroup(peak: true),
            const Divider(height: 24),
            _buildRefreshGroup(peak: false),
            const SizedBox(height: 12),
            const Text(
              '部分机型改完需重启应用或重进页面才生效',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRefreshGroup({required bool peak}) {
    final current = peak ? _peakRate : _minRate;
    final controller = peak ? _peakCustomController : _minCustomController;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          peak ? '最高刷新率' : '最低刷新率',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _infoRow('当前', current == null ? '—' : '$current Hz'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hz in _ratePresets)
              ChoiceChip(
                label: Text('$hz Hz'),
                selected: current == hz,
                onSelected: _busy
                    ? null
                    : (_) => _onSetRefreshRate(hz, peak: peak),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '自定义（30-240）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed:
                  _busy ? null : () => _onApplyCustomRate(peak: peak),
              child: const Text('应用'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPowerSaveCard() {
    return Card(
      child: SwitchListTile(
        title: const Text('省电模式'),
        subtitle: Text(
          _powerSave == null
              ? '无法读取当前状态'
              : _powerSave!
                  ? '已开启'
                  : '已关闭',
        ),
        secondary: const Icon(Icons.battery_saver_rounded),
        value: _powerSave ?? false,
        onChanged: (_busy || _powerSave == null)
            ? null
            : _onTogglePowerSave,
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
