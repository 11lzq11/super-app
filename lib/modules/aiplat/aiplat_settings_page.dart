import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';

/// AiPlat 设置页：Base URL、API Key、模型、temperature、system prompt、最大 token。
///
/// API Key 只保存在本机 SharedPreferences，绝不写进代码、绝不上传。
class AiPlatSettingsPage extends StatefulWidget {
  const AiPlatSettingsPage({super.key});

  @override
  State<AiPlatSettingsPage> createState() => _AiPlatSettingsPageState();
}

class _AiPlatSettingsPageState extends State<AiPlatSettingsPage> {
  static const String _customPreset = '自定义';

  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _systemPromptController = TextEditingController();
  final _maxTokensController = TextEditingController();

  double _temperature = 0.7;
  String _selectedPreset = 'DeepSeek';
  bool _obscureKey = true;
  bool _loaded = false;
  bool _testing = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _systemPromptController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await AiPlatConfig.load();
    if (!mounted) {
      return;
    }
    _baseUrlController.text = config.baseUrl;
    _apiKeyController.text = config.apiKey;
    _modelController.text = config.model;
    _systemPromptController.text = config.systemPrompt;
    _maxTokensController.text = config.maxTokens.toString();
    setState(() {
      _temperature = config.temperature;
      _selectedPreset = _presetForBaseUrl(config.baseUrl);
      _loaded = true;
    });
  }

  String _presetForBaseUrl(String baseUrl) {
    for (final entry in AiPlatConfig.presets.entries) {
      if (entry.value == baseUrl) {
        return entry.key;
      }
    }
    return _customPreset;
  }

  AiPlatConfig _currentConfig() {
    final maxTokens = int.tryParse(_maxTokensController.text.trim()) ?? 4096;
    return AiPlatConfig(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim().isEmpty
          ? 'deepseek-chat'
          : _modelController.text.trim(),
      temperature: _temperature,
      systemPrompt: _systemPromptController.text,
      maxTokens: maxTokens.clamp(1, 128000),
    );
  }

  /// 每次改动都立即保存到本机。
  Future<void> _save() async {
    await _currentConfig().save();
  }

  void _selectPreset(String preset) {
    final baseUrl = AiPlatConfig.presets[preset];
    if (baseUrl == null) {
      setState(() => _selectedPreset = _customPreset);
      return;
    }
    _baseUrlController.text = baseUrl;
    final model = AiPlatConfig.presetModels[preset];
    if (model != null) {
      _modelController.text = model;
    }
    setState(() => _selectedPreset = preset);
    _save();
  }

  void _onBaseUrlChanged(String value) {
    setState(() => _selectedPreset = _presetForBaseUrl(value.trim()));
    _save();
  }

  Future<void> _testConnection() async {
    final config = _currentConfig();
    if (!config.hasApiKey) {
      setState(() {
        _testResult = '请先填写 API Key';
        _testSuccess = false;
      });
      return;
    }
    if (config.baseUrl.isEmpty) {
      setState(() {
        _testResult = '请先填写 Base URL';
        _testSuccess = false;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      await OpenAiClient().testConnection(config);
      if (!mounted) {
        return;
      }
      setState(() {
        _testResult = '连接成功，API Key 可用';
        _testSuccess = true;
      });
    } on AiPlatException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _testResult = '连接失败：${e.message}';
        _testSuccess = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _testResult = '连接失败：$e';
        _testSuccess = false;
      });
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AiPlat 设置')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionTitle('服务商'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final preset in AiPlatConfig.presets.keys)
                      ChoiceChip(
                        label: Text(preset),
                        selected: _selectedPreset == preset,
                        onSelected: (_) => _selectPreset(preset),
                      ),
                    ChoiceChip(
                      label: const Text(_customPreset),
                      selected: _selectedPreset == _customPreset,
                      onSelected: (_) {
                        setState(() => _selectedPreset = _customPreset);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _baseUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.deepseek.com/v1',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  onChanged: _onBaseUrlChanged,
                ),
                const SizedBox(height: 16),
                _sectionTitle('API Key'),
                TextField(
                  controller: _apiKeyController,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: 'sk-...',
                    border: const OutlineInputBorder(),
                    helperText: '仅保存在本机，不会上传到任何服务器。',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      tooltip: _obscureKey ? '显示' : '隐藏',
                      onPressed: () {
                        setState(() => _obscureKey = !_obscureKey);
                      },
                    ),
                  ),
                  obscureText: _obscureKey,
                  onChanged: (_) => _save(),
                ),
                const SizedBox(height: 16),
                _sectionTitle('模型'),
                TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: '模型名',
                    hintText: 'deepseek-chat',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _save(),
                ),
                const SizedBox(height: 16),
                _sectionTitle('Temperature（创造性）'),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _temperature,
                        min: 0,
                        max: 2,
                        divisions: 20,
                        label: _temperature.toStringAsFixed(1),
                        onChanged: (value) {
                          setState(() => _temperature = value);
                          _save();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        _temperature.toStringAsFixed(1),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _sectionTitle('最大 Token'),
                TextField(
                  controller: _maxTokensController,
                  decoration: const InputDecoration(
                    labelText: '最大回复 Token 数',
                    hintText: '4096',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => _save(),
                ),
                const SizedBox(height: 16),
                _sectionTitle('System Prompt（系统提示词）'),
                TextField(
                  controller: _systemPromptController,
                  decoration: const InputDecoration(
                    hintText: '你是一个有用的 AI 助手。',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 3,
                  maxLines: 6,
                  onChanged: (_) => _save(),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_outlined),
                  label: Text(_testing ? '测试中…' : '测试连接'),
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _testResult!,
                    style: TextStyle(
                      color: _testSuccess
                          ? Colors.green.shade700
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
