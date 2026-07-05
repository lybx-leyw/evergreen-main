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

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';
import 'package:evergreen_base/core/core_text_app.dart' as text_app;
import 'package:evergreen_base/main.dart' show textModeServerPorts;
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/widgets/app_shell.dart';
import 'package:evergreen_base/renderer/widgets/command_palette.dart';
import 'package:evergreen_base/renderer/shared/renderer_providers.dart';
import 'package:evergreen_base/renderer/shared/theme_provider.dart';
import 'package:evergreen_base/renderer/shared/module_page.dart';


/// 文本模式编译常量。
const _textMode = bool.hasEnvironment('EVERGREEN_TEXT_MODE');

// ═══════ 导航键 ═══════

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

// ═══════ 主题 ═══════

/// 当前主题模式（亮色 / 暗色 / 跟随系统）。
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// 亮色主题——从 [themeDescriptorProvider] 解析。
final lightThemeProvider = Provider<ThemeData>((ref) {
  final descriptor = ref.watch(themeDescriptorProvider);
  if (descriptor != null) return buildThemeFromDescriptor(descriptor);
  return ThemeData(useMaterial3: true, brightness: Brightness.light);
});

/// 暗色主题——从亮色语义 token 派生出暗色变体。
final darkThemeProvider = Provider<ThemeData>((ref) {
  final descriptor = ref.watch(themeDescriptorProvider);
  if (descriptor != null) return _buildDarkTheme(descriptor);
  return ThemeData(useMaterial3: true, brightness: Brightness.dark);
});

/// 从 [ThemeDescriptor] 构建暗色 ThemeData。
ThemeData _buildDarkTheme(ThemeDescriptor descriptor) {
  final s = descriptor.semanticTokens;
  final colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _hex(s['primary'] ?? '#1677FF'),
    onPrimary: _hex(s['onPrimary'] ?? '#FFFFFF'),
    secondary: _hex(s['secondary'] ?? '#52C41A'),
    onSecondary: _hex(s['onSecondary'] ?? '#FFFFFF'),
    error: _hex(s['error'] ?? '#CF222E'),
    onError: _hex(s['onError'] ?? '#FFFFFF'),
    surface: _hex('#1A1D21'),
    onSurface: _hex('#E6E8EC'),
    outline: _hex('#3A3D42'),
    shadow: _hex('#000000'),
  );
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: _hex('#111316'),
  );
}

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
List<GoRoute> _buildModuleRoutes(ModuleRegistry registry, String pluginsDir) {
  final seen = <String>{};
  final routes = <GoRoute>[];
  final modules = registry.modules;
  debugPrint('[Router] registry has ${modules.length} modules');
  for (final m in modules) {
    debugPrint('[Router] module: id=${m.id} route=${m.route} ui=${m.ui}');
    final workingDir = p.join(pluginsDir, m.id) + p.separator;
    // 主路由
    if (m.route != null && m.route!.isNotEmpty && seen.add(m.route!)) {
      routes.add(GoRoute(
        path: m.route!,
        pageBuilder: (context, state) => _fadePage(
          EvergreenModulePage(descriptor: m, workingDirectory: workingDir),
          state,
        ),
      ));
    }
    // 子面板路由
    for (final p in m.layout.panels) {
      if (seen.add(p.path)) {
        routes.add(GoRoute(
          path: p.path,
          pageBuilder: (context, state) => _fadePage(
            EvergreenModulePage(descriptor: m, workingDirectory: workingDir),
            state,
          ),
        ));
      }
    }
    // 二级导航路由
    for (final s in m.secondaryNavs) {
      if (seen.add(s.routePath)) {
        routes.add(GoRoute(
          path: s.routePath,
          pageBuilder: (context, state) => _fadePage(
            EvergreenModulePage(descriptor: m, workingDirectory: workingDir),
            state,
          ),
        ));
      }
    }
    // composite 模式：为每个 page 生成子路由
    if (m.ui == 'composite' && m.route != null && m.route!.isNotEmpty) {
      for (final page in m.pages) {
        final pagePath = '${m.route!}/${page.id}';
        if (seen.add(pagePath)) {
          routes.add(GoRoute(
            path: pagePath,
            pageBuilder: (context, state) => _fadePage(
              EvergreenModulePage(descriptor: m, workingDirectory: workingDir),
              state,
            ),
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

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
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
          // Registry 驱动：所有模块路由
          ..._buildModuleRoutes(registry, pluginsDir),
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
    // 启动数据自动刷新
    Future.microtask(() {
      try {
        final orchestrator = ref.read(dataOrchestratorProvider);
        orchestrator.startAutoRefresh();
      } catch (_) {
        // dataOrchestratorProvider 未注入时静默忽略
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // ── 文本模式：Core 自证，不启动 Widget 渲染 ──
    if (_textMode) {
      stderr.writeln('[app] 文本模式启动，端口: $textModeServerPorts');
      return text_app.EvergreenTextApp(serverPorts: textModeServerPorts);
    }

    final router = ref.watch(routerProvider);
    final theme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);
    final themeMode = ref.watch(themeModeProvider);

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
        child: MaterialApp.router(
          title: 'Evergreen 多工具集成版',
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: darkTheme,
          themeMode: themeMode,
          routerConfig: router,
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
