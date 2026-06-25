import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import '../../widgets/wip_screen.dart';

class AutosignModule extends FeatureModule {
  @override String get id => 'autosign';
  @override String get name => '自动签到';
  @override IconData get icon => Icons.auto_mode;
  @override SidebarSection get sidebarSection => SidebarSection.campus;
  @override int get sidebarOrder => 60;
  @override List<String> get dependsOn => ['auth'];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/autosign-wip', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const WipScreen(title: '自动签到'),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
