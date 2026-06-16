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
// import 'features/auth/services/auth_service.dart';  // 由 connection_manager 管理
import 'features/zdbk/providers/zdbk_provider.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/courses/screens/courses_screen.dart';
import 'features/courses/providers/courses_provider.dart';
import 'features/todo/screens/todo_screen.dart';
import 'features/todo/providers/todo_provider.dart';
import 'features/plan/screens/plan_screen.dart';
import 'features/plan/providers/plan_provider.dart';
import 'features/scores/screens/scores_screen.dart';
import 'features/exams/screens/exams_screen.dart';
import 'features/exams/providers/exams_provider.dart';
import 'features/classroom/providers/classroom_provider.dart';
import 'features/downloads/screens/downloads_screen.dart';
import 'features/teachers/screens/teachers_screen.dart';
import 'features/pintia/screens/pintia_login_screen.dart';
import 'features/zdbk/screens/course_offerings_screen.dart';
import 'features/zdbk/screens/zdbk_notifications_screen.dart';
import 'features/zdbk/providers/zdbk_notifications_provider.dart';
import 'features/zdbk/screens/training_plan_screen.dart';
import 'features/classroom/screens/classroom_screen.dart';
import 'features/agent/chat_screen.dart';
import 'features/tutor/screens/notes_screen.dart';
import 'features/tutor/screens/tutor_screen.dart';
import 'features/schedule/screens/schedule_screen.dart';
import 'features/connectivity/screens/quick_connect_screen.dart';
import 'widgets/dashboard.dart';
import 'widgets/sidebar.dart';
import 'widgets/command_palette.dart';

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
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => _fadePage(DashboardScreen(), state),
          ),
          GoRoute(
            path: '/courses',
            pageBuilder: (context, state) => _fadePage(CoursesScreen(), state),
          ),
          GoRoute(
            path: '/teachers',
            pageBuilder: (context, state) => _fadePage(const TeachersScreen(), state),
          ),
          GoRoute(
            path: '/zdbk-notifications',
            pageBuilder: (context, state) => _slidePage(const ZdbkNotificationsScreen(), state),
          ),
          GoRoute(
            path: '/course-offerings',
            pageBuilder: (context, state) => _slidePage(const CourseOfferingsScreen(), state),
          ),
          GoRoute(
            path: '/training-plans',
            pageBuilder: (context, state) => _slidePage(const TrainingPlanScreen(), state),
          ),
          GoRoute(
            path: '/todo',
            pageBuilder: (context, state) => _fadePage(TodoScreen(), state),
          ),
          GoRoute(
            path: '/plan',
            pageBuilder: (context, state) => _fadePage(const PlanScreen(), state),
          ),
          GoRoute(
            path: '/scores',
            pageBuilder: (context, state) => _fadePage(ScoresScreen(), state),
          ),
          GoRoute(
            path: '/exams',
            pageBuilder: (context, state) => _fadePage(ExamsScreen(), state),
          ),
          GoRoute(
            path: '/downloads',
            pageBuilder: (context, state) => _fadePage(DownloadsScreen(), state),
          ),
          GoRoute(
            path: '/notes',
            pageBuilder: (context, state) => _fadePage(NotesScreen(), state),
          ),
          GoRoute(
            path: '/agent',
            pageBuilder: (context, state) => _fadePage(const AgentChatScreen(), state),
          ),
          GoRoute(
            path: '/tutor',
            pageBuilder: (context, state) => _fadePage(TutorScreen(), state),
          ),
          GoRoute(
            path: '/wordpecker-wip',
            pageBuilder: (context, state) => _fadePage(const _WipScreen(title: '背词', message: 'FSRS 间隔重复背词·半成品'), state),
          ),
          // GoRoute(
          //   path: '/wordpecker',
          //   pageBuilder: (context, state) => _fadePage(WordPeckerScreen(), state),
          // ),
          // GoRoute(
          //   path: '/wordpecker-stats',
          //   pageBuilder: (context, state) => _fadePage(WordPeckerStatsScreen(), state),
          // ),
          GoRoute(
            path: '/classroom',
            pageBuilder: (context, state) => _fadePage(ClassroomScreen(), state),
          ),
          GoRoute(
            path: '/quiz-wip',
            pageBuilder: (context, state) => _fadePage(const _WipScreen(title: '答题'), state),
          ),
          // /quiz 路由保留供日后实现；classrooms API 已废弃
          // GoRoute(
          //   path: '/quiz',
          //   pageBuilder: (context, state) => _fadePage(QuizScreen(), state),
          // ),
          GoRoute(
            path: '/library-wip',
            pageBuilder: (context, state) => _fadePage(const _WipScreen(title: '图书馆'), state),
          ),
          // /library 路由保留供日后实现
          // GoRoute(
          //   path: '/library',
          //   pageBuilder: (context, state) => _fadePage(LibraryScreen(), state),
          // ),
          GoRoute(
            path: '/pintia-login',
            pageBuilder: (context, state) => _slidePage(const PintiaLoginScreen(), state),
          ),
          GoRoute(
            path: '/ecard-wip',
            pageBuilder: (context, state) => _fadePage(const _WipScreen(), state),
          ),
          // /ecard 路由保留供日后实现
          GoRoute(
            path: '/autosign-wip',
            pageBuilder: (context, state) => _fadePage(const _WipScreen(title: '自动签到'), state),
          ),
          GoRoute(
            path: '/rvpn-wip',
            pageBuilder: (context, state) => _fadePage(const _WipScreen(title: 'RVPN'), state),
          ),
          GoRoute(
            path: '/scheduler-wip',
            pageBuilder: (context, state) => _fadePage(const _WipScreen(title: '智能调度'), state),
          ),
          GoRoute(
            path: '/quick-connect',
            pageBuilder: (context, state) => _slidePage(const QuickConnectScreen(), state),
          ),
          GoRoute(
            path: '/schedule-export',
            pageBuilder: (context, state) => _slidePage(const ScheduleScreen(), state),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => _slidePage(SettingsScreen(), state),
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

/// 开发中占位页面。
class _WipScreen extends StatelessWidget {
  final String title;
  final String? message;
  const _WipScreen({this.title = '一卡通', this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction, size: 64, color: Colors.orange.shade300),
            const SizedBox(height: 16),
            const Text('功能开发中',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                message ??
                    '该功能因后端 API 变更暂不可用，待实现后恢复。',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
