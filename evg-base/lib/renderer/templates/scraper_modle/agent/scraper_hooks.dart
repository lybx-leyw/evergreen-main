/// ScraperHooks — 爬虫 Agent 的工具钩子（L2 前置审查 + L4 结果摘要）。
///
/// L2 preToolUse：
/// - `run_terminal_command` → 命令黑白名单（命中黑名单 block，回灌拒绝消息）
/// - `run_python_scraper` → lintScraperCode（violation block；warning 放行 + 写 workflow guardFlags）
/// - `save_credential` → validateCredentialArgs（非法 block）
/// - `export_and_register_scraper` → G6 注册前强制 lint（violation / 假数据未清除 → block）
///
/// L4 postToolUse / postToolUseFailure：结果摘要（行数/字节数/前 200 字符）→ TraceBuffer。
library scraper_hooks;

import 'package:evergreen_base/core/agent/agent.dart' as agent;

import '../workflow/scraper_guard.dart';
import '../workflow/scraper_workflow.dart';

/// Trace 缓冲接口（Phase 1 定义，Phase 3 落地持久化视图）。
/// 记录三类事件供 Trace 消费（需求 C1）。
abstract class TraceBuffer {
  void recordTool(String tool, String argsSummary, String resultSummary,
      {bool isError = false});
  void recordThink(Duration elapsed);
  void recordReply(String preview, int byteCount);
}

/// 爬虫 Agent 工具钩子。
class ScraperHooks implements agent.ToolHooks {
  /// 工作流（读 guardFlags / 日志 URL 集合）。
  final ScraperWorkflow workflow;

  /// 可选的 Trace 缓冲（Phase 3 接入；Phase 1 可空）。
  final TraceBuffer? traceBuffer;

  ScraperHooks({required this.workflow, this.traceBuffer});

  @override
  String get match => '';

  @override
  Future<(bool block, String message)> preToolUse(
      String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'run_terminal_command':
        final cmd = args['command'] as String? ?? '';
        if (isTerminalCommandBlocked(cmd)) {
          return (true, blockedCommandMessage(cmd, '危险/走私命令'));
        }
        return (false, '');

      case 'run_python_scraper':
        final code = args['code'] as String? ?? '';
        final urls = workflow.logs
            .map((l) => l.url)
            .where((u) => u.startsWith('http'))
            .toSet();
        final result = lintScraperCode(code, capturedUrls: urls);
        if (result.hasViolations) {
          return (true,
              '[error: 代码审查未通过]\n${result.toMessage()}');
        }
        // warning 放行 + 写 guardFlags（G5 门禁用）
        if (result.suspectedFakeData) {
          workflow.setGuardFlag(GuardFlags.suspectedFakeData);
        } else if (workflow.suspectedFakeData) {
          // A5 语义：AI 修正为真实抓取后自动清除标记，G5 不再反复拦截
          workflow.clearGuardFlag(GuardFlags.suspectedFakeData);
        }
        return (false, '');

      case 'save_credential':
        final key = args['key'] as String? ?? '';
        final value = args['value'] as String? ?? '';
        final err = validateCredentialArgs(key, value);
        if (err != null) {
          return (true, blockedCredentialMessage(err));
        }
        return (false, '');

      case 'export_and_register_scraper':
        // G6：注册前强制 lint（读磁盘 scraper.py 由 _generatePlugin 负责；
        // 这里对 guardFlags 做兜底——假数据未清除拒绝注册）
        if (workflow.suspectedFakeData) {
          return (true, '[error: 检测到疑似假数据未澄清/未修正，拒绝注册。'
              '请先修正为真实抓取，或经用户确认放行]');
        }
        return (false, '');

      default:
        return (false, '');
    }
  }

  @override
  Future<void> postToolUse(
      String name, Map<String, dynamic> args, String result) async {
    _recordSummary(name, args, result, isError: false);
  }

  @override
  Future<void> postToolUseFailure(
      String name, Map<String, dynamic> args, String errorResult) async {
    _recordSummary(name, args, errorResult, isError: true);
  }

  /// 生成结果摘要（行数/字节数/前 200 字符）→ TraceBuffer。
  void _recordSummary(
      String name, Map<String, dynamic> args, String result,
      {required bool isError}) {
    final lines = result.split('\n').length;
    final bytes = result.length; // UTF-16 code units 近似字节数
    final preview = result.length > 200
        ? '${result.substring(0, 200)}…'
        : result;
    final argsSummary = _argsSummary(args);
    traceBuffer?.recordTool(name, argsSummary,
        '$lines 行 / $bytes 字符 / $preview',
        isError: isError);
  }

  static String _argsSummary(Map<String, dynamic> args) {
    final keys = ['command', 'code', 'data_name', 'key', 'path', 'plugin_name'];
    for (final k in keys) {
      final v = args[k];
      if (v is String && v.isNotEmpty) {
        return v.length > 60 ? '${v.substring(0, 60)}…' : v;
      }
    }
    final entries = args.entries.take(3)
        .map((e) => '${e.key}=${e.value}')
        .join(', ');
    return entries.isEmpty ? '(无参数)' : entries;
  }
}
