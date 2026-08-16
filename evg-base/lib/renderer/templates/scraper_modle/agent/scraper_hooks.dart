/// ScraperHooks — 爬虫 Agent 的工具钩子（L2 前置审查 + L4 结果摘要）。
///
/// L2 preToolUse：
/// - `run_terminal_command` → 命令黑白名单（命中黑名单 block，回灌拒绝消息）
/// - `run_python_scraper` → lintScraperCode（violation block；warning 放行 + 写 workflow guardFlags）
/// - `save_credential` → validateCredentialArgs（非法 block）
/// - `export_and_register_scraper` → G6 注册前强制 lint（violation / 假数据未清除 → block）
/// - **探索模式（Phase 4 · D9）**：接入 [exploreWorkflow] 后按阶段强制工具白名单；
///   `navigate_get` URL 守卫预检；`build_selected_source` lint；
///   `register_batch` 假数据未清除 → block
///
/// L4 postToolUse / postToolUseFailure：结果摘要（行数/字节数/前 200 字符）→ TraceBuffer。
library scraper_hooks;

import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/renderer/components/shared/trace/agent_trace_recorder.dart';

import '../explore/explore_workflow.dart';
import '../workflow/scraper_guard.dart';
import '../workflow/scraper_workflow.dart';

/// 爬虫 Agent 工具钩子。
class ScraperHooks implements agent.ToolHooks {
  /// 工作流（读 guardFlags / 日志 URL 集合）。
  final ScraperWorkflow workflow;

  /// 可选的 Trace 缓冲（Phase 3 接入；Phase 1 可空）。
  final TraceBuffer? traceBuffer;

  /// 探索模式工作流（Phase 4；非空 = 探索画板，启用阶段白名单等探索约束）。
  final ExploreWorkflow? exploreWorkflow;

  ScraperHooks({
    required this.workflow,
    this.traceBuffer,
    this.exploreWorkflow,
  });

  @override
  String get match => '';

  @override
  Future<(bool block, String message)> preToolUse(
      String name, Map<String, dynamic> args) async {
    // ── Phase 4 探索模式：阶段工具白名单（D9 不同 harness 约束）──
    final ew = exploreWorkflow;
    if (ew != null) {
      if (!exploreToolAllowedForPhase(name, ew.phase)) {
        return (true, blockedExploreToolMessage(name, ew.phase));
      }
    }

    switch (name) {
      case 'navigate_get':
        // GET-only 导航守卫预检（同域/协议；上限/节流由工具内 recordNavigation 判定）
        final url = args['url'] as String? ?? '';
        final err = validateExploreUrl(url, baseHost: ew?.baseHost);
        if (err != null) {
          return (true, '[error: 探索导航被守卫拒绝: $err'
              '（仅允许 http/https GET、同域）]');
        }
        return (false, '');

      case 'build_selected_source':
        // 逐源构建前 lint（violation block；假数据 warning 放行 + guardFlags，
        // register_batch 时强制清除，A5 语义与定向模式一致）
        final code = args['code'] as String? ?? '';
        final urls = workflow.logs
            .map((l) => l.url)
            .where((u) => u.startsWith('http'))
            .toSet();
        final result = lintScraperCode(code, capturedUrls: urls);
        if (result.hasViolations) {
          return (true, '[error: 代码审查未通过]\n${result.toMessage()}');
        }
        if (result.suspectedFakeData) {
          workflow.setGuardFlag(GuardFlags.suspectedFakeData);
        } else if (workflow.suspectedFakeData) {
          // A5 语义：修正为真实抓取后自动清除标记
          workflow.clearGuardFlag(GuardFlags.suspectedFakeData);
        }
        return (false, '');

      case 'register_batch':
        // G6 语义：假数据未清除 → 拒绝批量注册
        if (workflow.suspectedFakeData) {
          return (true, '[error: 检测到疑似假数据未澄清/未修正，拒绝批量注册。'
              '请用 build_selected_source 修正为真实抓取后重试]');
        }
        return (false, '');

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
