import 'dart:io';

import 'package:flutter/material.dart';

import '../supermax_bridge.dart';
import '../webos_paths.dart';

/// 文件管理器：浏览 webos/ 沙盒文件；
/// Super MAX 开启时可浏览真实文件系统（默认 /sdcard），写操作需二次确认。
class FilesApp extends StatefulWidget {
  /// 点开文件时的回调（由 WebOSPage 传入：文本进记事本，.html 提示安装）。
  final void Function(String path)? onOpenFile;

  const FilesApp({super.key, this.onOpenFile});

  @override
  State<FilesApp> createState() => _FilesAppState();
}

class _FilesAppState extends State<FilesApp> {
  String _currentPath = '';
  List<WebOSFileEntry> _entries = [];
  bool _loading = true;
  String? _error;
  bool _supermax = false;
  bool _rootMode = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _supermax = await SuperMaxBridge.isEnabled();
    final root = await WebOSPaths.root();
    if (mounted) {
      setState(() => _currentPath = root.path);
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await WebOSPaths.listDirectory(_currentPath);
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _navigate(String path) {
    setState(() => _currentPath = path);
    _load();
  }

  void _goUp() {
    final parent = Directory(_currentPath).parent.path;
    if (parent == _currentPath) return;
    _navigate(parent);
  }

  /// 进入系统根目录模式（仅 Super MAX）。
  Future<void> _enterRootMode() async {
    if (!_supermax) {
      _showMessage('需要开启 Super MAX 才能浏览真实文件系统');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('浏览真实文件系统'),
        content: const Text(
          'Super MAX 模式下可以浏览 /sdcard 等真实目录。\n删除、重命名等写操作仍会每次单独确认。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('进入'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _rootMode = true);
    _navigate('/sdcard');
  }

  void _exitRootMode() async {
    final root = await WebOSPaths.root();
    setState(() => _rootMode = false);
    _navigate(root.path);
  }

  Future<void> _createFolder() async {
    final name = await _askText('新建文件夹', '文件夹名');
    if (name == null || name.trim().isEmpty) return;
    if (name.contains('/') || name.contains('\\')) {
      _showMessage('文件夹名不能包含 / 或 \\');
      return;
    }
    try {
      if (_rootMode) {
        final result = await SuperMaxBridge.runAsRoot(
          'mkdir -p ${WebOSPaths.shellEscape('$_currentPath/$name')}',
        );
        if (!result.ok) throw StateError(result.output);
      } else {
        await Directory('$_currentPath/$name').create();
      }
      await _load();
    } catch (e) {
      _showMessage('创建失败：$e');
    }
  }

  Future<void> _rename(WebOSFileEntry entry) async {
    final name = await _askText('重命名', '新名称', initial: entry.name);
    if (name == null || name.trim().isEmpty || name == entry.name) return;
    // root 模式下重命名真实文件需要二次确认
    if (_rootMode) {
      final ok = await _confirm('重命名', '把 ${entry.name} 改名为 $name？');
      if (ok != true) return;
    }
    try {
      final target = '$_currentPath/$name';
      if (_rootMode) {
        final result = await SuperMaxBridge.runAsRoot(
          'mv ${WebOSPaths.shellEscape(entry.path)} ${WebOSPaths.shellEscape(target)}',
        );
        if (!result.ok) throw StateError(result.output);
      } else {
        if (entry.isDir) {
          await Directory(entry.path).rename(target);
        } else {
          await File(entry.path).rename(target);
        }
      }
      await _load();
    } catch (e) {
      _showMessage('重命名失败：$e');
    }
  }

  Future<void> _delete(WebOSFileEntry entry) async {
    final ok = await _confirm(
      '删除',
      _rootMode
          ? '确定删除 ${entry.name} 吗？\n（真实文件系统，删除后无法恢复）'
          : '确定删除 ${entry.name} 吗？',
    );
    if (ok != true) return;
    try {
      if (_rootMode) {
        final result = await SuperMaxBridge.runAsRoot(
          'rm -rf ${WebOSPaths.shellEscape(entry.path)}',
        );
        if (!result.ok) throw StateError(result.output);
      } else {
        if (entry.isDir) {
          await Directory(entry.path).delete(recursive: true);
        } else {
          await File(entry.path).delete();
        }
      }
      await _load();
    } catch (e) {
      _showMessage('删除失败：$e');
    }
  }

  Future<String?> _askText(String title, String label, {String? initial}) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirm(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<String> get _breadcrumbs {
    final parts = _currentPath.split(Platform.pathSeparator)
      ..removeWhere((p) => p.isEmpty);
    return parts;
  }

  String _breadcrumbPath(int index) {
    final parts = _breadcrumbs.sublist(0, index + 1);
    if (_currentPath.startsWith('/')) {
      return '/${parts.join('/')}';
    }
    return parts.join(Platform.pathSeparator);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        _buildBreadcrumbs(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '上一级',
            onPressed: _goUp,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _load,
          ),
          const Spacer(),
          if (_rootMode)
            FilledButton.tonalIcon(
              onPressed: _exitRootMode,
              icon: const Icon(Icons.home_outlined, size: 18),
              label: const Text('回 WebOS'),
            )
          else if (_supermax)
            FilledButton.tonalIcon(
              onPressed: _enterRootMode,
              icon: const Icon(Icons.sd_storage_outlined, size: 18),
              label: const Text('系统目录'),
            ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: '新建文件夹',
            onPressed: _createFolder,
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    final crumbs = _breadcrumbs;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < crumbs.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Text('/', style: TextStyle(color: Colors.grey)),
                ),
              InkWell(
                onTap: () => _navigate(_breadcrumbPath(i)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Text(
                    crumbs[i],
                    style: TextStyle(
                      color: i == crumbs.length - 1
                          ? Colors.black87
                          : Colors.blueGrey,
                      fontWeight: i == crumbs.length - 1
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off_outlined, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('空文件夹'));
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return ListTile(
          leading: Icon(
            entry.isDir ? Icons.folder : _iconForFile(entry.name),
            color: entry.isDir ? Colors.amber[700] : Colors.blueGrey,
          ),
          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () {
            if (entry.isDir) {
              _navigate(entry.path);
            } else if (widget.onOpenFile != null) {
              widget.onOpenFile!(entry.path);
            }
          },
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') _rename(entry);
              if (value == 'delete') _delete(entry);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('重命名')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        );
      },
    );
  }

  IconData _iconForFile(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return Icons.language_outlined;
    }
    if (lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.json')) {
      return Icons.description_outlined;
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    if (lower.endsWith('.zip') || lower.endsWith('.webos')) {
      return Icons.archive_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }
}
