import 'package:flutter/material.dart';

/// 一个窗口的状态。
class WindowModel {
  final String id;
  final String title;
  final String appId;

  /// 桌面模式下的位置与大小。
  Offset offset;
  Size size;

  bool minimized;
  bool maximized;

  /// 启动参数（例如记事本要打开的文件路径）。
  Map<String, dynamic>? params;

  Offset? _savedOffset;
  Size? _savedSize;

  WindowModel({
    required this.id,
    required this.title,
    required this.appId,
    required this.offset,
    required this.size,
    this.minimized = false,
    this.maximized = false,
    this.params,
  });

  void savePlacement() {
    _savedOffset = offset;
    _savedSize = size;
  }

  void restorePlacement() {
    if (_savedOffset != null) offset = _savedOffset!;
    if (_savedSize != null) size = _savedSize!;
  }
}

/// 窗口管理器：维护窗口列表（列表顺序即 z 序，末尾最上层）。
class WindowManager extends ChangeNotifier {
  final List<WindowModel> windows = [];
  int _counter = 0;

  /// 当前活动窗口：最上层且未最小化的窗口。
  WindowModel? get activeWindow {
    for (var i = windows.length - 1; i >= 0; i--) {
      if (!windows[i].minimized) return windows[i];
    }
    return null;
  }

  WindowModel? findByAppId(String appId) {
    for (final w in windows) {
      if (w.appId == appId) return w;
    }
    return null;
  }

  WindowModel? findById(String id) {
    for (final w in windows) {
      if (w.id == id) return w;
    }
    return null;
  }

  /// 打开窗口。同个应用默认单实例：已打开则聚焦并更新参数；
  /// [replaceExisting] 为 true 时先关闭旧窗口再开新的（用于记事本打开不同文件）。
  ///
  /// [area] 是窗口可活动的桌面区域（已扣掉顶栏避让区与任务栏）：
  /// 传入时初始位置与尺寸会被夹在区域内，窗口永远不会一打开就顶到
  /// 状态栏下面；不传则只用默认偏移（调用方自行保证区域安全）。
  WindowModel openWindow({
    required String appId,
    required String title,
    Offset? offset,
    Size? size,
    Map<String, dynamic>? params,
    bool replaceExisting = false,
    Size? area,
  }) {
    final existing = findByAppId(appId);
    if (existing != null) {
      if (replaceExisting) {
        windows.remove(existing);
      } else {
        existing.params = params;
        existing.minimized = false;
        focusWindow(existing.id);
        notifyListeners();
        return existing;
      }
    }
    final index = windows.length;
    var initialSize = size ?? const Size(520, 380);
    var initialOffset =
        offset ?? Offset(48 + (index % 5) * 36, 40 + (index % 4) * 32);
    if (area != null) {
      initialSize = Size(
        initialSize.width.clamp(320.0, area.width),
        initialSize.height.clamp(240.0, area.height),
      );
      initialOffset = _clampOffset(initialOffset, initialSize, area);
    }
    final window = WindowModel(
      id: 'win_${++_counter}',
      title: title,
      appId: appId,
      offset: initialOffset,
      size: initialSize,
      params: params,
    );
    windows.add(window);
    notifyListeners();
    return window;
  }

  /// 把窗口左上角夹在区域内（窗口整体不超出区域）。
  static Offset _clampOffset(Offset offset, Size size, Size area) {
    final maxX = (area.width - size.width).clamp(0.0, double.infinity);
    final maxY = (area.height - size.height).clamp(0.0, double.infinity);
    return Offset(
      offset.dx.clamp(0.0, maxX),
      offset.dy.clamp(0.0, maxY),
    );
  }

  void closeWindow(String id) {
    windows.removeWhere((w) => w.id == id);
    notifyListeners();
  }

  void closeAll() {
    windows.clear();
    notifyListeners();
  }

  void minimizeWindow(String id) {
    final w = findById(id);
    if (w == null) return;
    w.minimized = true;
    notifyListeners();
  }

  void restoreWindow(String id) {
    final w = findById(id);
    if (w == null) return;
    w.minimized = false;
    focusWindow(id);
    notifyListeners();
  }

  /// 最大化 / 还原。最大化时先保存当前摆放位置。
  void toggleMaximize(String id, Size area) {
    final w = findById(id);
    if (w == null) return;
    if (w.maximized) {
      w.maximized = false;
      w.restorePlacement();
    } else {
      w.savePlacement();
      w.maximized = true;
      w.offset = Offset.zero;
      w.size = area;
    }
    focusWindow(id);
    notifyListeners();
  }

  /// 把窗口移到最上层。
  void focusWindow(String id) {
    final index = windows.indexWhere((w) => w.id == id);
    if (index < 0 || index == windows.length - 1) return;
    final w = windows.removeAt(index);
    windows.add(w);
    notifyListeners();
  }

  /// 桌面模式：拖动标题栏移动窗口。
  void moveWindow(String id, Offset delta, Size area) {
    final w = findById(id);
    if (w == null || w.maximized) return;
    final next = w.offset + delta;
    final maxX = (area.width - 120).clamp(0.0, double.infinity);
    final maxY = (area.height - 48).clamp(0.0, double.infinity);
    w.offset = Offset(
      next.dx.clamp(0.0, maxX),
      next.dy.clamp(0.0, maxY),
    );
    notifyListeners();
  }

  /// 桌面模式：拖右下角缩放窗口。
  void resizeWindow(String id, Offset delta, Size area) {
    final w = findById(id);
    if (w == null || w.maximized) return;
    final width = (w.size.width + delta.dx).clamp(320.0, area.width);
    final height = (w.size.height + delta.dy).clamp(240.0, area.height);
    w.size = Size(width, height);
    notifyListeners();
  }
}
