import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/wordpecker_screen.dart';
import 'screens/stats_screen.dart';

class WordpeckerModule extends FeatureModule {
  @override String get id => 'wordpecker';
  @override String get name => '背词';
  @override IconData get icon => Icons.spellcheck;
  @override SidebarSection get sidebarSection => SidebarSection.aiTools;
  @override int get sidebarOrder => 60;

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/wordpecker', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const WordPeckerScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
    GoRoute(path: '/wordpecker-stats', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const WordPeckerStatsScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
