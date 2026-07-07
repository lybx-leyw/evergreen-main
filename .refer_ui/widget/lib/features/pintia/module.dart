import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/pintia_login_screen.dart';

class PintiaModule extends FeatureModule {
  @override String get id => 'pintia';
  @override String get name => 'PTA 编程题';
  @override IconData get icon => Icons.code;
  @override SidebarSection get sidebarSection => SidebarSection.campus;
  @override int get sidebarOrder => 10;
  @override List<String> get dependsOn => ['auth'];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/pintia-login', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const PintiaLoginScreen(),
      transitionsBuilder: (c, a, _, ch) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
        child: FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: ch),
      ),
      transitionDuration: const Duration(milliseconds: 250),
    )),
  ];
}
