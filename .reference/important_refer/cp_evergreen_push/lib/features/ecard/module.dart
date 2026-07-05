import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/ecard_screen.dart';

class EcardModule extends FeatureModule {
  @override String get id => 'ecard';
  @override String get name => '一卡通';
  @override IconData get icon => Icons.credit_card;
  @override SidebarSection get sidebarSection => SidebarSection.campus;
  @override int get sidebarOrder => 50;
  @override List<String> get dependsOn => ['auth'];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/ecard', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const EcardScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
