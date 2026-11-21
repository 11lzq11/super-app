import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_registry.dart';
import 'app_store.dart';
import 'apps/calculator_app.dart';
import 'apps/files_app.dart';
import 'apps/notes_app.dart';
import 'apps/settings_app.dart';
import 'apps/store_app.dart';
import 'apps/terminal_app.dart';
import 'html_app_view.dart';
import 'local_server.dart';
import 'supermax_bridge.dart';
import 'webos_paths.dart';
import 'webos_theme.dart';
import 'window_manager.dart';
import 'workshop_app.dart';

const List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

/// WebOS 桌面：壁纸、桌面图标、窗口、任务栏/Dock、开始菜单、时钟。
///
/// 宽屏（或设置强制桌面模式）为桌面模式：浮动窗口，可拖动/缩放；
/// 窄屏（或设置强制手机模式）为手机模式：窗口全屏，底部 Dock 切换。
class WebOSPage extends StatefulWidget {
  const WebOSPage({super.key});

  @override
  State<WebOSPage> createState() => _WebOSPageState();
}

class _WebOSPageState extends State<WebOSPage> {
  final WindowManager _wm = WindowManager();
  bool _ready = false;
  String? _serverError;
  String _windowMode = 'auto';
  bool _startMenuOpen = false;
  List<WebOSApp> _apps = [];
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  bool _supermax = false;

