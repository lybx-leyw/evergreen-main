/// Evergreen 2.0 应用入口——主题、路由、命令面板、数据自动刷新。
///
/// 支持两种运行模式：
/// - Widget 模式（默认）：MaterialApp.router + AppShell + go_router
/// - 文本模式（`--dart-define=EVERGREEN_TEXT_MODE=true`）：纯文本直输，Core 自证
///
/// 公开类：[EvergreenApp]
/// | 成员 | 说明 |
/// |------|------|
/// | `EvergreenApp()` | 根 Widget，根据编译常量选择模式 |
library;

import 'dart:async' show unawaited;

import 'package:evergreen_base/core/feedback/screenshot.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/app/app_mode.dart';
import 'package:evergreen_base/renderer/app/app_shell.dart';
import 'package:evergreen_base/renderer/app/command_palette.dart';
import 'package:evergreen_base/renderer/app/dev_mode_hub.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/scraper_bridge_registry.dart';
import 'package:evergreen_base/renderer/page/discovered_plugins_view.dart';
import 'package:evergreen_base/renderer/app/service/data_change_notification_service.dart';
import 'package:evergreen_base/renderer/app/service/providers/renderer_providers.dart';
import 'package:evergreen_base/renderer/app/service/theme/theme_provider.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/plugin_state_provider.dart';
import 'package:evergreen_base/renderer/module/module_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;


// ═══════ 导航键 ═══════

/// 根导航键（公开：供 ScraperBridgeServer 自动切换等跨层导航使用）。
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

// ═══════ 主题 ═══════

/// 当前主题模式（亮色 / 暗色 / 跟随系统）。
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// 亮色主题——从 [themeDescriptorProvider] 解析 app 层。
final lightThemeProvider = Provider<ThemeData>((ref) {
  final descriptor = ref.watch(themeDescriptorProvider);
  if (descriptor != null) {
    return buildAppThemeFromDescriptor(descriptor, brightness: Brightness.light);
  }
  return ThemeData(useMaterial3: true, brightness: Brightness.light);
});

/// 暗色主题——从 [themeDescriptorProvider] 解析 app 层（dark 变体）。
final darkThemeProvider = Provider<ThemeData>((ref) {
  final descriptor = ref.watch(themeDescriptorProvider);
  if (descriptor != null) {
    return buildAppThemeFromDescriptor(descriptor, brightness: Brightness.dark);
  }
  return ThemeData(useMaterial3: true, brightness: Brightness.dark);
});

Color _hex(String hex) {
  final s = hex.replaceFirst('#', '');
  final intVal = int.parse(
    s.length == 6 ? 'FF$s' : s,
    radix: 16,
  );
  return Color(intVal);
}

// ═══════ 路由 ═══════

/// 淡入过渡——所有路由复用此构建器。
Page<void> _fadePage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, _, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 200),
  );
}

/// 为 [ModuleRegistry] 中的所有模块生成 GoRoute 列表。
///
/// [pluginsDir] 为插件根目录，所有模块的工作目录均从该目录解析。
/// [v2Manifests] 为 V2 原始 JSON 映射（schemaVersion: "2.0"），
/// 用于 HTML 渲染模式。
List<GoRoute> _buildModuleRoutes(
  ModuleRegistry registry,
  String pluginsDir,
  Map<String, Map<String, dynamic>> v2Manifests,
) {
  final seen = <String>{};
  final routes = <GoRoute>[];
  final modules = registry.modules;
  debugPrint('[Router] registry has ${modules.length} modules');
  for (final m in modules) {
    debugPrint('[Router] module: id=${m.id} route=${m.route} pages=${m.pages.length}');
    final v2Json = v2Manifests[m.id];
    final renderMode = v2Json?['renderMode'] as String? ?? 'dart';

    final workingDir = p.join(pluginsDir, m.id) + p.separator;

    Widget modulePage(GoRouterState state) => EvergreenModulePage(
      descriptor: m,
      workingDirectory: workingDir,
      renderMode: renderMode,
      initialPrompt: state.uri.queryParameters['prompt'],
    );

    // 主路由
    if (m.route != null && m.route!.isNotEmpty && seen.add(m.route!)) {
      routes.add(GoRoute(
        path: m.route!,
        pageBuilder: (context, state) => _fadePage(modulePage(state), state),
      ));
    }
    // V2: secondary nav 路由（扁平，子路径）
    for (final s in m.nav.secondary) {
      if (seen.add(s.routePath)) {
        routes.add(GoRoute(
          path: s.routePath,
          pageBuilder: (context, state) => _fadePage(modulePage(state), state),
        ));
      }
    }
    // V2: page 子路由（扁平，CompositeView 解析 pageId 切 Tab）
    if (m.pages.isNotEmpty && m.route != null && m.route!.isNotEmpty) {
      for (final page in m.pages) {
        final pagePath = '${m.route!}/${page.id}';
        if (seen.add(pagePath)) {
          routes.add(GoRoute(
            path: pagePath,
            pageBuilder: (context, state) => _fadePage(modulePage(state), state),
          ));
        }
      }
    }
  }
  return routes;
}

