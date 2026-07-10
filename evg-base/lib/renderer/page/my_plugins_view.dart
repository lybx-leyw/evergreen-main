/// "我的插件"页面——按维度分组 + 排序 + 卸载确认弹窗。
///
/// 对应 R-S2-6。遵循描述符驱动 + 数据注入模式。
import 'package:flutter/material.dart';
import '../components/shared/widgets/models.dart';
import '../components/shared/widgets/ability_tag.dart';
import '../components/shared/widgets/confirm_dialog.dart';

/// 排序方式。
enum PluginSortBy { name, recentlyUsed, dimension }

/// 我的插件页。
class MyPluginsView extends StatefulWidget {
  final List<PluginDescriptor> plugins;
  final void Function(PluginDescriptor plugin)? onPluginTap;
  final void Function(PluginDescriptor plugin)? onUninstall;
  final void Function()? onCheckUpdates;

  const MyPluginsView({
    super.key,
    required this.plugins,
    this.onPluginTap,
    this.onUninstall,
    this.onCheckUpdates,
  });

  @override
  State<MyPluginsView> createState() => _MyPluginsViewState();
}

class _MyPluginsViewState extends State<MyPluginsView> {
  PluginSortBy _sortBy = PluginSortBy.dimension;
  bool _groupByDim = true;

  List<PluginDescriptor> get _sorted {
    var list = List<PluginDescriptor>.from(widget.plugins);
    switch (_sortBy) {
      case PluginSortBy.name:
        list.sort((a, b) => a.name.compareTo(b.name));
      case PluginSortBy.recentlyUsed:
        // 模拟：已安装优先
        list.sort((a, b) {
          if (a.installed && !b.installed) return -1;
          if (!a.installed && b.installed) return 1;
          return a.name.compareTo(b.name);
        });
      case PluginSortBy.dimension:
        list.sort((a, b) {
          final da = a.dimensions.isNotEmpty ? a.dimensions.first.index : 99;
          final db = b.dimensions.isNotEmpty ? b.dimensions.first.index : 99;
          if (da != db) return da.compareTo(db);
          return a.name.compareTo(b.name);
        });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sorted = _sorted;

    if (sorted.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48,
                color: scheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('你还没有安装任何插件',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.4))),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {}, // 由父级处理导航
              child: const Text('前往市场'),
            ),
          ],
        ),
      );
    }

    // 按维度分组
    final groups = <AbilityDim, List<PluginDescriptor>>{};
    for (final p in sorted) {
      final dim = p.dimensions.isNotEmpty ? p.dimensions.first : AbilityDim.settings;
      groups.putIfAbsent(dim, () => []).add(p);
    }

    return Column(
      children: [
        // 工具栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Text(
                '${sorted.length} 个插件',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const Spacer(),
              // 分组开关
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('分组', style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.5))),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 24,
                    child: Switch(
                      value: _groupByDim,
                      onChanged: (v) => setState(() => _groupByDim = v),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              // 排序按钮
              PopupMenuButton<PluginSortBy>(
                initialValue: _sortBy,
                onSelected: (v) => setState(() => _sortBy = v),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: PluginSortBy.dimension, child: Text('按维度排序')),
                  const PopupMenuItem(value: PluginSortBy.name, child: Text('按名称排序')),
                  const PopupMenuItem(value: PluginSortBy.recentlyUsed, child: Text('按最近使用')),
                ],
                child: const Icon(Icons.sort, size: 20),
              ),
              if (widget.onCheckUpdates != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '检查更新',
                  onPressed: widget.onCheckUpdates,
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        // 插件列表
        Expanded(
          child: _groupByDim
              ? ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: groups.entries.expand((entry) => [
                    _GroupHeader(dim: entry.key, count: entry.value.length, scheme: scheme),
                    ...entry.value.map((p) => _PluginRow(
                      plugin: p,
                      onTap: () => widget.onPluginTap?.call(p),
                      onUninstall: () => _confirmUninstall(context, p),
                    )),
                  ]).toList(),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: sorted.length,
                  itemBuilder: (ctx, i) => _PluginRow(
                    plugin: sorted[i],
                    onTap: () => widget.onPluginTap?.call(sorted[i]),
                    onUninstall: () => _confirmUninstall(context, sorted[i]),
                  ),
                ),
        ),
      ],
    );
  }

  void _confirmUninstall(BuildContext context, PluginDescriptor p) async {
    final ok = await ConfirmDialog.show(
      context,
      title: '卸载 ${p.name}',
      message: '确定要卸载此插件吗？相关数据将被删除。',
      confirmLabel: '卸载',
    );
    if (ok == true) {
      widget.onUninstall?.call(p);
    }
  }
}

class _GroupHeader extends StatelessWidget {
  final AbilityDim dim;
  final int count;
  final ColorScheme scheme;

  const _GroupHeader({required this.dim, required this.count, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          AbilityTag(dim: dim),
          const SizedBox(width: 8),
          Text(
            '${dim.displayName} ($count)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PluginRow extends StatelessWidget {
  final PluginDescriptor plugin;
  final VoidCallback? onTap;
  final VoidCallback? onUninstall;

  const _PluginRow({required this.plugin, this.onTap, this.onUninstall});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // 图标
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.6)!],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      plugin.name[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plugin.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                      Text(
                        'v${plugin.version} · ${plugin.author}',
                        style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
                // 操作
                if (plugin.hasUpdate)
                  TextButton(
                    onPressed: onTap,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('更新', style: TextStyle(fontSize: 12)),
                  ),
                AbilityTag(dim: plugin.dimensions.isNotEmpty ? plugin.dimensions.first : AbilityDim.settings, compact: true),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
                  tooltip: '卸载',
                  onPressed: onUninstall,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
