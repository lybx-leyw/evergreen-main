/// Palace 情境快照模型。
///
/// 记录认知事件发生时的应用上下文——用户正在哪个功能模块、做什么任务、
/// 最近进行了哪些操作。内嵌在事件文件的 frontmatter 中，非独立存储。
library;

/// 捕捉认知事件时的情境快照。
class ContextSnapshot {
  /// 当时激活的功能模块名（如 "agent"、"courses"）。
  final String? activeFeature;

  /// 当时正在进行的任务描述（如"讨论工作习惯"）。
  final String? activeTask;

  /// 最近的用户操作列表（最多 5 条）。
  final List<String> recentActions;

  /// 触发源描述（如"Agent 对话中用户主动触发"）。
  final String? triggerSource;

  /// 扩展字段（供后续使用）。
  final Map<String, String>? extra;

  const ContextSnapshot({
    this.activeFeature,
    this.activeTask,
    this.recentActions = const [],
    this.triggerSource,
    this.extra,
  });

  /// 空快照（当无法采集情境时）。
  static const empty = ContextSnapshot();

  /// 是否有任何有意义的内容。
  bool get isEmpty =>
      activeFeature == null &&
      activeTask == null &&
      recentActions.isEmpty &&
      triggerSource == null &&
      (extra == null || extra!.isEmpty);

  /// 从 YAML 解析的 map 构造。
  factory ContextSnapshot.fromYaml(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) return empty;

    final feature = map['active_feature']?.toString();
    final task = map['active_task']?.toString();
    final List<String> actions;
    final rawActions = map['recent_actions'];
    if (rawActions is List) {
      actions = rawActions.map((a) => a.toString()).toList();
    } else {
      actions = [];
    }
    final trigger = map['trigger_source']?.toString();

    if (feature == 'null' && task == 'null' && trigger == 'null') return empty;

    return ContextSnapshot(
      activeFeature: feature == 'null' ? null : feature,
      activeTask: (task == 'null' || task == 'null')
          ? null
          : task?.replaceAll('"', ''),
      recentActions: actions.where((a) => a != 'null').toList(),
      triggerSource: trigger == 'null' ? null : trigger,
    );
  }

  /// 制为可序列化的 map。
  Map<String, dynamic> toYaml() {
    return {
      'active_feature': activeFeature,
      'active_task': activeTask,
      'recent_actions': recentActions,
      'trigger_source': triggerSource,
    };
  }

  @override
  String toString() =>
      'ContextSnapshot(feature=$activeFeature, task=$activeTask, '
      'actions=${recentActions.length})';
}
