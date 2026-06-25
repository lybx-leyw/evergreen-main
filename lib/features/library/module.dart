import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import '../../widgets/wip_screen.dart';

class LibraryModule extends FeatureModule {
  @override String get id => 'library';
  @override String get name => '图书馆';
  @override IconData get icon => Icons.local_library;
  @override SidebarSection get sidebarSection => SidebarSection.campus;
  @override int get sidebarOrder => 40;
  @override List<String> get dependsOn => ['auth'];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/library-wip', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const WipScreen(title: '图书馆'),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
