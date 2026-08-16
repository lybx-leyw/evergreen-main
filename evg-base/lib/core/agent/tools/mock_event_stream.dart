/// Mock AgentEvent 流生成器 — 供渲染工程师开发 UI 使用。
///
/// 覆盖全部 18 种 EventKind，每种事件携带完整示例 payload。
/// 渲染工程师通过 `MockEventStream.generate()` 获取模拟事件流，
/// 无需真实 Agent/Provider/Registry 即可开发 UI 渲染逻辑。
///
/// ## 用法
/// ```dart
/// await for (final event in MockEventStream.generate()) {
///   // 根据 event.kind 渲染对应的 UI 组件
///   switch (event.kind) {
///     case EventKind.turnStarted: ...
///     case EventKind.reasoning: ...
///     ...
///   }
/// }
/// ```
library;

import 'dart:async';

import '../event.dart';

// ═══════ MockEventStream ═══════

/// 生成覆盖全部 EventKind 的模拟事件流。
///
/// 每个事件之间间隔 [delay]，模拟真实流式延迟。
/// 总事件数 ≈ 36（18 种类型 + 变体示例）。
class MockEventStream {
  /// 生成完整 mock 流。事件间隔 [delay]（默认 50ms）。
  static Stream<AgentEvent> generate({Duration delay = const Duration(milliseconds: 50)}) async* {
    // ── 1. turnStarted ──
    yield AgentEvent.turnStarted();
    await _pause(delay);

    // ── 2. reasoning (thinking delta, streamed) ──
    yield AgentEvent.reasoning('用户询问了天气和时间…');
    await _pause(delay);
    yield AgentEvent.reasoning('我需要调用 weather 和 time 工具来获取实时数据…');
    await _pause(delay);

    // ── 3. text (visible answer delta, streamed) ──
    yield AgentEvent.text('好的，');
    await _pause(delay);
    yield AgentEvent.text('我来帮你查一下。');
    await _pause(delay);

    // ── 4. phase (planner→executor transition) ──
    yield AgentEvent.phase('execution');
    await _pause(delay);

    // ── 5. toolDispatch (tool call about to execute) ──
    yield AgentEvent.toolDispatch(ToolEventPayload(
      id: 'call_w1',
      name: 'weather',
      arguments: '{"city":"北京","days":1}',
      readOnly: true,
    ));
    await _pause(delay);

    yield AgentEvent.toolDispatch(ToolEventPayload(
      id: 'call_t1',
      name: 'time',
      arguments: '{"offset":8,"format":"24h"}',
      readOnly: true,
    ));
    await _pause(delay);

    // ── 6. toolProgress (long-running tool intermediate output) ──
    yield AgentEvent.toolProgress(ToolEventPayload(
      id: 'call_w1',
      name: 'weather',
      arguments: '{"city":"北京","days":1}',
      output: '正在查询北京天气…',
    ));
    await _pause(delay);

    // ── 7. toolResult (tool execution complete) ──
    yield AgentEvent.toolResult(ToolEventPayload(
      id: 'call_w1',
      name: 'weather',
      arguments: '{"city":"北京","days":1}',
      output: '北京：晴，25°C，湿度 45%，北风 3 级',
    ));
    await _pause(delay);

    yield AgentEvent.toolResult(ToolEventPayload(
      id: 'call_t1',
      name: 'time',
      arguments: '{"offset":8,"format":"24h"}',
      output: '当前北京时间: 2026-07-02 14:30:00',
    ));
    await _pause(delay);

    // ── 8. toolResult with error ──
    yield AgentEvent.toolResult(ToolEventPayload(
      id: 'call_f1',
      name: 'fetch',
      arguments: '{"url":"https://example.com"}',
      error: '连接超时',
    ));
    await _pause(delay);

    // ── 9. text (more streaming text after tools) ──
    yield AgentEvent.text('根据查询结果，');
    await _pause(delay);
    yield AgentEvent.text('北京今天天气晴好，');
    await _pause(delay);
    yield AgentEvent.text('当前时间 14:30。');
    await _pause(delay);

    // ── 10. message (complete assistant message) ──
    yield AgentEvent.message(
      text: '根据查询结果，北京今天天气晴好，当前时间 14:30。',
      reasoning: '用户询问了天气和时间…我需要调用 weather 和 time 工具…',
    );
    await _pause(delay);

    // ── 11. usage (token statistics) ──
    yield AgentEvent.usage(TokenUsage(
      promptTokens: 245,
      completionTokens: 128,
      totalTokens: 373,
      promptCacheHitTokens: 120,
      promptCacheMissTokens: 125,
      cacheHitRatio: 0.49,
    ));
    await _pause(delay);

    // ── 12. notice (out-of-band notification) ──
    yield AgentEvent.notice('上下文使用率已达 80%，建议压缩', level: NoticeLevel.warn);
    await _pause(delay);

    yield AgentEvent.notice('MemoryAgent 已提取 2 条新记忆', level: NoticeLevel.info);
    await _pause(delay);

    // ── 13. approvalRequest (request user to approve tool) ──
    yield AgentEvent.approvalRequest(ApprovalPayload(
      id: 'a1',
      toolName: 'write_file',
      subject: '写入 3 个文件到 src/utils/',
    ));
    await _pause(delay);

    // ── 14. askRequest (ask user multiple-choice question) ──
    yield AgentEvent.askRequest('q1', [
      AskQuestion(
        id: 'q1_a',
        header: '环境',
        question: '选择部署环境',
        options: const [
          AskOption(label: '开发环境', description: '本地调试'),
          AskOption(label: '测试环境', description: '联调验证'),
          AskOption(label: '生产环境', description: '正式发布'),
        ],
      ),
    ]);
    await _pause(delay);

    // ── 15. retrying (API retry notification) ──
    yield AgentEvent.retrying(1, 3, 'rate limit (429)');
    await _pause(delay);

    yield AgentEvent.retrying(2, 3, 'rate limit (429)');
    await _pause(delay);

    // ── 16. compactionStarted ──
    yield AgentEvent.compactionStarted('token_limit');
    await _pause(delay);

    // ── 17. compactionDone ──
    yield AgentEvent.compactionDone(CompactionPayload(
      trigger: 'token_limit',
      messagesBefore: 48,
      messagesAfter: 24,
      summary: '[上下文摘要] 用户查询了北京天气和时间，助手调用了 weather 和 time 工具获取实时数据。天气晴好 25°C，时间 14:30。',
    ));
    await _pause(delay);

    // ── 18. mcpSurfaceReady (MCP server resource loaded) ──
    yield AgentEvent(kind: EventKind.mcpSurfaceReady, text: 'mcp-server-filesystem');
    await _pause(delay);

    // ── 18.5 guardianAssessment (Phase 3 · A12/A13: Guardian 裁决) ──
    yield AgentEvent.guardianAssessment(GuardianResult(
      id: 'guardian-1',
      tool: 'G6',
      subject: '注册 data-courses 插件到数据中心',
      outcome: 'deny',
      riskLevel: 'high',
      userAuthorization: 'low',
      rationale: '产物含疑似硬编码假数据且用户未确认放行。',
    ));
    await _pause(delay);

    // ── 19. turnDone (success) ──
    yield AgentEvent.turnDone();
    await _pause(delay);

    // ── Bonus: turnDone with error ──
    // 模拟新一轮对话失败的场景
    yield AgentEvent.turnStarted();
    await _pause(delay);
    yield AgentEvent.text('处理中…');
    await _pause(delay);
    yield AgentEvent.turnDone(error: 'API 调用失败: 连接超时');
  }

