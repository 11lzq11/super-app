import 'package:flutter/material.dart';

import '../core/app_registry.dart';
import '../core/theme.dart';

/// 首页模块卡片：图标 + 标题 + 简介，圆角、轻阴影。
///
/// 简介遮挡的根因（v0.1.0）：首页网格用 childAspectRatio: 1.3 固定卡片
/// 高度，手机 2 列时卡片只有约 121dp 高，而内容（内边距 + 图标 44 +
/// 标题 + 简介 2 行）要约 140dp，简介第二行被 Card 的裁剪直接切掉。
/// 修复：卡片内容收紧（图标 40、内边距 12），网格改用固定高度
/// [AppDimens.moduleCardHeight]（148dp，内容约 132dp + 16dp 余量），
/// 高度不再随列宽变化，简介 2 行完整可见。
class ModuleCard extends StatelessWidget {
  const ModuleCard({
    super.key,
    required this.module,
    required this.onTap,
  });

  final ModuleInfo module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  module.icon,
                  size: 22,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                module.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                module.subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
