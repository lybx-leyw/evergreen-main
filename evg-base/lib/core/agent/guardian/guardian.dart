/// AI Guardian — 独立 LLM 子代理审查（移植 reasonix/internal/guardian/）。
///
/// - [GuardianSession]：独立 LLM 会话 + 安全策略 prompt + `review()` → JSON 裁决
///   `{risk_level, user_authorization, outcome(allow|deny), rationale}`
/// - circuit breaker：连续 [maxConsecutiveDenials] 次 deny（或近 [recentWindow]
///   次中 ≥ [maxRecentDenials] 次）→ 中断提示，之后直接 fail-closed deny
/// - transcript 增量：游标只发新增条目，控制成本（对应 transcript.go）
/// - fail-closed：审查失败 / 超时 / 输出不可解析 → high-risk deny（[GuardianVerdict.failed]）
///
/// 纯 Dart（不引 Flutter），遵循 core 层 stub 隔离模式；LLM 调用走
/// [GuardianLlm] 抽象（生产用 [ProviderGuardianLlm]，测试注入假实现）。
library;

import 'dart:async';
import 'dart:convert';

import '../agent.dart' as agent;
import 'guardian_policy.dart' show buildGuardianPolicyPrompt;

// ═══════ 常量（对应 guardian.go） ═══════

/// 连续 deny 阈值：达到即触发 circuit breaker 中断。
const int maxConsecutiveDenials = 3;

/// 近窗口 deny 总数阈值。
const int maxRecentDenials = 10;

/// 近窗口长度。
const int recentWindow = 50;

/// 单次审查超时（对应 reviewTimeout = 30s）。
const Duration guardianReviewTimeout = Duration(seconds: 30);

/// transcript 预算（对应 transcript.go）。
const int maxTranscriptRecentEntries = 40;
const int maxEntryChars = 2000;
const int maxToolEntryChars = 1000;

// ═══════ GuardianAssessment ═══════

/// Guardian 结构化裁决（对应 guardian.Assessment）。
class GuardianAssessment {
  /// low | medium | high | critical
  final String riskLevel;

  /// unknown | low | medium | high
  final String userAuthorization;

  /// allow | deny
  final String outcome;

  final String rationale;

  const GuardianAssessment({
    required this.riskLevel,
    required this.userAuthorization,
    required this.outcome,
    required this.rationale,
  });

  bool get isAllow => outcome == 'allow';

