import 'package:flutter/material.dart';

/// 首页模块分类。
enum ModuleCategory {
  tools('工具'),
  ai('AI'),
  system('系统');

  const ModuleCategory(this.label);

  /// 分区标题。
  final String label;
}

/// 首页模块注册信息：首页应用抽屉从这里读取模块列表。
class ModuleInfo {
  const ModuleInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.category,
    required this.route,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final ModuleCategory category;

  /// 在 [AppRoutes] 中定义的路由名。
  final String route;
}

/// 模块注册表：v0.1.0 全部模块。
class AppRegistry {
  AppRegistry._();

  static const List<ModuleInfo> modules = [
    // 工具
    ModuleInfo(
      id: 'calculator',
      title: '科学计算器',
      subtitle: '表达式计算、三角函数、对数',
      icon: Icons.calculate_outlined,
      category: ModuleCategory.tools,
      route: '/calculator',
    ),
    ModuleInfo(
      id: 'converter',
      title: '单位转换',
      subtitle: '长度、质量、温度等 12 类单位',
      icon: Icons.swap_horiz,
      category: ModuleCategory.tools,
      route: '/converter',
    ),
    ModuleInfo(
      id: 'plotter',
      title: '函数绘制',
      subtitle: '绘制 y=f(x) 曲线、缩放平移',
      icon: Icons.show_chart,
      category: ModuleCategory.tools,
      route: '/plotter',
    ),
    ModuleInfo(
      id: 'password-generator',
      title: '密码生成器',
      subtitle: '随机强密码，可自定义长度字符',
      icon: Icons.key_outlined,
      category: ModuleCategory.tools,
      route: '/tools/password',
    ),
    ModuleInfo(
      id: 'json-formatter',
      title: 'JSON 格式化',
      subtitle: '格式化、压缩与校验 JSON',
      icon: Icons.data_object,
      category: ModuleCategory.tools,
      route: '/tools/json',
    ),
    ModuleInfo(
      id: 'qr-generator',
      title: '二维码生成',
      subtitle: '文本、链接转二维码',
      icon: Icons.qr_code_2,
      category: ModuleCategory.tools,
      route: '/tools/qr',
    ),
    // AI
    ModuleInfo(
      id: 'aiplat',
      title: 'AiPlat',
      subtitle: '连接 API Key，与 AI 对话',
      icon: Icons.smart_toy_outlined,
      category: ModuleCategory.ai,
      route: '/aiplat',
    ),
    // 系统
    ModuleInfo(
      id: 'webos',
      title: 'WebOS',
      subtitle: '桌面操作系统环境',
      icon: Icons.desktop_windows_outlined,
      category: ModuleCategory.system,
      route: '/webos',
    ),
  ];

  /// 按分类取模块。
  static List<ModuleInfo> modulesOf(ModuleCategory category) {
    return modules.where((m) => m.category == category).toList();
  }

  /// 按标题/副标题过滤（首页搜索用）。
  static List<ModuleInfo> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return modules;
    return modules
        .where(
          (m) =>
              m.title.toLowerCase().contains(q) ||
              m.subtitle.toLowerCase().contains(q),
        )
        .toList();
  }
}
