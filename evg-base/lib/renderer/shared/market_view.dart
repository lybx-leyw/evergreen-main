/// 市场页——瀑布流卡片 + 六色能力标签 + 搜索栏 + 筛选标签。
///
/// 对应 R-S2-1。遵循描述符驱动 + 数据注入模式。
import 'package:flutter/material.dart';
import '../widgets/models.dart';
import '../widgets/ability_tag.dart';

/// 市场页——展示可安装的插件列表。
///
/// 数据通过 [plugins] 注入，搜索/筛选在页面内部管理。
class MarketView extends StatefulWidget {
  final List<PluginDescriptor> plugins;
  final void Function(PluginDescriptor plugin)? onPluginTap;
  final void Function(PluginDescriptor plugin)? onInstallTap;
  final String? searchQuery;

  const MarketView({
    super.key,
    required this.plugins,
    this.onPluginTap,
    this.onInstallTap,
    this.searchQuery,
  });

  @override
  State<MarketView> createState() => _MarketViewState();
}

class _MarketViewState extends State<MarketView> {
  final _searchController = TextEditingController();
  AbilityDim? _activeDim;

  @override
  void initState() {
    super.initState();
    if (widget.searchQuery != null) {
      _searchController.text = widget.searchQuery!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PluginDescriptor> get _filtered {
    var list = widget.plugins;
    final q = _searchController.text.toLowerCase();
    if (q.isNotEmpty) {
      list = list.where(
        (p) =>
            p.name.toLowerCase().contains(q) ||
            p.description.toLowerCase().contains(q),
      ).toList();
    }
    if (_activeDim != null) {
      list = list.where((p) => p.dimensions.contains(_activeDim)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;

    return Column(
      children: [
        // 搜索栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索插件...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        // 筛选标签
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _FilterChip(
                label: '全部',
                selected: _activeDim == null,
                onTap: () => setState(() => _activeDim = null),
              ),
              ...AbilityDim.values.map(
                (d) => _FilterChip(
                  label: d.displayName,
                  selected: _activeDim == d,
                  onTap: () => setState(() => _activeDim = d),
                ),
              ),
            ],
          ),
        ),
        // 结果计数
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '${filtered.length} 个插件',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 卡片网格
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off, size: 48,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text('没有找到匹配的插件',
                          style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
                    ],
                  ),
                )
              : LayoutBuilder(
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
                        childAspectRatio: 0.82,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) =>
                          _MarketCard(
                            plugin: filtered[i],
                            onTap: () => widget.onPluginTap?.call(filtered[i]),
                            onInstall: () => widget.onInstallTap?.call(filtered[i]),
                          ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _FilterChip({
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketCard extends StatelessWidget {
  final PluginDescriptor plugin;
  final VoidCallback? onTap;
  final VoidCallback? onInstall;

  const _MarketCard({
    required this.plugin,
    this.onTap,
    this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部图片区域
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
                        fontSize: 32,
                        fontWeight: FontWeight.w300,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // 安装状态徽章
                if (plugin.installed)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: plugin.hasUpdate
                            ? const Color(0xFFFA8C16)
                            : const Color(0xFF2DA44E),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        plugin.hasUpdate ? '更新' : '已安装',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // 内容区
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
                    plugin.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  AbilityTagRow(dims: plugin.dimensions),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _statChip(Icons.star, plugin.rating.toString(), scheme),
                      const SizedBox(width: 8),
                      _statChip(Icons.download, '${plugin.installCount}', scheme),
                      const Spacer(),
                      Text(
                        'v${plugin.version}',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withValues(alpha: 0.4),
                        ),
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

  Widget _statChip(IconData icon, String text, ColorScheme scheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: scheme.onSurface.withValues(alpha: 0.5)),
        const SizedBox(width: 2),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
