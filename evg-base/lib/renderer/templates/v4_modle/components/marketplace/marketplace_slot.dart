/// 插件市场主槽位 —— 本地插件管理视图。
///
/// 功能：
/// - 扫描 `plugins/` 目录下所有插件清单（module/agent/data 的 manifest.json、config.json、theme.json 等）
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
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
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
  /// 当前类型筛选，'all' 表示全部。
  String _typeFilter = 'all';

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
          scannedIds.add(m.id);
          builtinCount++;
        }
      } catch (e) {
        // 未注入 registry（如独立运行/测试环境）→ 仅展示磁盘插件，不影响市场可用。
        debugPrint('[Marketplace] 读取内置模块失败（降级为仅磁盘插件）: $e');
      }
      if (builtinCount > 0) {
        debugPrint('[Marketplace] 合并内置模块: $builtinCount 个（zju 等）');
      }

      // 合并运行时已注册数据源（DataOrchestrator 真相源）。
      // marketplace 主扫 plugins/<name>/data/manifest.json，但运行时热注册（zju 校园
      // 数据源、设计器自动爬取生成、assets 内置等）只活在 orchestrator.registeredTypes，
      // 磁盘未必有 manifest——这里并入保证「已注册即显示」。磁盘已扫到的同名 data-source
      // 卡按 id 去重（不重复），其余标 isBuiltin（无磁盘目录，隐藏卸载）。
      var dsCount = 0;
      try {
        final orch = ref.read(dataOrchestratorProvider);
        for (final status in orch.allStatuses) {
          if (scannedIds.contains(status.name)) continue;
          descriptors.add(pluginInfoFromDataSource(status, isBuiltin: true));
          scannedIds.add(status.name);
          dsCount++;
        }
      } catch (e) {
        debugPrint('[Marketplace] 读取已注册数据源失败（降级为仅磁盘数据源）: $e');
      }
      if (dsCount > 0) {
        debugPrint('[Marketplace] 合并已注册数据源: $dsCount 个');
      }

      // 合并运行时已加载 Skill（skillIndexProvider 真相源）。
      // 旧扫描只查 plugins/<name>/skill/*.md，漏掉 app_bootstrap 实际扫描的
      // .greenix/skills/（真实 skill 所在地）与 plugins/<name>/SKILL.md 布局 A。
      // 统一从 SkillIndex.all 读取（与技能管理页/RunSkillTool 同源）。
      // 磁盘 skill 卡按 id（归一化 Skill 名）去重；其余按路径判定是否内置：
      // 含 .../plugins/<id>/skill/... 的自定义 skill 定位到插件目录（可卸载），
      // 否则（.greenix/skills/ 等）视为内置（隐藏卸载）。
      var skillCount = 0;
      try {
        final skillIndex = ref.read(skillIndexProvider);
        for (final skill in skillIndex.all()) {
          final id = normalizeSkillName(skill.name);
          if (scannedIds.contains(id)) continue;
          final isBuiltin = !skill.path
              .replaceAll('\\', '/')
              .contains(RegExp(r'/plugins/[^/]+/skill/'));
          descriptors.add(pluginInfoFromSkill(skill, isBuiltin: isBuiltin));
          scannedIds.add(id);
          skillCount++;
        }
      } catch (e) {
        debugPrint('[Marketplace] 读取已加载 Skill 失败（降级为仅磁盘 skill）: $e');
      }
      if (skillCount > 0) {
        debugPrint('[Marketplace] 合并已加载 Skill: $skillCount 个');
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
    Iterable<PluginInfo> result = _allPlugins;
    if (_typeFilter != 'all') {
      result = result.where((p) => p.type == _typeFilter);
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((p) {
        return p.name.toLowerCase().contains(q) ||
            p.id.toLowerCase().contains(q) ||
            p.description.toLowerCase().contains(q) ||
            p.type.toLowerCase().contains(q);
      });
    }
    return result.toList();
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
    final isWholeDir = plugin.deletePath.isEmpty ||
        p.normalize(plugin.deletePath) == p.normalize(plugin.dirPath);
    final scopeText = isWholeDir
        ? '此操作将删除整个插件目录中的所有文件，不可恢复。'
        : '此操作将删除其对应的插件子目录，不可恢复。';
    final message = plugin.isSkill
        ? '确定要删除技能「${plugin.name}」吗？\n\n此操作将删除其 skill/ 目录中的技能文件，不可恢复。'
        : plugin.isModule
            ? '确定要卸载插件「${plugin.name}」吗？\n\n$scopeText'
            : '确定要卸载「${plugin.name}」（${plugin.typeLabel}）吗？\n\n$scopeText';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认卸载'),
        content: Text(plugin.isSkill
            ? '确定要删除技能「${plugin.name}」吗？\n\n此操作将删除其 skill/ 目录中的技能文件，不可恢复。'
            : plugin.isModule
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
      // 优先使用扫描阶段捕获的精确删除路径（能力分支目录或整个插件目录）；
      // 否则回退到扫描阶段捕获的真实磁盘目录，再回退到 pluginsDir/id
      // （当 id 恰好等于文件夹名时仍可用）。绝不能只靠 id 反推路径——
      // manifest 的 id 与文件夹名可能不同，反推会指向不存在的路径导致卸载静默失败。
      final captured = _pluginDirs[plugin.id];
      final fallback = (captured != null && captured.isNotEmpty)
          ? captured
          : '$_pluginsDir${Platform.pathSeparator}${plugin.id}';
      final pluginDir = Directory(p.normalize(fallback));
      if (pluginDir.existsSync()) {
        if (plugin.isSkill) {
          // Skill 能力卸载：只删 skill/ 子目录，避免误删同目录其他能力（module/agent/...）。
          final skillDir = Directory(p.join(pluginDir.path, 'skill'));
          if (skillDir.existsSync()) {
            skillDir.deleteSync(recursive: true);
          }
          // 目录被删空（纯 skill 插件）→ 连外层目录一起清掉。
          if (pluginDir.listSync().isEmpty) {
            pluginDir.deleteSync();
          }
        } else {
          pluginDir.deleteSync(recursive: true);
        }
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
            ],
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
          const SizedBox(height: 8),
          _buildTypeFilterChips(),
        ],
      ),
    );
  }

  /// 类型标签筛选条：全部 / 模块 / Agent / 数据源 / 配置 / 主题 / 技能。
  Widget _buildTypeFilterChips() {
    const filters = <(String, String)>[
      ('all', '全部'),
      ('module', '模块'),
      ('agent', 'Agent'),
      ('data-source', '数据源'),
      ('config', '配置'),
      ('theme', '主题'),
      ('skill', '技能'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (value, label) in filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: _typeFilter == value,
                onSelected: (_) => setState(() => _typeFilter = value),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
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
              _searchQuery.isEmpty && _typeFilter == 'all'
                  ? '暂无本地插件'
                  : '未找到匹配的插件',
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

    // 4. 扁平化：单个 ReorderableListView 承载「组头 + 组内插件」。
    //    关键修复：此前外层 RLV 嵌套内层 RLV，折叠时条件增删内层可滚动列表，
    //    触发 Sliver 布局反馈死循环（child._parent == this 断言、界面无响应）。
    //    扁平化后只有一个 Sliver 列表，折叠仅「不生成组内插件 item」，无嵌套滚动容器。
    final flat = <FlatItem>[];
    for (var gi = 0; gi < keys.length; gi++) {
      final label = keys[gi];
      flat.add(FlatItem.header(label, gi));
      if (!(config.groups[label]?.collapsed ?? false)) {
        for (final p in grouped[label]!) {
          flat.add(FlatItem.plugin(label, gi, p));
        }
      }
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
              onReorder: (oldIndex, newIndex) =>
                  _handleFlatReorder(flat, keys, grouped, oldIndex, newIndex),
              children: [
                for (var i = 0; i < flat.length; i++)
                  flat[i].isHeader
                      ? _GroupHeader(
                          key: ValueKey('h:${flat[i].label}'),
                          label: flat[i].label,
                          flatIndex: i,
                          count: grouped[flat[i].label]!.length,
                          groupConfig: config.groups[flat[i].label],
                          onToggleSidebarName: () => _toggleGroupNameInSidebar(
                              flat[i].label,
                              !(config.groups[flat[i].label]
                                      ?.showNameInSidebar ??
                                  true)),
                          onToggleCollapse: () => _toggleGroupCollapsed(
                              flat[i].label,
                              !(config.groups[flat[i].label]?.collapsed ??
                                  false)),
                        )
                      : ReorderableDragStartListener(
                          key: ValueKey(
                              'p:${flat[i].label}:${flat[i].plugin!.id}'),
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Tooltip(
                                  message: '拖动调整插件顺序',
                                  child: Icon(
                                    Icons.drag_indicator,
                                    size: 20,
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                Expanded(
                                  child: LocalPluginCard(
                                    plugin: flat[i].plugin!,
                                    state: states[flat[i].plugin!.id],
                                    onToggleEnabled: () =>
                                        _toggleEnabled(flat[i].plugin!),
                                    onToggleSidebar: () =>
                                        _toggleSidebar(flat[i].plugin!),
                                    onUninstall: () =>
                                        _uninstall(flat[i].plugin!),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 扁平列表拖拽重排：把单个 RLV 的 (oldIndex,newIndex) 映射回
  /// 「组间重排」或「组内重排」，保持与原嵌套实现一致的持久化语义。
  ///
  /// - 拖的是组头 → 在 [keys] 中把该组移到新位置（newIndex 之前最后一个组头之后）。
  /// - 拖的是插件 → 仅支持「同组」重排（跨组移动不在当前数据模型内，忽略以复原）；
  ///   按 flat 中该组插件子序列做 removeAt/insert，写入该组 sortOrder。
  void _handleFlatReorder(
    List<FlatItem> flat,
    List<String> keys,
    Map<String, List<PluginInfo>> grouped,
    int oldIndex,
    int newIndex,
  ) {
    final old = flat[oldIndex];
    if (old.isHeader) {
      final newKeys = computeGroupReorder(flat, keys, oldIndex, newIndex);
      ref.read(pluginStateProvider.notifier).setGroupOrderAll(newKeys);
      return;
    }
    final newIds = computePluginReorder(flat, grouped, oldIndex, newIndex);
    if (newIds != null) {
      ref
          .read(pluginStateProvider.notifier)
          .setPluginSortOrderAll(old.groupLabel, newIds);
    }
  }
}

/// 组头拖拽 → 新 keys 顺序（纯函数，便于单测）。
List<String> computeGroupReorder(
    List<FlatItem> flat, List<String> keys, int oldIndex, int newIndex) {
  final label = flat[oldIndex].label;
  final newKeys = List<String>.from(keys)..remove(label);
  var insertAt = 0;
  for (var i = 0; i < newIndex; i++) {
    if (i == oldIndex) continue;
    if (flat[i].isHeader) insertAt++;
  }
  newKeys.insert(insertAt, label);
  return newKeys;
}

/// 插件拖拽 → 新插件 id 顺序；跨组移动返回 null（调用方忽略以复原）。
List<String>? computePluginReorder(
  List<FlatItem> flat,
  Map<String, List<PluginInfo>> grouped,
  int oldIndex,
  int newIndex,
) {
  final gi = flat[oldIndex].groupLabel;
  String? targetLabel;
  for (var i = 0; i < newIndex; i++) {
    if (i == oldIndex) continue;
    if (flat[i].isHeader) targetLabel = flat[i].label;
  }
  if (targetLabel != gi) return null; // 跨组：忽略
  final ids = grouped[gi]!.map((p) => p.id).toList();
  final po = ids.indexOf(flat[oldIndex].plugin!.id);
  if (po < 0) return null;
  var pn = 0;
  for (var i = 0; i < newIndex; i++) {
    if (i == oldIndex) continue;
    if (!flat[i].isHeader && flat[i].groupLabel == gi) pn++;
  }
  final moved = ids.removeAt(po);
  ids.insert(pn, moved);
  return ids;
}

/// 扁平列表项：组头或组内插件。用于单个 ReorderableListView 的统一承载。
class FlatItem {
  FlatItem.header(this.label, this.groupIndex)
      : isHeader = true,
        plugin = null;
  FlatItem.plugin(this.label, this.groupIndex, this.plugin)
      : isHeader = false;

  final bool isHeader;
  final String label; // 组名（组头与组内插件共享）
  final int groupIndex;
  final PluginInfo? plugin;

  String get groupLabel => label;
}

/// 分组头：组间拖拽手柄 + 名称 + 折叠 + 侧边栏组名开关。
/// 仅作为扁平 RLV 的一个普通 item，不再内嵌可滚动列表。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    super.key,
    required this.label,
    required this.flatIndex,
    required this.count,
    required this.groupConfig,
    required this.onToggleSidebarName,
    required this.onToggleCollapse,
  });

  final String label;
  final int flatIndex; // 在扁平 RLV 中的真实 index（拖拽手柄用）
  final int count;
  final PluginGroupConfig? groupConfig;
  final VoidCallback onToggleSidebarName;
  final VoidCallback onToggleCollapse;

  bool get _showNameInSidebar => groupConfig?.showNameInSidebar ?? true;
  bool get _collapsed => groupConfig?.collapsed ?? false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(
        children: [
          // 组间拖拽手柄（触发扁平 RLV 的拖拽，index 为扁平位置）。
          ReorderableDragStartListener(
            index: flatIndex,
            child: Tooltip(
              message: '拖动调整分组顺序',
              child: Icon(Icons.drag_indicator,
                  size: 20,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.folder_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$label ($count)',
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
            icon: Icon(_collapsed ? Icons.expand_more : Icons.expand_less,
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
    );
  }
}
