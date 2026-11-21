import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'aiplat_settings_page.dart';
import 'api_client.dart';
import 'chat_store.dart';
import 'message_bubble.dart';

/// AiPlat 聊天主界面：多会话、流式输出、图片/文件上传、Markdown 渲染。
class AiPlatPage extends StatefulWidget {
  const AiPlatPage({super.key});

  @override
  State<AiPlatPage> createState() => _AiPlatPageState();
}

class _AiPlatPageState extends State<AiPlatPage> {
  /// 单个文件最大读取 200KB，避免请求体过大。
  static const int _maxFileBytes = 200 * 1024;

  /// 单个文件最多拼进 20000 字上下文。
  static const int _maxFileChars = 20000;

  /// 允许读取为文本的文件扩展名。
  static const List<String> _textFileExtensions = [
    'txt',
    'md',
    'csv',
    'json',
    'dart',
    'py',
    'js',
    'ts',
    'java',
    'kt',
    'c',
    'cpp',
    'h',
    'html',
    'css',
    'xml',
    'yaml',
    'yml',
    'log',
    'sql',
  ];

  static const List<String> _suggestions = [
    '写一首关于秋天的诗',
    '用 Python 写一个快速排序',
    '解释一下量子计算',
    '帮我制定一周健身计划',
  ];

  late final ChatStore _store;
  final OpenAiClient _client = OpenAiClient();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  AiPlatConfig? _config;
  bool _isGenerating = false;
  CancelToken? _cancelToken;

  /// 待发送的图片（已压缩并转 base64）。
  final List<_PendingImage> _pendingImages = [];

  /// 待发送的文件（已读成文本）。
  final List<_PendingFile> _pendingFiles = [];

  @override
  void initState() {
    super.initState();
    _store = ChatStore();
    _store.load();
    _loadConfig();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _cancelToken?.cancel();
    _store.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await AiPlatConfig.load();
    if (!mounted) {
      return;
    }
    setState(() => _config = config);
  }

