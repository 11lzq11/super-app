import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_registry.dart';
import '../app_store.dart';

/// 应用市场：安装内置示例应用，从文件导入 .html / .webos，卸载已安装应用。
class StoreApp extends StatefulWidget {
  const StoreApp({super.key});

  @override
  State<StoreApp> createState() => _StoreAppState();
}

class _StoreAppState extends State<StoreApp> {
  List<WebOSApp> _installed = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final apps = await WebOSAppRegistry.installedHtmlApps();
    if (mounted) setState(() => _installed = apps);
  }

  bool _isInstalled(String id) {
    return _installed.any((a) => a.id == id);
  }

  Future<void> _installTemplate(HtmlAppTemplate template) async {
    setState(() => _busy = true);
    try {
      await AppStoreService.installTemplate(template);
      await _refresh();
      _showMessage('已安装 ${template.name}');
    } catch (e) {
      _showMessage('安装失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importHtml() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['html', 'htm'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    String? html;
    if (picked.bytes != null) {
      html = utf8.decode(picked.bytes!);
    } else if (picked.path != null) {
      html = await File(picked.path!).readAsString();
    }
    if (html == null || html.trim().isEmpty) {
      _showMessage('读取文件失败');
      return;
    }
    final name = picked.name.replaceAll(RegExp(r'\.(html|htm)$'), '');
    setState(() => _busy = true);
    try {
      final id = await AppStoreService.installHtmlFile(
        name: name.isEmpty ? '未命名应用' : name,
        html: html,
      );
      await _refresh();
      _showMessage('已安装 $name（id: $id）');
    } catch (e) {
      _showMessage('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importWebos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['webos'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    File? file;
    if (picked.path != null) {
      file = File(picked.path!);
    } else if (picked.bytes != null) {
      final temp = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}${picked.name}',
      );
      await temp.writeAsBytes(picked.bytes!);
      file = temp;
    }
    if (file == null) {
      _showMessage('读取文件失败');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await AppStoreService.importWebosPackage(file);
      await _refresh();
      _showMessage('已安装（id: $id）');
    } catch (e) {
      _showMessage('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uninstall(WebOSApp app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卸载应用'),
        content: Text('确定卸载「${app.name}」吗？应用文件将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AppStoreService.uninstall(app.id);
    await _refresh();
    _showMessage('已卸载 ${app.name}');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '应用市场',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          '示例应用一键安装；也可以从文件导入自己或他人制作的 .html / .webos 应用。',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        const Text(
          '精选',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final template in SampleHtmlApps.templates)
          _buildTemplateCard(template),
        const SizedBox(height: 20),
        const Text(
          '从文件导入',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _importHtml,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('导入 .html'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _importWebos,
                icon: const Icon(Icons.archive_outlined, size: 18),
                label: const Text('导入 .webos'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          '已安装',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (_installed.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('还没有安装任何 HTML 应用。'),
          )
        else
          for (final app in _installed)
            ListTile(
              leading: Icon(app.icon),
              title: Text(app.name),
              subtitle: Text(
                [if (app.version != null) 'v${app.version}']
                    .join(' · '),
              ),
              trailing: TextButton(
                onPressed: () => _uninstall(app),
                child: const Text('卸载'),
              ),
              contentPadding: EdgeInsets.zero,
            ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildTemplateCard(HtmlAppTemplate template) {
    final installed = _isInstalled(template.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(template.icon, size: 20),
        ),
        title: Text(template.name),
        subtitle: Text(template.description),
        trailing: installed
            ? const Text('已安装', style: TextStyle(color: Colors.green))
            : FilledButton(
                onPressed: _busy ? null : () => _installTemplate(template),
                child: const Text('安装'),
              ),
      ),
    );
  }
}