  /// 解析模型原始输出（对应 ParseAssessment）：
  /// 直接 JSON 对象，或散文包裹中的第一个 `{...}`（首 `{` 到末 `}`）。
  /// 非 JSON → 抛 [FormatException]（触发 fail-closed）。
  factory GuardianAssessment.parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('guardian review produced empty output');
    }
    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) map = decoded;
    } catch (_) {
      map = null;
    }
    if (map == null) {
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          final decoded = jsonDecode(trimmed.substring(start, end + 1));
          if (decoded is Map<String, dynamic>) map = decoded;
        } catch (_) {
          map = null;
        }
      }
    }
    if (map == null) {
      throw FormatException(
          'guardian output is not valid JSON: ${_firstRunes(trimmed, 120)}');
    }
    return GuardianAssessment.fromJson(map);
  }

  /// 归一化 + 硬策略后门（对应 normalizeAssessment + enforcePolicyRules）。
  factory GuardianAssessment.fromJson(Map<String, dynamic> json) {
    // ParseOutcome：非 "allow" 一律 deny。
    final rawOutcome =
        (json['outcome']?.toString() ?? '').trim().toLowerCase();
    var outcome = rawOutcome == 'allow' ? 'allow' : 'deny';

    var risk = (json['risk_level']?.toString() ?? '').trim().toLowerCase();
    if (risk.isEmpty) risk = outcome == 'allow' ? 'low' : 'high';
    if (!_validRisk.contains(risk)) {
      throw FormatException('guardian output has unknown risk_level "$risk"');
    }

    var auth =
        (json['user_authorization']?.toString() ?? '').trim().toLowerCase();
    if (auth.isEmpty) auth = 'unknown';
    if (!_validAuth.contains(auth)) {
      throw FormatException(
          'guardian output has unknown user_authorization "$auth"');
    }

    var rationale = (json['rationale']?.toString() ?? '').trim();
    if (rationale.isEmpty) {
      rationale = outcome == 'allow'
          ? 'guardian review returned a low-risk allow decision'
          : 'guardian review returned a deny decision without a specific rationale';
    }

    // ── enforcePolicyRules（模型 prompt 无法覆盖的硬约束）──
    if (risk == 'critical' && outcome != 'deny') {
      outcome = 'deny';
      if (rationale ==
          'guardian review returned a low-risk allow decision') {
        rationale =
            'guardian review returned a critical-risk action with allow outcome — forced deny';
      }
    }
    if (risk == 'high' &&
        outcome == 'allow' &&
        auth != 'medium' &&
        auth != 'high') {
      outcome = 'deny';
      if (rationale ==
          'guardian review returned a low-risk allow decision') {
        rationale =
            'guardian review allowed a high-risk action without sufficient user authorization — forced deny';
      }
    }

    return GuardianAssessment(
      riskLevel: risk,
      userAuthorization: auth,
      outcome: outcome,
      rationale: rationale,
    );
  }

  static const Set<String> _validRisk = {
    'low',
    'medium',
    'high',
    'critical',
  };
  static const Set<String> _validAuth = {
    'unknown',
    'low',
    'medium',
    'high',
  };

  Map<String, dynamic> toJson() => {
        'risk_level': riskLevel,
        'user_authorization': userAuthorization,
        'outcome': outcome,
        'rationale': rationale,
      };

  @override
  String toString() => 'GuardianAssessment($outcome risk=$riskLevel auth=$userAuthorization)';
}

// ═══════ GuardianVerdict ═══════

/// 一次审查的裁决结果。
class GuardianVerdict {
  final bool allow;

  /// deny 原因（allow 时为空串）；circuit breaker 触发时为中断提示。
  final String reason;

  final GuardianAssessment assessment;

  /// true = 审查失败/不可解析/中断 → fail-closed deny。
  final bool failed;

  const GuardianVerdict({
    required this.allow,
    required this.reason,
    required this.assessment,
    this.failed = false,
  });
}

// ═══════ GuardianReviewRequest ═══════

/// 一次门禁 / 工具审查请求（G5 / G6 / guardian_review 共用）。
class GuardianReviewRequest {
  /// 触发点：'G5' | 'G6' | 'tool'。
  final String gate;

  /// 人类可读的动作描述。
  final String action;

  /// 证据（关键 trace 摘要 + 产物摘要等），非 JSON 亦可（作为散文拼接）。
  final String arguments;

  /// 规则守卫发现的违规记录（lint violation 等）。
  final List<String> violations;

  const GuardianReviewRequest({
    required this.gate,
    required this.action,
    this.arguments = '',
    this.violations = const [],
  });
}

// ═══════ Transcript ═══════

/// 一条简化 transcript 条目（对应 transcript.go TranscriptEntry）。
class TranscriptEntry {
  /// "user" | "assistant" | "tool"
  final String kind;
  final String text;

  const TranscriptEntry(this.kind, this.text);
}

/// 从 parent session 消息构建紧凑 transcript（对应 ExtractTranscript）。
List<TranscriptEntry> guardianExtractTranscript(List<agent.Message> messages) {
  final entries = <TranscriptEntry>[];
  for (final m in messages) {
    switch (m.role) {
      case agent.Role.system:
        continue; // guardian 有独立 system prompt
      case agent.Role.user:
        final t = m.content.trim();
        if (t.isNotEmpty) entries.add(TranscriptEntry('user', t));
        break;
      case agent.Role.assistant:
        final t = m.content.trim();
        if (t.isNotEmpty) entries.add(TranscriptEntry('assistant', t));
        break;
      case agent.Role.tool:
        final t = m.content.trim();
        if (t.isNotEmpty) entries.add(TranscriptEntry('tool', t));
        break;
    }
  }
  return entries;
}

