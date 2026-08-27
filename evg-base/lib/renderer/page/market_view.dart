/// 市场页——瀑布流卡片 + 六色能力标签 + 搜索栏 + 筛选标签。
///
/// 对应 R-S2-1。遵循描述符驱动 + 数据注入模式。
import 'package:evergreen_base/core/module/capability.dart';
import 'package:evergreen_base/core/module/plugin_review.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/ability_capability_bridge.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/permission_dialog.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/plugin_review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/plugin_registry.dart';
import 'package:evergreen_base/core/module/github_source.dart';
import '../components/shared/widgets/models.dart';
import '../components/shared/widgets/ability_tag.dart';

/// 远程 registry 加载器（M6-0 自动发现）。
///
/// 市场打开时调用，返回从 registry 文件（如 GitHub 上的 plugins.json）解析出的
/// 插件清单（[RegistryPlugin] 列表）。调用方负责把 [RegistryPlugin] 转成
/// [PluginDescriptor]（见 [registryPluginToDescriptor]）。
typedef RegistryLoader = Future<List<RegistryPlugin>> Function();

/// 把 core 层 [RegistryPlugin] 映射为渲染层 [PluginDescriptor]（M6-0）。
///
/// [installed] 为外部传入的「已下载/已安装」标记（M6 下载安装），
/// 命中后卡片显示「已安装」徽章。
///
/// [liveStars] 为实时拉取的 `owner/repo -> stars` 映射（M6 实时 star），
/// 命中时覆盖 [RegistryPlugin.stars] 静态值；否则回退静态值。
PluginDescriptor registryPluginToDescriptor(
  RegistryPlugin p, {
  bool installed = false,
  Map<String, int>? liveStars,
}) {
  AbilityDim _dim(String s) {
    for (final d in AbilityDim.values) {
      if (d.name == s) return d;
    }
    return AbilityDim.data;
  }

  // 实时 star：按 owner/repo 匹配，命中则覆盖静态 stars。
  int? stars = p.stars;
  if (liveStars != null) {
    final url = p.installUrl;
    if (url != null && url.isNotEmpty) {
      final full = _ownerRepoOf(url);
      if (full != null && liveStars.containsKey(full)) {
        stars = liveStars[full];
      }
    }
  }

  // 分类维度 = registry `dimensions`（能力标签）∪ `lattice`（插件类型权威声明）。
  //
  // 背景（t24）：warm_study 等主题插件的 registry 条目声明 `"lattice":"theme"`
  // 但能力标签只有 `"dimensions":["ui"]`——旧逻辑只消费 dimensions，导致主题
  // 插件在「发现插件」页显示/筛选为「界面」而非「主题」。这里把 lattice 也并入
  // 维度（去重、声明维度在前），保证插件类型与展示/筛选一致，且不依赖修改
  // registry 数据。未知 lattice 返回 null 保持既有行为。
  final latticeDim = _latticeDim(p.lattice);
  final dims = <AbilityDim>[
    for (final d in p.dimensions) _dim(d),
    if (latticeDim != null &&
        !p.dimensions.any((d) => _dim(d) == latticeDim))
      latticeDim,
  ];

  return PluginDescriptor(
    id: p.id,
    name: p.name,
    description: p.description,
    longDescription: p.longDescription ?? '',
    author: p.author ?? '',
    version: p.version,
    dimensions: dims,
    installCount: p.installCount,
    rating: p.rating,
    stars: stars,
    installed: installed,
  );
}

/// registry `lattice`（插件类型声明）→ 能力维度。
///
/// 与 [AbilityDim] 六色标签对应；未识别的 lattice 返回 null（保持既有
/// `dimensions` 不变）。theme 型插件（如 warm_study）由此映射为「主题」。
AbilityDim? _latticeDim(String? lattice) => switch (lattice) {
      'theme' => AbilityDim.theme,
      'module' || 'static-web' || 'web-bridged' => AbilityDim.ui,
      'data-source' => AbilityDim.data,
      'agent' || 'agent-tool' => AbilityDim.agent,
      'config' => AbilityDim.settings,
      'skill' => AbilityDim.skill,
      'skin' => AbilityDim.skin,
      _ => null,
    };

/// 从 GitHub URL 提取 `owner/repo`（失败返回 null）。
String? _ownerRepoOf(String url) {
  try {
    final src = parseGithubSource(url);
    return src.fullName;
  } catch (_) {
    return null;
  }
}

