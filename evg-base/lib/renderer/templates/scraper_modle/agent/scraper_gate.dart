/// ScraperGate — 爬虫 Agent 的权限门控（L1）。
///
/// 基于 core 的 [InteractiveGate]，为 scraper 场景定义规则表：
/// - `run_terminal_command` → confirm（pendingCallback 内分级：黑名单硬拒 / 白名单自动 / 其余弹窗）
/// - `save_credential` → confirm（弹窗显示 key，value 打码）
/// - `run_python_scraper` / `export_and_register_scraper` → always（内容由 L2 lint / L3 产物校验管）
/// - 只读工具 → always
/// - 未知工具 → deny
library scraper_gate;

import 'package:evergreen_base/core/agent/agent.dart' as agent;

import '../workflow/scraper_guard.dart';

/// 爬虫场景权限门控。
class ScraperGate extends agent.InteractiveGate {
  /// 用户确认回调（UI 层注入）：返回 true=放行，false=拒绝。
  /// 参数：工具名、参数摘要（用于弹窗展示）、说明文本。
  final Future<bool> Function(String toolName, Map<String, dynamic> args, String subject)?
      onConfirm;

  ScraperGate({this.onConfirm}) : super(rules: const [
          // 只读工具 —— 总是允许
          agent.PermissionRule(toolName: 'get_request_logs', level: agent.PermissionLevel.always),
          agent.PermissionRule(toolName: 'read_workspace_file', level: agent.PermissionLevel.always),
          agent.PermissionRule(toolName: 'read_existing_credential', level: agent.PermissionLevel.always),
          agent.PermissionRule(toolName: 'read_request_snapshot', level: agent.PermissionLevel.always),
          agent.PermissionRule(toolName: 'ask', level: agent.PermissionLevel.always),
          agent.PermissionRule(toolName: 'list_skills', level: agent.PermissionLevel.always),
          // 只读审查工具（Phase 3 · A13 显式 tool 审核）
          agent.PermissionRule(toolName: 'guardian_review', level: agent.PermissionLevel.always),
          // 执行类 —— always（内容由 L2 lint 管）
          agent.PermissionRule(toolName: 'run_python_scraper', level: agent.PermissionLevel.always),
          agent.PermissionRule(toolName: 'export_and_register_scraper', level: agent.PermissionLevel.always),
          // 写凭证 —— 弹窗确认
          agent.PermissionRule(toolName: 'save_credential', level: agent.PermissionLevel.confirm),
          // 终端命令 —— confirm（pendingCallback 内再分级）
          agent.PermissionRule(toolName: 'run_terminal_command', level: agent.PermissionLevel.confirm),
          // 锁定产物根名 —— 面板内部状态回写，无副作用（名称合法性由工具内校验管）
          agent.PermissionRule(toolName: 'set_data_name', level: agent.PermissionLevel.always),
          // 门控一次性豁免 —— 请求用户放行（真正放行由弹窗确认，工具本身无副作用）
          agent.PermissionRule(toolName: 'guard_override', level: agent.PermissionLevel.always),
          // ── Phase 4 探索工具（阶段白名单由 ScraperHooks 依据 ExploreWorkflow 强制；
          //    navigate_get 的 GET-only/同域/节流守卫在工具内；build/register 由 L2 lint + G6 Guardian 管）──
          agent.PermissionRule(toolName: 'explore_page_links', level: agent.PermissionLevel.always),
          agent.PermissionRule(toolName: 'navigate_get', level: agent.PermissionLevel.always),
          agent.PermissionRule(toolName: 'list_captured_requests', level: agent.PermissionLevel.always),
          agent.PermissionRule(toolName: 'list_python_capabilities', level: agent.PermissionLevel.always),
          agent.PermissionRule(toolName: 'present_data_sources', level: agent.PermissionLevel.always),
          agent.PermissionRule(toolName: 'build_selected_source', level: agent.PermissionLevel.always),
          agent.PermissionRule(toolName: 'register_batch', level: agent.PermissionLevel.always),
        ]) {
    pendingCallback = _handlePending;
  }

  /// pendingCallback 实现：命令黑/白名单分级 + 凭证弹窗。
  Future<bool> _handlePending(
      String toolName, Map<String, dynamic> args, String reason) async {
    if (toolName == 'run_terminal_command') {
      final cmd = args['command'] as String? ?? '';
      final verdict = classifyTerminalCommand(cmd);
      switch (verdict) {
        case CommandVerdict.block:
          // 黑名单硬拒（不进弹窗）——返回 false + reason 已由 pre-hook 给出
          return false;
        case CommandVerdict.auto:
          return true; // 白名单自动放行
        case CommandVerdict.confirm:
          final approved = await onConfirm?.call(toolName, args,
              '执行终端命令: $cmd\n（不在自动放行白名单内，请确认）') ??
              false;
          return approved;
      }
    }
    if (toolName == 'save_credential') {
      final key = args['key'] as String? ?? '';
      final value = args['value'] as String? ?? '';
      final masked = value.length > 8
          ? '${value.substring(0, 4)}…${value.substring(value.length - 4)} (${value.length} chars)'
          : '***';
      final approved = await onConfirm?.call(toolName, args,
          '保存凭证: key=$key, value=$masked\n请确认 AI 保存的凭证正确。') ??
          false;
      return approved;
    }
    // 其它写工具 → 默认拒绝（安全兜底）
    return false;
  }
}
