import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/downloads_screen.dart';

class DownloadsModule extends FeatureModule {
  @override String get id => 'downloads';
  @override String get name => '下载';
  @override IconData get icon => Icons.download;
  @override SidebarSection get sidebarSection => SidebarSection.learning;
  @override int get sidebarOrder => 70;
  @override List<String> get dependsOn => ['auth'];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/downloads', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: DownloadsScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
