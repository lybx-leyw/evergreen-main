import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/teachers_screen.dart';

class TeachersModule extends FeatureModule {
  @override String get id => 'teachers';
  @override String get name => '查老师';
  @override IconData get icon => Icons.person_search;
  @override SidebarSection get sidebarSection => SidebarSection.campus;
  @override int get sidebarOrder => 20;

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/teachers', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const TeachersScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
