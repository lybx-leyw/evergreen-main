import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'providers/exams_provider.dart';
import 'screens/exams_screen.dart';

class ExamsModule extends FeatureModule {
  @override String get id => 'exams';
  @override String get name => '考试';
  @override IconData get icon => Icons.event;
  @override SidebarSection get sidebarSection => SidebarSection.learning;
  @override int get sidebarOrder => 60;
  @override List<String> get dependsOn => ['auth', 'zdbk', 'courses'];
  @override ProviderListenable<int?>? get sidebarBadgeProvider => _badgeProvider;

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/exams', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: ExamsScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}

/// 即将到来的考试数目角标。
final _badgeProvider = Provider<int?>((ref) {
  return ref.watch(examsListProvider).when(
    data: (exams) {
      final now = DateTime.now();
      return exams.where((e) {
        if (e.startTime == null) return false;
        final start = e.startTime!;
        final diffDays = start.difference(now).inDays;
        return diffDays >= 0 && diffDays <= 21;
      }).length;
    },
    error: (_, __) => null,
    loading: () => null,
  );
});
