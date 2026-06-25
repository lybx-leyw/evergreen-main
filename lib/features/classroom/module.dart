import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/classroom_screen.dart';
// import 'screens/classroom_viewer_screen.dart';  // 需要 courseId 参数，保留在旧路由中

class ClassroomModule extends FeatureModule {
  @override String get id => 'classroom';
  @override String get name => '智云课堂';
  @override IconData get icon => Icons.video_library;
  @override SidebarSection get sidebarSection => SidebarSection.aiTools;
  @override int get sidebarOrder => 50;
  @override List<String> get dependsOn => ['auth'];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/classroom', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: ClassroomScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
