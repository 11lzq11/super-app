import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

import 'app_registry.dart';
import 'webos_paths.dart';

/// 一个内置示例 HTML 应用的模板（单文件 HTML 字符串）。
class HtmlAppTemplate {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final String version;
  final String html;

  const HtmlAppTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.version = '1.0.0',
    required this.html,
  });
}

/// 内置示例应用：时钟、待办、画板、便签。
/// 每个都是完整的单文件 HTML，首次进入 WebOS 时自动安装。
class SampleHtmlApps {
  SampleHtmlApps._();

  static const List<HtmlAppTemplate> templates = [
    HtmlAppTemplate(
      id: 'clock',
      name: '时钟',
      description: '实时时钟与日期，可一键启动其他应用。',
      icon: Icons.access_time_outlined,
      html: r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>时钟</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #0f172a; color: #f1f5f9;
    min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center; }
  .time { font-size: 72px; font-weight: 200; letter-spacing: 2px; font-variant-numeric: tabular-nums; }
  .date { font-size: 18px; color: #94a3b8; margin-top: 8px; }
  .row { display: flex; gap: 12px; margin-top: 36px; }
  button { background: #334155; color: #f1f5f9; border: none; border-radius: 10px;
    padding: 10px 18px; font-size: 15px; cursor: pointer; }
  button:hover { background: #475569; }
</style>
</head>
<body>
  <div class="time" id="time">--:--:--</div>
  <div class="date" id="date"></div>
  <div class="row">
    <button onclick="WebOS && WebOS.launchApp('calculator')">打开计算器</button>
    <button onclick="WebOS && WebOS.launchApp('files')">打开文件管理器</button>
  </div>
<script>
  var weeks = ['星期日','星期一','星期二','星期三','星期四','星期五','星期六'];
  function tick() {
    var d = new Date();
    function p(n) { return (n < 10 ? '0' : '') + n; }
    document.getElementById('time').textContent = p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
    document.getElementById('date').textContent = d.getFullYear() + '年' + (d.getMonth() + 1) + '月' + d.getDate() + '日 ' + weeks[d.getDay()];
  }
  tick();
  setInterval(tick, 1000);
</script>
</body>
</html>''',
    ),
    HtmlAppTemplate(
      id: 'todo',
      name: '待办',
      description: '待办清单，保存在本应用内；可接收其他应用发来的消息。',
      icon: Icons.checklist_outlined,
      html: r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>待办</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #f8fafc; color: #0f172a; padding: 20px; }
  h1 { font-size: 20px; margin-bottom: 16px; }
  .add { display: flex; gap: 8px; margin-bottom: 16px; }
  input { flex: 1; border: 1px solid #cbd5e1; border-radius: 8px; padding: 10px 12px; font-size: 15px; outline: none; }
  input:focus { border-color: #334155; }
  button { background: #0f172a; color: #fff; border: none; border-radius: 8px; padding: 10px 16px; font-size: 15px; cursor: pointer; }
  .item { display: flex; align-items: center; gap: 10px; background: #fff; border: 1px solid #e2e8f0;
    border-radius: 10px; padding: 12px; margin-bottom: 8px; }
  .item.done span { text-decoration: line-through; color: #94a3b8; }
  .item span { flex: 1; font-size: 15px; }
  .item .del { background: none; color: #dc2626; padding: 4px 8px; }
  .hint { color: #64748b; font-size: 13px; margin-top: 16px; }
</style>
</head>
<body>
  <h1>待办清单</h1>
  <div class="add">
    <input id="input" placeholder="输入一件要做的事…" onkeydown="if(event.key==='Enter')addTodo()">
    <button onclick="addTodo()">添加</button>
  </div>
  <div id="list"></div>
  <p class="hint">提示：画板应用可以把灵感直接发到这里（应用间消息）。</p>
<script>
  var KEY = 'webos-todo-list';
  var todos = [];
  try { todos = JSON.parse(localStorage.getItem(KEY) || '[]'); } catch (e) { todos = []; }
  function save() { localStorage.setItem(KEY, JSON.stringify(todos)); }
  function render() {
    var list = document.getElementById('list');
    list.innerHTML = '';
    todos.forEach(function (t, i) {
      var div = document.createElement('div');
      div.className = 'item' + (t.done ? ' done' : '');
      var box = document.createElement('input');
      box.type = 'checkbox'; box.checked = !!t.done;
      box.onchange = function () { todos[i].done = box.checked; save(); render(); };
      var span = document.createElement('span');
      span.textContent = t.text;
      var del = document.createElement('button');
      del.className = 'del'; del.textContent = '删除';
      del.onclick = function () { todos.splice(i, 1); save(); render(); };
      div.appendChild(box); div.appendChild(span); div.appendChild(del);
      list.appendChild(div);
    });
  }
  function addTodo(text) {
    var input = document.getElementById('input');
    var value = (text || input.value || '').trim();
    if (!value) return;
    todos.push({ text: value, done: false });
    input.value = '';
    save(); render();
  }
  // 接收其他应用的消息：data.text 会被加为一条待办
  window.addEventListener('webos-message', function (e) {
    var data = (e.detail && e.detail.data) || {};
    if (data.text) { addTodo(data.text); }
  });
  render();
</script>
</body>
</html>''',
    ),
    HtmlAppTemplate(
      id: 'draw',
      name: '画板',
      description: '随手涂鸦，可调颜色与粗细，能把灵感发给待办。',
      icon: Icons.brush_outlined,
      html: r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>画板</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #f8fafc; color: #0f172a;
    display: flex; flex-direction: column; height: 100vh; }
  .bar { display: flex; align-items: center; gap: 10px; padding: 12px 16px;
    background: #fff; border-bottom: 1px solid #e2e8f0; flex-wrap: wrap; }
  .bar h1 { font-size: 18px; margin-right: 8px; }
  .swatch { width: 28px; height: 28px; border-radius: 50%; border: 2px solid transparent; cursor: pointer; }
  .swatch.on { border-color: #0f172a; }
  button { background: #0f172a; color: #fff; border: none; border-radius: 8px; padding: 8px 14px; font-size: 14px; cursor: pointer; }
  button.ghost { background: #e2e8f0; color: #0f172a; }
  canvas { flex: 1; background: #fff; touch-action: none; cursor: crosshair; }
</style>
</head>
<body>
  <div class="bar">
    <h1>画板</h1>
    <div class="swatch on" data-c="#0f172a" style="background:#0f172a"></div>
    <div class="swatch" data-c="#dc2626" style="background:#dc2626"></div>
    <div class="swatch" data-c="#2563eb" style="background:#2563eb"></div>
    <div class="swatch" data-c="#16a34a" style="background:#16a34a"></div>
    <div class="swatch" data-c="#d97706" style="background:#d97706"></div>
    <button class="ghost" onclick="clearCanvas()">清空</button>
    <button onclick="sendIdea()">发灵感给待办</button>
  </div>
  <canvas id="cv"></canvas>
<script>
  var cv = document.getElementById('cv');
  var ctx = cv.getContext('2d');
  var color = '#0f172a';
  var drawing = false, last = null;
  function resize() {
    var img = ctx.getImageData(0, 0, cv.width, cv.height);
    cv.width = cv.clientWidth; cv.height = cv.clientHeight;
    ctx.putImageData(img, 0, 0);
  }
  window.addEventListener('resize', resize);
  resize();
  document.querySelectorAll('.swatch').forEach(function (s) {
    s.onclick = function () {
      color = s.getAttribute('data-c');
      document.querySelectorAll('.swatch').forEach(function (x) { x.classList.remove('on'); });
      s.classList.add('on');
    };
  });
  function pos(e) {
    var r = cv.getBoundingClientRect();
    var t = e.touches ? e.touches[0] : e;
    return { x: t.clientX - r.left, y: t.clientY - r.top };
  }
  function start(e) { drawing = true; last = pos(e); e.preventDefault(); }
  function move(e) {
    if (!drawing) return;
    var p = pos(e);
    ctx.strokeStyle = color; ctx.lineWidth = 4; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(last.x, last.y); ctx.lineTo(p.x, p.y); ctx.stroke();
    last = p; e.preventDefault();
  }
  function end() { drawing = false; }
  cv.addEventListener('mousedown', start);
  cv.addEventListener('mousemove', move);
  cv.addEventListener('mouseup', end);
  cv.addEventListener('mouseleave', end);
  cv.addEventListener('touchstart', start, { passive: false });
  cv.addEventListener('touchmove', move, { passive: false });
  cv.addEventListener('touchend', end);
  function clearCanvas() { ctx.clearRect(0, 0, cv.width, cv.height); }
  // 应用互联示例：给待办应用发一条消息
  function sendIdea() {
    if (window.WebOS) {
      window.WebOS.sendMessage('todo', { text: '来自画板的灵感：' + new Date().toLocaleTimeString() });
      alert('已发送到待办');
    }
  }
</script>
</body>
</html>''',
    ),
    HtmlAppTemplate(
      id: 'memo',
      name: '便签',
      description: '彩色便签墙，随手记，随手贴。',
      icon: Icons.sticky_note_2_outlined,
      html: r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>便签</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #f8fafc; color: #0f172a; padding: 20px; }
  h1 { font-size: 20px; margin-bottom: 16px; }
  .add { display: flex; gap: 8px; margin-bottom: 16px; }
  input { flex: 1; border: 1px solid #cbd5e1; border-radius: 8px; padding: 10px 12px; font-size: 15px; outline: none; }
  button { background: #0f172a; color: #fff; border: none; border-radius: 8px; padding: 10px 16px; font-size: 15px; cursor: pointer; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 12px; }
  .note { border-radius: 10px; padding: 14px; min-height: 110px; position: relative;
    font-size: 15px; line-height: 1.5; white-space: pre-wrap; word-break: break-all; }
  .note .del { position: absolute; right: 6px; top: 6px; background: rgba(255,255,255,.7);
    color: #0f172a; border-radius: 6px; padding: 2px 8px; font-size: 12px; }
  .c0 { background: #fef9c3; } .c1 { background: #dcfce7; } .c2 { background: #dbeafe; } .c3 { background: #fce7f3; }
</style>
</head>
<body>
  <h1>便签</h1>
  <div class="add">
    <input id="input" placeholder="写一条便签…" onkeydown="if(event.key==='Enter')addNote()">
    <button onclick="addNote()">贴上</button>
  </div>
  <div class="grid" id="grid"></div>
<script>
  var KEY = 'webos-memo-list';
  var notes = [];
  try { notes = JSON.parse(localStorage.getItem(KEY) || '[]'); } catch (e) { notes = []; }
  function save() { localStorage.setItem(KEY, JSON.stringify(notes)); }
  function render() {
    var grid = document.getElementById('grid');
    grid.innerHTML = '';
    notes.forEach(function (n, i) {
      var div = document.createElement('div');
      div.className = 'note c' + (n.c || 0);
      div.textContent = n.text;
      var del = document.createElement('button');
      del.className = 'del'; del.textContent = '×';
      del.onclick = function () { notes.splice(i, 1); save(); render(); };
      div.appendChild(del);
      grid.appendChild(div);
    });
  }
  function addNote() {
    var input = document.getElementById('input');
    var value = (input.value || '').trim();
    if (!value) return;
    notes.push({ text: value, c: notes.length % 4 });
    input.value = '';
    save(); render();
  }
  render();
</script>
</body>
</html>''',
    ),
  ];
}

/// 应用市场服务：示例应用安装、.html / .webos 导入、卸载。
class AppStoreService {
  AppStoreService._();

  /// 首次进入 WebOS 时调用：把缺失的示例应用装好。
  static Future<void> ensureSamplesInstalled() async {
    for (final template in SampleHtmlApps.templates) {
      final dir = Directory(
        '${(await WebOSPaths.appsDir()).path}${Platform.pathSeparator}${template.id}',
      );
      final index = File('${dir.path}${Platform.pathSeparator}index.html');
      if (!await index.exists()) {
        await installTemplate(template);
      }
    }
  }

  /// 安装一个内置示例应用。
  static Future<void> installTemplate(HtmlAppTemplate template) async {
    final dir = Directory(
      '${(await WebOSPaths.appsDir()).path}${Platform.pathSeparator}${template.id}',
    );
    await dir.create(recursive: true);
    await File('${dir.path}${Platform.pathSeparator}index.html')
        .writeAsString(template.html);
    await File('${dir.path}${Platform.pathSeparator}manifest.json')
        .writeAsString(jsonEncode({
      'name': template.name,
      'version': template.version,
      'entry': 'index.html',
      'description': template.description,
    }));
    notifyWebOSAppsChanged();
  }

  /// 从一个单文件 HTML 安装应用。
  static Future<String> installHtmlFile({
    required String name,
    required String html,
  }) async {
    final id = await _uniqueId(_slugify(name));
    final dir = Directory(
      '${(await WebOSPaths.appsDir()).path}${Platform.pathSeparator}$id',
    );
    await dir.create(recursive: true);
    await File('${dir.path}${Platform.pathSeparator}index.html')
        .writeAsString(html);
    await File('${dir.path}${Platform.pathSeparator}manifest.json')
        .writeAsString(jsonEncode({
      'name': name,
      'version': '1.0.0',
      'entry': 'index.html',
    }));
    notifyWebOSAppsChanged();
    return id;
  }

  /// 从 .webos 包（zip，内含 manifest.json）安装应用。
  /// 返回安装后的应用 id；manifest 缺失或损坏时抛错。
  static Future<String> importWebosPackage(File packageFile) async {
    final bytes = await packageFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    Map<String, dynamic>? manifest;
    for (final file in archive.files) {
      if (file.isFile && file.name == 'manifest.json') {
        manifest = jsonDecode(utf8.decode(file.content as List<int>))
            as Map<String, dynamic>;
        break;
      }
    }
    if (manifest == null) {
      throw StateError('不是有效的 .webos 包：缺少 manifest.json');
    }
    final name = (manifest['name'] as String?)?.trim().isNotEmpty == true
        ? manifest['name'] as String
        : '未命名应用';
    final id = await _uniqueId(_slugify(name));
    final target = Directory(
      '${(await WebOSPaths.appsDir()).path}${Platform.pathSeparator}$id',
    );
    await target.create(recursive: true);
    var hasEntry = false;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      // 防目录穿越：只允许包内相对路径
      if (file.name.startsWith('/') || file.name.split('/').contains('..')) {
        continue;
      }
      final bytes = file.content as List<int>;
      final out = File('${target.path}${Platform.pathSeparator}${file.name}');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes);
      if (file.name == 'index.html' ||
          file.name == (manifest['entry'] as String? ?? 'index.html')) {
        hasEntry = true;
      }
    }
    if (!hasEntry) {
      await target.delete(recursive: true);
      throw StateError('不是有效的 .webos 包：缺少入口文件 index.html');
    }
    // 补写/规范化 manifest
    await File('${target.path}${Platform.pathSeparator}manifest.json')
        .writeAsString(jsonEncode({
      'name': name,
      'version': manifest['version'] as String? ?? '1.0.0',
      'entry': manifest['entry'] as String? ?? 'index.html',
      'description': manifest['description'] as String?,
    }));
    notifyWebOSAppsChanged();
    return id;
  }

  /// 卸载一个已安装的 HTML 应用。
  static Future<void> uninstall(String appId) async {
    final dir = Directory(
      '${(await WebOSPaths.appsDir()).path}${Platform.pathSeparator}$appId',
    );
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    notifyWebOSAppsChanged();
  }

  /// 某个应用是否已安装。
  static Future<bool> isInstalled(String appId) async {
    final index = File(
      '${(await WebOSPaths.appsDir()).path}${Platform.pathSeparator}$appId${Platform.pathSeparator}index.html',
    );
    return index.exists();
  }

  /// 名字转 id：中文名用时间戳 id，英文名转 slug，并保证唯一。
  static String _slugify(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) {
      return 'app-${DateTime.now().millisecondsSinceEpoch}';
    }
    return slug;
  }

  static Future<String> _uniqueId(String base) async {
    var id = base;
    var n = 2;
    while (await isInstalled(id)) {
      id = '$base-$n';
      n++;
    }
    return id;
  }
}
