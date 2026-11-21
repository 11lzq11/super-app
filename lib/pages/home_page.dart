import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_registry.dart';
import '../core/router.dart';
import '../core/settings.dart';
import '../widgets/module_card.dart';

/// 首页：应用抽屉。
///
/// 顶部 SuperApp 标题 + 搜索框，按分类分组显示模块卡片，
/// 右上角设置入口；Super MAX 开启时顶部显示徽标。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _crossAxisCount(double width) {
    if (width >= 1000) return 4;
    if (width >= 640) return 3;
    return 2;
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _moduleGrid(List<ModuleInfo> modules, double width) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _crossAxisCount(width),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
        ),
        itemCount: modules.length,
        itemBuilder: (context, index) {
          final module = modules[index];
          return ModuleCard(
            module: module,
            onTap: () => Navigator.pushNamed(context, module.route),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final width = MediaQuery.sizeOf(context).width;
    final searching = _query.trim().isNotEmpty;
    final filtered = AppRegistry.search(_query);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SuperApp'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索功能',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: '清除',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (settings.superMaxEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bolt,
                          size: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Super MAX 已开启',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: searching
                ? _buildSearchResult(filtered, width)
                : _buildSections(width),
          ),
        ],
      ),
    );
  }

  Widget _buildSections(double width) {
    return ListView(
      children: [
        for (final category in ModuleCategory.values) ...[
          _sectionTitle(category.label),
          _moduleGrid(AppRegistry.modulesOf(category), width),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSearchResult(List<ModuleInfo> modules, double width) {
    if (modules.isEmpty) {
      return Center(
        child: Text(
          '没有找到相关功能',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    return ListView(
      children: [
        _sectionTitle('搜索结果'),
        _moduleGrid(modules, width),
        const SizedBox(height: 24),
      ],
    );
  }
}
