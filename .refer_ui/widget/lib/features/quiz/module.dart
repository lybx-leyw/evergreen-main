import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/quiz_screen.dart';

class QuizModule extends FeatureModule {
  @override String get id => 'quiz';
  @override String get name => '答题';
  @override IconData get icon => Icons.quiz;
  @override SidebarSection get sidebarSection => SidebarSection.aiTools;
  @override int get sidebarOrder => 70;

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/quiz', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const QuizScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
