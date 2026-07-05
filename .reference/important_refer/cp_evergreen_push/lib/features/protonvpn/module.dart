import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/registry/modules.dart';
import 'screens/protonvpn_screen.dart';

class ProtonVpnModule extends FeatureModule {
  @override
  String get id => 'protonvpn';

  @override
  String get name => 'ProtonVPN';

  @override
  IconData get icon => Icons.shield;

  @override
  SidebarSection get sidebarSection => SidebarSection.campus;

  @override
  int get sidebarOrder => 71;

  @override
  List<String> get dependsOn => ['auth'];

  @override
  List<RouteBase> buildRoutes() => [
        GoRoute(
          path: '/protonvpn',
          pageBuilder: (c, s) => CustomTransitionPage<void>(
            key: s.pageKey,
            child: const ProtonVpnScreen(),
            transitionsBuilder: (c, a, _, ch) =>
                FadeTransition(opacity: a, child: ch),
            transitionDuration: const Duration(milliseconds: 200),
          ),
        ),
      ];
}
