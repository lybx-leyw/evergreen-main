import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/course_offerings_screen.dart';
import 'screens/training_plan_screen.dart';
import 'screens/zdbk_notifications_screen.dart';

class ZdbkModule extends FeatureModule {
  @override String get id => 'zdbk';
  @override String get name => '教务通知';
  @override IconData get icon => Icons.campaign;
  @override SidebarSection get sidebarSection => SidebarSection.campus;
  @override int get sidebarOrder => 15;
  @override List<String> get dependsOn => ['auth'];

  @override
  List<NavEntryDecl> get secondaryNavs => [
    NavEntryDecl(icon: Icons.book, label: '开课情况', routePath: '/course-offerings',
      section: SidebarSection.learning, order: 20),
    NavEntryDecl(icon: Icons.account_tree, label: '培养方案', routePath: '/training-plans',
      section: SidebarSection.learning, order: 25),
  ];

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/zdbk-notifications', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const ZdbkNotificationsScreen(),
      transitionsBuilder: (c, a, _, ch) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
        child: FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: ch),
      ),
      transitionDuration: const Duration(milliseconds: 250),
    )),
    GoRoute(path: '/course-offerings', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const CourseOfferingsScreen(),
      transitionsBuilder: (c, a, _, ch) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
        child: FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: ch),
      ),
      transitionDuration: const Duration(milliseconds: 250),
    )),
    GoRoute(path: '/training-plans', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const TrainingPlanScreen(),
      transitionsBuilder: (c, a, _, ch) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
        child: FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: ch),
      ),
      transitionDuration: const Duration(milliseconds: 250),
    )),
  ];
}
