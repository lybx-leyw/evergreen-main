/// 插件市场主槽位 —— 本地插件管理视图。
///
/// 功能：
/// - 扫描 `plugins/` 目录下所有 manifest.json
/// - 展示为 LocalPluginCard 列表
/// - 支持搜索/过滤
/// - 启用/停用、侧边栏可见性、卸载操作
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/providers.dart';
import 'nav_filter.dart';
import 'plugin_state_provider.dart';
import 'local_plugin_card.dart';
import 'marketplace_scan.dart';
import 'marketplace_plugin_info.dart';

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

      // 按名称排序
      descriptors.sort((a, b) => a.name.compareTo(b.name));

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
    final current = ref.read(pluginStateProvider)[plugin.id];
    final newEnabled = !(current?.enabled ?? true);
    // 经共享 Provider 写入，侧边栏（同 watch 本 Provider）会即时反映。
    ref.read(pluginStateProvider.notifier).setEnabled(plugin.id, newEnabled);
  }

  void _toggleSidebar(PluginInfo plugin) {
    final current = ref.read(pluginStateProvider)[plugin.id];
    final newVisible = !(current?.sidebarVisible ?? true);
    ref
        .read(pluginStateProvider.notifier)
        .setSidebarVisible(plugin.id, newVisible);
  }

  void _uninstall(PluginInfo plugin) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部搜索栏 + 计数
        _buildHeader(theme),
        // 内容区
        Expanded(child: _buildContent(theme)),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
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
          const SizedBox(width: 8),
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
    final states = ref.watch(pluginStateProvider);

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

    return RefreshIndicator(
      onRefresh: _loadPlugins,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final plugin = filtered[index];
          final state = states[plugin.id];
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
}
