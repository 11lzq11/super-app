import 'dart:io';

import 'package:flutter/material.dart';

import '../webos_paths.dart';

/// 记事本：纯文本编辑，保存在 webos/notes/。
/// 可通过 [initialPath] 直接打开指定文件（文件管理器 / openFile 调用）。
class NotesApp extends StatefulWidget {
  final String? initialPath;

  const NotesApp({super.key, this.initialPath});

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  List<File> _notes = [];
  File? _current;
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (!_dirty) setState(() => _dirty = true);
    });
    _init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _refreshList();
    final initial = widget.initialPath;
    if (initial != null && initial.isNotEmpty) {
      final file = File(initial);
      if (await file.exists()) {
        await _openFile(file);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshList() async {
    final dir = await WebOSPaths.notesDir();
    final files = <File>[];
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.txt')) {
          files.add(entity);
        }
      }
    }
    files.sort((a, b) {
      final aName = a.path.split(Platform.pathSeparator).last;
      final bName = b.path.split(Platform.pathSeparator).last;
      return bName.compareTo(aName);
    });
    if (mounted) setState(() => _notes = files);
  }

  Future<void> _openFile(File file) async {
    if (_dirty && _current != null) {
      final save = await _confirmDiscard();
      if (save == true) {
        await _save();
      } else if (save == null) {
        return; // 取消切换
      }
    }
    final content = await file.readAsString();
    setState(() {
      _current = file;
      _controller.text = content;
      _dirty = false;
    });
  }

  /// 返回 true=保存后继续，false=不保存继续，null=取消。
  Future<bool?> _confirmDiscard() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未保存的更改'),
        content: const Text('当前笔记有未保存的更改，要保存吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _newNote() async {
    if (_dirty && _current != null) {
      final save = await _confirmDiscard();
      if (save == true) {
        await _save();
      } else if (save == null) {
        return;
      }
    }
    final dir = await WebOSPaths.notesDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(
      '${dir.path}${Platform.pathSeparator}note-$stamp.txt',
    );
    await file.writeAsString('');
    await _refreshList();
    setState(() {
      _current = file;
      _controller.text = '';
      _dirty = false;
    });
  }

  Future<void> _save() async {
    final file = _current;
    if (file == null) return;
    await file.writeAsString(_controller.text);
    await _refreshList();
    if (mounted) {
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
    }
  }

  Future<void> _deleteCurrent() async {
    final file = _current;
    if (file == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除笔记'),
        content: Text('确定删除 ${_noteTitle(file)} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await file.delete();
    await _refreshList();
    setState(() {
      _current = null;
      _controller.text = '';
      _dirty = false;
    });
  }

  String _noteTitle(File file) {
    final name = file.path.split(Platform.pathSeparator).last;
    return name.replaceAll(RegExp(r'\.txt$'), '');
  }

  String _notePreview(File file) {
    return _noteTitle(file);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_current == null) {
      return _buildList();
    }
    return _buildEditor();
  }

  Widget _buildList() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Text(
                '我的笔记',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _newNote,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _notes.isEmpty
              ? const Center(child: Text('还没有笔记，点右上角新建一篇'))
              : ListView.builder(
                  itemCount: _notes.length,
                  itemBuilder: (context, index) {
                    final file = _notes[index];
                    return ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(_notePreview(file)),
                      onTap: () => _openFile(file),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('删除笔记'),
                              content: Text('确定删除 ${_noteTitle(file)} 吗？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('删除'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await file.delete();
                            await _refreshList();
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEditor() {
    final file = _current!;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回列表',
                onPressed: () async {
                  if (_dirty) {
                    final save = await _confirmDiscard();
                    if (save == true) {
                      await _save();
                    } else if (save == null) {
                      return;
                    }
                  }
                  setState(() {
                    _current = null;
                    _controller.text = '';
                    _dirty = false;
                  });
                },
              ),
              Expanded(
                child: Text(
                  _noteTitle(file) + (_dirty ? ' *' : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除',
                onPressed: _deleteCurrent,
              ),
              FilledButton(
                onPressed: _dirty ? _save : null,
                child: const Text('保存'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '在这里输入…',
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}
