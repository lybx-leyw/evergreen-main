// Guardian 测试（Phase 3 · A12/A13 core 层）。
//
// 覆盖：
// 1. 裁决解析：直接 JSON / 散文包裹 / 非法输出
// 2. 策略后门：critical+allow 强制 deny；high+低授权+allow 强制 deny
// 3. review allow / deny 路径 + deny reason 格式
// 4. circuit breaker：连续 3 deny 中断 + 之后直接 fail-closed
// 5. fail-closed：LLM 失败 → deny + failed=true
// 6. transcript 增量：第二次只发 DELTA
// 7. resetTurn 复位
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/guardian/guardian.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假 LLM：按序返回响应；可注入抛错。
class FakeGuardianLlm implements GuardianLlm {
  final List<String> responses;
  final Object? throwError;
  int callCount = 0;
  final List<String> systemPrompts = [];
  final List<String> userPrompts = [];

  FakeGuardianLlm(this.responses, {this.throwError});

  @override
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    callCount++;
    systemPrompts.add(systemPrompt);
    userPrompts.add(userPrompt);
    if (throwError != null) throw throwError!;
    final idx = callCount - 1;
    return idx < responses.length ? responses[idx] : responses.last;
  }
}

GuardianSession newSession(FakeGuardianLlm llm) => GuardianSession(
      llm: llm,
      policyPrompt: 'policy',
      recentWindow: 50,
    );

GuardianReviewRequest req({String gate = 'G6'}) => GuardianReviewRequest(
      gate: gate,
      action: '注册 data-courses 插件',
      arguments: '{"plugin_dir": "data-courses"}',
    );

