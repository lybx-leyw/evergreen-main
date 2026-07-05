/// Gate 权限门控 — 对应 reasonix/internal/permission/。
library;

import 'agent.dart';

// ═══════ PermissionLevel ═══════

/// 工具权限等级。
enum PermissionLevel { always, confirm, approve, deny }

// ═══════ PermissionRule ═══════

/// 为特定工具指定权限等级。
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

// ═══════ InteractiveGate ═══════

/// 交互式权限门控。 [pendingCallback] 触发时前端展示批准对话框。
class InteractiveGate extends Gate {
  final List<PermissionRule> _rules;

  /// 批准回调。返回 true = 批准，false = 拒绝。
  Future<bool> Function(String toolName, Map<String, dynamic> args, String reason)?
      pendingCallback;

  InteractiveGate({
    List<PermissionRule>? rules,
    this.pendingCallback,
  }) : _rules = rules != null ? List.of(rules) : List.of(_defaultRules);

  static const List<PermissionRule> _defaultRules = [
    // 只读 —— 总是允许
    PermissionRule(toolName: 'get_courses', level: PermissionLevel.always),
    PermissionRule(toolName: 'get_scores', level: PermissionLevel.always),
    PermissionRule(toolName: 'get_todos', level: PermissionLevel.always),
    PermissionRule(toolName: 'get_exams', level: PermissionLevel.always),
    PermissionRule(toolName: 'get_classroom_videos', level: PermissionLevel.always),
    PermissionRule(toolName: 'ecard_balance', level: PermissionLevel.always),
    PermissionRule(toolName: 'search_materials', level: PermissionLevel.always),

    // 需要确认
    PermissionRule(toolName: 'run_cli_tool', level: PermissionLevel.confirm),
    PermissionRule(toolName: 'run_skill', level: PermissionLevel.confirm),
    PermissionRule(toolName: 'remember', level: PermissionLevel.confirm),

    // 危险操作 —— 明确批准
    PermissionRule(toolName: 'write_file', level: PermissionLevel.approve),
    PermissionRule(toolName: 'bash', level: PermissionLevel.approve),

    // 禁止
    PermissionRule(toolName: 'delete_file', level: PermissionLevel.deny, reason: '危险操作'),
    PermissionRule(toolName: 'delete_directory', level: PermissionLevel.deny, reason: '危险操作'),
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

  void addRule(PermissionRule rule) {
    _rules.add(rule);
  }

  void setLevel(String toolName, PermissionLevel level) {
    _rules.removeWhere((r) => r.toolName == toolName);
    _rules.add(PermissionRule(toolName: toolName, level: level));
  }
}

// ═══════ NoOpGate ═══════

/// 所有工具调用都允许。
class NoOpGate extends Gate {
  @override
  Future<(bool allow, String reason)> check(
      String toolName, Map<String, dynamic> args, bool readOnly) async {
    return (true, '');
  }
}
