/// 插件市场主槽位 —— 本地插件管理视图。
///
/// 功能：
/// - 扫描 `plugins/` 目录下所有 manifest.json
/// - 展示为 LocalPluginCard 列表
/// - 支持搜索/过滤
/// - 启用/停用、侧边栏可见性、卸载操作
/// - 多种排序策略（持久化到 `_config.sortMode`）：
///   1. 分组排序（默认）：按侧边栏分组（manifest `nav.sidebar.section`）分组展示，
///      组间/组内可拖拽调整顺序（像文件夹），组头可折叠、可控制「侧边栏是否显示组名」；
///   2. 按名称排序；
///   3. 按最近使用排序（真实打开记录 `lastUsedAt`，由模块打开时 `touch()` 写入）。
library;

import 'dart:io';

import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/plugin_state_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'local_plugin_card.dart';
import 'marketplace_plugin_info.dart';
import 'marketplace_scan.dart';
import 'plugin_state_provider.dart';

/// 排序策略常量（与 [PluginCenterConfig.sortMode] 对应）。
abstract final class PluginSortMode {
  static const String group = 'group';
  static const String name = 'name';
  static const String recent = 'recent';
}

/// 无侧边栏插件的兜底分组名（与 [PluginInfo.section] 默认值一致）。

/// 市场超市 —— 本地插件管理槽位。
///
/// config 可选参数:
/// - `pluginsDir` (String): plugins/ 目录路径，默认 "plugins/"
/// - `title` (String): 面板标题，默认 "插件市场"
class MarketplaceSlot extends ConsumerStatefulWidget {
  final Map<String, dynamic> config;

  const MarketplaceSlot({super.key, this.config = const {}});

  @override
  ConsumerState<MarketplaceSlot> createState() => _MarketplaceSlotState();
}

class _MarketplaceSlotState extends ConsumerState<MarketplaceSlot> {
  String? _pluginsDirOverride;

  List<PluginInfo> _allPlugins = [];
  /// 每个描述符 id → 扫描时捕获的真实磁盘文件夹路径（卸载时精确删除用）。
  Map<String, String> _pluginDirs = {};
  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  String get _pluginsDir {
    // 优先级：config.pluginsDir > Riverpod pluginsDirProvider > 硬编码回退 'plugins'
    // 最后统一 normalize 消除路径中的 ..
    String raw;
    final override = widget.config['pluginsDir'] as String?;
    if (override != null && override.isNotEmpty) {
      raw = override;
    } else if (_pluginsDirOverride != null && _pluginsDirOverride!.isNotEmpty) {
      raw = _pluginsDirOverride!;
    } else {
      try {
        raw = ref.read(pluginsDirProvider);
      } catch (_) {
        raw = 'plugins';
      }
    }
    return p.normalize(raw);
  }

  @override
  void initState() {
    super.initState();
    final injected = widget.config['pluginsDir'] as String?;
    if (injected != null && injected.isNotEmpty) {
      _pluginsDirOverride = injected;
    }
    debugPrint('[Marketplace] 扫描目录: ${_pluginsDir}');
    _loadPlugins();
  }

  Future<void> _loadPlugins() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dir = Directory(_pluginsDir);
      if (!dir.existsSync()) {
        setState(() {
          _loading = false;
          _error = '插件目录不存在: ${dir.path}';
        });
        return;
      }

      debugPrint('[Marketplace] 扫描目录: ${dir.path}');
      // 扫描并捕获每个描述符的真实磁盘目录（供卸载精确删除，见 _doUninstall）。
      final (descriptors, dirs) = scanPluginManifests(_pluginsDir);
      debugPrint('[Marketplace] 扫描完成: 解析 ${descriptors.length} 个插件');

      // 合并内置模块（随应用分发，非 plugins/ 目录插件，如 zju 9 个校园模块）：
      // 从 ModuleRegistry 读取已注册模块，与磁盘扫描结果按 id 去重后追加，
      // 标 isBuiltin 供卡片显示「内置」徽标并隐藏「卸载」按钮。
      final scannedIds = descriptors.map((p) => p.id).toSet();
      var builtinCount = 0;
      try {
        final registry = ref.read(moduleRegistryProvider);
        for (final m in registry.modules) {
          if (scannedIds.contains(m.id)) continue;
          descriptors.add(pluginInfoFromBuiltinModule(m));
          builtinCount++;
        }
      } catch (e) {
        // 未注入 registry（如独立运行/测试环境）→ 仅展示磁盘插件，不影响市场可用。
        debugPrint('[Marketplace] 读取内置模块失败（降级为仅磁盘插件）: $e');
      }
      if (builtinCount > 0) {
        debugPrint('[Marketplace] 合并内置模块: $builtinCount 个（zju 等）');
      }

