import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/rvpn_screen.dart';

class RvpnModule extends FeatureModule {
  @override String get id => 'rvpn';
  @override String get name => 'RVPN';
  @override IconData get icon => Icons.vpn_lock;
  @override SidebarSection get sidebarSection => SidebarSection.campus;
  @override int get sidebarOrder => 70;
  @override List<String> get dependsOn => ['auth'];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/rvpn', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const RvpnScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
