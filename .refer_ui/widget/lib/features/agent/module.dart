import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/registry/modules.dart';
import 'chat_screen.dart';

/// AI 助手模块声明。
///
/// Agent 运行时提供商——其他模块可依赖此模块以复用
/// agentRuntimeProvider 和 DeepSeekProvider。
class AgentModule extends FeatureModule {
  @override
  String get id => 'agent';

  @override
  String get name => 'AI 助手';

  @override
  IconData get icon => Icons.smart_toy;

  @override
  SidebarSection get sidebarSection => SidebarSection.aiTools;

  @override
  int get sidebarOrder => 20;

  @override
  List<RouteBase> buildRoutes() => [
        GoRoute(
          path: '/agent',
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: const AgentChatScreen(),
            transitionsBuilder: (context, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 200),
          ),
        ),
      ];
}