/// 市场页——展示可安装的插件列表。
///
/// 数据通过 [plugins] 注入，搜索/筛选在页面内部管理。
///
/// 审核闸（M5-6）：传入 [reviewQueue] 时，仅 [ReviewQueue.allows] 通过的插件
/// 出现在列表（fail-closed：传了队列但插件不在白名单 → 不显示）。
/// 评分（M5-9）：传入 [reviewsById] 时，卡片显示聚合平均分与评价数，缺省回退 [PluginDescriptor.rating]。
///
/// 安装采用 fail-closed 闸：点「安装」先弹 [PermissionConfirmDialog] 展示
/// 该插件的能力维度与风险定级，用户确认后才回调 [onInstallTap]。
class MarketView extends StatefulWidget {
  final List<PluginDescriptor> plugins;
  final void Function(PluginDescriptor plugin)? onPluginTap;
  final void Function(PluginDescriptor plugin)? onInstallTap;

  /// 安装完成后回调（M5-13：装完可引导评价）。
  final void Function(PluginDescriptor plugin)? onInstalled;

  /// 用户提交评价回调（M5-8）。提供后卡片显示「评价」入口。
  final void Function(String pluginId, PluginReview review)? onReviewSubmit;

  /// 审核白名单（M5-6）。传 null 表示不审核（全量展示）。
  final ReviewQueue? reviewQueue;

  /// 插件 id → 评分聚合（M5-9）。传 null 表示不展示聚合分。
  final Map<String, ReviewAggregate>? reviewsById;

  final String? searchQuery;

  /// 可选：把 [PluginDescriptor] 解析为真实核心能力维度清单。
  /// 不提供时回退用 [toCoreDims]（从卡片已有的 [AbilityDim] 桥接，缺 process 等）。
  final List<CapabilityDimension> Function(PluginDescriptor plugin)? capabilityResolver;

  /// M6-0 自动发现：远程 registry 加载器。
  ///
  /// 提供后，市场打开时自动拉取 registry 插件清单并合并展示；
  /// 自带加载态 / 错误态 / 刷新按钮。registry 解析异常不影响注入的 [plugins]。
  final RegistryLoader? registryLoader;

  /// M6 下载安装：已被下载/安装的插件 id 集合。
  /// 命中后该插件卡片显示「已安装」徽章且安装按钮变为「打开/已下载」。
  final Set<String> installedIds;

  /// M6 下载安装：正在下载中的插件 id 集合（卡片显示进度环而非安装按钮）。
  final Set<String> installingIds;

  /// M6 · 补 5：删除已安装插件回调。提供后，「已安装」卡片显示删除按钮。
  final void Function(PluginDescriptor plugin)? onUninstall;

  const MarketView({
    super.key,
    required this.plugins,
    this.onPluginTap,
    this.onInstallTap,
    this.onInstalled,
    this.onReviewSubmit,
    this.reviewQueue,
    this.reviewsById,
    this.searchQuery,
    this.capabilityResolver,
    this.registryLoader,
    this.installedIds = const {},
    this.installingIds = const {},
    this.onUninstall,
  });

  @override
  State<MarketView> createState() => _MarketViewState();
}

class _MarketViewState extends State<MarketView> {
  final _searchController = TextEditingController();
  AbilityDim? _activeDim;

