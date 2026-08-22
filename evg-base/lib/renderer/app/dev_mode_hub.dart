/// 开发者模式主区——懒挂载 + Offstage 保持已访问插件状态。
///
/// 设计依据：《三模式视图重构_实施计划.md》（根目录）。
///
/// - 路由：/dev-hub（app.dart 注册）；可选深链 ?plugin=theme-creator|html-creator|scraper；
/// - 选中态：优先 query 参数（深链），否则 [devHubIndexProvider]
///   （左栏点击设置，会话内记忆上次选择）；
/// - 懒挂载：只构建当前选中的插件页；切换后已访问页面用 Offstage 保活，
///   避免进入开发者模式时一次性初始化全部 5 个插件（WebView/Agent/磁盘扫描等）；
/// - 安卓：scraper 槽位渲染占位页（数据爬取仅支持 Windows 版）；
/// - 插件未安装：槽位渲染「插件未安装」占位，不崩溃。
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/app/app_mode.dart';
import 'package:evergreen_base/renderer/app/service/providers/renderer_providers.dart';
import 'package:evergreen_base/renderer/module/module_page.dart';
import 'package:evergreen_base/core/module/module_registry.dart';

/// query 参数 → 插件索引。
const Map<String, int> _pluginIndex = {
  'theme-creator': 0,
  'html-creator': 1,
  'scraper': 2,
  'dsh': 3,
  'skill-creator': 4,
};

int? _indexFromQuery(String? plugin) =>
    (plugin == null || plugin.isEmpty) ? null : _pluginIndex[plugin];

/// 开发者模式主区。
class DevModeHub extends ConsumerStatefulWidget {
  const DevModeHub({super.key});

  @override
  ConsumerState<DevModeHub> createState() => _DevModeHubState();
}

class _DevModeHubState extends ConsumerState<DevModeHub> {
  /// 已访问过的插件索引。只有这些槽位才会被构建，Offstage 保活其 State。
  final Set<int> _visited = {};

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(moduleRegistryProvider);
    final pluginsDir = ref.watch(pluginsDirProvider);
    final v2 = ref.watch(v2ManifestProvider);
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    final queryPlugin = GoRouterState.of(context).uri.queryParameters['plugin'];
    // `??` 上 lub 推断会把 `int? ?? int` 保留为 `int?`，显式 `as int` 消除可空，
    // 使 `.clamp` 可在非空 int 上调用（queryIndex 为空时回退值恒为非空 int）。
    final selected = ((_indexFromQuery(queryPlugin) ??
                ref.watch(devHubIndexProvider)) as int)
        .clamp(0, kDevPluginIds.length - 1)
        .toInt();
    _visited.add(selected);

    final children = <Widget>[];
    for (int i = 0; i < kDevPluginIds.length; i++) {
      if (!_visited.contains(i)) continue;
      children.add(
        Positioned.fill(
          child: Offstage(
            offstage: i != selected,
            child: _buildPage(
              i,
              registry: registry,
              pluginsDir: pluginsDir,
              v2: v2,
              isAndroid: isAndroid,
            ),
          ),
        ),
      );
    }

    return Stack(children: children);
  }

  Widget _buildPage(
    int i, {
    required ModuleRegistry registry,
    required String pluginsDir,
    required Map<String, Map<String, dynamic>> v2,
    required bool isAndroid,
  }) {
    final id = kDevPluginIds[i];
    // 仅 Windows 插件（scraper / dsh / skill-creator 依赖 WebView2 或桌面能力）在安卓端渲染占位页。
    if (kWindowsOnlyPluginIds.contains(id) && isAndroid) {
      return _AndroidPlaceholder(label: _labelFor(id));
    }
    final descriptor = registry.findById(id);
    if (descriptor == null) {
      return _MissingPluginPage(pluginId: id);
    }
    return EvergreenModulePage(
      descriptor: descriptor,
      workingDirectory: p.join(pluginsDir, id) + p.separator,
      renderMode: v2[id]?['renderMode'] as String? ?? 'dart',
    );
  }
}

// ═══════ 占位页 ═══════

/// 插件 id → 显示标签（安卓占位页 / 弹窗共用）。
String _labelFor(String id) => switch (id) {
  'scraper' => '数据爬取',
  'dsh' => 'DSH',
  'skill-creator' => 'Skill 创作',
  _ => id,
};

/// 安卓端「仅 Windows 插件」占位页——提示使用 Windows 版。
class _AndroidPlaceholder extends StatelessWidget {
  final String label;
  const _AndroidPlaceholder({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.phonelink_lock_outlined, size: 64, color: scheme.primary),
          const SizedBox(height: 16),
          Text(
            '$label仅支持 Windows 版',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '安卓版暂未提供 $label，请使用 Windows 版 Evergreen。',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 插件未安装占位页——兜底不崩溃。
class _MissingPluginPage extends StatelessWidget {
  final String pluginId;
  const _MissingPluginPage({required this.pluginId});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.extension_off_outlined,
            size: 48,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('插件未安装', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            pluginId,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
