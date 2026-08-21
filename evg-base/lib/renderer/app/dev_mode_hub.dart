/// 开发者模式主区——IndexedStack 保持 主题创作 / 插件制作 / 数据爬取 三插件状态。
///
/// 设计依据：《三模式视图重构_实施计划.md》（根目录）。
///
/// - 路由：/dev-hub（app.dart 注册）；可选深链 ?plugin=theme-creator|html-creator|scraper；
/// - 选中态：优先 query 参数（深链），否则 [devHubIndexProvider]
///   （左栏点击设置，会话内记忆上次选择）；
/// - IndexedStack：三页同时挂载，切换不丢各插件状态；
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
class DevModeHub extends ConsumerWidget {
  const DevModeHub({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(moduleRegistryProvider);
    final pluginsDir = ref.watch(pluginsDirProvider);
    final v2 = ref.watch(v2ManifestProvider);
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    final queryPlugin =
        GoRouterState.of(context).uri.queryParameters['plugin'];
    final selected =
        _indexFromQuery(queryPlugin) ?? ref.watch(devHubIndexProvider);

    final pages = <Widget>[];
    for (int i = 0; i < kDevPluginIds.length; i++) {
      final id = kDevPluginIds[i];
      // 仅 Windows 插件（scraper / dsh / skill-creator 依赖 WebView2 或桌面能力）在安卓端渲染占位页。
      if (kWindowsOnlyPluginIds.contains(id) && isAndroid) {
        pages.add(_AndroidPlaceholder(label: _labelFor(id)));
        continue;
      }
      final descriptor = registry.findById(id);
      if (descriptor == null) {
        pages.add(_MissingPluginPage(pluginId: id));
        continue;
      }
      pages.add(EvergreenModulePage(
        descriptor: descriptor,
        workingDirectory: p.join(pluginsDir, id) + p.separator,
        renderMode: v2[id]?['renderMode'] as String? ?? 'dart',
      ));
    }

    return IndexedStack(
      index: (selected ?? 0).clamp(0, pages.length - 1).toInt(),
      children: pages,
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
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '安卓版暂未提供 $label，请使用 Windows 版 Evergreen。',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
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
          Icon(Icons.extension_off_outlined,
              size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('插件未安装', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            pluginId,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