  @override
  void initState() {
    super.initState();
    _wm.addListener(_rebuild);
    webOSWallpaperNotifier.addListener(_rebuild);
    webOSDarkModeNotifier.addListener(_rebuild);
    webOSAppsChanged.addListener(_refreshApps);
    _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _init();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _wm.removeListener(_rebuild);
    webOSWallpaperNotifier.removeListener(_rebuild);
    webOSDarkModeNotifier.removeListener(_rebuild);
    webOSAppsChanged.removeListener(_refreshApps);
    _wm.dispose();
    unawaited(WebOSLocalServer.instance.stop());
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    await WebOSPaths.ensureAll();
    try {
      await WebOSLocalServer.instance.start();
    } catch (e) {
      _serverError = '$e';
    }
    await AppStoreService.ensureSamplesInstalled();
    await loadWebOSWallpaper();
    await loadWebOSDarkMode();
    _windowMode = await loadWebOSWindowMode();
    _supermax = await SuperMaxBridge.isEnabled();
    await _refreshApps();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _refreshApps() async {
    final apps = await WebOSAppRegistry.allApps();
    if (mounted) setState(() => _apps = apps);
  }

  bool _isDesktopMode(Size size) {
    if (_windowMode == 'desktop') return true;
    if (_windowMode == 'phone') return false;
    return size.width > size.height;
  }

  WebOSApp? _findApp(String id) {
    for (final app in _apps) {
      if (app.id == id) return app;
    }
    return null;
  }

  void _launchApp(
    WebOSApp app, {
    Map<String, dynamic>? params,
    bool replaceExisting = false,
  }) {
    final desktop = _isDesktopMode(MediaQuery.of(context).size);
    _wm.openWindow(
      appId: app.id,
      title: app.name,
      params: params,
      size: desktop ? const Size(520, 380) : const Size(520, 380),
      replaceExisting: replaceExisting,
    );
    if (_startMenuOpen) setState(() => _startMenuOpen = false);
  }

  Future<void> _launchById(
    String appId, {
    Map<String, dynamic>? params,
    bool replaceExisting = false,
  }) async {
    var app = _findApp(appId);
    if (app == null) {
      await _refreshApps();
      app = _findApp(appId);
    }
    if (app == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('找不到应用：$appId')),
        );
      }
      return;
    }
    _launchApp(app, params: params, replaceExisting: replaceExisting);
  }

  /// HTML 应用 openFile 回调：文本进记事本，.html 提示安装为应用。
  Future<void> _openFile(String path) async {
    final lower = path.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      final install = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('安装为 WebOS 应用'),
          content: Text('要把 $path 安装为 WebOS 应用吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('安装'),
            ),
          ],
        ),
      );
      if (install == true) {
        try {
          final html = await File(path).readAsString();
          final name = path
              .split(Platform.pathSeparator)
              .last
              .replaceAll(RegExp(r'\.(html|htm)$'), '');
          final id = await AppStoreService.installHtmlFile(
            name: name.isEmpty ? '未命名应用' : name,
            html: html,
          );
          await _refreshApps();
          await _launchById(id);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('安装失败：$e')),
            );
          }
        }
      }
      return;
    }
    if (lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.json') ||
        lower.endsWith('.log')) {
      await _launchById(
        'notes',
        params: {'path': path},
        replaceExisting: true,
      );
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已选择：$path')),
      );
    }
  }

  /// 传给 HtmlAppView 的宿主接口。
  WebOSHost get _host => WebOSHost(
        launchApp: (appId, {params}) =>
            _launchById(appId, params: params),
        openFile: _openFile,
        getFileList: (dir) async {
          final root = await WebOSPaths.root();
          final String target;
          if (dir.isEmpty) {
            target = root.path;
          } else if (dir.startsWith('/')) {
            target = dir;
          } else {
            target = '${root.path}${Platform.pathSeparator}$dir';
          }
          final entries = await WebOSPaths.listDirectory(target);
          return entries.map((e) => e.toJson()).toList();
        },
      );

  IconData _iconFor(String appId) {
    final app = _findApp(appId);
    return app?.icon ?? Icons.web_asset_outlined;
  }

  Widget _buildWindowContent(WindowModel window) {
    final app = _findApp(window.appId);
    if (app == null) {
      return const Center(child: Text('应用不存在或已被卸载'));
    }
    if (app.kind == WebOSAppKind.html) {
      return HtmlAppView(appId: app.id, appName: app.name, host: _host);
    }
    final params = window.params;
    switch (app.id) {
      case 'files':
        return FilesApp(onOpenFile: _openFile);
      case 'notes':
        final path = params?['path'] as String?;
        return NotesApp(
          key: ValueKey('notes:${path ?? ''}'),
          initialPath: path,
        );
      case 'terminal':
        return const TerminalApp();
      case 'calculator':
        return const CalculatorApp();
      case 'store':
        return const StoreApp();
      case 'workshop':
        return WorkshopApp(onLaunchApp: (id) => _launchById(id));
      case 'settings':
        return const SettingsApp();
      default:
        return const Center(child: Text('未知应用'));
    }
  }

  Widget _buildTitleBar(WindowModel window, bool desktop, Size area) {
    return GestureDetector(
      onTap: () => _wm.focusWindow(window.id),
      onDoubleTap: desktop
          ? () => _wm.toggleMaximize(window.id, area)
          : null,
      onPanUpdate: desktop && !window.maximized
          ? (details) => _wm.moveWindow(window.id, details.delta, area)
          : null,
      child: Container(
        height: 40,
        color: WebOSColors.titleBarBackground,
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            Icon(
              _iconFor(window.appId),
              size: 18,
              color: WebOSColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                window.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: WebOSColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.minimize, size: 18),
              tooltip: '最小化',
              onPressed: () => _wm.minimizeWindow(window.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            if (desktop)
              IconButton(
                icon: Icon(
                  window.maximized
                      ? Icons.fullscreen_exit
                      : Icons.crop_square,
                  size: 16,
                ),
                tooltip: window.maximized ? '还原' : '最大化',
                onPressed: () => _wm.toggleMaximize(window.id, area),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: '关闭',
              onPressed: () => _wm.closeWindow(window.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowFrame(WindowModel window, bool desktop, Size area) {
    final isActive = _wm.activeWindow?.id == window.id;
    final frame = Material(
      elevation: isActive ? 14 : 6,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      color: WebOSColors.windowBackground,
      child: Column(
        children: [
          _buildTitleBar(window, desktop, area),
          Expanded(child: _buildWindowContent(window)),
        ],
      ),
    );
    if (!desktop) {
      return Positioned.fill(child: frame);
    }
    if (window.maximized) {
      return Positioned(
        left: 0,
        top: 0,
        width: area.width,
        height: area.height,
        child: frame,
      );
    }
    return Positioned(
      left: window.offset.dx,
      top: window.offset.dy,
      width: window.size.width,
      height: window.size.height,
      child: Stack(
        children: [
          Positioned.fill(child: frame),
          // 右下角缩放手柄
          Positioned(
            right: 0,
            bottom: 0,
            width: 22,
            height: 22,
            child: GestureDetector(
              onPanUpdate: (details) =>
                  _wm.resizeWindow(window.id, details.delta, area),
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: Container(
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.open_in_full,
                    size: 12,
                    color: WebOSColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopIcon(WebOSApp app) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: () => _launchApp(app),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 78,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(app.icon, size: 26, color: const Color(0xFF0F172A)),
              ),
              const SizedBox(height: 5),
              Text(
                app.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStartMenu(Size size) {
    return Positioned(
      left: 12,
      bottom: 56,
      width: 360,
      height: size.height > 560 ? 440 : size.height - 120,
      child: Material(
        elevation: 16,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        color: WebOSColors.windowBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Text(
                    'WebOS',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: WebOSColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(color: WebOSColors.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _apps
                    .map(
                      (app) => InkWell(
                        onTap: () => _launchApp(app),
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                app.icon,
                                size: 24,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              app.name,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: WebOSColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: WebOSColors.border),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _launchById('settings'),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('WebOS 设置'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('退出 WebOS'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClock({bool light = false}) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    final date =
        '${_now.month}月${_now.day}日 周${_weekdays[_now.weekday - 1]}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$hh:$mm',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: light ? Colors.white : WebOSColors.textPrimary,
            ),
          ),
          Text(
            date,
            style: TextStyle(
              fontSize: 11,
              color: light
                  ? Colors.white.withValues(alpha: 0.8)
                  : WebOSColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _onTaskbarItemTap(WindowModel window) {
    if (window.minimized) {
      _wm.restoreWindow(window.id);
    } else if (_wm.activeWindow?.id == window.id) {
      _wm.minimizeWindow(window.id);
    } else {
      _wm.focusWindow(window.id);
    }
  }

  Widget _buildTaskbar(Size size) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 48,
      child: Container(
        color: WebOSColors.taskbarBackground,
        child: Row(
          children: [
            InkWell(
              onTap: () => setState(() => _startMenuOpen = !_startMenuOpen),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.grid_view,
                      size: 20,
                      color: WebOSColors.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '开始',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: WebOSColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(width: 1, height: 28, color: WebOSColors.border),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: _wm.windows.map((w) {
                    final active = _wm.activeWindow?.id == w.id;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: InkWell(
                        onTap: () => _onTaskbarItemTap(w),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.black.withValues(alpha: 0.08)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              bottom: BorderSide(
                                color: active
                                    ? Colors.blue
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _iconFor(w.appId),
                                size: 18,
                                color: WebOSColors.textPrimary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                w.title,
                                style: TextStyle(
                                  color: WebOSColors.textPrimary,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            if (_supermax)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red[700],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Super MAX',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            _buildClock(),
          ],
        ),
      ),
    );
  }

  Widget _buildDock(Size size) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 64,
      child: Container(
        color: WebOSColors.taskbarBackground,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _apps.length,
                itemBuilder: (context, index) {
                  final app = _apps[index];
                  final open = _wm.findByAppId(app.id) != null;
                  final active =
                      _wm.activeWindow?.appId == app.id;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () {
                        final existing = _wm.findByAppId(app.id);
                        if (existing == null) {
                          _launchApp(app);
                        } else {
                          _onTaskbarItemTap(existing);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: active
                                  ? Colors.blue.withValues(alpha: 0.15)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                              border: active
                                  ? Border.all(color: Colors.blue)
                                  : null,
                            ),
                            child: Icon(
                              app.icon,
                              size: 22,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: open
                                  ? Colors.blue
                                  : Colors.transparent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: '退出 WebOS',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneHome() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 80),
        child: Column(
          children: [
            Text(
              '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 56,
                fontWeight: FontWeight.w200,
              ),
            ),
            Text(
              '${_now.month}月${_now.day}日 周${_weekdays[_now.weekday - 1]}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 32),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: _apps.map(_desktopIcon).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final desktop = _isDesktopMode(size);
          final taskbarHeight = desktop ? 48.0 : 64.0;
          final area = Size(size.width, size.height - taskbarHeight);
          final wallpaper = webOSWallpapers[webOSWallpaperNotifier.value];
          final visibleWindows = desktop
              ? _wm.windows.where((w) => !w.minimized).toList()
              : (_wm.activeWindow == null
                  ? <WindowModel>[]
                  : [_wm.activeWindow!]);

          return Stack(
            children: [
              // 壁纸
              Container(
                decoration: BoxDecoration(gradient: wallpaper.gradient),
              ),
              // 桌面图标（桌面模式）
              if (desktop)
                Positioned(
                  left: 16,
                  top: 16,
                  bottom: taskbarHeight + 8,
                  child: SingleChildScrollView(
                    child: Column(
                      children: _apps.map(_desktopIcon).toList(),
                    ),
                  ),
                ),
              // 手机模式：无活动窗口时显示主屏幕
              if (!desktop && visibleWindows.isEmpty) _buildPhoneHome(),
              // 窗口层
              Positioned(
                left: 0,
                top: 0,
                width: size.width,
                height: area.height,
                child: Stack(
                  children: visibleWindows
                      .map((w) => _buildWindowFrame(w, desktop, area))
                      .toList(),
                ),
              ),
              // 本地服务失败提示
              if (_serverError != null)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  child: Center(
                    child: Material(
                      color: Colors.red[700],
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          '本地服务启动失败：$_serverError（HTML 应用无法运行）',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // 开始菜单
              if (desktop && _startMenuOpen) _buildStartMenu(size),
              // 任务栏 / Dock
              if (desktop) _buildTaskbar(size) else _buildDock(size),
            ],
          );
        },
      ),
    );
  }
}
