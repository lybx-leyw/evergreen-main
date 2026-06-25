import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'screens/translate_screen.dart';

class TranslateModule extends FeatureModule {
  @override String get id => 'translate';
  @override String get name => 'PDF 翻译';
  @override IconData get icon => Icons.translate;
  @override SidebarSection get sidebarSection => SidebarSection.aiTools;
  @override int get sidebarOrder => 30;

  @override
  List<RouteBase> buildRoutes() => [
    GoRoute(path: '/translate', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const TranslateScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
