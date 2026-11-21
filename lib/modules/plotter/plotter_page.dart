/// 函数绘制页面：输入 y=f(x)，多函数同屏绘制，支持平移/缩放。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plotter_engine.dart';
import 'plotter_settings_page.dart';

class PlotterPage extends StatefulWidget {
  const PlotterPage({super.key});

  @override
  State<PlotterPage> createState() => _PlotterPageState();
}

class _PlotFunction {
  final String id;
  final String raw;
  final Expression exp;
  final Color color;
  final List<double> zeros;
  bool visible = true;

  _PlotFunction({
    required this.id,
    required this.raw,
    required this.exp,
    required this.color,
    required this.zeros,
  });
}

const List<Color> _palette = [
  Colors.blue,
  Colors.red,
  Colors.green,
  Colors.orange,
  Colors.purple,
  Colors.teal,
  Colors.pink,
  Colors.brown,
];

const List<String> _examples = [
  'sin(x)',
  'cos(x)',
  'x^2',
  '1/x',
  'sqrt(x)',
  'tan(x)',
  'x^3-3x',
  'log(x)',
];

class _PlotterPageState extends State<PlotterPage> {
  final TextEditingController _inputController = TextEditingController();
  final List<_PlotFunction> _functions = [];

  bool _showGrid = PlotterPrefs.defaultShowGrid;
  double _defaultXMin = PlotterPrefs.defaultXMin;
  double _defaultXMax = PlotterPrefs.defaultXMax;

  double _centerX = 0;
  double _centerY = 0;
  double _scale = 30;
  bool _viewInitialized = false;
  Size _canvasSize = Size.zero;

