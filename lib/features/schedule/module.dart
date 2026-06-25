import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/schedule_screen.dart';

class ScheduleModule extends FeatureModule {
  @override String get id => 'schedule';
  @override String get name => '课表导出';
  @override IconData get icon => Icons.calendar_month;
  @override SidebarSection get sidebarSection => SidebarSection.campus;
  @override int get sidebarOrder => 30;
  @override List<String> get dependsOn => ['courses'];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/schedule-export', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const ScheduleScreen(),
      transitionsBuilder: (c, a, _, ch) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
        child: FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: ch),
      ),
      transitionDuration: const Duration(milliseconds: 250),
    )),
  ];
}