/// GoRouter 提供者——从 [moduleRegistryProvider] 动态生成路由表。
final routerProvider = Provider<GoRouter>((ref) {
  final registry = ref.watch(moduleRegistryProvider);
  final pluginsDir = ref.watch(pluginsDirProvider);
  final v2Manifests = ref.watch(v2ManifestProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    // '/' 按模式重定向到默认视图（AI → /ai-assistant，开发者 → /dev-hub，
    // 插件 → 第一个可见插件）。深层链接（模块路由/命令面板）不受影响。
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (loc != '/') return null;
      final mode = ref.read(appModeProvider);
      final pluginStates = ref.read(pluginStateProvider).records;
      final target = defaultRouteForMode(
        mode: mode,
        registry: registry,
        pluginStates: pluginStates,
      );
      return target == null || target == '/' ? null : target;
    },
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          // 首页占位
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => _fadePage(
              const _HomePlaceholder(),
              state,
            ),
          ),
          // 开发者模式主区（三插件 IndexedStack + 深链 ?plugin=）
          GoRoute(
            path: '/dev-hub',
            pageBuilder: (context, state) => _fadePage(
              const DevModeHub(),
              state,
            ),
          ),
          // M6-0 插件发现页（消费远程 registry，自动列出可发现插件）
          GoRoute(
            path: '/discover',
            pageBuilder: (context, state) => _fadePage(
              DiscoveredPluginsView(),
              state,
            ),
          ),
          // Registry 驱动：所有模块路由
          ..._buildModuleRoutes(registry, pluginsDir, v2Manifests),

        ],
      ),
    ],
  );
});

// ═══════ EvergreenApp ═══════

/// 根 MaterialApp——主题、路由、键盘快捷键。
class EvergreenApp extends ConsumerStatefulWidget {
  const EvergreenApp({super.key});

  @override
  ConsumerState<EvergreenApp> createState() => _EvergreenAppState();
}

class _EvergreenAppState extends ConsumerState<EvergreenApp> {
  @override
  void initState() {
    super.initState();
    // 启动数据自动刷新 + 数据变更通知（后台循环刷新发现变化 → 系统通知）
    Future.microtask(() {
      try {
        final orchestrator = ref.read(dataOrchestratorProvider);
        orchestrator.startAutoRefresh();
        DataChangeNotificationService.instance.listenTo(orchestrator);
        // 异步初始化通知渠道/权限，不阻塞 UI
        unawaited(DataChangeNotificationService.instance.ensureInitialized());
      } catch (_) {
        // dataOrchestratorProvider 未注入时静默忽略
      }
    });
    // B3：注入 ScraperBridgeServer 的自动切换回调。
    // DSH RPC 到达但 scraper WebView 未挂载时，切到开发者模式的 scraper 插件。
    _injectScraperActivate();
  }

  void _injectScraperActivate() {
    final server = scraperBridgeRegistry.server;
    if (server == null || server.activateScraper != null) return;
    server.activateScraper = () async {
      final scraperIndex = kDevPluginIds.indexOf('scraper');
      ref.read(devHubIndexProvider.notifier).state =
          scraperIndex < 0 ? 0 : scraperIndex;
      ref.read(appModeProvider.notifier).state = AppMode.developer;
      // 导航到开发者模式主区（scraper 插件会经 devHubIndexProvider 激活）。
      ref.read(routerProvider).go('/dev-hub');
    };
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final theme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);
    final themeMode = ref.watch(themeModeProvider);
    // 激活 RenderTokens 响应链：主题切换时执行 applyTheme，
    // 让所有消费 RenderTokens.colors 的组件随主题换色（此前无人 watch，静态色板永不更新）。
    ref.watch(renderTokensProvider);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.keyK, LogicalKeyboardKey.controlLeft):
            const _CommandPaletteIntent(),
        LogicalKeySet(LogicalKeyboardKey.keyK, LogicalKeyboardKey.controlRight):
            const _CommandPaletteIntent(),
        LogicalKeySet(LogicalKeyboardKey.comma, LogicalKeyboardKey.controlLeft):
            const _SettingsIntent(),
        LogicalKeySet(LogicalKeyboardKey.comma, LogicalKeyboardKey.controlRight):
            const _SettingsIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _CommandPaletteIntent: CallbackAction<_CommandPaletteIntent>(
            onInvoke: (_) => _showCommandPalette(context),
          ),
          _SettingsIntent: CallbackAction<_SettingsIntent>(
            onInvoke: (_) {
              GoRouter.of(context).go('/settings');
              return null;
            },
          ),
        },
        child: RepaintBoundary(
          key: screenshotKey,
          child: MaterialApp.router(
            title: 'Evergreen 多工具集成版',
            debugShowCheckedModeBanner: false,
            theme: theme,
            darkTheme: darkTheme,
            themeMode: themeMode,
            routerConfig: router,
          ),
        ),
      ),
    );
  }

  void _showCommandPalette(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        CommandPalette.show(context);
      }
    });
  }
}

// ═══════ 键盘快捷键 Intent ═══════

class _CommandPaletteIntent extends Intent {
  const _CommandPaletteIntent();
}

class _SettingsIntent extends Intent {
  const _SettingsIntent();
}

// ═══════ _HomePlaceholder ═══════

/// 首页占位——无模块注册 `/` 路由时显示欢迎页。
class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Evergreen',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '通过 ProviderScope.override 注入模块以开始使用',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
