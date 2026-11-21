import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AiPlat 配置：OpenAI 兼容接口的连接参数。
///
/// 全部只保存在本机 SharedPreferences，绝不写进代码、绝不上传。
class AiPlatConfig {
  const AiPlatConfig({
    this.baseUrl = AiPlatConfig.defaultBaseUrl,
    this.apiKey = '',
    this.model = 'deepseek-chat',
    this.temperature = 0.7,
    this.systemPrompt = '你是一个有用的 AI 助手。',
    this.maxTokens = 4096,
  });

  /// 默认 Base URL（DeepSeek）。
  static const String defaultBaseUrl = 'https://api.deepseek.com/v1';

  /// 预置服务商 Base URL。
  static const Map<String, String> presets = {
    'DeepSeek': 'https://api.deepseek.com/v1',
    'OpenAI': 'https://api.openai.com/v1',
  };

  /// 预置服务商的默认模型。
  static const Map<String, String> presetModels = {
    'DeepSeek': 'deepseek-chat',
    'OpenAI': 'gpt-4o-mini',
  };

  static const String _kBaseUrl = 'aiplat_base_url';
  static const String _kApiKey = 'aiplat_api_key';
  static const String _kModel = 'aiplat_model';
  static const String _kTemperature = 'aiplat_temperature';
  static const String _kSystemPrompt = 'aiplat_system_prompt';
  static const String _kMaxTokens = 'aiplat_max_tokens';

  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final String systemPrompt;
  final int maxTokens;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  AiPlatConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    double? temperature,
    String? systemPrompt,
    int? maxTokens,
  }) {
    return AiPlatConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }

  /// 从本机读取配置。
  static Future<AiPlatConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AiPlatConfig(
      baseUrl: prefs.getString(_kBaseUrl) ?? defaultBaseUrl,
      apiKey: prefs.getString(_kApiKey) ?? '',
      model: prefs.getString(_kModel) ?? 'deepseek-chat',
      temperature: prefs.getDouble(_kTemperature) ?? 0.7,
      systemPrompt: prefs.getString(_kSystemPrompt) ?? '你是一个有用的 AI 助手。',
      maxTokens: prefs.getInt(_kMaxTokens) ?? 4096,
    );
  }

  /// 保存配置到本机。
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, baseUrl);
    await prefs.setString(_kApiKey, apiKey);
    await prefs.setString(_kModel, model);
    await prefs.setDouble(_kTemperature, temperature);
    await prefs.setString(_kSystemPrompt, systemPrompt);
    await prefs.setInt(_kMaxTokens, maxTokens);
  }
}

/// 发给 OpenAI 兼容接口的一条消息。
class ApiChatMessage {
  const ApiChatMessage({
    required this.role,
    required this.text,
    this.images = const [],
  });

  /// 'system' / 'user' / 'assistant'
  final String role;

  /// 文本内容。
  final String text;

  /// 图片，base64 data URL 列表，如 `data:image/jpeg;base64,...`。
  /// 非空时以 vision 格式（content 数组）发送。
  final List<String> images;

  Map<String, dynamic> toJson() {
    if (images.isEmpty) {
      return {'role': role, 'content': text};
    }
    final parts = <Map<String, dynamic>>[
      {'type': 'text', 'text': text},
      for (final image in images)
        {
          'type': 'image_url',
          'image_url': {'url': image},
        },
    ];
    return {'role': role, 'content': parts};
  }
}

/// AiPlat 请求失败，[message] 已是给用户看的中文友好提示。
class AiPlatException implements Exception {
  AiPlatException(
    this.message, {
    this.statusCode,
    this.isVisionUnsupported = false,
    this.isCancelled = false,
  });

  final String message;
  final int? statusCode;

  /// 模型不支持图片输入（可自动降级为纯文本重试）。
  final bool isVisionUnsupported;

  /// 用户主动停止生成。
  final bool isCancelled;

  @override
  String toString() => message;
}

/// OpenAI 兼容接口客户端（dio）。
///
/// 支持流式 SSE（chat completions）和 vision（base64 图片）。
class OpenAiClient {
  OpenAiClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Map<String, String> _headers(AiPlatConfig config) {
    return {
      'Authorization': 'Bearer ${config.apiKey}',
      'Content-Type': 'application/json',
    };
  }

  String _url(AiPlatConfig config) {
    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/chat/completions';
  }

