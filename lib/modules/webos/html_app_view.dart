import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'local_server.dart';
import 'message_bus.dart';

/// HTML 应用与 WebOS 宿主之间的回调接口（由 WebOSPage 提供实现）。
class WebOSHost {
  /// 启动另一个 WebOS 应用。
  final Future<void> Function(String appId, {Map<String, dynamic>? params})
      launchApp;

  /// 打开一个文件（文本进记事本，.html 提示安装为应用）。
  final Future<void> Function(String path) openFile;

  /// 列出目录内容（JS Bridge 的 getFileList 用）。
  final Future<List<Map<String, dynamic>>> Function(String dir) getFileList;

  const WebOSHost({
    required this.launchApp,
    required this.openFile,
    required this.getFileList,
  });
}

/// 注入到每个 HTML 应用页面的 JS Bridge。
///
/// 提供：WebOS.launchApp / WebOS.openFile / WebOS.sendMessage / WebOS.getFileList，
/// 以及 window 的 'webos-message' 事件（接收其他应用发来的消息）。
const String _bridgeJs = r'''
(function () {
  if (window.WebOS) return;
  window.__webosPending = {};
  window.__webosResolve = function (id, json) {
    var p = window.__webosPending[id];
    if (!p) return;
    delete window.__webosPending[id];
    try { p(JSON.parse(json)); } catch (e) { p(null); }
  };
  function post(msg) {
    if (window.WebOSBridge) {
      window.WebOSBridge.postMessage(JSON.stringify(msg));
    }
  }
  window.WebOS = {
    launchApp: function (appId, params) {
      post({ action: 'launchApp', appId: appId, params: params || {} });
    },
    openFile: function (path) {
      post({ action: 'openFile', path: path });
    },
    sendMessage: function (target, data) {
      post({ action: 'sendMessage', target: target, data: data });
    },
    getFileList: function (dir) {
      return new Promise(function (resolve) {
        var id = 'r' + Math.random().toString(36).slice(2);
        window.__webosPending[id] = resolve;
        post({ action: 'getFileList', dir: dir || '', _id: id });
      });
    }
  };
})();
''';

/// HTML 应用窗口内容：WebView 加载 localhost 上的应用页面。
///
/// 加载加固：
/// - 加载前先探测本地服务是否真的能响应，不行就重启服务再试；
/// - 只把主框架（main frame）的资源错误当失败：favicon 等子资源 404
///   会被忽略，不会再把已经打开的应用误判成加载失败；
/// - 主框架失败或 15 秒无响应时自动重试，最多 3 次；
/// - 3 次都失败才显示错误页，带诊断信息（端口、地址、错误原因）与重试。
class HtmlAppView extends StatefulWidget {
  final String appId;
  final String appName;
  final WebOSHost host;

  const HtmlAppView({
    super.key,
    required this.appId,
    required this.appName,
    required this.host,
  });

  @override
  State<HtmlAppView> createState() => _HtmlAppViewState();
}

class _HtmlAppViewState extends State<HtmlAppView> {
  static const int _maxAttempts = 3;
  static const Duration _loadTimeout = Duration(seconds: 15);
  static const Duration _retryDelay = Duration(milliseconds: 800);

  WebViewController? _controller;
  String? _error;
  String? _errorDetail;
  bool _loading = true;
  bool _pageLoaded = false;
  int _attempt = 0;
  Timer? _loadTimer;

  @override
  void initState() {
    super.initState();
    // 订阅发给本应用的消息，转成页面内的 webos-message 事件。
    webOSMessageBus.subscribe(widget.appId, _onBusMessage);
    _startLoad();
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    webOSMessageBus.unsubscribe(widget.appId, _onBusMessage);
    super.dispose();
  }

  void _onBusMessage(String from, dynamic data) {
    final controller = _controller;
    if (controller == null) return;
    final payload = jsonEncode({'from': from, 'data': data});
    controller
        .runJavaScript(
          "window.dispatchEvent(new CustomEvent('webos-message', {detail: $payload}));",
        )
        .catchError((_) {});
  }

  /// 从头开始加载（手动重试时调）：重置计数与状态。
  Future<void> _startLoad() async {
    // webview_flutter 不支持 Linux：直接给友好提示，不创建控制器。
    if (Platform.isLinux) {
      setState(() {
        _error = '当前平台不支持 WebView，HTML 应用无法运行';
        _errorDetail = 'webview_flutter 没有 Linux 实现';
        _loading = false;
      });
      return;
    }
    _attempt = 0;
    _pageLoaded = false;
    await _loadAttempt();
  }

