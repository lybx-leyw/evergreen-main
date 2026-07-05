import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import '../../core/palace/palace.dart';
import 'providers/palace_event_store_provider.dart';
import 'screens/palace_screen.dart';

/// Palace（个人世界宫殿）模块声明。
///
/// 依赖 agent 模块（复用其 DeepSeekProvider 和 agentRuntimeProvider）。
/// 对外暴露 [palaceEventStoreProvider]，供 agent 模块写入事件。
class PalaceModule extends FeatureModule {
  @override
  String get id => 'palace';

  @override
  String get name => '宫殿';

  @override
  IconData get icon => Icons.fort;

  @override
  SidebarSection get sidebarSection => SidebarSection.system;

  @override
  int get sidebarOrder => 60;

  @override
  List<String> get dependsOn => ['agent'];

  // 路由
  @override
  List<RouteBase> buildRoutes() => [
        GoRoute(
          path: '/palace',
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: const PalaceScreen(),
            transitionsBuilder: (context, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 200),
          ),
        ),
      ];

  // 对外暴露
  @override
  List<ProviderBase<Object?>> get exports => [
        palaceEventStoreProvider,
      ];

  // 命令面板（自动生成，无需覆写 paletteItems）
}