  void _openSettings() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => const AiPlatSettingsPage(),
          ),
        )
        .then((_) => _loadConfig());
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- 会话 ----------

  void _newSession() {
    _store.newSession();
    _scrollToBottom();
  }

  Future<void> _confirmDeleteSession(ChatSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除会话'),
          content: Text('确定删除「${session.title}」吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      _store.deleteSession(session.id);
    }
  }

  // ---------- 附件 ----------

  void _showAttachMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('图片'),
                subtitle: const Text('从相册选择，自动压缩后发送'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('文件'),
                subtitle: const Text('读取文本内容拼进消息（最大 200KB）'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage() async {
    try {
      final xfile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        // 压缩到最长边 1024、JPEG 质量 80，避免请求体过大。
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (xfile == null) {
        return;
      }
      final bytes = await xfile.readAsBytes();
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingImages.add(_PendingImage(bytes: bytes, dataUrl: dataUrl));
      });
    } catch (e) {
      if (mounted) {
        _showSnack('选择图片失败：$e');
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _textFileExtensions,
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        if (mounted) {
          _showSnack('无法读取该文件');
        }
        return;
      }
      if (bytes.length > _maxFileBytes) {
        if (mounted) {
          _showSnack('文件过大（超过 200KB），请选更小的文件');
        }
        return;
      }
      var content = utf8.decode(bytes, allowMalformed: true);
      if (content.length > _maxFileChars) {
        content = content.substring(0, _maxFileChars);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingFiles.add(_PendingFile(name: file.name, content: content));
      });
    } catch (e) {
      if (mounted) {
        _showSnack('选择文件失败：$e');
      }
    }
  }

  // ---------- 发送 / 停止 ----------

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (_isGenerating) {
      return;
    }
    if (text.isEmpty && _pendingImages.isEmpty && _pendingFiles.isEmpty) {
      return;
    }
    final config = _config;
    if (config == null || !config.hasApiKey) {
      _showSnack('请先在设置里配置 API Key');
      _openSettings();
      return;
    }

    // 组装发给 API 的文本：用户文字 + 文件内容（前面加“[文件 xxx 内容]”）。
    final buffer = StringBuffer(text);
    for (final file in _pendingFiles) {
      if (buffer.isNotEmpty) {
        buffer.write('\n\n');
      }
      buffer.write('[文件 ${file.name} 内容]\n${file.content}');
    }
    final sendText = buffer.toString();
    final images = _pendingImages.map((e) => e.dataUrl).toList();
    final fileNames = _pendingFiles.map((e) => e.name).toList();
    // 界面只显示用户输入的文字（和文件名），不把文件内容全文显示出来。
    final displayText = text.isEmpty && fileNames.isNotEmpty
        ? '发送了文件：${fileNames.join('、')}'
        : text;

    _textController.clear();
    _pendingImages.clear();
    _pendingFiles.clear();

    final session = _store.currentSession;
    if (session == null) {
      return;
    }
    _store.addUserMessage(
      text: sendText,
      displayText: displayText,
      images: images,
      fileNames: fileNames,
    );
    final assistantMessage = _store.startAssistantMessage();
    _scrollToBottom();

    setState(() => _isGenerating = true);
    _cancelToken = CancelToken();

    final apiMessages = <ApiChatMessage>[
      if (config.systemPrompt.trim().isNotEmpty)
        ApiChatMessage(role: 'system', text: config.systemPrompt.trim()),
      for (final message in session.messages)
        if (message.id != assistantMessage.id)
          ApiChatMessage(
            role: message.role == ChatRole.user ? 'user' : 'assistant',
            text: message.text,
            images: message.images,
          ),
    ];

    try {
      await for (final delta in _client.streamChat(
        config: config,
        messages: apiMessages,
        cancelToken: _cancelToken,
        onVisionFallback: () {
          if (mounted) {
            _showSnack('当前模型不支持图片，已只发文字');
          }
        },
      )) {
        _store.appendAssistantText(assistantMessage.id, delta);
        _scrollToBottom();
      }
      _store.finishAssistantMessage(assistantMessage.id);
    } on AiPlatException catch (e) {
      if (e.isCancelled) {
        // 用户主动停止：保留已有内容，不显示错误。
        _store.finishAssistantMessage(assistantMessage.id);
      } else {
        _store.setAssistantError(assistantMessage.id, e.message);
      }
    } catch (e) {
      _store.setAssistantError(assistantMessage.id, '请求失败：$e');
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
      _cancelToken = null;
      _scrollToBottom();
    }
  }

  void _stopGenerating() {
    _cancelToken?.cancel('用户停止生成');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      // 只有接近底部时才自动滚动，避免打断用户翻看历史。
      if (position.maxScrollExtent - position.pixels < 300) {
        _scrollController.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------- 界面 ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AiPlat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: '新建会话',
            onPressed: _newSession,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: _openSettings,
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          _buildAttachmentPreview(),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          final sessions = _store.sessions;
          final currentId = _store.currentSession?.id;
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AiPlat',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    const Text('多会话 AI 聊天'),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('新建会话'),
                onTap: () {
                  _store.newSession();
                  Navigator.of(context).pop();
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final selected = session.id == currentId;
                    final lastText = session.messages.isEmpty
                        ? '空会话'
                        : session.messages.last.shownText.replaceAll(
                            RegExp(r'\s+'),
                            ' ',
                          );
                    return ListTile(
                      selected: selected,
                      title: Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        lastText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        _store.switchSession(session.id);
                        Navigator.of(context).pop();
                        _scrollToBottom();
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: '删除会话',
                        onPressed: () => _confirmDeleteSession(session),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_config == null || !_store.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_config!.hasApiKey) {
      return _buildNoKeyGuide();
    }
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final session = _store.currentSession;
        if (session == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (session.messages.isEmpty) {
          return _buildEmptyState();
        }
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: session.messages.length,
          itemBuilder: (context, index) {
            final message = session.messages[index];
            final isLast = index == session.messages.length - 1;
            return MessageBubble(
              message: message,
              isStreaming:
                  _isGenerating &&
                  isLast &&
                  message.role == ChatRole.assistant,
            );
          },
        );
      },
    );
  }

  /// 未配置 API Key 时的引导卡片，点一下跳到设置页。
  Widget _buildNoKeyGuide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: InkWell(
            onTap: _openSettings,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.key_outlined, size: 48),
                  SizedBox(height: 16),
                  Text(
                    '还没有配置 API Key',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '去设置里填写 Base URL、API Key 和模型，就可以开始聊天了。支持 DeepSeek、OpenAI 等 OpenAI 兼容接口。',
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  Text('去设置 →'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 空会话的欢迎页 + 示例问题。
  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              '你好，我是 AiPlat',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('输入消息开始聊天，也可以上传图片或文件一起聊。'),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _suggestions.map((suggestion) {
                return ActionChip(
                  label: Text(suggestion),
                  onPressed: () {
                    _textController.text = suggestion;
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  /// 待发送附件预览：图片缩略图 + 文件名，点 × 移除。
  Widget _buildAttachmentPreview() {
    if (_pendingImages.isEmpty && _pendingFiles.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final image in _pendingImages)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        image.bytes,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _pendingImages.remove(image));
                        },
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            for (final file in _pendingFiles)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  label: Text(file.name),
                  avatar: const Icon(Icons.attach_file, size: 16),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() => _pendingFiles.remove(file));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file),
              tooltip: '上传图片或文件',
              onPressed: _isGenerating ? null : _showAttachMenu,
            ),
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '输入消息…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_isGenerating)
              IconButton.filled(
                onPressed: _stopGenerating,
                icon: const Icon(Icons.stop),
                tooltip: '停止生成',
              )
            else
              IconButton.filled(
                onPressed: _send,
                icon: const Icon(Icons.send),
                tooltip: '发送',
              ),
          ],
        ),
      ),
    );
  }
}

/// 待发送的图片：压缩后的字节（用于缩略图）+ base64 data URL（用于发给 API）。
class _PendingImage {
  _PendingImage({required this.bytes, required this.dataUrl});

  final Uint8List bytes;
  final String dataUrl;
}

/// 待发送的文件：文件名 + 读出的文本内容。
class _PendingFile {
  _PendingFile({required this.name, required this.content});

  final String name;
  final String content;
}