/// 预算裁剪 + 渲染（对应 renderTranscript 的精简移植）：
/// 恒保留首/末 user 条目；从尾部补最近 [maxTranscriptRecentEntries] 条非 user 条目。
List<String> guardianRenderTranscript(List<TranscriptEntry> entries) {
  if (entries.isEmpty) return const ['<no retained transcript entries>'];

  final rendered = <String>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final cap = e.kind == 'tool' ? maxToolEntryChars : maxEntryChars;
    final text = _firstRunes(e.text, cap);
    rendered.add('[${i + 1}] ${e.kind}: $text');
  }

  final included = List<bool>.filled(entries.length, false);

  // 首/末 user 条目锚点。
  final userIdx = <int>[];
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].kind == 'user') userIdx.add(i);
  }
  if (userIdx.isNotEmpty) included[userIdx.first] = true;
  if (userIdx.length > 1 && userIdx.last != userIdx.first) {
    included[userIdx.last] = true;
  }

  // 尾部最近非 user 条目（含部分 user 兜底）。
  var recent = 0;
  for (var i = entries.length - 1; i >= 0 && recent < maxTranscriptRecentEntries; i--) {
    if (included[i]) continue;
    included[i] = true;
    if (entries[i].kind != 'user') recent++;
  }

  final lines = <String>[];
  for (var i = 0; i < rendered.length; i++) {
    if (included[i]) lines.add(rendered[i]);
  }
  final omitted = included.contains(false);
  if (omitted) lines.add('(Some conversation entries were omitted.)');
  return lines;
}

/// 完整/增量 transcript 块（对应 FormatTranscript / formatDelta）。
String guardianFormatTranscript(
  List<TranscriptEntry> entries, {
  required int from,
}) {
  final buf = StringBuffer();
  if (from == 0) {
    buf.writeln('>>> TRANSCRIPT START');
  } else {
    buf.writeln('>>> TRANSCRIPT DELTA START');
  }
  for (var i = from; i < entries.length; i++) {
    final e = entries[i];
    final cap = e.kind == 'tool' ? maxToolEntryChars : maxEntryChars;
    buf.writeln('[${i + 1}] ${e.kind}: ${_firstRunes(e.text, cap)}');
  }
  buf.writeln(from == 0 ? '>>> TRANSCRIPT END' : '>>> TRANSCRIPT DELTA END');
  return buf.toString();
}

// ═══════ LLM 抽象 ═══════

/// Guardian LLM 调用抽象（core 纯 Dart，测试注入假实现）。
abstract class GuardianLlm {
  /// 单次完整调用：system = 策略 prompt，user = transcript + 动作请求。
  /// 返回模型文本；出错抛异常（fail-closed）。
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
  });
}

/// [agent.Provider] 适配：流式 content 拼接。
class ProviderGuardianLlm implements GuardianLlm {
  final agent.Provider provider;

  ProviderGuardianLlm(this.provider);

  @override
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final messages = [
      agent.Message(role: agent.Role.system, content: systemPrompt),
      agent.Message(role: agent.Role.user, content: userPrompt),
    ];
    final buf = StringBuffer();
    String? error;
    await for (final e in provider.chat(messages: messages)) {
      switch (e.kind) {
        case agent.ProviderEventKind.content:
          if (e.text != null) buf.write(e.text);
          break;
        case agent.ProviderEventKind.error:
          error = e.error ?? 'provider error';
          break;
        default:
          break;
      }
    }
    if (error != null) {
      throw GuardianReviewException(error!);
    }
    return buf.toString();
  }
}