void main() {
  group('GuardianAssessment.parse（裁决解析）', () {
    test('直接 JSON → 解析', () {
      final a = GuardianAssessment.parse(
          '{"risk_level":"low","user_authorization":"high","outcome":"allow","rationale":"用户明确要求"}');
      expect(a.outcome, 'allow');
      expect(a.riskLevel, 'low');
      expect(a.userAuthorization, 'high');
      expect(a.rationale, '用户明确要求');
      expect(a.isAllow, isTrue);
    });

    test('散文包裹（首 { 到末 }）→ 解析', () {
      final a = GuardianAssessment.parse(
          '审查结论：{"risk_level":"medium","user_authorization":"medium","outcome":"allow","rationale":"风险可控"}，请放行。');
      expect(a.outcome, 'allow');
      expect(a.riskLevel, 'medium');
    });

    test('非法输出 → FormatException（触发 fail-closed）', () {
      expect(() => GuardianAssessment.parse(''), throwsFormatException);
      expect(() => GuardianAssessment.parse('hello world'),
          throwsFormatException);
      expect(
          () => GuardianAssessment.parse(
              '{"risk_level":"bogus","outcome":"allow"}'),
          throwsFormatException);
      expect(
          () => GuardianAssessment.parse(
              '{"risk_level":"low","outcome":"allow","user_authorization":"bogus"}'),
          throwsFormatException);
    });

    test('缺省字段归一化：空 risk→low(allow)/high(deny)、空 auth→unknown、空 rationale→默认', () {
      final allow = GuardianAssessment.fromJson({'outcome': 'allow'});
      expect(allow.riskLevel, 'low');
      expect(allow.userAuthorization, 'unknown');
      expect(allow.rationale, contains('low-risk allow'));

      final deny = GuardianAssessment.fromJson({'outcome': 'deny'});
      expect(deny.riskLevel, 'high');
    });

    test('策略后门：critical+allow → 强制 deny；high+低授权+allow → 强制 deny', () {
      final critical = GuardianAssessment.fromJson({
        'risk_level': 'critical',
        'user_authorization': 'high',
        'outcome': 'allow',
        'rationale': 'guardian review returned a low-risk allow decision',
      });
      expect(critical.outcome, 'deny');
      expect(critical.rationale, contains('forced deny'));

      final highWeak = GuardianAssessment.fromJson({
        'risk_level': 'high',
        'user_authorization': 'low',
        'outcome': 'allow',
        'rationale': 'guardian review returned a low-risk allow decision',
      });
      expect(highWeak.outcome, 'deny');

      // high + medium 授权 → 允许
      final highOk = GuardianAssessment.fromJson({
        'risk_level': 'high',
        'user_authorization': 'medium',
        'outcome': 'allow',
      });
      expect(highOk.outcome, 'allow');
    });
  });

  group('GuardianSession.review', () {
    test('allow 路径：verdict.allow=true、reason 空、failed=false', () async {
      final llm = FakeGuardianLlm([
        '{"risk_level":"low","user_authorization":"high","outcome":"allow","rationale":"真实抓取，风险低"}',
      ]);
      final s = newSession(llm);
      final v = await s.review(request: req());
      expect(v.allow, isTrue);
      expect(v.reason, isEmpty);
      expect(v.failed, isFalse);
      expect(v.assessment.isAllow, isTrue);
      // 策略 prompt 作为 system
      expect(llm.systemPrompts.single, 'policy');
      expect(llm.userPrompts.single, contains('The agent has requested the following action:'));
      expect(llm.userPrompts.single, contains('Output ONLY the JSON verdict.'));
    });

    test('deny 路径：reason 格式 "guardian denied: risk=..."', () async {
      final llm = FakeGuardianLlm([
        '{"risk_level":"high","user_authorization":"unknown","outcome":"deny","rationale":"疑似假数据"}',
      ]);
      final s = newSession(llm);
      final v = await s.review(request: req());
      expect(v.allow, isFalse);
      expect(v.failed, isFalse);
      expect(v.reason, startsWith('guardian denied: risk=high'));
      expect(v.reason, contains('疑似假数据'));
    });

    test('fail-closed：LLM 抛错 → deny + failed=true + high-risk', () async {
      final llm = FakeGuardianLlm([], throwError: Exception('network down'));
      final s = newSession(llm);
      final v = await s.review(request: req());
      expect(v.allow, isFalse);
      expect(v.failed, isTrue);
      expect(v.assessment.riskLevel, 'high');
      expect(v.assessment.rationale, contains('guardian review failed'));
      expect(v.reason, startsWith('guardian denied: risk=high'));
    });

    test('fail-closed：不可解析输出 → deny + failed=true', () async {
      final llm = FakeGuardianLlm(['这不是 JSON']);
      final s = newSession(llm);
      final v = await s.review(request: req());
      expect(v.allow, isFalse);
      expect(v.failed, isTrue);
      expect(v.assessment.outcome, 'deny');
    });
  });

  group('circuit breaker', () {
    test('连续 3 deny → 中断提示；之后直接 deny（fail-closed）', () async {
      final llm = FakeGuardianLlm([
        '{"risk_level":"high","outcome":"deny","rationale":"r1"}',
        '{"risk_level":"high","outcome":"deny","rationale":"r2"}',
        '{"risk_level":"high","outcome":"deny","rationale":"r3"}',
      ]);
      final s = newSession(llm);

      final v1 = await s.review(request: req());
      expect(v1.allow, isFalse);
      expect(v1.reason, startsWith('guardian denied'));
      expect(s.circuitBreakerTripped, isFalse);

      final v2 = await s.review(request: req());
      expect(v2.allow, isFalse);
      expect(s.circuitBreakerTripped, isFalse);

      // 第 3 次 → 触发中断
      final v3 = await s.review(request: req());
      expect(v3.allow, isFalse);
      expect(s.circuitBreakerTripped, isTrue);
      expect(v3.reason, contains('Guardian 自动审查本轮已拒绝过多请求'));
      expect(v3.reason, contains('3 次'));

      // 第 4 次 → 不再调 LLM，直接 deny（fail-closed）
      final callsBefore = llm.callCount;
      final v4 = await s.review(request: req());
      expect(v4.allow, isFalse);
      expect(v4.failed, isTrue);
      expect(llm.callCount, callsBefore); // 未再调用 LLM
    });

    test('allow 后重置连续计数', () async {
      final llm = FakeGuardianLlm([
        '{"risk_level":"high","outcome":"deny","rationale":"r1"}',
        '{"risk_level":"high","outcome":"deny","rationale":"r2"}',
        '{"risk_level":"low","outcome":"allow","rationale":"ok"}',
        '{"risk_level":"high","outcome":"deny","rationale":"r3"}',
      ]);
      final s = newSession(llm);
      await s.review(request: req());
      await s.review(request: req());
      final v3 = await s.review(request: req());
      expect(v3.allow, isTrue);
      expect(s.circuitBreakerTripped, isFalse);
      // 中断计数已清零 → 继续累计不会立刻触发
      final v4 = await s.review(request: req());
      expect(v4.allow, isFalse);
      expect(s.circuitBreakerTripped, isFalse);
    });

    test('resetTurn 复位中断状态', () async {
      final llm = FakeGuardianLlm([
        '{"risk_level":"high","outcome":"deny","rationale":"r1"}',
        '{"risk_level":"high","outcome":"deny","rationale":"r2"}',
        '{"risk_level":"high","outcome":"deny","rationale":"r3"}',
        '{"risk_level":"low","outcome":"allow","rationale":"ok"}',
      ]);
      final s = newSession(llm);
      await s.review(request: req());
      await s.review(request: req());
      await s.review(request: req());
      expect(s.circuitBreakerTripped, isTrue);

      s.resetTurn();
      expect(s.circuitBreakerTripped, isFalse);
      final v = await s.review(request: req());
      expect(v.allow, isTrue); // 复位后重新工作
    });
  });

  group('transcript 增量（成本控制）', () {
    test('第二次审查只发 DELTA 新增条目', () async {
      final llm = FakeGuardianLlm([
        '{"risk_level":"low","outcome":"allow","rationale":"ok"}',
        '{"risk_level":"low","outcome":"allow","rationale":"ok"}',
      ]);
      final s = newSession(llm);
      final messages = <agent.Message>[
        agent.Message(role: agent.Role.user, content: '帮我生成爬虫'),
      ];
      await s.review(request: req(), parentTranscript: messages);

      // 追加新消息后第二次审查
      messages.add(
          agent.Message(role: agent.Role.assistant, content: '好的，开始分析'));
      messages.add(
          agent.Message(role: agent.Role.tool, content: '请求日志已获取'));
      await s.review(request: req(), parentTranscript: messages);

      final first = llm.userPrompts[0];
      expect(first, contains('>>> TRANSCRIPT START'));
      expect(first, contains('[1] user: 帮我生成爬虫'));

      final second = llm.userPrompts[1];
      expect(second, contains('>>> TRANSCRIPT DELTA START'));
      expect(second, isNot(contains('>>> TRANSCRIPT START')));
      expect(second, contains('[2] assistant: 好的，开始分析'));
      expect(second, contains('[3] tool: 请求日志已获取'));
      // 已发送过的旧条目不再重复
      expect(second, isNot(contains('帮我生成爬虫')));
    });

    test('条目变少（会话重写）→ 重发全量', () async {
      final llm = FakeGuardianLlm([
        '{"risk_level":"low","outcome":"allow","rationale":"ok"}',
        '{"risk_level":"low","outcome":"allow","rationale":"ok"}',
      ]);
      final s = newSession(llm);
      final messages = <agent.Message>[
        agent.Message(role: agent.Role.user, content: 'a'),
        agent.Message(role: agent.Role.assistant, content: 'b'),
      ];
      await s.review(request: req(), parentTranscript: messages);

      // 会话被压缩重写为更少条目
      final short = <agent.Message>[
        agent.Message(role: agent.Role.user, content: '压缩后'),
      ];
      await s.review(request: req(), parentTranscript: short);

      final second = llm.userPrompts[1];
      expect(second, contains('>>> TRANSCRIPT START')); // 全量
      expect(second, contains('压缩后'));
    });
  });

  group('GuardianResult 事件输出', () {
    test('review 后向 sink 发射 GuardianResult 事件', () async {
      final llm = FakeGuardianLlm([
        '{"risk_level":"high","outcome":"deny","rationale":"疑似假数据"}',
      ]);
      final emitted = <agent.AgentEvent>[];
      final sink = agent.EventSink(onEvent: emitted.add);
      final s = GuardianSession(llm: llm, policyPrompt: 'policy', sink: sink);
      await s.review(request: req());
      expect(emitted, hasLength(1));
      final e = emitted.single;
      expect(e.kind, agent.EventKind.guardianAssessment);
      final g = e.guardian!;
      expect(g.tool, 'G6');
      expect(g.outcome, 'deny');
      expect(g.riskLevel, 'high');
      expect(g.rationale, contains('疑似假数据'));
      expect(g.failed, isFalse);
    });
  });
}
