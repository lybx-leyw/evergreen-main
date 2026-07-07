import 'dart:io';

import 'package:flutter/services.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/config/theme.dart';
import 'core/connectivity/connection_manager.dart';
import 'core/config/providers.dart';
import 'core/log.dart';
import 'core/network/dio_client.dart';
import 'core/utils/auto_refresh.dart';
import 'core/services/background_refresher.dart';
import 'core/network/auth_interceptor.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/connectivity/providers/connectivity_provider.dart';
import 'features/zdbk/providers/zdbk_provider.dart';
import 'features/courses/providers/courses_provider.dart';
import 'features/todo/providers/todo_provider.dart';
import 'features/plan/providers/plan_provider.dart';
import 'features/exams/providers/exams_provider.dart';
import 'features/classroom/providers/classroom_provider.dart';
import 'features/zdbk/providers/zdbk_notifications_provider.dart';
import 'widgets/dashboard.dart';
import 'widgets/sidebar.dart';
import 'widgets/command_palette.dart';
import 'modules.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Fade-transition page builder for all routes.
///
/// Wraps [child] in a [CustomTransitionPage] with a 200ms fade transition.
/// Centralized so changing the transition style (e.g. slide + fade) requires
/// only one edit.
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

/// Slide-from-right + fade transition for drill-down pages.
Page<void> _slidePage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, _, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.05, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        )),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 250),
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final registry = ref.watch(moduleRegistryProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          // Registry 驱动：所有 24 个模块的路由自动在此注入
          ...registry.buildRoutes(),

          // Dashboard（lib/widgets/ 中的特殊组件，不属于 feature 模块）
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => _fadePage(DashboardScreen(), state),
          ),
        ],
      ),
    ],
  );
});

/// 当前选中的主题变体——启动时从 SharedPreferences 恢复，切换时自动持久化。
final themeVariantProvider =
    StateNotifierProvider<ThemeVariantNotifier, ThemeVariant>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  final saved = prefs.getString('theme_variant') ?? 'system';
  return ThemeVariantNotifier(
      ThemeVariantStorage.fromStorageKey(saved), prefs);
});

class ThemeVariantNotifier extends StateNotifier<ThemeVariant> {
  final SharedPreferences _prefs;
  ThemeVariantNotifier(super.initialState, this._prefs);

  void set(ThemeVariant variant) {
    state = variant;
    _prefs.setString('theme_variant', variant.toStorageKey());
  }
}

/// Root MaterialApp with theme and router
class EvergreenApp extends ConsumerStatefulWidget {
  const EvergreenApp({super.key});
  @override
  ConsumerState<EvergreenApp> createState() => _EvergreenAppState();
}