  /// 测试连接：发一条极短请求，验证 API Key 与模型是否可用。
  /// 成功返回 null，失败抛 [AiPlatException]。
  Future<void> testConnection(AiPlatConfig config) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _url(config),
        data: {
          'model': config.model,
          'messages': [
            {'role': 'user', 'content': '你好'},
          ],
          'max_tokens': 1,
          'temperature': 0,
          'stream': false,
        },
        options: Options(
          headers: _headers(config),
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      if (response.statusCode != 200) {
        throw _mapStatusError(response.statusCode, response.data);
      }
    } on DioException catch (e) {
      throw await _mapDioError(e);
    }
  }

  /// 流式聊天：逐 token 产出 AI 回复内容。
  ///
  /// 模型不支持图片时（400 且报错提到 image/vision），自动去掉图片
  /// 用纯文本重试一次，并调用 [onVisionFallback] 通知界面提示用户。
  Stream<String> streamChat({
    required AiPlatConfig config,
    required List<ApiChatMessage> messages,
    CancelToken? cancelToken,
    void Function()? onVisionFallback,
  }) async* {
    final hasImages = messages.any((m) => m.images.isNotEmpty);
    try {
      yield* _streamOnce(
        config: config,
        messages: messages,
        cancelToken: cancelToken,
      );
    } on AiPlatException catch (e) {
      if (hasImages && e.isVisionUnsupported) {
        onVisionFallback?.call();
        final textOnly = messages
            .map((m) => ApiChatMessage(role: m.role, text: m.text))
            .toList();
        yield* _streamOnce(
          config: config,
          messages: textOnly,
          cancelToken: cancelToken,
        );
      } else {
        rethrow;
      }
    }
  }

  /// 一次流式请求：POST chat completions（stream: true），按行解析 SSE。
  Stream<String> _streamOnce({
    required AiPlatConfig config,
    required List<ApiChatMessage> messages,
    CancelToken? cancelToken,
  }) async* {
    late final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        _url(config),
        data: {
          'model': config.model,
          'messages': messages.map((m) => m.toJson()).toList(),
          'temperature': config.temperature,
          'max_tokens': config.maxTokens,
          'stream': true,
        },
        options: Options(
          headers: _headers(config),
          responseType: ResponseType.stream,
          connectTimeout: const Duration(seconds: 15),
          // 流式输出耗时较长，给足接收时间；中途停止用 CancelToken。
          receiveTimeout: const Duration(seconds: 300),
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw await _mapDioError(e);
    }

    if (response.statusCode != null && response.statusCode! >= 400) {
      final body = await _readStreamBody(response.data!);
      throw _mapStatusError(response.statusCode, body);
    }

    // 逐行解析 SSE：`data: {...}`，遇到 `data: [DONE]` 结束。
    // 非 data 行（如 `: ping` 注释）直接忽略。
    await for (final line in utf8.decoder
        .bind(response.data!.stream)
        .transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('data:')) {
        continue;
      }
      final data = trimmed.substring(5).trim();
      if (data == '[DONE]') {
        break;
      }
      Map<String, dynamic> json;
      try {
        json = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      // 流式通道里也可能返回错误：{"error": {...}}
      if (json.containsKey('error')) {
        throw _mapStatusError(null, json);
      }
      final choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        continue;
      }
      final delta = choices.first as Map<String, dynamic>?;
      final content = delta?['delta']?['content'];
      if (content is String && content.isNotEmpty) {
        yield content;
      }
    }
  }

  /// 把流式响应体读成字符串（用于解析错误响应）。
  Future<String> _readStreamBody(ResponseBody body) async {
    final bytes = await body.stream.fold<List<int>>(
      <int>[],
      (previous, element) => previous..addAll(element),
    );
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Dio 异常 → 中文友好的 [AiPlatException]。
  Future<AiPlatException> _mapDioError(DioException e) async {
    if (e.type == DioExceptionType.cancel) {
      return AiPlatException('已停止生成', isCancelled: true);
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return AiPlatException('请求超时，请稍后重试');
    }
    if (e.type == DioExceptionType.connectionError ||
        (e.type == DioExceptionType.unknown && e.error is SocketException)) {
      return AiPlatException('网络错误，请检查网络');
    }
    if (e.type == DioExceptionType.badResponse && e.response != null) {
      final response = e.response!;
      final data = response.data;
      if (data is ResponseBody) {
        // 流式请求的错误体还在流里，先读出来再解析。
        final body = await _readStreamBody(data);
        return _mapStatusError(response.statusCode, body);
      }
      return _mapStatusError(response.statusCode, data);
    }
    return AiPlatException('请求失败：${e.message ?? '未知错误'}');
  }

  /// 按 HTTP 状态码和错误体生成中文提示。
  AiPlatException _mapStatusError(int? statusCode, dynamic data) {
    final serverMessage = _extractErrorMessage(data);
    final lower = serverMessage?.toLowerCase() ?? '';
    final visionUnsupported = lower.contains('image') ||
        lower.contains('vision') ||
        lower.contains('multimodal') ||
        lower.contains('图片');

    switch (statusCode) {
      case 401:
        return AiPlatException('API Key 无效，请检查设置', statusCode: 401);
      case 404:
        return AiPlatException(
          '模型不存在，请检查模型名或 Base URL',
          statusCode: 404,
        );
      case 429:
        return AiPlatException('请求过于频繁，请稍后再试', statusCode: 429);
      case 400:
        if (visionUnsupported) {
          return AiPlatException(
            '当前模型不支持图片',
            statusCode: 400,
            isVisionUnsupported: true,
          );
        }
        return AiPlatException(
          serverMessage != null ? '请求参数有误：$serverMessage' : '请求参数有误',
          statusCode: 400,
        );
      default:
        if (statusCode != null && statusCode >= 500) {
          return AiPlatException(
            '服务器错误（$statusCode），请稍后再试',
            statusCode: statusCode,
          );
        }
        if (visionUnsupported) {
          return AiPlatException(
            '当前模型不支持图片',
            statusCode: statusCode,
            isVisionUnsupported: true,
          );
        }
        if (serverMessage != null && serverMessage.isNotEmpty) {
          return AiPlatException(
            statusCode != null ? '请求失败（$statusCode）：$serverMessage' : serverMessage,
            statusCode: statusCode,
          );
        }
        return AiPlatException(
          statusCode != null ? '请求失败（$statusCode）' : '请求失败',
          statusCode: statusCode,
        );
    }
  }

  /// 从错误响应里提取服务端的错误信息。
  /// 兼容 OpenAI 格式 {"error": {"message": ...}} 和纯文本。
  String? _extractErrorMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.isNotEmpty) {
          return message;
        }
      }
      if (error is String && error.isNotEmpty) {
        return error;
      }
      final message = data['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
      return null;
    }
    if (data is String && data.isNotEmpty) {
      try {
        final json = jsonDecode(data);
        if (json is Map<String, dynamic>) {
          return _extractErrorMessage(json);
        }
      } catch (_) {
        // 不是 JSON，直接当纯文本用。
      }
      return data.length > 200 ? data.substring(0, 200) : data;
    }
    return null;
  }
}
