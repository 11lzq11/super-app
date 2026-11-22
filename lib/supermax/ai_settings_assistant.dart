import '../modules/aiplat/api_client.dart';
import 'toolbox_commands.dart';

/// 未配置 AiPlat API Key（调用方显示手动设置浏览器兜底）。
class AiSettingsNoKeyException implements Exception {
  @override
  String toString() => '未配置 AiPlat API Key';
}

/// AI 调设置：把用户的自然语言需求翻译成系统命令列表。
///
/// 复用 AiPlat 已配置的 OpenAI 兼容 API（[AiPlatConfig.load] + [OpenAiClient]，
/// 不改 AiPlat 核心）：system prompt 要求模型只输出 JSON 命令列表，
/// 再经 [parseAiCommandList] 白名单校验后返回。
/// 模型温度固定 0（确定性输出），maxTokens 1024（命令列表很短，够用）。
class AiSettingsAssistant {
  AiSettingsAssistant({OpenAiClient? client})
      : _client = client ?? OpenAiClient();

  final OpenAiClient _client;

  /// AI 调设置的 system prompt：只输出 JSON，不解释。
  static const String systemPrompt = '''
你是一个 Android 系统设置助手。用户用中文描述想改的系统设置，你把它翻译成命令列表。

只输出 JSON，不要解释、不要多余文字。格式：
{"commands": [{"action": "settings_put", "table": "system", "key": "screen_brightness", "value": "10"}, {"action": "svc", "service": "bluetooth", "state": "disable"}]}

可用的 action（只能用这些）：
- settings_put：修改 settings 表。table 只能是 system/secure/global。
  常用键：
  亮度 screen_brightness（0-255，system 表；手动亮度时同时把 screen_brightness_mode 设为 0，自动亮度设为 1）、
  屏幕超时 screen_off_timeout（毫秒，system 表，如 10 分钟是 600000）、
  动画速度 window_animation_scale / transition_animation_scale / animator_duration_scale（global 表，0 表示关闭动画，0.5 表示 0.5x）、
  字体大小 font_scale（system 表，如 1.15）、
  勿扰 zen_mode（global 表，0 关闭，1 仅优先，2 完全静音，3 仅闹钟）、
  自动旋转 accelerometer_rotation（system 表，0 关，1 开）、
  省电模式 low_power（global 表，0 关，1 开）、
  最高刷新率 peak_refresh_rate / 最低刷新率 min_refresh_rate（system 表，单位 Hz，如 120）。
- svc：开关服务。service 只能是 wifi/bluetooth/data/nfc，state 是 enable/disable。
- wm：屏幕尺寸/密度。size 可为 "1080x2400" 或 "reset"，density 可为数字（如 "420"）或 "reset"。一次只能改 size 或 density 其中一个。
- night：深色模式。value 是 yes/no。
- input：模拟按键。keycode 是数字，如 26 电源键、3 Home、4 返回、24 音量加、25 音量减。

注意：
- "把亮度调到最低" → screen_brightness 设为 10（不要设 0，会黑屏看不见），同时 screen_brightness_mode 设为 0；
- "关闭动画" → 三个动画 scale 都设为 0；
- 无法完成的需求返回 {"commands": []}。
''';

  /// 把 [request] 翻译成命令列表。
  ///
  /// 未配置 API Key 时抛 [AiSettingsNoKeyException]；
  /// API 调用失败时抛 [AiPlatException]（中文友好提示）；
  /// 解析失败时返回带 error 的结果（commands 为空）。
  Future<AiCommandParseResult> translate(String request) async {
    final config = await AiPlatConfig.load();
    if (!config.hasApiKey) {
      throw AiSettingsNoKeyException();
    }
    final taskConfig = config.copyWith(temperature: 0, maxTokens: 1024);
    final fullText = await _client
        .streamChat(
          config: taskConfig,
          messages: [
            const ApiChatMessage(role: 'system', text: systemPrompt),
            ApiChatMessage(role: 'user', text: request),
          ],
        )
        .join();
    return parseAiCommandList(fullText);
  }
}
