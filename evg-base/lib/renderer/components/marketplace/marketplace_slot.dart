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

import '../../../core/module/module_descriptor.dart';
import '../../../providers.dart';
import '../document/plugin-designer/services/plugin_state_service.dart';
import 'local_plugin_card.dart';

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
  late final PluginStateService _stateService;

  List<ModuleDescriptor> _allPlugins = [];
  Map<String, PluginStateRecord> _states = {};
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
    _stateService = PluginStateService(_pluginsDir);
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

      final descriptors = <ModuleDescriptor>[];
      final entities = dir.listSync();
      debugPrint('[Marketplace] 目录存在: ${dir.path}，子实体数: ${entities.length}');
      int parsedCount = 0;
      int skippedNonDir = 0;
      int skippedHidden = 0;
      int skippedNoManifest = 0;
      int parseErrors = 0;

      for (final entity in entities) {
        if (entity is! Directory) {
          skippedNonDir++;
          continue;
        }
        // 跳过隐藏目录（仅检测目录名是否以 . 开头，不检测路径中的 .）
        if (p.basename(entity.path).startsWith('.')) {
          skippedHidden++;
          continue;
        }

        // 在子目录中查找 manifest.json（可能在 module/、agent/、data/ 下）
        final manifestPaths = <String>[
          '${entity.path}${Platform.pathSeparator}module${Platform.pathSeparator}manifest.json',
          '${entity.path}${Platform.pathSeparator}agent${Platform.pathSeparator}manifest.json',
          '${entity.path}${Platform.pathSeparator}data${Platform.pathSeparator}manifest.json',
          '${entity.path}${Platform.pathSeparator}manifest.json',
        ];

        bool found = false;
        for (final mp in manifestPaths) {
          final mf = File(mp);
          if (mf.existsSync()) {
            try {
              final jsonStr = mf.readAsStringSync();
              final json = jsonDecode(jsonStr) as Map<String, dynamic>;
              descriptors.add(ModuleDescriptor.fromJson(json));
              parsedCount++;
              found = true;
              break; // 只取第一个找到的 manifest
            } catch (e) {
              parseErrors++;
              // 跳过解析失败的 manifest
              debugPrint('[Marketplace] 解析失败: $mp — $e');
            }
          }
        }
        if (!found) skippedNoManifest++;
      }
      debugPrint(
          '[Marketplace] 扫描完成: 解析 $parsedCount 个, 非目录 $skippedNonDir, 隐藏 $skippedHidden, 无 manifest $skippedNoManifest, 解析失败 $parseErrors');

      // 按名称排序
      descriptors.sort((a, b) => a.name.compareTo(b.name));

      // 加载状态
      final states = _stateService.loadAll();

      setState(() {
        _allPlugins = descriptors;
        _states = states;
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

  List<ModuleDescriptor> get _filteredPlugins {
    if (_searchQuery.isEmpty) return _allPlugins;
    final q = _searchQuery.toLowerCase();
    return _allPlugins.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.id.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q);
    }).toList();
  }

  void _toggleEnabled(ModuleDescriptor plugin) {
    final current = _states[plugin.id];
    final newEnabled = !(current?.enabled ?? true);
    _stateService.setEnabled(plugin.id, newEnabled);
    setState(() {
      _states = _stateService.loadAll();
    });
  }

  void _toggleSidebar(ModuleDescriptor plugin) {
    final current = _states[plugin.id];
    final newVisible = !(current?.sidebarVisible ?? true);
    _stateService.setSidebarVisible(plugin.id, newVisible);
    setState(() {
      _states = _stateService.loadAll();
    });
  }

  void _uninstall(ModuleDescriptor plugin) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认卸载'),
        content: Text('确定要卸载插件「${plugin.name}」吗？\n\n此操作将删除插件目录中的所有文件，不可恢复。'),
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
  }

  void _doUninstall(ModuleDescriptor plugin) {
    try {
      final pluginDir = Directory('$_pluginsDir${Platform.pathSeparator}${plugin.id}');
      if (pluginDir.existsSync()) {
        pluginDir.deleteSync(recursive: true);
      }
      _stateService.remove(plugin.id);
      _loadPlugins();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('卸载失败: $e')),
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
          final state = _states[plugin.id];
          return LocalPluginCard(
            manifest: plugin,
            state: state,
            isModule: plugin.nav.sidebar?.section != null,
            onToggleEnabled: () => _toggleEnabled(plugin),
            onToggleSidebar: () => _toggleSidebar(plugin),
            onUninstall: () => _uninstall(plugin),
          );
        },
      ),
    );
  }
}
