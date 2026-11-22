import 'dart:async';

import 'package:flutter/material.dart';

/// 秒表与倒计时：纯 Dart 实现，不用任何插件。
///
/// 上方分段按钮切换模式：秒表（开始/暂停、计次、重置）与
/// 倒计时（分/秒步进设置、进度条、时间到提示）。
class StopwatchPage extends StatefulWidget {
  const StopwatchPage({super.key});

  @override
  State<StopwatchPage> createState() => _StopwatchPageState();
}

enum _Mode { stopwatch, countdown }

class _StopwatchPageState extends State<StopwatchPage> {
  _Mode _mode = _Mode.stopwatch;

  // 秒表
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  final List<Duration> _laps = [];

  // 倒计时
  int _countMinutes = 5;
  int _countSeconds = 0;
  Duration _remaining = const Duration(minutes: 5);
  bool _countdownRunning = false;
  // 按结束时间点算剩余，不用每 tick 累减，不会越走越偏。
  DateTime? _countdownEnd;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// MM:SS.cc（百分秒）。
  static String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final cs = (d.inMilliseconds.remainder(1000) ~/ 10)
        .toString()
        .padLeft(2, '0');
    return '$m:$s.$cs';
  }

  Duration get _countdownTotal =>
      Duration(minutes: _countMinutes, seconds: _countSeconds);

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 31),
      (_) {
        if (!mounted) return;
        setState(() {
          if (_mode == _Mode.countdown && _countdownRunning) {
            final end = _countdownEnd;
            if (end == null) return;
            _remaining = end.difference(DateTime.now());
            if (_remaining <= Duration.zero) {
              _remaining = Duration.zero;
              _countdownRunning = false;
              _countdownEnd = null;
              _ticker?.cancel();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('时间到')),
              );
            }
          }
        });
      },
    );
  }

  void _toggleStopwatch() {
    setState(() {
      if (_stopwatch.isRunning) {
        _stopwatch.stop();
        _ticker?.cancel();
      } else {
        _stopwatch.start();
        _startTicker();
      }
    });
  }

  void _lap() {
    if (!_stopwatch.isRunning) return;
    setState(() => _laps.insert(0, _stopwatch.elapsed));
  }

  void _resetStopwatch() {
    setState(() {
      _stopwatch.stop();
      _stopwatch.reset();
      _laps.clear();
      _ticker?.cancel();
    });
  }

  void _toggleCountdown() {
    if (_countdownRunning) {
      setState(() {
        _countdownRunning = false;
        _countdownEnd = null;
        _ticker?.cancel();
      });
      return;
    }
    if (_remaining <= Duration.zero) {
      _remaining = _countdownTotal;
    }
    if (_countdownTotal <= Duration.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先设置倒计时时长')),
      );
      return;
    }
    setState(() {
      _countdownRunning = true;
      _countdownEnd = DateTime.now().add(_remaining);
      _startTicker();
    });
  }

  void _resetCountdown() {
    setState(() {
      _countdownRunning = false;
      _countdownEnd = null;
      _ticker?.cancel();
      _remaining = _countdownTotal;
    });
  }

  void _changeCountdown({int minutesDelta = 0, int secondsDelta = 0}) {
    if (_countdownRunning) return;
    setState(() {
      _countMinutes = (_countMinutes + minutesDelta).clamp(0, 59);
      _countSeconds = (_countSeconds + secondsDelta).clamp(0, 59);
      _remaining = _countdownTotal;
    });
  }

  Widget _stepper({
    required String label,
    required int value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              tooltip: '减少',
              onPressed: onMinus,
            ),
            SizedBox(
              width: 44,
              child: Text(
                value.toString().padLeft(2, '0'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '增加',
              onPressed: onPlus,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('秒表与倒计时')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment<_Mode>(
                value: _Mode.stopwatch,
                icon: Icon(Icons.timer_outlined, size: 18),
                label: Text('秒表'),
              ),
              ButtonSegment<_Mode>(
                value: _Mode.countdown,
                icon: Icon(Icons.hourglass_bottom_outlined, size: 18),
                label: Text('倒计时'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (modes) {
              setState(() {
                _mode = modes.first;
                // 切换模式时停掉正在跑的计时，避免后台继续刷新。
                _stopwatch.stop();
                _countdownRunning = false;
                _ticker?.cancel();
              });
            },
          ),
          const SizedBox(height: 24),
          if (_mode == _Mode.stopwatch) ...[
            Center(
              child: Text(
                _format(_stopwatch.elapsed),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  icon: Icon(
                    _stopwatch.isRunning ? Icons.pause : Icons.play_arrow,
                  ),
                  label: Text(_stopwatch.isRunning ? '暂停' : '开始'),
                  onPressed: _toggleStopwatch,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('计次'),
                  onPressed: _stopwatch.isRunning ? _lap : null,
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed:
                      _stopwatch.elapsed > Duration.zero ? _resetStopwatch : null,
                  child: const Text('重置'),
                ),
              ],
            ),
            if (_laps.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                '计次',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _laps.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        title: Text('第 ${_laps.length - i} 次'),
                        trailing: Text(
                          _format(_laps[i]),
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ] else ...[
            Center(
              child: Text(
                _format(_remaining),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: _remaining <= Duration.zero &&
                              _countdownTotal > Duration.zero
                          ? scheme.error
                          : null,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _countdownTotal > Duration.zero
                  ? (_remaining.inMilliseconds /
                          _countdownTotal.inMilliseconds)
                      .clamp(0.0, 1.0)
                  : 0,
              backgroundColor: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stepper(
                  label: '分钟',
                  value: _countMinutes,
                  onMinus: () => _changeCountdown(minutesDelta: -1),
                  onPlus: () => _changeCountdown(minutesDelta: 1),
                ),
                const SizedBox(width: 16),
                _stepper(
                  label: '秒',
                  value: _countSeconds,
                  onMinus: () => _changeCountdown(secondsDelta: -5),
                  onPlus: () => _changeCountdown(secondsDelta: 5),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '秒按 5 秒步进；运行时不能改时长',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  icon: Icon(
                    _countdownRunning ? Icons.pause : Icons.play_arrow,
                  ),
                  label: Text(_countdownRunning ? '暂停' : '开始'),
                  onPressed: _toggleCountdown,
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _resetCountdown,
                  child: const Text('重置'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