  /// 一次加载尝试：先确认服务就绪，再加载 URL。
  Future<void> _loadAttempt() async {
    if (!mounted) return;
    _attempt++;
    setState(() {
      _error = null;
      _errorDetail = null;
      _loading = true;
    });

    // 1. 确保本地服务真的能响应（不行就重启服务再探测一次）。
    final ready = await WebOSLocalServer.instance.ensureReady();
    if (!mounted) return;
    if (!ready) {
      _handleFailure(
        '本地服务未启动',
        'localhost 服务启动后仍无响应，请退出 WebOS 后重新进入',
      );
      return;
    }
    final url = WebOSLocalServer.instance.appUrl(widget.appId);
    if (url == null) {
      _handleFailure('本地服务未启动', '服务地址为空，请退出 WebOS 后重新进入');
      return;
    }

    // 2. 加载页面（控制器只建一次，重试时复用）。
    try {
      var controller = _controller;
      if (controller == null) {
        controller = WebViewController();
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.setBackgroundColor(Colors.white);
        await controller.setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              _pageLoaded = false;
              _armLoadTimeout();
            },
            onNavigationRequest: (request) {
              // webos://launch?app=<id>&param=... ：应用内链接启动另一应用
              if (request.url.startsWith('webos://')) {
                final uri = Uri.tryParse(request.url);
                final appId = uri?.queryParameters['app'];
                if (appId != null && appId.isNotEmpty) {
                  final params = Map<String, dynamic>.from(
                    uri!.queryParameters,
                  )..remove('app');
                  widget.host.launchApp(appId, params: params);
                }
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onPageFinished: (_) {
              _pageLoaded = true;
              _loadTimer?.cancel();
              _controller?.runJavaScript(_bridgeJs).catchError((_) {});
              if (mounted) {
                setState(() {
                  _loading = false;
                  _error = null;
                  _errorDetail = null;
                });
              }
            },
            onWebResourceError: (error) {
              // 子资源错误（典型如 favicon.ico 404）不是页面失败：
              // 只有明确是主框架的错误才当作加载失败。
              if (error.isForMainFrame == false) return;
              _handleFailure(
                '页面加载失败',
                '错误码 ${error.errorCode}'
                '（${error.errorType?.name ?? 'unknown'}）'
                '${error.description.isNotEmpty ? '：${error.description}' : ''}',
              );
            },
          ),
        );
        await controller.addJavaScriptChannel(
          'WebOSBridge',
          onMessageReceived: _onBridgeMessage,
        );
        _controller = controller;
      }
      _armLoadTimeout();
      await controller.loadRequest(Uri.parse(url));
      if (mounted) setState(() => _controller = controller);
    } catch (e) {
      _handleFailure('WebView 加载失败', '$e');
    }
  }

  /// 15 秒内没 onPageFinished 就算超时。
  void _armLoadTimeout() {
    _loadTimer?.cancel();
    _loadTimer = Timer(_loadTimeout, () {
      if (!mounted || _pageLoaded) return;
      _handleFailure(
        '页面加载超时',
        '应用在 ${_loadTimeout.inSeconds} 秒内没有响应',
      );
    });
  }

  /// 一次失败：次数未用完就自动重试，用完才显示错误页。
  void _handleFailure(String title, String detail) {
    _loadTimer?.cancel();
    if (_attempt < _maxAttempts && mounted && !_pageLoaded) {
      Future.delayed(_retryDelay, () {
        if (mounted && !_pageLoaded) _loadAttempt();
      });
      return;
    }
    if (mounted) {
      setState(() {
        _error = title;
        _errorDetail = detail;
        _loading = false;
      });
    }
  }

  /// 诊断信息：端口、地址、尝试次数、错误原因，供错误页展示与复制。
  String get _diagnostics {
    final port = WebOSLocalServer.instance.port;
    final url = WebOSLocalServer.instance.appUrl(widget.appId);
    return '应用：${widget.appId}（${widget.appName}）\n'
        '地址：${url ?? '（服务未启动）'}\n'
        '端口：${port?.toString() ?? '（未知）'}\n'
        '尝试：$_attempt/$_maxAttempts 次\n'
        '错误：${_errorDetail ?? '未知'}';
  }

  /// 处理 JS Bridge 发来的消息（JSON 字符串）。
  Future<void> _onBridgeMessage(JavaScriptMessage message) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final action = msg['action'] as String?;
    switch (action) {
      case 'launchApp':
        final appId = msg['appId'] as String?;
        if (appId != null && appId.isNotEmpty) {
          final params = msg['params'];
          await widget.host.launchApp(
            appId,
            params: params is Map<String, dynamic> ? params : null,
          );
        }
      case 'openFile':
        final path = msg['path'] as String?;
        if (path != null && path.isNotEmpty) {
          await widget.host.openFile(path);
        }
      case 'sendMessage':
        final target = msg['target'] as String?;
        if (target != null && target.isNotEmpty) {
          webOSMessageBus.send(
            target,
            msg['data'],
            from: widget.appId,
          );
        }
      case 'getFileList':
        final dir = (msg['dir'] as String?) ?? '';
        final reqId = msg['_id'] as String?;
        List<Map<String, dynamic>> list = [];
        String? error;
        try {
          list = await widget.host.getFileList(dir);
        } catch (e) {
          error = '$e';
        }
        if (reqId != null) {
          final payload = jsonEncode({
            'ok': error == null,
            'error': error,
            'list': list,
          });
          await _controller
              ?.runJavaScript(
                'window.__webosResolve(${jsonEncode(reqId)}, ${jsonEncode(payload)});',
              )
              .catchError((_) {});
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_outlined,
                size: 40,
                color: Colors.orange,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _diagnostics,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _errorDetail = null;
                        _loading = true;
                      });
                      _startLoad();
                    },
                    child: const Text('重试'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: _diagnostics),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('诊断信息已复制')),
                      );
                    },
                    child: const Text('复制诊断信息'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        WebViewWidget(controller: controller),
        if (_loading)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
