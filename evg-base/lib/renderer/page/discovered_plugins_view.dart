/// 发现插件独立视图（带 AppBar + 搜索栏 + 刷新，内容委托 [DiscoverSection]）。
///
/// 与「插件中心」([MarketplaceSlot]) 并列的独立视图（mode_rail 的「发现插件」
/// 按钮、app.dart 的 `/discover` 路由）。两者管理层次不同，故作为两个并列入口
/// 而非合并为单一页面。发现插件的展示卡片（[DiscoverPluginCard]）视觉风格与
/// 插件中心 ([LocalPluginCard]) 对齐。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/core/services/github_clone.dart'
    show CloneResult, CloneErrorType;
import 'package:evergreen_base/core/module/github_source.dart';
import 'package:evergreen_base/core/services/release_downloader.dart' show ReleaseResult;
import 'package:evergreen_base/core/module/plugin_registry.dart';
import 'discover_section.dart';

/// 下载器签名（与 DiscoverSection 一致）。
typedef PluginDownloader = Future<CloneResult> Function(
  GithubSource src,
  String targetDir,
);

/// star 批量拉取器签名（与 DiscoverSection 一致）。
typedef StarFetcher = Future<Map<String, int>> Function(List<String> urls);

/// release 下载器签名（与 DiscoverSection 一致）。
typedef ReleaseDownloader = Future<ReleaseResult> Function(
  GithubSource src,
  String targetDir, {
  String? assetPattern,
  List<String>? platforms,
});

/// 发现插件独立页：AppBar + 搜索栏 + 刷新 + [DiscoverSection] 列表。
///
/// 与「插件中心」([MarketplaceSlot]) 是并列的两个独立视图：插件中心管本地已装
/// 插件的启用/侧栏/卸载/排序；本页管外部可发现插件的浏览与安装。两者层次不同，
/// 故作为独立入口而非合并为单一页面（详见需求 C 之澄清：发现插件不是插件中心的子功能）。
class DiscoveredPluginsView extends ConsumerStatefulWidget {
  final PluginDownloader? cloner;
  final Future<List<RegistryPlugin>> Function()? registryLoader;
  final StarFetcher? starFetcher;
  final ReleaseDownloader? releaseDownloader;

  const DiscoveredPluginsView({
    super.key,
    this.cloner,
    this.registryLoader,
    this.starFetcher,
    this.releaseDownloader,
  });

  @override
  ConsumerState<DiscoveredPluginsView> createState() =>
      _DiscoveredPluginsViewState();
}

class _DiscoveredPluginsViewState extends ConsumerState<DiscoveredPluginsView> {
  final _searchController = TextEditingController();
  String _query = '';
  /// 刷新计数：仅刷新时改变，触发 DiscoverSection 重建重载；搜索不重建。
  int _reloadNonce = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('发现插件'),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      body: Column(
        children: [
          // 搜索栏（与插件中心风格一致）
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: '搜索外部插件...',
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '刷新发现列表',
                  onPressed: () => setState(() => _reloadNonce++),
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: DiscoverSection(
              key: ValueKey(_reloadNonce),
              cloner: widget.cloner,
              registryLoader: widget.registryLoader,
              starFetcher: widget.starFetcher,
              releaseDownloader: widget.releaseDownloader,
              searchQuery: _query,
            ),
          ),
        ],
      ),
    );
  }
}