  /// M6-0：registry 加载结果（null=未加载；空列表=加载完但无插件）。
  List<PluginDescriptor>? _registryPlugins;
  Object? _registryError;
  bool _registryLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.searchQuery != null) {
      _searchController.text = widget.searchQuery!;
    }
    if (widget.registryLoader != null) {
      _loadRegistry();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 拉取并解析远程 registry（M6-0）。
  Future<void> _loadRegistry() async {
    final loader = widget.registryLoader;
    if (loader == null) return;
    setState(() {
      _registryLoading = true;
      _registryError = null;
    });
    try {
      final raw = await loader();
      // raw 为 List<RegistryPlugin>，统一映射为 PluginDescriptor。
      // 命中 [widget.installedIds] 的标记为已安装（M6 下载安装）。
      final mapped = raw
          .map((p) => registryPluginToDescriptor(p,
              installed: widget.installedIds.contains(p.id)))
          .toList();
      if (!mounted) return;
      setState(() {
        _registryPlugins = mapped;
        _registryLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _registryError = e;
        _registryLoading = false;
      });
    }
  }

  List<PluginDescriptor> get _allPlugins {
    final base = List<PluginDescriptor>.from(widget.plugins);
    if (_registryPlugins != null) base.addAll(_registryPlugins!);
    return base;
  }

  List<PluginDescriptor> get _filtered {
    var list = _allPlugins;
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
    // M5-6 审核闸：传入 reviewQueue 时仅白名单插件可见（fail-closed）。
    final queue = widget.reviewQueue;
    if (queue != null) {
      list = list.where((p) => queue.allows(p.id)).toList();
    }
    return list;
  }

  /// 安装前权限闸（fail-closed）：先弹确认弹窗，确认后才回调 [widget.onInstallTap]。
  Future<void> _handleInstall(PluginDescriptor plugin) async {
    if (widget.onInstallTap == null) return;
    // 解析真实能力维度：优先 capabilityResolver，回退 AbilityDim 桥接。
    final dims = widget.capabilityResolver?.call(plugin) ??
        toCoreDims(plugin.dimensions);
    final confirmed = await showPermissionConfirmDialog(
      context: context,
      pluginName: plugin.name,
      dims: dims,
      onConfirm: () => widget.onInstallTap?.call(plugin),
    );
    // confirmed=false（取消/ESC/遮罩）→ 不安装，静默返回。
    if (!confirmed) {
      debugPrint('[MarketView] 用户取消安装 ${plugin.id}（权限闸未过）');
      return;
    }
    // M5-13 安装确认后通知上层（用于装完引导评价）。
    widget.onInstalled?.call(plugin);
  }

  /// 弹出评价面板（M5-8）。
  Future<void> _showReviewSheet(PluginDescriptor plugin) async {
    if (widget.onReviewSubmit == null) return;
    final review = await showPluginReviewSheet(context: context, plugin: plugin);
    if (review != null) {
      widget.onReviewSubmit?.call(plugin.id, review);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;

    return Column(
      children: [
        // 搜索栏 + 刷新（M6-0）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
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
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              if (widget.registryLoader != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '刷新发现列表',
                  onPressed: _registryLoading ? null : _loadRegistry,
                  icon: _registryLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                ),
              ],
            ],
          ),
        ),
        // M6-0 registry 错误态（远程不可达等）。
        if (_registryError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off,
                      size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '发现源加载失败：${_registryError}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadRegistry,
                    child: const Text('重试', style: TextStyle(fontSize: 12)),
                  ),
                ],
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
                            installing: widget.installingIds.contains(filtered[i].id),
                            onTap: () => widget.onPluginTap?.call(filtered[i]),
                            onInstall: () => _handleInstall(filtered[i]),
                            onReview: widget.onReviewSubmit == null
                                ? null
                                : () => _showReviewSheet(filtered[i]),
                            onUninstall: widget.onUninstall == null
                                ? null
                                : () => widget.onUninstall!(filtered[i]),
                            aggregate: widget.reviewsById?[filtered[i].id],
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
  final VoidCallback? onReview;
  final VoidCallback? onUninstall;
  final ReviewAggregate? aggregate;

  /// M6 下载安装：是否正在下载（显示进度环）。
  final bool installing;

  const _MarketCard({
    required this.plugin,
    this.onTap,
    this.onInstall,
    this.onReview,
    this.onUninstall,
    this.aggregate,
    this.installing = false,
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
                      // M6 市场信息：统一展示 GitHub 作者 + star 数（替代评分/下载量）。
                      _statChip(
                        Icons.person_outline,
                        plugin.author.isEmpty ? '未知作者' : plugin.author,
                        scheme,
                        overflow: TextOverflow.ellipsis,
                        maxWidth: 120,
                      ),
                      const SizedBox(width: 8),
                      _statChip(
                        Icons.star_border,
                        '${plugin.stars ?? 0}',
                        scheme,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // M6 下载安装按钮 + 评价：左安装、右评价（独占一行，避免溢出）。
                  Row(
                    children: [
                      plugin.installed
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer
                                        .withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_outline,
                                          size: 14, color: scheme.primary),
                                      const SizedBox(width: 4),
                                      Text('已安装',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.primary,
                                            fontWeight: FontWeight.w500,
                                          )),
                                    ],
                                  ),
                                ),
                                if (onUninstall != null) ...[
                                  const SizedBox(width: 6),
                                  IconButton(
                                    tooltip: '删除插件',
                                    icon: Icon(Icons.delete_outline,
                                        size: 16, color: scheme.error),
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(
                                        minWidth: 28, minHeight: 28),
                                    padding: EdgeInsets.zero,
                                    onPressed: onUninstall,
                                  ),
                                ],
                              ],
                            )
                          : installing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : onInstall != null
                                  ? FilledButton(
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                      ),
                                      onPressed: onInstall,
                                      child: const Text('安装',
                                          style: TextStyle(fontSize: 12)),
                                    )
                                  : const SizedBox.shrink(),
                      const Spacer(),
                      Text(
                        'v${plugin.version}',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                      if (onReview != null)
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: onReview,
                          child:
                              const Text('评价', style: TextStyle(fontSize: 12)),
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

  Widget _statChip(IconData icon, String text, ColorScheme scheme,
      {TextOverflow? overflow, double? maxWidth}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: scheme.onSurface.withValues(alpha: 0.5)),
        const SizedBox(width: 2),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
          child: Text(
            text,
            maxLines: 1,
            overflow: overflow ?? TextOverflow.clip,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}