      // 基准排序：磁盘插件在前，内置模块在后；同组按名称。
      // 仅作为未自定义顺序时的稳定回退（用户拖拽布局优先）。
      descriptors.sort((a, b) {
        if (a.isBuiltin != b.isBuiltin) return a.isBuiltin ? 1 : -1;
        return a.name.compareTo(b.name);
      });

      setState(() {
        _allPlugins = descriptors;
        _pluginDirs = dirs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '加载插件失败: $e';
      });
      debugPrint('[Marketplace] 加载失败: $e');
    }
  }

  List<PluginInfo> get _filteredPlugins {
    if (_searchQuery.isEmpty) return _allPlugins;
    final q = _searchQuery.toLowerCase();
    return _allPlugins.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.id.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q) ||
          p.type.toLowerCase().contains(q);
    }).toList();
  }

  void _toggleEnabled(PluginInfo plugin) {
    final current = ref.read(pluginStateProvider).records[plugin.id];
    final newEnabled = !(current?.enabled ?? true);
    // 经共享 Provider 写入，侧边栏（同 watch 本 Provider）会即时反映。
    ref.read(pluginStateProvider.notifier).setEnabled(plugin.id, newEnabled);
  }

  void _toggleSidebar(PluginInfo plugin) {
    final current = ref.read(pluginStateProvider).records[plugin.id];
    final newVisible = !(current?.sidebarVisible ?? true);
    ref
        .read(pluginStateProvider.notifier)
        .setSidebarVisible(plugin.id, newVisible);
  }

  void _uninstall(PluginInfo plugin) {
    // 内置模块不可卸载（无磁盘目录，随应用分发）。
    if (plugin.isBuiltin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('内置模块不可卸载（随应用分发）')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认卸载'),
        content: Text(plugin.isModule
            ? '确定要卸载插件「${plugin.name}」吗？\n\n此操作将删除插件目录中的所有文件，不可恢复。'
            : '确定要卸载「${plugin.name}」（${plugin.typeLabel}）吗？\n\n此操作将删除其所在插件目录中的所有文件，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doUninstall(plugin);
            },
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
  }

  void _doUninstall(PluginInfo plugin) {
    try {
      // 优先使用扫描阶段捕获的真实磁盘目录；否则回退到 pluginsDir/id
      // （当 id 恰好等于文件夹名时仍可用）。绝不能只靠 id 反推路径——
      // manifest 的 id 与文件夹名可能不同，反推会指向不存在的路径导致卸载静默失败。
      final captured = _pluginDirs[plugin.id];
      final dirPath = (captured != null && captured.isNotEmpty)
          ? captured
          : '$_pluginsDir${Platform.pathSeparator}${plugin.id}';
      final pluginDir = Directory(p.normalize(dirPath));
      if (pluginDir.existsSync()) {
        pluginDir.deleteSync(recursive: true);
      }
      ref.read(pluginStateProvider.notifier).remove(plugin.id);
      _loadPlugins();
    } catch (e) {
      if (mounted) {
        // 权限/文件被占用（如插件 .exe 仍在运行持锁）是常见卸载失败原因，
        // 给出可操作的提示，而不是只抛原始异常。
        final msg = e.toString();
        final hint = msg.contains('denied') ||
                msg.contains('locked') ||
                msg.contains('拒绝访问') ||
                msg.contains('另一个程序')
            ? '（文件可能被占用，请先关闭该插件/进程后重试）'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('卸载失败: $msg$hint')),
        );
      }
    }
  }

  // ═══════ 排序策略 ═══════

  /// 分组视图：组间排序（用户配置 order 优先，回退组内最小 manifest sectionOrder）。
  int _groupSortKey(
      String label, List<PluginInfo> group, PluginCenterConfig config) {
    final configured = config.groups[label]?.order;
    if (configured != null) return configured;
    var minOrder = 1 << 30;
    for (final p in group) {
      if (p.sectionOrder < minOrder) minOrder = p.sectionOrder;
    }
    return minOrder + 1000;
  }

  /// 组内排序（用户拖拽 sortOrder 优先，回退 manifest order）。
  int _pluginSortKey(PluginInfo p, Map<String, PluginStateRecord> states) {
    return states[p.id]?.sortOrder ?? p.order + 1000;
  }

  void _onGroupReorder(List<String> keys, int oldIndex, int newIndex) {
    final ids = List<String>.from(keys);
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    ref.read(pluginStateProvider.notifier).setGroupOrderAll(ids);
  }

  void _onPluginReorder(String groupKey, List<PluginInfo> ordered,
      int oldIndex, int newIndex) {
    final ids = ordered.map((p) => p.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    ref.read(pluginStateProvider.notifier).setPluginSortOrderAll(groupKey, ids);
  }

  void _toggleGroupNameInSidebar(String label, bool show) {
    ref
        .read(pluginStateProvider.notifier)
        .setGroupShowNameInSidebar(label, show);
  }

  void _toggleGroupCollapsed(String label, bool collapsed) {
    ref.read(pluginStateProvider.notifier).setGroupCollapsed(label, collapsed);
  }

  // ═══════ UI ═══════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部搜索栏 + 排序策略 + 计数
        _buildHeader(theme),
        // 内容区
        Expanded(child: _buildContent(theme)),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final config = ref.watch(pluginStateProvider).config;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.store, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索插件...',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => setState(() => _searchQuery = ''),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          const SizedBox(width: 4),
          // 排序策略下拉（持久化到 _config.sortMode）
          Tooltip(
            message: '排序方式',
            child: PopupMenuButton<String>(
              initialValue: config.sortMode,
              onSelected: (v) =>
                  ref.read(pluginStateProvider.notifier).setSortMode(v),
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: PluginSortMode.group,
                  child: Text('分组排序'),
                ),
                PopupMenuItem(
                  value: PluginSortMode.name,
                  child: Text('按名称排序'),
                ),
                PopupMenuItem(
                  value: PluginSortMode.recent,
                  child: Text('按最近使用'),
                ),
              ],
              icon: const Icon(Icons.sort, size: 18),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${_allPlugins.length} 个插件',
            style: TextStyle(fontSize: 12, color: theme.disabledColor),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // 读取共享插件状态（与侧边栏同一 Provider，开关即时同步）。
    final pstate = ref.watch(pluginStateProvider);

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.disabledColor),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.disabledColor)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadPlugins,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredPlugins;

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: theme.disabledColor),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isEmpty ? '暂无本地插件' : '未找到匹配的插件',
              style: TextStyle(color: theme.disabledColor),
            ),
          ],
        ),
      );
    }

    // 按当前排序策略渲染。
    switch (pstate.config.sortMode) {
      case PluginSortMode.recent:
        return _buildRecentList(filtered, pstate, theme);
      case PluginSortMode.name:
        return _buildNameList(filtered, pstate, theme);
      default:
        return _buildGroupedList(filtered, pstate, theme);
    }
  }

  /// 按名称排序（普通扁平列表）。
  Widget _buildNameList(
      List<PluginInfo> items, PluginCenterState pstate, ThemeData theme) {
    final sorted = List<PluginInfo>.from(items)
      ..sort((a, b) => a.name.compareTo(b.name));
    return _buildFlatList(sorted, pstate, theme);
  }

  /// 按最近使用排序：真实 `lastUsedAt` 倒序；无记录/从未打开的排最后。
  Widget _buildRecentList(
      List<PluginInfo> items, PluginCenterState pstate, ThemeData theme) {
    final states = pstate.records;
    final sorted = List<PluginInfo>.from(items)
      ..sort((a, b) {
        final ta = states[a.id]?.lastUsedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = states[b.id]?.lastUsedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final c = tb.compareTo(ta);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    final hasAnyUsage =
        items.any((p) => states[p.id]?.lastUsedAt != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            hasAnyUsage
                ? '按打开时间倒序（打开插件时自动记录）'
                : '暂无使用记录：打开任意插件后会自动记录，并出现在这里',
            style: TextStyle(
                fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(child: _buildFlatList(sorted, pstate, theme)),
      ],
    );
  }

  Widget _buildFlatList(
      List<PluginInfo> items, PluginCenterState pstate, ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadPlugins,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final plugin = items[index];
          final state = pstate.records[plugin.id];
          return LocalPluginCard(
            plugin: plugin,
            state: state,
            onToggleEnabled: () => _toggleEnabled(plugin),
            onToggleSidebar: () => _toggleSidebar(plugin),
            onUninstall: () => _uninstall(plugin),
          );
        },
      ),
    );
  }

  /// 分组排序视图：分组标题（拖拽手柄 + 折叠 + 侧边栏组名开关）+ 组内可拖拽列表。
  Widget _buildGroupedList(
      List<PluginInfo> items, PluginCenterState pstate, ThemeData theme) {
    final states = pstate.records;
    final config = pstate.config;

    // 1. 按分组名归组。
    final grouped = <String, List<PluginInfo>>{};
    for (final p in items) {
      grouped.putIfAbsent(p.section, () => []).add(p);
    }

    // 2. 组间排序：用户拖拽 order 优先，回退 manifest sectionOrder。
    final keys = grouped.keys.toList()
      ..sort((a, b) {
        final oa = _groupSortKey(a, grouped[a]!, config);
        final ob = _groupSortKey(b, grouped[b]!, config);
        final c = oa.compareTo(ob);
        return c != 0 ? c : a.compareTo(b);
      });

    // 3. 组内排序：用户拖拽 sortOrder 优先，回退 manifest order。
    for (final key in keys) {
      grouped[key]!.sort((a, b) {
        final oa = _pluginSortKey(a, states);
        final ob = _pluginSortKey(b, states);
        final c = oa.compareTo(ob);
        return c != 0 ? c : a.order.compareTo(b.order);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            '拖动手柄调整分组/插件顺序，组名开关控制侧边栏显示',
            style: TextStyle(
                fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadPlugins,
            child: ReorderableListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) =>
                  _onGroupReorder(keys, oldIndex, newIndex),
              children: [
                for (var gi = 0; gi < keys.length; gi++)
                  ReorderableDragStartListener(
                    key: ValueKey('group:${keys[gi]}'),
                    index: gi,
                    child: _MarketplaceGroupBlock(
                      label: keys[gi],
                      groupIndex: gi,
                      plugins: grouped[keys[gi]]!,
                      groupConfig: config.groups[keys[gi]],
                      states: states,
                      onToggleSidebarName: () => _toggleGroupNameInSidebar(
                          keys[gi],
                          !(config.groups[keys[gi]]?.showNameInSidebar ?? true)),
                      onToggleCollapse: () => _toggleGroupCollapsed(
                          keys[gi],
                          !(config.groups[keys[gi]]?.collapsed ?? false)),
                      onPluginReorder: (oldIndex, newIndex) =>
                          _onPluginReorder(
                              keys[gi], grouped[keys[gi]]!, oldIndex, newIndex),
                      onToggleEnabled: (plugin) => _toggleEnabled(plugin),
                      onToggleSidebar: (plugin) => _toggleSidebar(plugin),
                      onUninstall: (plugin) => _uninstall(plugin),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 分组块：组头（拖拽手柄 + 名称 + 折叠 + 侧边栏组名开关）+ 组内插件列表。
class _MarketplaceGroupBlock extends StatelessWidget {
  const _MarketplaceGroupBlock({
    required this.label,
    required this.groupIndex,
    required this.plugins,
    required this.groupConfig,
    required this.states,
    required this.onToggleSidebarName,
    required this.onToggleCollapse,
    required this.onPluginReorder,
    required this.onToggleEnabled,
    required this.onToggleSidebar,
    required this.onUninstall,
  });

  final String label;
  final int groupIndex;
  final List<PluginInfo> plugins;
  final PluginGroupConfig? groupConfig;
  final Map<String, PluginStateRecord> states;
  final VoidCallback onToggleSidebarName;
  final VoidCallback onToggleCollapse;
  final void Function(int oldIndex, int newIndex) onPluginReorder;
  final void Function(PluginInfo plugin) onToggleEnabled;
  final void Function(PluginInfo plugin) onToggleSidebar;
  final void Function(PluginInfo plugin) onUninstall;

  bool get _showNameInSidebar => groupConfig?.showNameInSidebar ?? true;
  bool get _collapsed => groupConfig?.collapsed ?? false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 组头
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Row(
            children: [
              // 组间拖拽手柄（触发外层 ReorderableListView 的拖拽）。
              ReorderableDragStartListener(
                index: groupIndex,
                child: Tooltip(
                  message: '拖动调整分组顺序',
                  child: Icon(Icons.drag_indicator,
                      size: 20, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.folder_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$label (${plugins.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 折叠/展开
              IconButton(
                icon: Icon(
                    _collapsed ? Icons.expand_more : Icons.expand_less,
                    size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: _collapsed ? '展开分组' : '折叠分组',
                onPressed: onToggleCollapse,
              ),
              // 侧边栏组名开关
              Tooltip(
                message: _showNameInSidebar ? '侧边栏显示组名' : '侧边栏隐藏组名',
                child: IconButton(
                  icon: Icon(
                    _showNameInSidebar ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                    color: _showNameInSidebar
                        ? scheme.onSurfaceVariant
                        : scheme.outline,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleSidebarName,
                ),
              ),
            ],
          ),
        ),
        if (!_collapsed)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: onPluginReorder,
            children: [
              for (var i = 0; i < plugins.length; i++)
                ReorderableDragStartListener(
                  key: ValueKey('$label:${plugins[i].id}'),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 组内拖拽手柄
                        Tooltip(
                          message: '拖动调整插件顺序',
                          child: Icon(Icons.drag_indicator,
                              size: 20,
                              color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                        ),
                        Expanded(
                          child: LocalPluginCard(
                            plugin: plugins[i],
                            state: states[plugins[i].id],
                            onToggleEnabled: () => onToggleEnabled(plugins[i]),
                            onToggleSidebar: () => onToggleSidebar(plugins[i]),
                            onUninstall: () => onUninstall(plugins[i]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
