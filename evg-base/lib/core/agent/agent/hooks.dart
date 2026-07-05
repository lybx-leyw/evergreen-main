/// ToolHooks 实现 — 对应 reasonix/internal/hook/。
library;

import 'agent.dart';

// ═══════ LoggingHooks ═══════

/// 记录每次工具调用。
class LoggingHooks implements ToolHooks {
  final void Function(String message)? onLog;

  LoggingHooks({this.onLog});

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
}

// ═══════ NoOpHooks ═══════

class NoOpHooks implements ToolHooks {
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
}
