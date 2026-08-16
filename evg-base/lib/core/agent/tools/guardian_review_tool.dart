/// GuardianReviewTool — 显式 tool 审核（A13：AI 可主动调用 `guardian_review`）。
///
/// AI 主动调用时审查「当前 trace 摘要 + 产物」（证据由 [evidenceProvider]
/// 提供，通常来自 AI 面板拼装的关键 trace + scraper.py 摘要）。
/// 与 G5/G6 门禁自动审查（另调 API）互补，两者共用 [GuardianSession]。
///
/// 直接实现 [Tool]（非 SimpleTool）以保留实例字段 [session] / [evidenceProvider]
/// 访问能力（同 AskTool 模式）。
library;

import 'dart:convert';

import '../guardian/guardian.dart';
import '../tool.dart';

/// 显式审查工具。
class GuardianReviewTool extends Tool {
  /// 共享 Guardian 会话（与 G5/G6 门禁同一实例）。
  final GuardianSession session;

  /// 证据提供者：返回"关键 trace + 产物"摘要（AI 面板注入）。
  /// null = 无证据 → 按证据缺失审查（fail-closed）。
  final Future<String> Function()? evidenceProvider;

  GuardianReviewTool({required this.session, this.evidenceProvider});

  @override
  String get name => 'guardian_review';

  @override
  String get description =>
      '调用独立安全审查子代理（Guardian）审核当前工作：关键 trace（工具序列摘要）'
      '与产物（scraper.py / manifest / config）。返回 JSON 裁决 '
      '{outcome, risk_level, user_authorization, rationale}。'
      '适合在关键决策前主动自审（如注册前确认产物无假数据/无违规），'
      '也用于门禁被拒后复核。只读，不产生副作用。';

  @override
  Map<String, dynamic> get schema => const {
        'type': 'object',
        'properties': {
          'target': {
            'type': 'string',
            'description': '审查对象标识，如 "scraper.py" / "manifest" / "全部产物"。',
          },
          'description': {
            'type': 'string',
            'description': '你想让审查器重点确认的问题（可选）。',
          },
        },
        'required': ['target'],
      };

  /// 审查是只读的：无宿主副作用，永远不需要批准。
  @override
  bool get readOnly => true;

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final target = (args['target'] as String? ?? '').trim();
    final description = (args['description'] as String? ?? '').trim();
    if (target.isEmpty) return '[error: guardian_review 需要 target 参数]';

    final evidence = await evidenceProvider?.call() ?? '(无 trace/产物证据)';
    final request = GuardianReviewRequest(
      gate: 'tool',
      action: 'guardian_review($target)',
      arguments: jsonEncode({
        'target': target,
        if (description.isNotEmpty) 'description': description,
        'evidence': evidence,
      }),
    );

    final verdict = await session.review(request: request);
    final a = verdict.assessment;
    return jsonEncode({
      'outcome': a.outcome,
      'risk_level': a.riskLevel,
      'user_authorization': a.userAuthorization,
      'rationale': a.rationale,
      'failed': verdict.failed,
      if (!verdict.allow && verdict.reason.isNotEmpty)
        'reason': verdict.reason,
    });
  }
}
