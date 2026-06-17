import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_multi_tools/widgets/sidebar.dart';

/// Set the test surface to a mobile-sized screen.
void _setMobileScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
  });
}

/// Build a mobile-width app with the given route.
Future<void> _pumpMobileApp(WidgetTester tester, String location) async {
  _setMobileScreen(tester);

  final router = GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const Text('Dashboard')),
          GoRoute(path: '/courses', builder: (_, __) => const Text('Courses')),
          GoRoute(path: '/course-offerings', builder: (_, __) => const Text('Offerings')),
          GoRoute(path: '/training-plans', builder: (_, __) => const Text('Plans')),
          GoRoute(path: '/todo', builder: (_, __) => const Text('Todo')),
          GoRoute(path: '/plan', builder: (_, __) => const Text('Plan')),
          GoRoute(path: '/scores', builder: (_, __) => const Text('Scores')),
          GoRoute(path: '/exams', builder: (_, __) => const Text('Exams')),
          GoRoute(path: '/downloads', builder: (_, __) => const Text('Downloads')),
          GoRoute(path: '/notes', builder: (_, __) => const Text('Notes')),
          GoRoute(path: '/agent', builder: (_, __) => const Text('Agent')),
          GoRoute(path: '/classroom', builder: (_, __) => const Text('Classroom')),
          GoRoute(path: '/tutor', builder: (_, __) => const Text('Tutor')),
          GoRoute(path: '/zdbk-notifications', builder: (_, __) => const Text('Notifications')),
          GoRoute(path: '/teachers', builder: (_, __) => const Text('Teachers')),
          GoRoute(path: '/schedule-export', builder: (_, __) => const Text('Schedule')),
          GoRoute(path: '/quick-connect', builder: (_, __) => const Text('Connect')),
          GoRoute(path: '/settings', builder: (_, __) => const Text('Settings')),
          GoRoute(path: '/pintia-login', builder: (_, __) => const Text('PTA')),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Mobile shell — bottom navigation', () {
    testWidgets('shows 5 bottom nav destinations', (tester) async {
      await _pumpMobileApp(tester, '/dashboard');

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('仪表盘'), findsWidgets);
      expect(find.text('课程'), findsWidgets);
      expect(find.text('待办'), findsWidgets);
      expect(find.text('AI笔记'), findsWidgets);
      expect(find.text('AI助手'), findsWidgets);
    });

    testWidgets('bottom nav highlights active route', (tester) async {
      await _pumpMobileApp(tester, '/courses');

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 1);
    });

    testWidgets('agent tab selects correctly', (tester) async {
      await _pumpMobileApp(tester, '/agent');

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 4);
    });
  });

  group('Mobile shell — AppBar', () {
    testWidgets('shows AppBar with menu button', (tester) async {
      await _pumpMobileApp(tester, '/dashboard');

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);
    });

    testWidgets('AppBar title for common routes', (tester) async {
      await _pumpMobileApp(tester, '/courses');
      expect(find.text('课程'), findsWidgets); // AppBar title

      await _pumpMobileApp(tester, '/agent');
      expect(find.text('AI 助手'), findsWidgets);
    });
  });

  group('Mobile shell — drawer content', () {
    testWidgets('drawer widget is configured on mobile', (tester) async {
      await _pumpMobileApp(tester, '/dashboard');

      // The Drawer should be configured as part of the Scaffold
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.drawer, isNotNull);
    });

    testWidgets('drawer includes the app branding', (tester) async {
      await _pumpMobileApp(tester, '/dashboard');

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Evergreen 多工具集成版'), findsOneWidget);
    });

  });

  group('Mobile shell — desktop width', () {
    testWidgets('wide screen shows sidebar, not mobile nav', (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
      });

      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          ShellRoute(
            builder: (_, __, child) => AppShell(child: child),
            routes: [
              GoRoute(path: '/dashboard', builder: (_, __) => const Text('Dashboard')),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Mobile nav and AppBar should NOT be present on desktop
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(AppBar), findsNothing);
    });
  });
}
