/// Palace 情境自动采集器。
///
/// 从应用当前状态自动采集情境快照——用户在哪个页面、做什么任务、
/// 最近进行了哪些操作。由调用方（UI 层）通过 Riverpod ref 提供数据。
library;

import '../models/context_snapshot.dart';

/// 情境采集器的输入——调用方从 Riverpod + GoRouter 收集的数据。
class CapturerInput {
  /// 当前路由路径（如 "/agent"）。
  final String? currentRoute;

  /// 当前激活的待办标题（如果有）。
  final String? activeTodo;

  /// 最近的操作描述（最多 5 条）。
  final List<String> recentActions;

  /// 触发源描述。
  final String? triggerSource;

  const CapturerInput({
    this.currentRoute,
    this.activeTodo,
    this.recentActions = const [],
    this.triggerSource,
  });

  /// 是否完全没有可用信息。
  bool get isEmpty =>
      currentRoute == null &&
      activeTodo == null &&
      recentActions.isEmpty &&
      triggerSource == null;
}

/// 情境自动采集器——纯函数，无状态。
class ContextCapturer {
  /// 根据输入生成情境快照。
  ContextSnapshot capture(CapturerInput input) {
    // 从路由推断功能模块
    final feature = _inferFeature(input.currentRoute);

    // 修剪操作列表到 5 条
    final actions = input.recentActions.length > 5
        ? input.recentActions.sublist(0, 5)
        : input.recentActions;

    return ContextSnapshot(
      activeFeature: feature,
      activeTask: input.activeTodo,
      recentActions: actions,
      triggerSource: input.triggerSource,
    );
  }

  /// 从路由路径推断 Feature 名称。
  String? _inferFeature(String? route) {
    if (route == null || route.isEmpty) return null;
    // /agent -> agent, /courses -> courses, /scores -> scores, etc.
    final segment = route.startsWith('/') ? route.substring(1) : route;
    final slashIdx = segment.indexOf('/');
    final feature = slashIdx > 0 ? segment.substring(0, slashIdx) : segment;
    return feature.isEmpty ? null : feature;
  }
}
