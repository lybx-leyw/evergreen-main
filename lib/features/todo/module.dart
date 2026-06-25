import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'providers/todo_provider.dart';
import 'screens/todo_screen.dart';

class TodoModule extends FeatureModule {
  @override String get id => 'todo';
  @override String get name => '待办';
  @override IconData get icon => Icons.checklist;
  @override SidebarSection get sidebarSection => SidebarSection.learning;
  @override int get sidebarOrder => 30;
  @override List<String> get dependsOn => ['auth', 'zdbk', 'courses'];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/todo', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: TodoScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
