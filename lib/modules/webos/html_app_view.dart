import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
  WebViewController? _controller;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // 订阅发给本应用的消息，转成页面内的 webos-message 事件。
    webOSMessageBus.subscribe(widget.appId, _onBusMessage);
    _initWebView();
  }

  @override
  void dispose() {
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

  Future<void> _initWebView() async {
    // webview_flutter 不支持 Linux：直接给友好提示，不创建控制器。
    if (Platform.isLinux) {
      setState(() {
        _error = '当前平台不支持 WebView，HTML 应用无法运行';
        _loading = false;
      });
      return;
    }
    final url = WebOSLocalServer.instance.appUrl(widget.appId);
    if (url == null) {
      setState(() {
        _error = '本地服务未启动，请退出 WebOS 后重新进入';
        _loading = false;
      });
      return;
    }
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.white);
      await controller.setNavigationDelegate(
        NavigationDelegate(
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
            _controller?.runJavaScript(_bridgeJs).catchError((_) {});
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _error = '页面加载失败：${error.description}';
                _loading = false;
              });
            }
          },
        ),
      );
      await controller.addJavaScriptChannel(
        'WebOSBridge',
        onMessageReceived: _onBridgeMessage,
      );
      await controller.loadRequest(Uri.parse(url));
      if (mounted) setState(() => _controller = controller);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'WebView 初始化失败：$e';
          _loading = false;
        });
      }
    }
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _loading = true;
                    _controller = null;
                  });
                  _initWebView();
                },
                child: const Text('重试'),
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
