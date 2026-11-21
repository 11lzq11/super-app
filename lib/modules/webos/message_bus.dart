/// WebOS 应用间消息总线：简单的发布 / 订阅。
///
/// HTML 应用通过 JS Bridge 的 `WebOS.sendMessage(target, data)` 发消息；
/// Flutter 迷你应用与 HTML 应用（经 HtmlAppView 转发）都可以订阅。
typedef WebOSMessageHandler = void Function(String from, dynamic data);

class WebOSMessageBus {
  final Map<String, List<WebOSMessageHandler>> _subscribers = {};

  void subscribe(String target, WebOSMessageHandler handler) {
    final list = _subscribers.putIfAbsent(target, () => []);
    if (!list.contains(handler)) {
      list.add(handler);
    }
  }

  void unsubscribe(String target, WebOSMessageHandler handler) {
    final list = _subscribers[target];
    if (list == null) return;
    list.remove(handler);
    if (list.isEmpty) {
      _subscribers.remove(target);
    }
  }

  /// 向 [target]（应用 id）发送消息，[data] 必须是可 JSON 序列化的数据。
  void send(String target, dynamic data, {String from = 'system'}) {
    final handlers = List<WebOSMessageHandler>.of(_subscribers[target] ?? const []);
    for (final handler in handlers) {
      try {
        handler(from, data);
      } catch (_) {
        // 单个订阅者出错不影响其他订阅者
      }
    }
  }
}

/// 全局唯一的消息总线实例。
final WebOSMessageBus webOSMessageBus = WebOSMessageBus();
