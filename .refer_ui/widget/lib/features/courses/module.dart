import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/courses_screen.dart';

/// 课程模块声明。
///
/// 依赖 auth（SSO 认证）和 zdbk（教务网数据）。
class CoursesModule extends FeatureModule {
  @override
  String get id => 'courses';

  @override
  String get name => '课程';

  @override
  IconData get icon => Icons.school;

  @override
  SidebarSection get sidebarSection => SidebarSection.learning;

  @override
  int get sidebarOrder => 10;

  @override
  List<String> get dependsOn => ['auth', 'zdbk'];

  @override
  List<RouteBase> buildRoutes() => [
        GoRoute(
          path: '/courses',
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: CoursesScreen(),
            transitionsBuilder: (context, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 200),
          ),
        ),
      ];
}
