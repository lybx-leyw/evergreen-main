import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import '../../widgets/wip_screen.dart';

class QuizModule extends FeatureModule {
  @override String get id => 'quiz';
  @override String get name => '答题';
  @override IconData get icon => Icons.quiz;
  @override SidebarSection get sidebarSection => SidebarSection.aiTools;
  @override int get sidebarOrder => 70;

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/quiz-wip', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const WipScreen(title: '答题'),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
