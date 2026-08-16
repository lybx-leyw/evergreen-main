/// ToolHooks 实现 — 对应 reasonix/internal/hook/ 的事件矩阵子集。
///
/// 事件位（接口定义见 agent/agent.dart 的 [ToolHooks]）：
/// - [ToolHooks.preToolUse]：工具调用前，可 block（返回 block=true + 消息回灌模型）
/// - [ToolHooks.postToolUse]：工具调用成功后
/// - [ToolHooks.postToolUseFailure]：工具调用失败（结果以 `[error:` 开头或含 ❌）后
///
/// match 语义：每个 hook 可声明匹配的工具名（正则，锚定）；"" 或 "*" 匹配全部。
library;

import 'agent.dart';

/// 判断 hook 是否匹配某工具名（锚定正则；"" 或 "*" 匹配全部）。
bool hookMatches(ToolHooks hooks, String toolName) {
  final m = hooks.match;
  if (m.isEmpty || m == '*') return true;
  try {
    return RegExp('^(?:$m)\$').hasMatch(toolName);
  } catch (_) {
    return false;
  }
}

// ═══════ LoggingHooks ═══════

/// 记录每次工具调用。
class LoggingHooks implements ToolHooks {
  final void Function(String message)? onLog;

  LoggingHooks({this.onLog});

  @override
  String get match => '';

  void _log(String msg) {
    onLog?.call(msg);
    // ignore: avoid_print
    print('[ToolHooks] $msg');
  }

  @override
  Future<(bool block, String message)> preToolUse(
      String name, Map<String, dynamic> args) async {
    _log('▶️ 工具调用: $name 参数=$args');
    return (false, ''); // 不阻止
  }

  @override
  Future<void> postToolUse(
      String name, Map<String, dynamic> args, String result) async {
    final preview = result.length > 100
        ? '${result.substring(0, 100)}...(${result.length} chars)'
        : result;
    _log('✅ 工具完成: $name → $preview');
  }

  @override
  Future<void> postToolUseFailure(
      String name, Map<String, dynamic> args, String errorResult) async {
    final preview = errorResult.length > 100
        ? '${errorResult.substring(0, 100)}...(${errorResult.length} chars)'
        : errorResult;
    _log('❌ 工具失败: $name → $preview');
  }
}

// ═══════ NoOpHooks ═══════

class NoOpHooks implements ToolHooks {
  @override
  String get match => '';

  @override
  Future<(bool block, String message)> preToolUse(
      String name, Map<String, dynamic> args) async {
    return (false, '');
  }

  @override
  Future<void> postToolUse(
      String name, Map<String, dynamic> args, String result) async {
    // 无操作
  }

  @override
  Future<void> postToolUseFailure(
      String name, Map<String, dynamic> args, String errorResult) async {
    // 无操作
  }
}

// ═══════ CompositeHooks ═══════

/// 组合多个 hooks 顺序执行：pre 任一 block 则整体 block（消息取第一个 block）；
/// post/failure 全部执行。match 匹配的工具才触发（CompositeHooks 自身 match
/// 由每个子 hook 自行判定，见 [hookMatches]）。
class CompositeHooks implements ToolHooks {
  final List<ToolHooks> _hooks;

  CompositeHooks(List<ToolHooks> hooks) : _hooks = List.of(hooks);

  @override
  String get match => '';

  @override
  Future<(bool block, String message)> preToolUse(
      String name, Map<String, dynamic> args) async {
    for (final h in _hooks) {
      if (!hookMatches(h, name)) continue;
      final (block, msg) = await h.preToolUse(name, args);
      if (block) return (true, msg);
    }
    return (false, '');
  }

  @override
  Future<void> postToolUse(
      String name, Map<String, dynamic> args, String result) async {
    for (final h in _hooks) {
      if (!hookMatches(h, name)) continue;
      await h.postToolUse(name, args, result);
    }
  }

  @override
  Future<void> postToolUseFailure(
      String name, Map<String, dynamic> args, String errorResult) async {
    for (final h in _hooks) {
      if (!hookMatches(h, name)) continue;
      await h.postToolUseFailure(name, args, errorResult);
    }
  }
}
