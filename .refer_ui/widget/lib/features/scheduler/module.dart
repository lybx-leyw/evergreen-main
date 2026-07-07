import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/scheduler_screen.dart';

class SchedulerModule extends FeatureModule {
  @override String get id => 'scheduler';
  @override String get name => '智能调度';
  @override IconData get icon => Icons.schedule;
  @override SidebarSection get sidebarSection => SidebarSection.system;
  @override int get sidebarOrder => 70;
  @override List<String> get dependsOn => ['zdbk'];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/scheduler', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const SchedulerScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
