import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

import 'webos_paths.dart';

/// WebOS 内置 localhost 服务。
///
/// 用 shelf + shelf_static 在 127.0.0.1 的随机空闲端口上托管
/// webos/apps/，HTML 应用通过 `http://127.0.0.1:<port>/<appId>/index.html`
/// 加载，能用相对路径加载资源、能 fetch 同源内容，行为像真网站。
///
/// 单例：WebOS 打开时启动，退出时关闭；WebOS 设置页可直接读当前端口。
class WebOSLocalServer {
  WebOSLocalServer._();

  static final WebOSLocalServer instance = WebOSLocalServer._();

  HttpServer? _server;

  bool get isRunning => _server != null;

  int? get port => _server?.port;

  /// 如 http://127.0.0.1:54321/，未启动时为 null。
  String? get baseUrl =>
      _server == null ? null : 'http://127.0.0.1:${_server!.port}/';

  /// 启动服务（已启动时直接返回）。端口由系统分配空闲端口。
  Future<void> start() async {
    if (isRunning) return;
    final root = await WebOSPaths.appsDir();
    final handler = createStaticHandler(
      root.path,
      defaultDocument: 'index.html',
      listDirectories: false,
    );
    _server = await shelf_io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      0,
    );
  }

  /// 确保服务真的能响应：未启动则启动；启动后探测一次，
  /// 探测失败则重启一次再探测。
  ///
  /// 任意一次 HTTP 响应（哪怕 404）都算服务存活 —— 只有连接不上
  /// 才算未就绪。WebView 加载前调一次，避免对着没起来的服务发请求。
  Future<bool> ensureReady() async {
    if (!isRunning) {
      try {
        await start();
      } catch (_) {
        return false;
      }
    }
    if (await _probe()) return true;
    try {
      await stop();
      await start();
    } catch (_) {
      return false;
    }
    return _probe();
  }

  /// 向服务根地址发一个 GET：能拿到响应即存活。
  Future<bool> _probe() async {
    final base = baseUrl;
    if (base == null) return false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(Uri.parse(base));
      final response =
          await request.close().timeout(const Duration(seconds: 2));
      await response.drain<void>();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// 某个 HTML 应用的完整 URL，未启动时为 null。
  String? appUrl(String appId) {
    final base = baseUrl;
    if (base == null) return null;
    return '$base$appId/index.html';
  }

  /// 关闭服务。
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
