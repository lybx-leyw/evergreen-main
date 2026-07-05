/// 工作台页面——插件卡片网格 + 点击打开 + 右键上下文菜单。
///
/// 对应 R-S2-4。组合 MarketView 模式的卡片网格 + 快捷入口。
import 'package:flutter/material.dart';
import '../widgets/models.dart';
import '../widgets/ability_tag.dart';

/// 工作台页面——展示已安装插件的操作面板。
class WorkspacePage extends StatelessWidget {
  final List<PluginDescriptor> installedPlugins;
  final void Function(PluginDescriptor plugin)? onPluginTap;
  final void Function(PluginDescriptor plugin)? onContextMenu;
  final VoidCallback? onGoToMarket;
  final VoidCallback? onRefresh;

  const WorkspacePage({
    super.key,
    required this.installedPlugins,
    this.onPluginTap,
    this.onContextMenu,
    this.onGoToMarket,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (installedPlugins.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_customize, size: 48, color: scheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('工作台为空', style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
            const SizedBox(height: 8),
            Text('前往市场安装插件以开始使用',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 16),
            if (onGoToMarket != null)
              FilledButton.tonal(onPressed: onGoToMarket, child: const Text('前往市场')),
          ],
        ),
      );
    }

    final needsUpdate = installedPlugins.where((p) => p.hasUpdate).length;

    return Column(
      children: [
        // 快捷信息栏
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.widgets, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                '${installedPlugins.length} 个插件已安装',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              if (needsUpdate > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFA8C16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$needsUpdate 个可更新',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                ),
              ],
              const Spacer(),
              if (onRefresh != null)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: '刷新',
                  onPressed: onRefresh,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 卡片网格
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final crossAxisCount = constraints.maxWidth > 900
                  ? 4
                  : constraints.maxWidth > 600
                      ? 3
                      : 2;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: installedPlugins.length,
                itemBuilder: (ctx, i) => _WorkspaceCard(
                  plugin: installedPlugins[i],
                  onTap: () => onPluginTap?.call(installedPlugins[i]),
                  onContextMenu: () => onContextMenu?.call(installedPlugins[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  final PluginDescriptor plugin;
  final VoidCallback? onTap;
  final VoidCallback? onContextMenu;

  const _WorkspaceCard({
    required this.plugin,
    this.onTap,
    this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onSecondaryTap: onContextMenu,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部图标
            Stack(
              children: [
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.6)!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      plugin.name[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.w300, color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (plugin.hasUpdate)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFA8C16),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '更新',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            // 内容
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plugin.name,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'v${plugin.version}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(height: 6),
                  AbilityTagRow(dims: plugin.dimensions),
                  const Spacer(),
                  // 底部操作
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (plugin.hasUpdate) ...[
                        TextButton(
                          onPressed: onTap,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('更新', style: TextStyle(fontSize: 12)),
                        ),
                      ] else
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: const Color(0xFF2DA44E),
                        ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.more_vert, size: 16, color: scheme.onSurface.withValues(alpha: 0.4)),
                        tooltip: '更多操作',
                        onPressed: onContextMenu,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