  double _startScale = 30;
  double _startCenterX = 0;
  double _startCenterY = 0;
  Offset _startFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final showGrid =
        prefs.getBool(PlotterPrefs.showGridKey) ?? PlotterPrefs.defaultShowGrid;
    final xMin =
        prefs.getDouble(PlotterPrefs.xMinKey) ?? PlotterPrefs.defaultXMin;
    final xMax =
        prefs.getDouble(PlotterPrefs.xMaxKey) ?? PlotterPrefs.defaultXMax;
    if (!mounted) return;
    final defaultsChanged = xMin != _defaultXMin || xMax != _defaultXMax;
    setState(() {
      _showGrid = showGrid;
      _defaultXMin = xMin;
      _defaultXMax = xMax;
      if (defaultsChanged) _viewInitialized = false;
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _addFunction() {
    final raw = _inputController.text.trim();
    if (raw.isEmpty) {
      _showError('请输入函数表达式');
      return;
    }
    if (_functions.any((f) => f.raw == raw)) {
      _showError('该函数已存在');
      return;
    }
    late final Expression exp;
    try {
      exp = parsePlotFunction(raw);
    } on PlotParseException catch (e) {
      _showError(e.message);
      return;
    }
    if (!hasAnyValidValue(exp, xMin: _defaultXMin, xMax: _defaultXMax)) {
      _showError('该函数在当前范围内无有效值，请检查表达式');
      return;
    }
    final zeros = findZeros(exp, -100, 100);
    final color = _palette[_functions.length % _palette.length];
    setState(() {
      _functions.add(
        _PlotFunction(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          raw: raw,
          exp: exp,
          color: color,
          zeros: zeros,
        ),
      );
      _inputController.clear();
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startScale = _scale;
    _startCenterX = _centerX;
    _startCenterY = _centerY;
    _startFocal = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size size) {
    if (size.isEmpty) return;
    final newScale = (_startScale * details.scale).clamp(2.0, 2000.0);
    final focalMath = screenToMath(
      sx: _startFocal.dx,
      sy: _startFocal.dy,
      width: size.width,
      height: size.height,
      centerX: _startCenterX,
      centerY: _startCenterY,
      scale: _startScale,
    );
    setState(() {
      _scale = newScale;
      _centerX =
          focalMath.x - (details.localFocalPoint.dx - size.width / 2) / newScale;
      _centerY =
          focalMath.y + (details.localFocalPoint.dy - size.height / 2) / newScale;
    });
  }

  void _zoomIn() {
    setState(() {
      _scale = (_scale * 1.25).clamp(2.0, 2000.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _scale = (_scale / 1.25).clamp(2.0, 2000.0);
    });
  }

  void _resetView() {
    if (_canvasSize.isEmpty) return;
    setState(() {
      _centerX = (_defaultXMin + _defaultXMax) / 2;
      _centerY = 0;
      _scale = _canvasSize.width / (_defaultXMax - _defaultXMin);
    });
  }

  /// y 自适应：让当前可见函数的 y 值都落在画布内。
  void _fitY() {
    if (_canvasSize.isEmpty || _functions.isEmpty) return;
    final left = _centerX - _canvasSize.width / 2 / _scale;
    final right = _centerX + _canvasSize.width / 2 / _scale;
    double? yMin;
    double? yMax;
    for (final fn in _functions) {
      if (!fn.visible) continue;
      final step = (right - left) / 200;
      for (var i = 0; i <= 200; i++) {
        final y = evaluateAt(fn.exp, left + step * i);
        if (y == null) continue;
        yMin = yMin == null ? y : math.min(yMin, y);
        yMax = yMax == null ? y : math.max(yMax, y);
      }
    }
    if (yMin == null || yMax == null) return;
    final range = (yMax - yMin).abs();
    if (range < 1e-9) return;
    final newScale = (_canvasSize.height / (range * 1.2)).clamp(2.0, 2000.0);
    setState(() {
      _centerY = (yMin! + yMax!) / 2;
      _scale = newScale;
    });
  }

  String _zerosText(List<double> zeros) {
    if (zeros.isEmpty) return '无零点';
    final shown = zeros.take(3).map((z) {
      var s = z.toStringAsFixed(2);
      if (s == '-0.00') s = '0.00';
      return 'x≈$s';
    }).join('，');
    if (zeros.length > 3) {
      return '零点：$shown 等 ${zeros.length} 个';
    }
    return '零点：$shown';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('函数绘制'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PlotterSettingsPage(),
                ),
              );
              await _loadPrefs();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 函数输入
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    decoration: const InputDecoration(
                      hintText: '输入函数，如 sin(x) + x^2',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addFunction(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _addFunction,
                  child: const Text('添加'),
                ),
              ],
            ),
          ),
          // 示例
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _examples
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: ActionChip(
                          label: Text(e),
                          onPressed: () {
                            _inputController.text = e;
                            _inputController.selection =
                                TextSelection.collapsed(offset: e.length);
                          },
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          // 画布
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  _canvasSize = size;
                  if (!_viewInitialized && size.width > 0) {
                    _viewInitialized = true;
                    _centerX = (_defaultXMin + _defaultXMax) / 2;
                    _centerY = 0;
                    _scale = size.width / (_defaultXMax - _defaultXMin);
                  }
                  return Stack(
                    children: [
                      GestureDetector(
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: (d) => _onScaleUpdate(d, size),
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: CustomPaint(
                            size: size,
                            painter: _PlotterPainter(
                              functions: _functions,
                              centerX: _centerX,
                              centerY: _centerY,
                              scale: _scale,
                              showGrid: _showGrid,
                              backgroundColor:
                                  colorScheme.surfaceContainerLow,
                              gridColor: colorScheme.outlineVariant,
                              axisColor: colorScheme.onSurfaceVariant,
                              textColor: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ViewButton(
                              icon: Icons.add,
                              tooltip: '放大',
                              onPressed: _zoomIn,
                            ),
                            const SizedBox(height: 6),
                            _ViewButton(
                              icon: Icons.remove,
                              tooltip: '缩小',
                              onPressed: _zoomOut,
                            ),
                            const SizedBox(height: 6),
                            _ViewButton(
                              icon: Icons.fit_screen,
                              tooltip: 'y 自适应',
                              onPressed: _fitY,
                            ),
                            const SizedBox(height: 6),
                            _ViewButton(
                              icon: Icons.refresh,
                              tooltip: '重置视图',
                              onPressed: _resetView,
                            ),
                          ],
                        ),
                      ),
                      if (_functions.isEmpty)
                        const Center(
                          child: Text(
                            '拖动平移，双指缩放\n添加一个函数开始绘制',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 函数列表
          if (_functions.isNotEmpty)
            SizedBox(
              height: 148,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '函数列表（${_functions.length} 个）',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _functions.length,
                      itemBuilder: (context, index) {
                        final fn = _functions[index];
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: fn.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(
                            'y = ${fn.raw}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _zerosText(fn.zeros),
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  fn.visible
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  size: 20,
                                ),
                                tooltip: fn.visible ? '隐藏' : '显示',
                                onPressed: () {
                                  setState(() => fn.visible = !fn.visible);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 20),
                                tooltip: '删除',
                                onPressed: () {
                                  setState(
                                    () => _functions.removeAt(index),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ViewButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

class _PlotterPainter extends CustomPainter {
  final List<_PlotFunction> functions;
  final double centerX;
  final double centerY;
  final double scale;
  final bool showGrid;
  final Color backgroundColor;
  final Color gridColor;
  final Color axisColor;
  final Color textColor;

  _PlotterPainter({
    required this.functions,
    required this.centerX,
    required this.centerY,
    required this.scale,
    required this.showGrid,
    required this.backgroundColor,
    required this.gridColor,
    required this.axisColor,
    required this.textColor,
  });

  void _drawText(Canvas canvas, String text, Offset offset) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: textColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final left = centerX - size.width / 2 / scale;
    final right = centerX + size.width / 2 / scale;
    final top = centerY + size.height / 2 / scale;
    final bottom = centerY - size.height / 2 / scale;
    final step = niceGridStep(scale);

    // 网格
    if (showGrid) {
      final gridPaint = Paint()
        ..color = gridColor
        ..strokeWidth = 1;
      var x = (left / step).floor() * step;
      while (x <= right) {
        final sx = size.width / 2 + (x - centerX) * scale;
        canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), gridPaint);
        x += step;
      }
      var y = (bottom / step).floor() * step;
      while (y <= top) {
        final sy = size.height / 2 - (y - centerY) * scale;
        canvas.drawLine(Offset(0, sy), Offset(size.width, sy), gridPaint);
        y += step;
      }
      // 刻度文字：x 标在底部，y 标在左侧
      var tx = (left / step).floor() * step;
      while (tx <= right) {
        final sx = size.width / 2 + (tx - centerX) * scale;
        if (sx >= 0 && sx <= size.width - 28) {
          _drawText(canvas, formatTick(tx), Offset(sx + 2, size.height - 14));
        }
        tx += step;
      }
      var ty = (bottom / step).floor() * step;
      while (ty <= top) {
        final sy = size.height / 2 - (ty - centerY) * scale;
        if (sy >= 12 && sy <= size.height - 4) {
          _drawText(canvas, formatTick(ty), Offset(4, sy - 6));
        }
        ty += step;
      }
    }

    // 坐标轴
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.5;
    if (bottom <= 0 && 0 <= top) {
      final sy = size.height / 2 + centerY * scale;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), axisPaint);
    }
    if (left <= 0 && 0 <= right) {
      final sx = size.width / 2 - centerX * scale;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), axisPaint);
    }

    // 曲线与零点
    for (final fn in functions) {
      if (!fn.visible) continue;
      final paint = Paint()
        ..color = fn.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      var started = false;
      double? prevSy;
      for (var px = 0; px <= size.width; px++) {
        final mx = centerX + (px - size.width / 2) / scale;
        final my = evaluateAt(fn.exp, mx);
        if (my == null) {
          started = false;
          prevSy = null;
          continue;
        }
        var sy = size.height / 2 - (my - centerY) * scale;
        sy = sy.clamp(-1e6, 1e6);
        if (started &&
            prevSy != null &&
            (sy - prevSy).abs() > size.height * 2) {
          // 渐近线处断开，避免出现竖线
          started = false;
        }
        if (!started) {
          path.moveTo(px.toDouble(), sy);
          started = true;
        } else {
          path.lineTo(px.toDouble(), sy);
        }
        prevSy = sy;
      }
      canvas.drawPath(path, paint);

      final dotFill = Paint()..color = fn.color;
      final dotRing = Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final z in fn.zeros) {
        if (z < left || z > right) continue;
        final p = mathToScreen(
          mx: z,
          my: 0,
          width: size.width,
          height: size.height,
          centerX: centerX,
          centerY: centerY,
          scale: scale,
        );
        canvas.drawCircle(Offset(p.x, p.y), 4.5, dotFill);
        canvas.drawCircle(Offset(p.x, p.y), 4.5, dotRing);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlotterPainter oldDelegate) => true;
}