/// Guardian 审查失败异常（LLM 调用失败 / 超时等）。
class GuardianReviewException implements Exception {
  final String message;
  const GuardianReviewException(this.message);

  @override
  String toString() => 'GuardianReviewException: $message';
}

// ═══════ GuardianSession ═══════

/// 长寿命 Guardian 子代理会话（对应 guardian.go Session 的 Dart 移植）。
///
/// 复用策略 prompt 与 transcript 增量维持成本；串行化审查
/// （并发审查会交错 transcript 游标，调用方需自行保证串行）。
class GuardianSession {
  final GuardianLlm llm;
  final String policyPrompt;
  final int maxConsecutiveDenials;
  final int maxRecentDenials;
  final int recentWindow;
  final Duration timeout;

  /// 可选事件输出（Phase 3：GuardianResult 事件，UI 可观测）。
  /// 允许稍后绑定（assembly 创建后接线）。
  agent.EventSink? sink;

  /// 用户授权范围摘要（Scope Contract；探索模式开始后由调用方注入）。
  ///
  /// 非空时经 [buildGuardianPolicyPrompt] 追加到每次审查的 system prompt，
  /// 让 Guardian 以"持久化授权边界"为事实源评估 user_authorization。
  /// 默认 null → system prompt 保持原样，不改变既有行为。
  String? scopePromptSuffix;

  // ── circuit breaker 状态 ──
  int _consecutiveDenials = 0;
  final List<bool> _recentDenials = [];
  bool _interruptTriggered = false;

  // ── transcript 增量游标 ──
  int _cursorEntryCount = 0;
  int _reviewCount = 0;

  String? _lastCircuitBreakerReason;
  GuardianAssessment? _lastAssessment;

  GuardianSession({
    required this.llm,
    required this.policyPrompt,
    this.maxConsecutiveDenials = 3,
    this.maxRecentDenials = 10,
    this.recentWindow = 50,
    this.timeout = guardianReviewTimeout,
    this.sink,
  });

  bool get circuitBreakerTripped => _interruptTriggered;
  String? get lastCircuitBreakerReason => _lastCircuitBreakerReason;
  GuardianAssessment? get lastAssessment => _lastAssessment;
  int get reviewCount => _reviewCount;

  /// 执行一次审查。裁决语义与 Go 一致：
  /// 审查失败/超时/不可解析 → fail-closed deny（[GuardianVerdict.failed]=true）。
  ///
  /// [parentTranscript]：父会话消息（自动做增量裁剪）；null = 纯证据审查
  /// （如 guardian_review 显式工具调用）。
  Future<GuardianVerdict> review({
    required GuardianReviewRequest request,
    List<agent.Message>? parentTranscript,
  }) async {
    if (_interruptTriggered) {
      // circuit breaker 已触发：直接 deny（fail-closed）。
      final reason = _lastCircuitBreakerReason ??
          'Guardian 自动审查已中断，请先向用户报告并请求明确指示。';
      return GuardianVerdict(
        allow: false,
        reason: reason,
        assessment: GuardianAssessment(
          riskLevel: 'high',
          userAuthorization: 'unknown',
          outcome: 'deny',
          rationale: reason,
        ),
        failed: true,
      );
    }

    _reviewCount++;
    final entries = parentTranscript == null
        ? <TranscriptEntry>[]
        : guardianExtractTranscript(parentTranscript);
    // 增量：仅发新增条目；条目变少（会话重写）则重发全量。
    final needFull = entries.length < _cursorEntryCount;
    final from = needFull ? 0 : _cursorEntryCount;
    _cursorEntryCount = entries.length;

    final transcriptBlock = guardianFormatTranscript(entries, from: from);
    final userPrompt = '$transcriptBlock\n${_formatReviewRequest(request)}\n'
        'Assess this action now. Output ONLY the JSON verdict.';

    GuardianAssessment assessment;
    var failed = false;
    try {
      final systemPrompt = buildGuardianPolicyPrompt(policyPrompt, scopePromptSuffix);
      final raw = await llm
          .complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
          .timeout(timeout);
      assessment = GuardianAssessment.parse(raw);
    } catch (e) {
      failed = true;
      assessment = GuardianAssessment(
        riskLevel: 'high',
        userAuthorization: 'unknown',
        outcome: 'deny',
        rationale: 'guardian review failed: $e',
      );
    }
    _lastAssessment = assessment;

    _emitAssessment(request, assessment, failed: failed);

    if (assessment.isAllow) {
      _recordAllow();
      return GuardianVerdict(
          allow: true, reason: '', assessment: assessment, failed: failed);
    }

    final interrupted = _recordDenial();
    if (interrupted) {
      final reason =
          'Guardian 自动审查本轮已拒绝过多请求（连续 $_consecutiveDenials 次，'
          '近 $recentWindow 次中 ${_countRecentDenials()} 次）。'
          '请停止当前方案，向用户报告情况并请求明确指示后再继续。';
      _lastCircuitBreakerReason = reason;
      return GuardianVerdict(
          allow: false,
          reason: reason,
          assessment: assessment,
          failed: failed);
    }
    return GuardianVerdict(
      allow: false,
      reason: _denyReason(assessment),
      assessment: assessment,
      failed: failed,
    );
  }

