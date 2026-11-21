import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
// 需要用到 markdown 的 Element 类型来自定义代码块渲染；markdown 是
// flutter_markdown 的传递依赖，pubspec 不由本模块维护，故忽略此提示。
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;

import 'chat_store.dart';

/// 一条聊天消息的气泡。
///
/// 用户消息居右，AI 消息居左（Markdown 渲染，代码块带复制按钮）。
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  final ChatMessage message;

  /// 是否正在流式生成中（显示输入中指示）。
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: isUser ? _buildUserContent(context) : _buildAssistantContent(context),
      ),
    );
  }

  Widget _buildUserContent(BuildContext context) {
    final children = <Widget>[];
    if (message.images.isNotEmpty) {
      children.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: message.images.map((dataUrl) {
            return _ImageThumbnail(dataUrl: dataUrl);
          }).toList(),
        ),
      );
    }
    if (message.fileNames.isNotEmpty) {
      children.add(
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: message.fileNames.map((name) {
            return Chip(
              label: Text(name, overflow: TextOverflow.ellipsis),
              avatar: const Icon(Icons.attach_file, size: 16),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      );
    }
    final text = message.shownText;
    if (text.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 8));
      }
      children.add(
        SelectableText(
          text,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildAssistantContent(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[
      MarkdownBody(
        data: message.text,
        shrinkWrap: true,
        builders: {'pre': _CodeBlockBuilder()},
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: theme.textTheme.bodyMedium,
          code: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          codeblockPadding: EdgeInsets.zero,
          codeblockDecoration: const BoxDecoration(),
        ),
      ),
    ];
    if (isStreaming) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (message.text.isNotEmpty) {
      children.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: () => _copyFullMessage(context),
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('复制全文'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Future<void> _copyFullMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制')));
  }
}

/// 用户消息里的图片缩略图，点击全屏查看。
class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.dataUrl});

  final String dataUrl;

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUrl(dataUrl);
    if (bytes == null) {
      return const Icon(Icons.broken_image);
    }
    return GestureDetector(
      onTap: () => _showFullImage(context, bytes),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          width: 160,
          height: 160,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  static Uint8List? _decodeDataUrl(String dataUrl) {
    try {
      final base64Part = dataUrl.contains(',')
          ? dataUrl.split(',').last
          : dataUrl;
      return base64Decode(base64Part);
    } catch (_) {
      return null;
    }
  }

  void _showFullImage(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              InteractiveViewer(
                child: Image.memory(bytes),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Markdown 代码块（`pre` 元素）的自定义渲染：带语言标签和复制按钮。
class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder();

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent;
    var language = '';
    final children = element.children;
    if (children != null && children.isNotEmpty) {
      final first = children.first;
      if (first is md.Element) {
        final cls = first.attributes['class'] ?? '';
        if (cls.startsWith('language-')) {
          language = cls.substring('language-'.length);
        }
      }
    }
    return _CodeBlock(code: code, language: language);
  }
}

/// 代码块：顶部语言标签 + 复制按钮，下方代码横向可滚动。
class _CodeBlock extends StatefulWidget {
  const _CodeBlock({required this.code, required this.language});

  final String code;
  final String language;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // markdown 解析出的代码常带结尾换行，显示时去掉。
    final code = widget.code.endsWith('\n')
        ? widget.code.substring(0, widget.code.length - 1)
        : widget.code;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  widget.language.isEmpty ? '代码' : widget.language,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _copy,
                icon: Icon(
                  _copied ? Icons.check : Icons.copy,
                  size: 16,
                ),
                label: Text(_copied ? '已复制' : '复制'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SelectableText(
              code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }
}
