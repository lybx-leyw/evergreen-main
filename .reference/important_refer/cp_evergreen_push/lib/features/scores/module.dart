import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/scores_screen.dart';

class ScoresModule extends FeatureModule {
  @override String get id => 'scores';
  @override String get name => '成绩';
  @override IconData get icon => Icons.grade;
  @override SidebarSection get sidebarSection => SidebarSection.learning;
  @override int get sidebarOrder => 50;
  @override List<String> get dependsOn => ['auth', 'zdbk'];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/scores', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: ScoresScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
