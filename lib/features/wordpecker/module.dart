import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import '../../widgets/wip_screen.dart';

class WordpeckerModule extends FeatureModule {
  @override String get id => 'wordpecker';
  @override String get name => '背词';
  @override IconData get icon => Icons.spellcheck;
  @override SidebarSection get sidebarSection => SidebarSection.aiTools;
  @override int get sidebarOrder => 60;

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/wordpecker-wip', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const WipScreen(title: '背词', message: 'FSRS 间隔重复背词·半成品'),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