  /// 每轮开始时复位 circuit breaker（对应 ResetTurn）。
  void resetTurn() {
    _consecutiveDenials = 0;
    _recentDenials.clear();
    _interruptTriggered = false;
    _lastCircuitBreakerReason = null;
  }

  // ── circuit breaker ──

  bool _recordDenial() {
    _consecutiveDenials++;
    _recentDenials.add(true);
    if (_recentDenials.length > recentWindow) {
      _recentDenials.removeRange(0, _recentDenials.length - recentWindow);
    }
    if (_consecutiveDenials >= maxConsecutiveDenials ||
        _countRecentDenials() >= maxRecentDenials) {
      if (!_interruptTriggered) {
        _interruptTriggered = true;
        return true;
      }
    }
    return false;
  }

  void _recordAllow() {
    _consecutiveDenials = 0;
    _recentDenials.add(false);
    if (_recentDenials.length > recentWindow) {
      _recentDenials.removeRange(0, _recentDenials.length - recentWindow);
    }
  }

  int _countRecentDenials() =>
      _recentDenials.where((d) => d).length;

  // ── 提示词拼装 ──

  String _formatReviewRequest(GuardianReviewRequest r) {
    final buf = StringBuffer()
      ..writeln('The agent has requested the following action:')
      ..writeln('Gate: ${r.gate}')
      ..writeln('Action: ${r.action}');
    if (r.arguments.isNotEmpty) {
      buf.writeln('Evidence/Arguments: ${_firstRunes(r.arguments, 2000)}');
    }
    if (r.violations.isNotEmpty) {
      buf.writeln('Guard violations: ${r.violations.join('; ')}');
    }
    return buf.toString();
  }

  String _denyReason(GuardianAssessment a) =>
      'guardian denied: risk=${a.riskLevel}, authorization=${a.userAuthorization}. ${a.rationale}';

  void _emitAssessment(
      GuardianReviewRequest request, GuardianAssessment a,
      {required bool failed}) {
    final sink = this.sink;
    if (sink == null) return;
    sink.emit(agent.AgentEvent.guardianAssessment(agent.GuardianResult(
      id: 'guardian-${DateTime.now().microsecondsSinceEpoch}',
      tool: request.gate,
      subject: _firstRunes(request.action, 120),
      outcome: a.outcome,
      riskLevel: a.riskLevel,
      userAuthorization: a.userAuthorization,
      rationale: a.rationale,
      failed: failed,
    )));
  }
}

// ═══════ 工具函数 ═══════

String _firstRunes(String s, int n) {
  if (s.length <= n) return s;
  return '${s.substring(0, n)}…';
}