  /// 所有 EventKind 的描述和示例 payload 一览表（供参考）。
  static List<Map<String, String>> get eventKindReference => [
        {
          'kind': 'turnStarted',
          'payload': '无',
          '说明': '新一轮对话开始，前端重置渲染状态',
        },
        {
          'kind': 'reasoning',
          'payload': 'reasoning: String',
          '说明': '思考过程 delta（reasoning_content），流式到达，在可见回答之前',
        },
        {
          'kind': 'text',
          'payload': 'text: String',
          '说明': '可见回答文本 delta（content），流式到达，前端逐字追加',
        },
        {
          'kind': 'message',
          'payload': 'text: String?, reasoning: String?',
          '说明': 'Assistant 回答完整。前端可用此事件将流式原始文本重渲染为格式化 Markdown',
        },
        {
          'kind': 'toolDispatch',
          'payload': 'tool: ToolEventPayload (id, name, arguments, readOnly)',
          '说明': '工具调用即将执行，前端显示工具调用卡片',
        },
        {
          'kind': 'toolResult',
          'payload': 'tool: ToolEventPayload (id, name, arguments, output?, error?, truncated)',
          '说明': '工具调用执行完毕。output=成功，error=失败，truncated=被截断',
        },
        {
          'kind': 'toolProgress',
          'payload': 'tool: ToolEventPayload (id, name, output)',
          '说明': '长时间运行的工具的中间输出，前端追加到工具卡片',
        },
        {
          'kind': 'usage',
          'payload': 'usage: TokenUsage, pricing: Pricing?',
          '说明': 'Token 用量统计，前端显示用量 + 可选成本',
        },
        {
          'kind': 'notice',
          'payload': 'text: String, noticeLevel: NoticeLevel',
          '说明': '带外通知（警告、截断、压实通知）。Level: info/warn',
        },
        {
          'kind': 'phase',
          'payload': 'text: String (label)',
          '说明': 'Planner→Executor 阶段切换，前端显示阶段标签',
        },
        {
          'kind': 'approvalRequest',
          'payload': 'approval: ApprovalPayload (id, toolName, subject)',
          '说明': '请求前端批准工具调用。Agent 阻塞直到 approve() 被调用',
        },
        {
          'kind': 'askRequest',
          'payload': 'askId: String, askQuestions: List<AskQuestion>',
          '说明': '请求前端向用户提问（多项选择），由 ask 工具触发',
        },
        {
          'kind': 'turnDone',
          'payload': 'error: String?',
          '说明': '本轮结束。error 非 null 表示本轮失败',
        },
        {
          'kind': 'compactionStarted',
          'payload': 'text: String (trigger)',
          '说明': '上下文压实开始，前端显示 "compacting..." 占位',
        },
        {
          'kind': 'compactionDone',
          'payload': 'compaction: CompactionPayload (trigger, messagesBefore, messagesAfter, summary)',
          '说明': '上下文压实完成。summary 为压缩后的内容',
        },
        {
          'kind': 'retrying',
          'payload': 'retry: RetryPayload (attempt, maxRetries, reason)',
          '说明': 'Provider 在临时故障后进行重试，前端显示重试状态',
        },
        {
          'kind': 'mcpSurfaceReady',
          'payload': 'text: String (server name)',
          '说明': 'MCP 服务器后台资源加载完成，前端可刷新可用工具列表',
        },
        {
          'kind': 'guardianAssessment',
          'payload': 'guardian: GuardianResult (outcome, riskLevel, rationale)',
          '说明': 'Guardian 审查裁决（Phase 3），前端可展示安全审查结果',
        },
      ];

  static Future<void> _pause(Duration d) async {
    await Future.delayed(d);
  }
}
