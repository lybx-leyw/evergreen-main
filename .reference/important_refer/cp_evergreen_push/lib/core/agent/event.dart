/// Agent 事件系统 — 完整对应 reasonix/internal/event/event.go。
///
/// Agent Loop 在运行过程中发射类型化的事件流，前端通过 EventSink 接收并渲染。
/// 不再有"格式化文本→前端重新解析"的损失，每个事件携带结构化数据。
library;

import 'dart:async';

// ─── 事件类型 ──────────────────────────────────────────────

/// 事件种类，对应 Go 的 event.Kind。
enum EventKind {
  /// 新一轮对话开始。前端重置渲染状态。
  turnStarted,

  /// 思考过程 delta（reasoning_content）。流式到达，在可见回答之前。
  reasoning,

  /// 可见回答文本 delta（content）。流式到达。
  text,

  /// Assistant 回答完整。Text 为完整文本，Reasoning 为完整思考过程。
  /// 前端可以用此事件将流式原始文本重渲染为格式化 Markdown。
  message,

  /// 工具调用即将执行。Tool 中携带 ID/Name/Args/ReadOnly。
  toolDispatch,

  /// 工具调用执行完毕。Tool 中携带 Output/Err/Truncated。
  toolResult,

  /// Token 用量统计。Usage 为统计数据，可选的 Pricing 为成本。
  usage,

  /// 带外通知（警告、截断、压实通知）。Level + Text。
  notice,

  /// Planner→Executor 阶段切换。
  phase,

  /// 请求前端批准工具调用。Agent 阻塞直到 Controller 的 approve() 被调用。
  approvalRequest,

  /// 请求前端向用户提问（多项选择）。Ask 携带 ID + Questions。
  /// 由 `ask` 工具触发。
  askRequest,

  /// 本轮结束。Err 非 null 表示失败。
  turnDone,

  /// 上下文压实开始。前端显示 "compacting..." 占位。
  compactionStarted,

  /// 上下文压实完成。Summary 为压缩后的内容。
  compactionDone,

  /// 长时间运行的工具（如 bash）的中间输出。
  toolProgress,

  /// MCP 服务器后台资源加载完成。
  mcpSurfaceReady,

  /// Provider 在临时故障后进行重试。
  retrying,
}

// ─── 载荷类型 ──────────────────────────────────────────────

/// 通知级别，对应 Go 的 event.Level。
enum NoticeLevel { info, warn }

/// Token 用量统计，对应 Go 的 provider.Usage。
class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int? promptCacheHitTokens;
  final int? promptCacheMissTokens;
  final double? cacheHitRatio;

  const TokenUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    this.promptCacheHitTokens,
    this.promptCacheMissTokens,
    this.cacheHitRatio,
  });

  /// 从 DeepSeek API 响应中的 usage 字段解析。
  factory TokenUsage.fromApi(Map<String, dynamic> json) {
    return TokenUsage(
      promptTokens: json['prompt_tokens'] ?? 0,
      completionTokens: json['completion_tokens'] ?? 0,
      totalTokens: json['total_tokens'] ?? 0,
      promptCacheHitTokens: json['prompt_cache_hit_tokens'],
      promptCacheMissTokens: json['prompt_cache_miss_tokens'],
      cacheHitRatio: json['cache_hit_ratio'] is num
          ? (json['cache_hit_ratio'] as num).toDouble()
          : null,
    );
  }

  @override
  String toString() =>
      '${totalTokens}tok (↑${promptTokens} ↓${completionTokens})'
      '${cacheHitRatio != null ? " cache:${(cacheHitRatio! * 100).toStringAsFixed(0)}%" : ""}';
}

/// 定价信息。
class Pricing {
  final double inputCost; // USD
  final double outputCost;
  final double cacheWriteCost;
  final double? cacheReadCost;

  const Pricing({
    required this.inputCost,
    required this.outputCost,
    required this.cacheWriteCost,
    this.cacheReadCost,
  });
}

/// 子 Agent 的模型/努力级别，对应 Go 的 event.Profile。
class AgentProfile {
  final String model;
  final String effort;

  const AgentProfile({required this.model, required this.effort});
}

/// 工具调用事件负载。
class ToolEventPayload {
  final String id;
  final String name;
  final String arguments; // raw JSON
  final bool readOnly;
  final String? output; // 执行结果（ToolResult 时）
  final String? error; // 错误信息（ToolResult 时）
  final bool truncated; // 结果是否被截断

  const ToolEventPayload({
    required this.id,
    required this.name,
    required this.arguments,
    this.readOnly = false,
    this.output,
    this.error,
    this.truncated = false,
  });

  bool get isError => error != null;
}

/// 批准请求负载。
class ApprovalPayload {
  final String id;
  final String toolName;
  final String subject; // 简短描述

  const ApprovalPayload({
    required this.id,
    required this.toolName,
    required this.subject,
  });
}

/// 提问请求负载，对应 Go 的 event.AskQuestion。
class AskQuestion {
  final String id;
  final String question;
  final List<String> options;

  const AskQuestion({
    required this.id,
    required this.question,
    this.options = const [],
  });
}

