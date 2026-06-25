import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/quick_connect_screen.dart';

class ConnectivityModule extends FeatureModule {
  @override String get id => 'connectivity';
  @override String get name => '数据状态';
  @override IconData get icon => Icons.wifi_tethering;
  @override SidebarSection get sidebarSection => SidebarSection.system;
  @override int get sidebarOrder => 80;

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/quick-connect', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const QuickConnectScreen(),
      transitionsBuilder: (c, a, _, ch) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
        child: FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: ch),
      ),
      transitionDuration: const Duration(milliseconds: 250),
    )),
  ];
}
