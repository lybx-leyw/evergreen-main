import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/notes_screen.dart';
import 'screens/tutor_screen.dart';

class TutorModule extends FeatureModule {
  @override String get id => 'tutor';
  @override String get name => 'AI 辅导';
  @override IconData get icon => Icons.psychology;
  @override SidebarSection get sidebarSection => SidebarSection.aiTools;
  @override int get sidebarOrder => 40;
  @override List<String> get dependsOn => ['classroom'];

  @override
  List<NavEntryDecl> get secondaryNavs => [
    NavEntryDecl(icon: Icons.auto_awesome, label: 'AI 笔记', routePath: '/notes',
      section: SidebarSection.aiTools, order: 10),
  ];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/notes', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: NotesScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
    GoRoute(path: '/tutor', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: TutorScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
