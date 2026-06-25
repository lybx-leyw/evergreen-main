import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/settings_screen.dart';

class SettingsModule extends FeatureModule {
  @override String get id => 'settings';
  @override String get name => '设置';
  @override IconData get icon => Icons.settings;
  @override SidebarSection get sidebarSection => SidebarSection.system;
  @override int get sidebarOrder => 90;
  @override List<String> get dependsOn => ['auth'];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/settings', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: SettingsScreen(),
      transitionsBuilder: (c, a, _, ch) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
        child: FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: ch),
      ),
      transitionDuration: const Duration(milliseconds: 250),
    )),
  ];
}