/// 压实事件负载。
class CompactionPayload {
  final String trigger; // 例如 "token_limit", "manual"
  final int messagesBefore;
  final int messagesAfter;
  final String summary;

  const CompactionPayload({
    required this.trigger,
    required this.messagesBefore,
    required this.messagesAfter,
    required this.summary,
  });
}

/// 重试信息。
class RetryPayload {
  final int attempt;
  final int maxRetries;
  final String reason;

  const RetryPayload({
    required this.attempt,
    required this.maxRetries,
    required this.reason,
  });
}

// ─── 事件 ──────────────────────────────────────────────────

/// 一个类型化的事件，由 Agent Loop 发射。
class AgentEvent {
  final EventKind kind;

  // —— 通用字段 ——
  final String? text;
  final String? reasoning;

  // —— 工具调用 ——
  final ToolEventPayload? tool;

  // —— Token ——
  final TokenUsage? usage;
  final Pricing? pricing;

  // —— 通知 ——
  final NoticeLevel? noticeLevel;

  // —— 批准 ——
  final ApprovalPayload? approval;

  // —— 提问 ——
  final List<AskQuestion>? askQuestions;
  final String? askId;

  // —— 压实 ——
  final CompactionPayload? compaction;

  // —— 重试 ——
  final RetryPayload? retry;

  // —— 子 Agent ——
  final AgentProfile? profile;

  // —— 错误 ——
  final String? error;

  const AgentEvent({
    required this.kind,
    this.text,
    this.reasoning,
    this.tool,
    this.usage,
    this.pricing,
    this.noticeLevel,
    this.approval,
    this.askQuestions,
    this.askId,
    this.compaction,
    this.retry,
    this.profile,
    this.error,
  });

  // ── 工厂构造器 ──

  factory AgentEvent.text(String content) =>
      AgentEvent(kind: EventKind.text, text: content);

  factory AgentEvent.reasoning(String content) =>
      AgentEvent(kind: EventKind.reasoning, reasoning: content);

  factory AgentEvent.toolDispatch(ToolEventPayload payload) =>
      AgentEvent(kind: EventKind.toolDispatch, tool: payload);

  factory AgentEvent.toolResult(ToolEventPayload payload) =>
      AgentEvent(kind: EventKind.toolResult, tool: payload);

  factory AgentEvent.toolProgress(ToolEventPayload payload) =>
      AgentEvent(kind: EventKind.toolProgress, tool: payload);

  factory AgentEvent.usage(TokenUsage u, {Pricing? p}) =>
      AgentEvent(kind: EventKind.usage, usage: u, pricing: p);

  factory AgentEvent.notice(String msg, {NoticeLevel level = NoticeLevel.info}) =>
      AgentEvent(kind: EventKind.notice, text: msg, noticeLevel: level);

  factory AgentEvent.phase(String label) =>
      AgentEvent(kind: EventKind.phase, text: label);

  factory AgentEvent.approvalRequest(ApprovalPayload payload) =>
      AgentEvent(kind: EventKind.approvalRequest, approval: payload);

  factory AgentEvent.askRequest(String id, List<AskQuestion> questions) =>
      AgentEvent(kind: EventKind.askRequest, askId: id, askQuestions: questions);

  factory AgentEvent.turnDone({String? error}) =>
      AgentEvent(kind: EventKind.turnDone, error: error);

  factory AgentEvent.compactionStarted(String trigger) =>
      AgentEvent(kind: EventKind.compactionStarted, text: trigger);

  factory AgentEvent.compactionDone(CompactionPayload payload) =>
      AgentEvent(kind: EventKind.compactionDone, compaction: payload);

  factory AgentEvent.retrying(int attempt, int maxRetries, String reason) =>
      AgentEvent(
        kind: EventKind.retrying,
        retry: RetryPayload(attempt: attempt, maxRetries: maxRetries, reason: reason),
      );

  factory AgentEvent.turnStarted() =>
      AgentEvent(kind: EventKind.turnStarted);

  factory AgentEvent.message({String? text, String? reasoning}) =>
      AgentEvent(kind: EventKind.message, text: text, reasoning: reasoning);

  @override
  String toString() => 'AgentEvent(${kind.name})';
}

// ─── Event Sink ────────────────────────────────────────────

/// Agent Loop 的事件输出接口。
///
/// 前端实现此接口来接收 Agent 的完整事件流。
/// 对应 Go 的 event.Sink。
class EventSink {
  void Function(AgentEvent)? onEvent;

  EventSink({this.onEvent});

  void emit(AgentEvent event) {
    onEvent?.call(event);
  }

  /// 无操作接收器，用于测试或无 UI 场景。
  static final EventSink discard = EventSink();
}

/// 使用 StreamController 桥接 EventSink → Stream。
///
/// 前端可以通过 [stream] 属性获取 Stream<AgentEvent>，
/// 配合 StreamBuilder 使用。
class StreamEventSink extends EventSink {
  final StreamController<AgentEvent> _controller =
      StreamController<AgentEvent>.broadcast();

  Stream<AgentEvent> get stream => _controller.stream;

  StreamEventSink() {
    onEvent = _controller.add;
  }

  void close() {
    _controller.close();
  }
}
