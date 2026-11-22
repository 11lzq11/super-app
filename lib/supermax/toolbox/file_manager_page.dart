import 'package:flutter/material.dart';

import '../root_shell.dart';
import '../supermax_service.dart';
import '../toolbox_commands.dart';

/// Root 文件管理：从 / 开始浏览，可进目录、预览文本文件、删除文件或目录。
///
/// 加载用 lsCommand + parseLsLa（解析器已把目录排在前面）；
/// 文本文件用 catCommand 查看（超过 64KB 截断并提示）；
/// 删除用 rmCommand，高危命令走 showRootCommandConfirmDialog 红色确认。
class RootFileManagerPage extends StatefulWidget {
  final SuperMaxService service;

  const RootFileManagerPage({super.key, required this.service});

  @override
  State<RootFileManagerPage> createState() => _RootFileManagerPageState();
}

class _RootFileManagerPageState extends State<RootFileManagerPage> {
  String _currentPath = '/';
  List<RootFileEntry> _entries = [];
  bool _loading = true;
  String? _error;
  String _busyPath = '';

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  String _join(String dir, String name) =>
      dir == '/' ? '/$name' : '$dir/$name';

  String? _parentPath(String path) {
    if (path == '/') return null;
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return '/';
    return path.substring(0, idx);
  }

  /// 面包屑的每一段：第一段是根目录，后面每段对应一级路径。
  List<String> _pathSegments(String path) {
    if (path == '/') return ['/'];
    return ['/', ...path.split('/').where((s) => s.isNotEmpty)];
  }

  String _pathUpTo(int segmentIndex) {
    if (segmentIndex == 0) return '/';
    final parts = _currentPath.split('/').where((s) => s.isNotEmpty).toList();
    return '/${parts.sublist(0, segmentIndex).join('/')}';
  }

  Future<void> _loadDirectory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.service.runRootCommand(
      lsCommand(_currentPath),
    );
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _loading = false;
        _error = 'Super MAX 未开启';
      });
      return;
    }
    if (!result.success) {
      setState(() {
        _loading = false;
        _error =
            '读取目录失败：${result.stderr.trim().isEmpty ? '退出码 ${result.exitCode}' : result.stderr.trim()}';
      });
      return;
    }
    setState(() {
      _entries = parseLsLa(result.stdout);
      _loading = false;
    });
  }

  void _navigateTo(String path) {
    if (path == _currentPath) return;
    setState(() => _currentPath = path);
    _loadDirectory();
  }

  Future<void> _previewFile(RootFileEntry entry) async {
    final path = _join(_currentPath, entry.name);
    final result = await widget.service.runRootCommand(catCommand(path));
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Super MAX 未开启')));
      return;
    }
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '读取文件失败：${result.stderr.trim().isEmpty ? '退出码 ${result.exitCode}' : result.stderr.trim()}',
          ),
        ),
      );
      return;
    }
    final content = result.stdout;
    final truncated = content.length >= 65536;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(entry.name),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (truncated)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '文件超过 64KB，只显示前 64KB 内容。',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      dialogContext,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      content.isEmpty ? '（空文件）' : content,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry(RootFileEntry entry) async {
    final path = _join(_currentPath, entry.name);
    final command = rmCommand(path, isDirectory: entry.isDirectory);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: entry.isDirectory ? Colors.red : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(entry.isDirectory ? '删除目录？' : '删除文件？'),
          ],
        ),
        content: Text(
          entry.isDirectory
              ? '将递归删除目录 $path 及其全部内容，此操作不可恢复。'
              : '将删除文件 $path，此操作不可恢复。',
          style: entry.isDirectory
              ? const TextStyle(color: Colors.red)
              : null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: entry.isDirectory
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 高危命令走红色高危确认。
    if (RootShell.isDangerous(command.command)) {
      final dangerousConfirmed = await showRootCommandConfirmDialog(
        context,
        command.command,
        dangerous: true,
      );
      if (!dangerousConfirmed || !mounted) return;
    }

    setState(() => _busyPath = path);
    final result = await widget.service.runRootCommand(command.command);
    if (!mounted) return;
    setState(() => _busyPath = '');
    if (result == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Super MAX 未开启')));
      return;
    }
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '删除失败：${result.stderr.trim().isEmpty ? '退出码 ${result.exitCode}' : result.stderr.trim()}',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已删除 ${entry.name}')));
    _loadDirectory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Root 文件管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
            onPressed: _loading ? null : _loadDirectory,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBreadcrumb(),
          _buildQuickPaths(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final segments = _pathSegments(_currentPath);
    final parent = _parentPath(_currentPath);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          if (parent != null)
            IconButton(
              icon: const Icon(Icons.arrow_upward_rounded),
              tooltip: '返回上级',
              onPressed: () => _navigateTo(parent),
            ),
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const Text(' / ', style: TextStyle(color: Colors.grey)),
            InkWell(
              onTap: () => _navigateTo(_pathUpTo(i)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 4,
                ),
                child: Text(
                  segments[i],
                  style: TextStyle(
                    fontWeight: i == segments.length - 1
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickPaths() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          for (final path in rootQuickPaths)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(path),
                onPressed: () => _navigateTo(path),
              ),
            ),
        ],
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
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadDirectory,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('该目录为空'));
    }
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final path = _join(_currentPath, entry.name);
        final busy = _busyPath == path;
        final subtitle = entry.isDirectory
            ? entry.permissions
            : '${entry.sizeLabel} · ${entry.permissions}';
        return ListTile(
          leading: Icon(
            entry.isDirectory
                ? Icons.folder_rounded
                : Icons.insert_drive_file_rounded,
            color: entry.isDirectory ? Colors.amber : null,
          ),
          title: Text(
            entry.linkTarget != null
                ? '${entry.name} -> ${entry.linkTarget}'
                : entry.name,
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: '删除',
                  onPressed: () => _deleteEntry(entry),
                ),
          onTap: () {
            if (entry.isDirectory) {
              _navigateTo(path);
            } else if (isTextFile(entry.name)) {
              _previewFile(entry);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('二进制文件，无法预览')),
              );
            }
          },
        );
      },
    );
  }
}
