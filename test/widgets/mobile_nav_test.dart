import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_multi_tools/core/registry/modules.dart';
import 'package:evergreen_multi_tools/widgets/sidebar.dart';
import 'package:evergreen_multi_tools/modules.dart';

/// Build a ModuleRegistry with test modules matching the expected bottom nav.
ModuleRegistry _testRegistry() {
  final reg = ModuleRegistry();
  // All in same section so navFlat order = sidebarOrder
  reg.register(_TestNavModule(id: 'dashboard', name: '仪表盘', icon: Icons.dashboard,
    section: SidebarSection.system, order: 0, route: '/dashboard'));
  reg.register(_TestNavModule(id: 'courses', name: '课程', icon: Icons.school,
    section: SidebarSection.system, order: 1, route: '/courses'));
  reg.register(_TestNavModule(id: 'todo', name: '待办', icon: Icons.checklist,
    section: SidebarSection.system, order: 2, route: '/todo'));
  reg.register(_TestNavModule(id: 'notes', name: 'AI笔记', icon: Icons.auto_awesome,
    section: SidebarSection.system, order: 3, route: '/notes'));
  reg.register(_TestNavModule(id: 'agent', name: 'AI助手', icon: Icons.smart_toy,
    section: SidebarSection.system, order: 4, route: '/agent'));
  reg.seal();
  return reg;
}

/// Minimal test-only FeatureModule for navigation testing.
class _TestNavModule extends FeatureModule {
  final String _id, _name, _route;
  final IconData _icon;
  final SidebarSection _section;
  final int _order;
  _TestNavModule({required String id, required String name, required IconData icon,
    required SidebarSection section, required int order, required String route})
    : _id = id, _name = name, _icon = icon, _section = section, _order = order, _route = route;
  @override String get id => _id;
  @override String get name => _name;
  @override IconData get icon => _icon;
  @override SidebarSection get sidebarSection => _section;
  @override int get sidebarOrder => _order;
  @override List<RouteBase> buildRoutes() => [
    GoRoute(path: _route, builder: (_, __) => Text(_name)),
  ];
}

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

  final testReg = _testRegistry();
  final routes = <RouteBase>[
    ...testReg.buildRoutes(),
    // Extra routes for AppBar title testing
    GoRoute(path: '/course-offerings', builder: (_, __) => const Text('Offerings')),
    GoRoute(path: '/training-plans', builder: (_, __) => const Text('Plans')),
    GoRoute(path: '/plan', builder: (_, __) => const Text('Plan')),
    GoRoute(path: '/scores', builder: (_, __) => const Text('Scores')),
    GoRoute(path: '/exams', builder: (_, __) => const Text('Exams')),
    GoRoute(path: '/downloads', builder: (_, __) => const Text('Downloads')),
    GoRoute(path: '/classroom', builder: (_, __) => const Text('Classroom')),
    GoRoute(path: '/tutor', builder: (_, __) => const Text('Tutor')),
    GoRoute(path: '/zdbk-notifications', builder: (_, __) => const Text('Notifications')),
    GoRoute(path: '/teachers', builder: (_, __) => const Text('Teachers')),
    GoRoute(path: '/schedule-export', builder: (_, __) => const Text('Schedule')),
    GoRoute(path: '/quick-connect', builder: (_, __) => const Text('Connect')),
    GoRoute(path: '/settings', builder: (_, __) => const Text('Settings')),
    GoRoute(path: '/pintia-login', builder: (_, __) => const Text('PTA')),
  ];

  final router = GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: routes,
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        moduleRegistryProvider.overrideWith((ref) => testReg),
      ],
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
      expect(navBar.selectedIndex, 1); // courses is index 1 in our test registry
    });

    testWidgets('agent tab selects correctly', (tester) async {
      await _pumpMobileApp(tester, '/agent');

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 4); // agent is index 4 in our test registry
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
      expect(find.text('AI助手'), findsWidgets);
    });
  });

  group('Mobile shell — drawer content', () {
    testWidgets('drawer widget is configured on mobile', (tester) async {
      await _pumpMobileApp(tester, '/dashboard');

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.drawer, isNotNull);
    });

    testWidgets('drawer includes the app branding', (tester) async {
      await _pumpMobileApp(tester, '/dashboard');

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

      final testReg = _testRegistry();
      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          ShellRoute(
            builder: (_, __, child) => AppShell(child: child),
            routes: testReg.buildRoutes(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            moduleRegistryProvider.overrideWith((ref) => testReg),
          ],
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
