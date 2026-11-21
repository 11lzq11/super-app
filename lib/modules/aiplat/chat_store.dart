import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 消息角色。
enum ChatRole { user, assistant }

/// 一条聊天消息。
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.displayText,
    this.images = const [],
    this.fileNames = const [],
    DateTime? createdAt,
    this.isError = false,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final ChatRole role;

  /// 发给 API 的完整文本（含文件内容等上下文）。
  String text;

  /// 界面上显示的文本；为空时显示 [text]。
  /// 带文件附件时只显示用户输入的文字，不把文件内容全文显示出来。
  final String? displayText;

  /// 附带的图片，base64 data URL 列表。
  final List<String> images;

  /// 随消息附带的文件名（仅展示用）。
  final List<String> fileNames;

  final DateTime createdAt;

  /// 是否为错误提示消息（红色样式展示）。
  bool isError;

  /// 界面实际显示的文本。
  String get shownText =>
      displayText != null && displayText!.isNotEmpty ? displayText! : text;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'text': text,
      'displayText': displayText,
      'images': images,
      'fileNames': fileNames,
      'createdAt': createdAt.toIso8601String(),
      'isError': isError,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: ChatRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => ChatRole.user,
      ),
      text: json['text'] as String? ?? '',
      displayText: json['displayText'] as String?,
      images:
          (json['images'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const [],
      fileNames:
          (json['fileNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      isError: json['isError'] as bool? ?? false,
    );
  }
}

/// 一个会话。
class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : messages = messages ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((m) => m.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '新会话',
      messages:
          (json['messages'] as List<dynamic>?)
              ?.map(
                (e) => ChatMessage.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// 会话管理：多会话、标题自动生成、内存 + SharedPreferences 简单持久化。
class ChatStore extends ChangeNotifier {
  static const String _prefsKey = 'aiplat_sessions_v1';
  static const String _defaultTitle = '新会话';

  static int _idCounter = 0;

  final List<ChatSession> _sessions = [];
  String? _currentId;
  bool _loaded = false;

  List<ChatSession> get sessions => List.unmodifiable(_sessions);

  bool get loaded => _loaded;

  ChatSession? get currentSession {
    if (_currentId == null) {
      return null;
    }
    for (final session in _sessions) {
      if (session.id == _currentId) {
        return session;
      }
    }
    return null;
  }

  String _newId() {
    _idCounter++;
    return '${DateTime.now().millisecondsSinceEpoch}_$_idCounter';
  }

  /// 从本机加载会话；首次使用时创建一个空会话。
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _sessions.clear();
        for (final item in list) {
          _sessions.add(ChatSession.fromJson(item as Map<String, dynamic>));
        }
        _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      } catch (_) {
        _sessions.clear();
      }
    }
    if (_sessions.isEmpty) {
      _sessions.add(ChatSession(id: _newId(), title: _defaultTitle));
    }
    _currentId = _sessions.first.id;
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_sessions.map((s) => s.toJson()).toList()),
      );
    } catch (_) {
      // 持久化失败不影响当前使用（如图片过多导致超限），忽略。
    }
  }

  /// 新建会话并切换过去。
  ChatSession newSession() {
    final session = ChatSession(id: _newId(), title: _defaultTitle);
    _sessions.insert(0, session);
    _currentId = session.id;
    _save();
    notifyListeners();
    return session;
  }

  /// 切换当前会话。
  void switchSession(String id) {
    if (_sessions.any((s) => s.id == id)) {
      _currentId = id;
      notifyListeners();
    }
  }

  /// 删除会话；删的是当前会话时自动切换到剩下的第一个，没有则新建。
  void deleteSession(String id) {
    _sessions.removeWhere((s) => s.id == id);
    if (_sessions.isEmpty) {
      _sessions.add(ChatSession(id: _newId(), title: _defaultTitle));
    }
    if (_currentId == id) {
      _currentId = _sessions.first.id;
    }
    _save();
    notifyListeners();
  }

  /// 添加一条用户消息；会话标题还是默认时，用第一条用户消息前 20 字自动命名。
  ChatMessage addUserMessage({
    required String text,
    String? displayText,
    List<String> images = const [],
    List<String> fileNames = const [],
  }) {
    final session = currentSession;
    if (session == null) {
      throw StateError('没有当前会话');
    }
    final message = ChatMessage(
      id: _newId(),
      role: ChatRole.user,
      text: text,
      displayText: displayText,
      images: List.of(images),
      fileNames: List.of(fileNames),
    );
    session.messages.add(message);
    if (session.title == _defaultTitle) {
      session.title = _autoTitle(displayText ?? text);
    }
    session.updatedAt = DateTime.now();
    _save();
    notifyListeners();
    return message;
  }

  /// 开始一条 AI 回复（空内容，流式追加）。
  ChatMessage startAssistantMessage() {
    final session = currentSession;
    if (session == null) {
      throw StateError('没有当前会话');
    }
    final message = ChatMessage(
      id: _newId(),
      role: ChatRole.assistant,
      text: '',
    );
    session.messages.add(message);
    notifyListeners();
    return message;
  }

  /// 流式追加 token 到指定的 AI 消息。
  void appendAssistantText(String messageId, String delta) {
    final message = _findMessage(messageId);
    if (message == null) {
      return;
    }
    message.text += delta;
    notifyListeners();
  }

  /// AI 回复结束：更新时间并持久化。
  /// 内容为空（用户刚开始就点了停止）时直接移除这条空消息。
  void finishAssistantMessage(String messageId) {
    final session = currentSession;
    final message = _findMessage(messageId);
    if (session == null || message == null) {
      return;
    }
    if (message.text.trim().isEmpty && !message.isError) {
      session.messages.remove(message);
    } else {
      session.updatedAt = DateTime.now();
    }
    _save();
    notifyListeners();
  }

  /// 把指定的 AI 消息标记为错误并写入错误提示。
  /// 已有部分内容时保留原文并追加错误说明。
  void setAssistantError(String messageId, String errorText) {
    final session = currentSession;
    final message = _findMessage(messageId);
    if (session == null || message == null) {
      return;
    }
    if (message.text.trim().isEmpty) {
      message.text = errorText;
    } else {
      message.text = '${message.text}\n\n⚠️ $errorText';
    }
    message.isError = true;
    session.updatedAt = DateTime.now();
    _save();
    notifyListeners();
  }

  ChatMessage? _findMessage(String messageId) {
    final session = currentSession;
    if (session == null) {
      return null;
    }
    for (final message in session.messages) {
      if (message.id == messageId) {
        return message;
      }
    }
    return null;
  }

  /// 标题：去掉多余空白后取前 20 字。
  String _autoTitle(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) {
      return _defaultTitle;
    }
    return clean.length <= 20 ? clean : clean.substring(0, 20);
  }
}
