import 'package:flutter/material.dart';

import 'app_store.dart';

/// 应用工坊 starter 模板：含 WebOS JS API 调用示例。
const String _workshopTemplate = r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>我的应用</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #f8fafc; color: #0f172a; padding: 24px; }
  h1 { font-size: 22px; margin-bottom: 8px; }
  p { color: #64748b; margin-bottom: 20px; }
  button { background: #0f172a; color: #fff; border: none; border-radius: 8px;
    padding: 10px 16px; font-size: 15px; cursor: pointer; margin-right: 8px; }
  #out { margin-top: 20px; background: #fff; border: 1px solid #e2e8f0;
    border-radius: 10px; padding: 14px; min-height: 60px; white-space: pre-wrap; }
</style>
</head>
<body>
  <h1>你好，WebOS！</h1>
  <p>这是应用工坊生成的模板，改一改就能变成你自己的应用。</p>
  <button onclick="WebOS.launchApp('calculator')">打开计算器</button>
  <button onclick="showFiles()">列出 WebOS 文件</button>
  <button onclick="WebOS.sendMessage('todo', { text: '来自我的应用的待办' })">发给待办</button>
  <div id="out">点上面的按钮试试应用互联。</div>
<script>
  // WebOS.getFileList 返回 Promise，resolve 一个 { ok, list } 对象
  function showFiles() {
    WebOS.getFileList('').then(function (res) {
      var out = document.getElementById('out');
      if (!res || !res.ok) { out.textContent = '读取失败：' + (res && res.error); return; }
      out.textContent = 'WebOS 文件：\n' + res.list.map(function (f) {
        return (f.isDir ? '[目录] ' : '[文件] ') + f.name;
      }).join('\n');
    });
  }
  // 接收其他应用的消息
  window.addEventListener('webos-message', function (e) {
    document.getElementById('out').textContent =
      '收到消息：' + JSON.stringify(e.detail);
  });
</script>
</body>
</html>''';

/// 应用工坊：内置简易代码编辑器 + WebOS JS API 文档，写完即可安装运行。
class WorkshopApp extends StatefulWidget {
  /// 安装成功后启动新应用的回调（由 WebOSPage 传入）。
  final void Function(String appId)? onLaunchApp;

  const WorkshopApp({super.key, this.onLaunchApp});

  @override
  State<WorkshopApp> createState() => _WorkshopAppState();
}

class _WorkshopAppState extends State<WorkshopApp> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController =
      TextEditingController(text: _workshopTemplate);
  bool _showDocs = false;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    final name = _nameController.text.trim();
    final code = _codeController.text;
    if (name.isEmpty) {
      _showMessage('请先填写应用名称');
      return;
    }
    if (code.trim().isEmpty) {
      _showMessage('代码不能为空');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await AppStoreService.installHtmlFile(name: name, html: code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已安装 $name')),
      );
      widget.onLaunchApp?.call(id);
    } catch (e) {
      _showMessage('安装失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _loadTemplate() {
    setState(() {
      _codeController.text = _workshopTemplate;
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = '我的应用';
      }
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '应用名称',
                    hintText: '例如：我的应用',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _loadTemplate,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('载入模板'),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _showDocs = !_showDocs),
                icon: Icon(
                  _showDocs ? Icons.menu_book : Icons.menu_book_outlined,
                  size: 18,
                ),
                label: const Text('API 文档'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _busy ? null : _install,
                child: const Text('安装并运行'),
              ),
            ],
          ),
        ),
        if (_showDocs) _buildDocs(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _codeController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                hintText: '在这里写 HTML（含内联 CSS / JS）…',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }

  Widget _buildDocs() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const SingleChildScrollView(
        child: Text(
          'WebOS JS API\n\n'
          '在 HTML 应用里可直接使用 window.WebOS：\n\n'
          '• WebOS.launchApp(appId, params?)\n'
          '  启动另一个 WebOS 应用。例：WebOS.launchApp(\'calculator\')\n\n'
          '• WebOS.openFile(path)\n'
          '  打开一个文件（文本进记事本，.html 提示安装）。\n'
          '  例：WebOS.openFile(\'/sdcard/Download/a.txt\')\n'
          '  （真实路径需要 Super MAX）\n\n'
          '• WebOS.sendMessage(target, data)\n'
          '  给另一个应用发消息。对方用下面方式接收：\n'
          '  window.addEventListener(\'webos-message\', e => {\n'
          '    console.log(e.detail.from, e.detail.data);\n'
          '  });\n\n'
          '• WebOS.getFileList(dir) → Promise<{ ok, list }>\n'
          '  列出目录内容（空字符串表示 WebOS 根目录）。\n'
          '  list 每项：{ name, path, isDir }。\n'
          '  例：WebOS.getFileList(\'\').then(res => console.log(res.list));\n\n'
          '• URL Scheme：在应用内放链接\n'
          '  <a href="webos://launch?app=notes">打开记事本</a>',
          style: TextStyle(fontFamily: 'monospace', fontSize: 12.5),
        ),
      ),
    );
  }
}
