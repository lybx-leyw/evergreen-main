import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/plan_screen.dart';

class PlanModule extends FeatureModule {
  @override String get id => 'plan';
  @override String get name => '计划管理';
  @override IconData get icon => Icons.assignment;
  @override SidebarSection get sidebarSection => SidebarSection.learning;
  @override int get sidebarOrder => 40;
  @override List<String> get dependsOn => ['auth'];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/plan', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const PlanScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