class _EvergreenAppState extends ConsumerState<EvergreenApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      initAutoRefresh(ref);
      // 启动后台静默刷新器（监听 auto-refresh tick，静默更新缓存）
      ref.read(backgroundRefresherProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final variant = ref.watch(themeVariantProvider);

    // 根据变体选择 theme / darkTheme / themeMode
    late final ThemeData theme;
    late final ThemeData darkTheme;
    late final ThemeMode themeMode;

    switch (variant) {
      case ThemeVariant.system:
        theme = AppTheme.lightTheme;
        darkTheme = AppTheme.darkTheme;
        themeMode = ThemeMode.system;
      case ThemeVariant.light:
        theme = AppTheme.lightTheme;
        darkTheme = AppTheme.darkTheme;
        themeMode = ThemeMode.light;
      case ThemeVariant.dark:
        theme = AppTheme.lightTheme;
        darkTheme = AppTheme.darkTheme;
        themeMode = ThemeMode.dark;
      case ThemeVariant.evergreen:
        theme = AppTheme.evergreenTheme;
        darkTheme = AppTheme.evergreenTheme;
        themeMode = ThemeMode.light;
      case ThemeVariant.liyu:
        theme = AppTheme.liyuTheme;
        darkTheme = AppTheme.liyuTheme;
        themeMode = ThemeMode.light;
      case ThemeVariant.highContrast:
        theme = AppTheme.highContrastTheme;
        darkTheme = AppTheme.highContrastTheme;
        themeMode = ThemeMode.light;
    }

    // Auto-login on first build: try to authenticate with saved credentials
    _triggerAutoLogin(ref);

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
        LogicalKeySet(LogicalKeyboardKey.f5): const _RefreshIntent(),
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
          _RefreshIntent: CallbackAction<_RefreshIntent>(
            onInvoke: (_) {
              _handleRefresh(ref);
              return null;
            },
          ),
        },
        child: MaterialApp.router(
          title: 'ZJU live better and better — Evergreen 多工具集成版',
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: darkTheme,
          themeMode: themeMode,
          routerConfig: router,
        ),
      ),
    );
  }

  void _handleRefresh(WidgetRef ref) {
    // 延迟到下一帧，避免在 action callback 中触发 rebuild
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(zdbkServiceInstanceProvider);
      ref.invalidate(zdbkExamsProvider);
      ref.invalidate(zdbkTranscriptProvider);
      ref.invalidate(zdbkEverythingProvider);
      ref.invalidate(zdbkTimetableProvider);
      ref.invalidate(zdbkNotificationsProvider);
      ref.invalidate(courseOfferingsProvider);
      ref.invalidate(pintiaServiceProvider);
      ref.invalidate(todoListProvider);
      ref.invalidate(planListProvider);
      ref.invalidate(examsListProvider);
      ref.invalidate(coursesListProvider);
      ref.invalidate(classroomCoursesProvider);
      ref.invalidate(connectionManagerProvider);
      ref.invalidate(connectivityCheckProvider);
      Log().info('Global manual refresh triggered');
    });
  }

  void _showCommandPalette(BuildContext context) {
    // 延迟避免在 Shortcuts action 回调中打开 dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        CommandPalette.show(context);
      }
    });
  }

  static bool _autoLoginStarted = false;



  void _triggerAutoLogin(WidgetRef ref) {
    if (_autoLoginStarted) return;
    _autoLoginStarted = true;

    Future.microtask(() async {
      final authNotifier = ref.read(authProvider.notifier);
      final loggedIn = await authNotifier.ensureAuth();
      if (!loggedIn || authNotifier.state.ssoCookie == null) return;

      // 注册重新登录后的全服务重连
      AuthInterceptor.onReconnected = () async {
        Log().info('Auth reconnected, re-checking all services');
        ref.invalidate(connectivityCheckProvider);
      };

      // SSO cookie 即将过期（< 10 分钟）→ 提前刷新
      final expiresAt = authNotifier.state.ssoExpiresAt;
      if (expiresAt != null &&
          expiresAt.difference(DateTime.now()).inMinutes < 10) {
        Log().info('SSO cookie expiring soon, refreshing login',
            data: {'expiresAt': expiresAt.toIso8601String()});
        await authNotifier.login();
      }

      final httpClient = ref.read(httpClientProvider);
      final cookieJar = ref.read(cookieJarProvider);
      final auth = ref.read(authProvider);
      final zdbkService = await ref.read(zdbkServiceInstanceProvider.future);

      // 统一连接管理（静默执行，不在启动时阻塞 UI）
      final manager = ConnectionManager(httpClient, cookieJar, auth, () => zdbkService);
      final results = await manager.checkAll();
      for (final r in results) {
        if (!r.ok) {
          Log().warn('AutoLogin ${r.service} failed',
              data: {'message': r.message, 'elapsed': r.elapsed.inMilliseconds});
        } else {
          Log().info('AutoLogin ${r.service} ok',
              data: {'elapsed': r.elapsed.inMilliseconds});
        }
      }

      // 首次启动——主动刷新所有数据模块
      ref.invalidate(zdbkEverythingProvider);
      ref.invalidate(todoListProvider);
      ref.invalidate(planListProvider);
      ref.invalidate(examsListProvider);
      ref.invalidate(coursesListProvider);
      ref.invalidate(classroomCoursesProvider);
      Log().info('Initial data refresh triggered');
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Keyboard shortcut intents
// ═══════════════════════════════════════════════════════════════════════════

class _CommandPaletteIntent extends Intent {
  const _CommandPaletteIntent();
}

class _SettingsIntent extends Intent {
  const _SettingsIntent();
}

class _RefreshIntent extends Intent {
  const _RefreshIntent();
}

/// Placeholder command palette — will be replaced by full implementation in Phase F.
class _PlaceholderCommandPalette extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('命令面板'),
      content: const Text('命令面板将在下一阶段实现。\n\n'
          '按 Ctrl+K 可快速搜索页面和功能。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

