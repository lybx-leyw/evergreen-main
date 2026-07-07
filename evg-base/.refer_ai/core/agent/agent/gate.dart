/// Gate 权限门控实现。
///
/// 对应 reasonix/internal/permission/。
/// 控制哪些工具调用需要用户批准，哪些可以自动执行。
library;

import 'agent.dart';

// ─── 权限策略 ─────────────────────────────────────────────

/// 工具权限等级。
enum PermissionLevel {
  /// 总是允许（只读工具、无副作用的查询）。
  always,

  /// 需要确认（写操作、可能产生副作用的工具）。
  confirm,

  /// 需要明确批准（危险操作、文件删除等）。
  approve,

  /// 总是拒绝（禁用的高危工具）。
  deny,
}

/// 权限规则——为特定工具指定权限等级。
class PermissionRule {
  final String toolName; // 支持通配符 * 和 ?
  final PermissionLevel level;
  final String reason; // deny 时的原因

  const PermissionRule({
    required this.toolName,
    required this.level,
    this.reason = '',
  });

  /// 规则是否匹配工具名。
  bool matches(String name) {
    if (toolName == '*') return true;
    if (toolName == name) return true;

    // 简单通配符匹配：结尾 *
    if (toolName.endsWith('*') &&
        name.startsWith(toolName.substring(0, toolName.length - 1))) {
      return true;
    }

    return false;
  }
}

// ─── 交互式门控 ────────────────────────────────────────────

/// 交互式权限门控——高危工具需要用户确认。
///
/// [pendingCallback] 在需要用户批准时触发。
/// 前端监听此回调，展示批准对话框。
class InteractiveGate extends Gate {
  final List<PermissionRule> _rules;

  /// 当需要用户批准时触发的回调。
  /// 返回 true = 批准，false = 拒绝。
  Future<bool> Function(String toolName, Map<String, dynamic> args, String reason)?
      pendingCallback;

  InteractiveGate({
    List<PermissionRule>? rules,
    this.pendingCallback,
  }) : _rules = rules != null ? List.of(rules) : List.of(_defaultRules);

  /// 默认权限规则集。
  static const List<PermissionRule> _defaultRules = [
    // —— 只读工具，总是允许 ——
    PermissionRule(toolName: 'get_courses', level: PermissionLevel.always),
    PermissionRule(toolName: 'get_scores', level: PermissionLevel.always),
    PermissionRule(toolName: 'get_todos', level: PermissionLevel.always),
    PermissionRule(toolName: 'get_exams', level: PermissionLevel.always),
    PermissionRule(toolName: 'get_classroom_videos', level: PermissionLevel.always),
    PermissionRule(toolName: 'ecard_balance', level: PermissionLevel.always),
    PermissionRule(toolName: 'search_materials', level: PermissionLevel.always),

    // —— 需要确认 ——
    PermissionRule(toolName: 'run_cli_tool', level: PermissionLevel.confirm),
    PermissionRule(toolName: 'run_skill', level: PermissionLevel.confirm),
    PermissionRule(toolName: 'remember', level: PermissionLevel.confirm),

    // —— 危险操作，需要明确批准 ——
    PermissionRule(toolName: 'write_file', level: PermissionLevel.approve),
    PermissionRule(toolName: 'bash', level: PermissionLevel.approve),

    // —— 禁止 ——
    PermissionRule(toolName: 'delete_file', level: PermissionLevel.deny, reason: '危险操作，当前不允许'),
    PermissionRule(toolName: 'delete_directory', level: PermissionLevel.deny, reason: '危险操作，当前不允许'),
  ];

  @override
  Future<(bool allow, String reason)> check(
      String toolName, Map<String, dynamic> args, bool readOnly) async {
    // 先查规则表
    for (final rule in _rules) {
      if (rule.matches(toolName)) {
        switch (rule.level) {
          case PermissionLevel.always:
            return (true, '');
          case PermissionLevel.deny:
            return (false, rule.reason.isNotEmpty
                ? rule.reason
                : '工具 "$toolName" 已被禁用');
          case PermissionLevel.approve:
          case PermissionLevel.confirm:
            // 需要用户交互
            break;
        }
      }
    }

    // 没有匹配规则：只读默认允许，写操作默认需要确认
    if (readOnly) return (true, '');

    // 需要用户批准
    if (pendingCallback != null) {
      final approved = await pendingCallback!(
        toolName,
        args,
        '工具 "$toolName" 需要你的确认',
      );
      if (approved) return (true, '');
      return (false, '用户拒绝了工具调用');
    }

    // 没有回调——默认拒绝写操作
    return (false, '没有权限门控回调，写操作被拒绝');
  }

  /// 添加自定义权限规则。
  void addRule(PermissionRule rule) {
    _rules.add(rule);
  }

  /// 为某个工具设置权限等级。
  void setLevel(String toolName, PermissionLevel level) {
    _rules.removeWhere((r) => r.toolName == toolName);
    _rules.add(PermissionRule(toolName: toolName, level: level));
  }
}

// ─── 无操作门控 ─────────────────────────────────────────────

/// 无操作门控——所有工具调用都允许。
class NoOpGate extends Gate {
  @override
  Future<(bool allow, String reason)> check(
      String toolName, Map<String, dynamic> args, bool readOnly) async {
    return (true, '');
  }
}
