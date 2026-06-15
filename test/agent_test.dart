/// Greenix Agent Runtime — 核心功能测试
///
/// 测试所有模块：消息模型、工具系统、Agent Loop、记忆、技能、压实、事件系统。
/// 不依赖 Flutter，纯 Dart 测试。
///
/// 运行: flutter test test/agent_test.dart
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/agent.dart';

// ═══════════════════════════════════════════════════════════
// 1. 消息模型测试 (message.dart)
// ═══════════════════════════════════════════════════════════

void testMessageModel() {
  group('Message 模型', () {
    test('创建用户消息', () {
      final msg = Message.user('有哪些课程？');
      expect(msg.role, Role.user);
      expect(msg.content, '有哪些课程？');
      expect(msg.isUser, true);
      expect(msg.isToolResult, false);
      expect(msg.isAssistant, false);
    });

    test('创建助手消息', () {
      final msg = Message.assistant('你有 6 门课程');
      expect(msg.role, Role.assistant);
      expect(msg.content, '你有 6 门课程');
      expect(msg.hasToolCalls, false);
    });

    test('创建助手工具调用消息', () {
      final calls = [ToolCall(id: 'call_1', name: 'get_courses', arguments: '{}')];
      final msg = Message.assistantTool(calls);
      expect(msg.role, Role.assistant);
      expect(msg.hasToolCalls, true);
      expect(msg.toolCalls.length, 1);
      expect(msg.toolCalls[0].name, 'get_courses');
    });

    test('创建工具结果消息', () {
      final msg = Message.toolResult('call_1', '查询结果');
      expect(msg.role, Role.tool);
      expect(msg.toolCallId, 'call_1');
      expect(msg.content, '查询结果');
      expect(msg.isToolResult, true);
    });

    test('序列化与反序列化 (无工具调用)', () {
      final original = Message.user('测试消息');
      final json = original.toJson();
      expect(json['role'], 'user');
      expect(json['content'], '测试消息');
    });

    test('序列化助手消息含 reasoning', () {
      final msg = Message.assistant('答案', reasoning: '思考过程');
      final json = msg.toJson();
      expect(json['reasoning_content'], '思考过程');
    });

    test('序列化工具调用消息', () {
      final calls = [ToolCall(id: 'c1', name: 'get_courses', arguments: '{}')];
      final msg = Message.assistantTool(calls);
      final json = msg.toJson();
      expect(json['tool_calls'], isList);
      expect((json['tool_calls'] as List).length, 1);
    });

    test('ToolCall 从 JSON 反序列化', () {
      final json = {
        'id': 'call_123',
        'type': 'function',
        'function': {'name': 'get_courses', 'arguments': '{}'}
      };
      final tc = ToolCall.fromJson(json);
      expect(tc.id, 'call_123');
      expect(tc.name, 'get_courses');
    });

    test('sanitizeToolPairing 移除孤立 tool 消息', () {
      final messages = [
        Message.user('查课程'),
        Message.toolResult('orphan_call', '结果'), // 孤立的 tool 消息
        Message.assistant('回答'),
      ];
      final result = sanitizeToolPairing(messages);
      expect(result.length, 2); // 孤立 tool 消息应被移除
      expect(result[0].isUser, true);
      expect(result[1].isAssistant, true);
    });

    test('sanitizeToolPairing 保留正确配对的 tool 消息', () {
      final messages = [
        Message.user('查课程'),
        Message.assistantTool([
          ToolCall(id: 'call_1', name: 'get_courses', arguments: '{}'),
        ]),
        Message.toolResult('call_1', '课程列表'),
        Message.assistant('你有 6 门课'),
      ];
      final result = sanitizeToolPairing(messages);
      expect(result.length, 4); // 全部保留
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 2. 工具系统测试 (tool.dart)
// ═══════════════════════════════════════════════════════════

/// 测试用模拟工具
class MockTool extends Tool {
  final String toolName;
  final bool isReadOnly;
  final Map<String, dynamic>? mockResult;

  MockTool({required this.toolName, this.isReadOnly = true, this.mockResult});

  @override
  String get name => toolName;

  @override
  String get description => '测试工具 $toolName';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '查询参数'}
        },
        'required': ['query'],
      };

  @override
  bool get readOnly => isReadOnly;

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    if (mockResult != null) {
      return jsonEncode(mockResult);
    }
    return 'mock result for $toolName: $args';
  }
}

void testToolSystem() {
  group('Registry 工具注册表', () {
    test('注册工具', () {
      final reg = Registry();
      final tool = MockTool(toolName: 'test_tool');
      reg.register(tool);
      expect(reg.has('test_tool'), true);
      expect(reg.isEnabled('test_tool'), true);
    });

    test('注册重复工具抛出异常', () {
      final reg = Registry();
      reg.register(MockTool(toolName: 'dup'));
      expect(() => reg.register(MockTool(toolName: 'dup')), throwsArgumentError);
    });

    test('禁用/启用工具', () {
      final reg = Registry();
      reg.register(MockTool(toolName: 't1'));
      reg.disable('t1');
      expect(reg.isEnabled('t1'), false);
      expect(reg.enabled().length, 0);
      reg.enable('t1');
      expect(reg.isEnabled('t1'), true);
      expect(reg.enabled().length, 1);
    });

    test('调用工具', () async {
      final reg = Registry();
      reg.register(MockTool(toolName: 'my_tool'));
      final result = await reg.call('my_tool', '{"query":"test"}');
      expect(result, contains('my_tool'));
      expect(result, contains('test'));
    });

    test('调用不存在的工具返回错误', () async {
      final reg = Registry();
      final result = await reg.call('ghost', '{}');
      expect(result, contains('not found'));
    });

    test('调用被禁用的工具返回错误', () async {
      final reg = Registry();
      reg.register(MockTool(toolName: 'disabled_tool'));
      reg.disable('disabled_tool');
      final result = await reg.call('disabled_tool', '{}');
      expect(result, contains('disabled'));
    });

    test('enabled() 按名称排序', () {
      final reg = Registry();
      reg.register(MockTool(toolName: 'z_tool'));
      reg.register(MockTool(toolName: 'a_tool'));
      reg.register(MockTool(toolName: 'm_tool'));
      final list = reg.enabled();
      expect(list[0].name, 'a_tool');
      expect(list[1].name, 'm_tool');
      expect(list[2].name, 'z_tool');
    });

    test('readOnlyToolNames', () {
      final reg = Registry();
      reg.register(MockTool(toolName: 'read', isReadOnly: true));
      reg.register(MockTool(toolName: 'write', isReadOnly: false));
      final names = reg.readOnlyToolNames;
      expect(names.contains('read'), true);
      expect(names.contains('write'), false);
    });
  });

  group('工具 Schema 生成', () {
    test('toolsToSchemas 生成正确结构', () {
      final tools = [MockTool(toolName: 'test')];
      final schemas = toolsToSchemas(tools);
      expect(schemas.length, 1);
      expect(schemas[0]['type'], 'function');
      expect(schemas[0]['function']['name'], 'test');
      expect(schemas[0]['function']['parameters'], isMap);
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 3. 会话测试 (session.dart)
// ═══════════════════════════════════════════════════════════

void testSession() {
  group('Session', () {
    test('新会话为空', () {
      final s = Session();
      expect(s.messages.length, 0);
      expect(s.totalTokens, 0);
    });

    test('添加消息', () {
      final s = Session();
      s.add(Message.user('你好'));
      s.add(Message.assistant('你好！'));
      expect(s.messageCount, 2);
    });

    test('添加系统消息', () {
      final s = Session();
      s.setSystemMessage('你是助手');
      expect(s.messageCount, 1);
      expect(s.systemMessage?.content, '你是助手');
    });

    test('更新系统消息', () {
      final s = Session();
      s.setSystemMessage('旧提示');
      s.setSystemMessage('新提示');
      expect(s.messageCount, 1);
      expect(s.systemMessage?.content, '新提示');
    });

    test('last(N) 获取最近 N 条', () {
      final s = Session();
      for (var i = 0; i < 10; i++) {
        s.add(Message.user('msg$i'));
      }
      final recent = s.last(3);
      expect(recent.length, 3);
      expect(recent[0].content, 'msg7');
      expect(recent[2].content, 'msg9');
    });

    test('累计用量', () {
      final s = Session();
      s.accumulateUsage(TokenUsage(
        promptTokens: 100, completionTokens: 50, totalTokens: 150,
      ));
      s.accumulateUsage(TokenUsage(
        promptTokens: 200, completionTokens: 100, totalTokens: 300,
      ));
      expect(s.totalPromptTokens, 300);
      expect(s.totalCompletionTokens, 150);
      expect(s.totalTokens, 450);
    });

    test('序列化与反序列化', () {
      final s = Session();
      s.add(Message.user('你好'));
      s.add(Message.assistant('你好！'));
      s.accumulateUsage(TokenUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15));

      final json = s.toJson();
      final restored = Session.fromJson(json);

      expect(restored.messageCount, 2);
      expect(restored.messages[0].content, '你好');
      expect(restored.messages[1].content, '你好！');
      expect(restored.totalPromptTokens, 10);
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 4. 消息组合测试 (compose.dart)
// ═══════════════════════════════════════════════════════════

void testCompose() {
  group('Compose 消息组合', () {
    test('空会话生成 system + user 消息', () {
      final session = Session();
      session.add(Message.user('查课程'));
      final messages = compose(
        systemPrompt: '你是一个助手',
        tools: [MockTool(toolName: 'get_courses')],
        session: session,
      );
      expect(messages.length, 2);
      expect(messages[0].role, Role.system);
      expect(messages[0].content, contains('你是一个助手'));
      expect(messages[1].role, Role.user);
      expect(messages[1].content, '查课程');
    });

    test('组合包含工具描述', () {
      final session = Session();
      session.add(Message.user('hi'));
      final messages = compose(
        systemPrompt: '助手',
        tools: [MockTool(toolName: 'my_tool')],
        session: session,
      );
      expect(messages[0].content, contains('my_tool'));
    });

    test('注入记忆上下文', () {
      final session = Session();
      session.add(Message.user('hi'));
      final messages = compose(
        systemPrompt: '助手',
        tools: [],
        session: session,
        memoryContext: '用户是浙大学生',
      );
      expect(messages[0].content, contains('用户是浙大学生'));
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 5. 事件系统测试 (event.dart)
// ═══════════════════════════════════════════════════════════

void testEventSystem() {
  group('AgentEvent', () {
    test('创建文本事件', () {
      final e = AgentEvent.text('你好');
      expect(e.kind, EventKind.text);
      expect(e.text, '你好');
    });

    test('创建工具调度事件', () {
      final payload = ToolEventPayload(id: 'c1', name: 'get_courses', arguments: '{}');
      final e = AgentEvent.toolDispatch(payload);
      expect(e.kind, EventKind.toolDispatch);
      expect(e.tool?.name, 'get_courses');
      expect(e.tool?.id, 'c1');
    });

    test('创建通知事件', () {
      final e = AgentEvent.notice('警告', level: NoticeLevel.warn);
      expect(e.kind, EventKind.notice);
      expect(e.text, '警告');
      expect(e.noticeLevel, NoticeLevel.warn);
    });
  });

  group('StreamEventSink', () {
    test('接收事件', () async {
      final sink = StreamEventSink();
      final events = <AgentEvent>[];

      sink.stream.listen(events.add);
      sink.emit(AgentEvent.text('测试'));

      // 等待事件传播
      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events[0].kind, EventKind.text);
    });

    test('丢弃模式', () {
      // 不抛出即可
      EventSink.discard.emit(AgentEvent.text('test'));
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 6. 记忆系统测试 (memory.dart)
// ═══════════════════════════════════════════════════════════

void testMemory() {
  group('MemoryStore', () {
    test('记忆类型转换', () {
      expect(MemoryType.fromString('user'), MemoryType.user);
      expect(MemoryType.fromString('feedback'), MemoryType.feedback);
      expect(MemoryType.fromString('project'), MemoryType.project);
      expect(MemoryType.fromString('reference'), MemoryType.reference);
      expect(MemoryType.fromString('unknown'), MemoryType.project); // 默认
    });

    test('Memory 自动填充标题', () {
      final mem = Memory(name: 'my-fact', description: '测试事实');
      expect(mem.title, 'My Fact');
    });

    test('Memory 的 filename', () {
      final mem = Memory(name: 'test-note', description: '测试');
      expect(mem.filename, 'test-note.md');
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 7. 输出风格测试 (output_style)
// ═══════════════════════════════════════════════════════════

void testOutputStyle() {
  group('OutputStyle', () {
    test('内置风格数量', () {
      expect(BuiltinStyles.all.length, 4);
    });

    test('按名称查找', () {
      final style = BuiltinStyles.byName('concise');
      expect(style, isNotNull);
      expect(style!.name, 'concise');
    });

    test('不区分大小写', () {
      final style = BuiltinStyles.byName('CONCISE');
      expect(style, isNotNull);
    });

    test('不存在的返回 null', () {
      expect(BuiltinStyles.byName('nonexistent'), isNull);
    });

    test('StyleManager 应用风格', () {
      final mgr = StyleManager();
      mgr.setStyle(BuiltinStyles.concise);
      final result = mgr.applyTo('原始提示词');
      expect(result, contains('原始提示词'));
      expect(result, contains('简洁'));
    });

    test('清除风格', () {
      final mgr = StyleManager();
      mgr.setStyle(BuiltinStyles.concise);
      mgr.clear();
      expect(mgr.current, isNull);
      expect(mgr.applyTo('原始'), '原始');
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 8. 证据系统测试 (evidence.dart)
// ═══════════════════════════════════════════════════════════

void testEvidence() {
  group('Ledger 证据分类账', () {
    test('创建空账本', () {
      final ledger = Ledger();
      expect(ledger.count, 0);
      expect(ledger.hasWrites, false);
    });

    test('添加收据', () {
      final ledger = Ledger();
      ledger.add(Receipt(toolName: 'get_courses', read: true));
      expect(ledger.count, 1);
      expect(ledger.hasReads, true);
    });

    test('检测写操作', () {
      final ledger = Ledger();
      ledger.add(Receipt(toolName: 'write_file', write: true));
      expect(ledger.hasWrites, true);
    });

    test('按工具筛选', () {
      final ledger = Ledger();
      ledger.add(Receipt(toolName: 'a'));
      ledger.add(Receipt(toolName: 'b'));
      ledger.add(Receipt(toolName: 'a'));
      expect(ledger.byTool('a').length, 2);
      expect(ledger.byTool('b').length, 1);
    });

    test('重置账本', () {
      final ledger = Ledger();
      ledger.add(Receipt(toolName: 't1'));
      ledger.reset();
      expect(ledger.count, 0);
    });

    test('验证步骤执行', () {
      final ledger = Ledger();
      ledger.add(Receipt(toolName: 't1', step: 'step-1', success: true));
      expect(ledger.verifyStepExecuted('step-1'), true);
      expect(ledger.verifyStepExecuted('step-2'), false);
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 9. 上下文压实测试 (compact.dart)
// ═══════════════════════════════════════════════════════════

void testCompactor() {
  group('Compactor', () {
    test('禁用时返回 false', () {
      final c = Compactor(llm: MockProvider([]), contextWindow: 0);
      final session = Session();
      final (should, _, _) = c.check(session);
      expect(should, false);
    });

    test('空会话时不压实', () {
      final c = Compactor(llm: MockProvider([]), contextWindow: 100000);
      final session = Session();
      final (should, _, _) = c.check(session);
      expect(should, false);
    });

    test('compat 返回会话本身（消息不足时）', () async {
      final c = Compactor(llm: MockProvider([]), contextWindow: 100000, recentKeep: 10);
      final session = Session();
      session.add(Message.user('hi'));
      session.add(Message.assistant('hello'));
      final result = await c.compact(session, 'test');
      expect(result.messages.length, 2);
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 10. 权限门控测试 (gate.dart)
// ═══════════════════════════════════════════════════════════

void testGate() {
  group('InteractiveGate', () {
    test('默认规则中只读工具允许', () async {
      final gate = InteractiveGate();
      final (allow, _) = await gate.check('get_courses', {}, true);
      expect(allow, true);
    });

    test('默认规则中危险操作被拒绝', () async {
      final gate = InteractiveGate();
      final (allow, reason) = await gate.check('delete_file', {}, false);
      expect(allow, false);
      expect(reason, isNotEmpty);
    });

    test('NoOpGate 全部允许', () async {
      final gate = NoOpGate();
      final (allow, _) = await gate.check('anything', {}, false);
      expect(allow, true);
    });

    test('自定义规则覆盖默认', () async {
      final gate = InteractiveGate();
      gate.setLevel('get_courses', PermissionLevel.deny);
      final (allow, _) = await gate.check('get_courses', {}, true);
      expect(allow, false);
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 11. Storm Breaker 测试
// ═══════════════════════════════════════════════════════════

void testStormBreaker() {
  group('StormBreaker', () {
    test('相同错误签名达阈值后抑制', () {
      final sb = StormBreaker(threshold: 3);
      expect(sb.record('tool1', 'error1'), false); // 第1次
      expect(sb.record('tool1', 'error1'), false); // 第2次
      expect(sb.record('tool1', 'error1'), true);  // 第3次 → 抑制
    });

    test('不同签名不触发抑制', () {
      final sb = StormBreaker(threshold: 3);
      expect(sb.record('tool1', 'err_a'), false);
      expect(sb.record('tool1', 'err_b'), false); // 不同签名，计数器重置
      expect(sb.record('tool1', 'err_b'), false);
      expect(sb.record('tool1', 'err_b'), true);  // err_b 连续3次
    });

    test('成功后重置', () {
      final sb = StormBreaker(threshold: 3);
      sb.record('tool1', 'error');
      sb.record('tool1', 'error');
      sb.record('tool1', null); // 成功
      expect(sb.record('tool1', 'error'), false); // 计数器已重置
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 12. Provider 测试 (模拟 LLM)
// ═══════════════════════════════════════════════════════════

/// 悬挂 Provider——永不返回，直到外部关闭 stream（用于取消测试）。
class _HangingProvider extends Provider {
  final StreamController<ProviderEvent> _sc;
  _HangingProvider(this._sc);

  @override String get name => 'hanging';

  @override
  Stream<ProviderEvent> chat({
    required List<Message> messages,
    List<Map<String, dynamic>> tools = const [],
  }) => _sc.stream;
}

/// 模拟 Provider——返回预设的响应，不调用真实 API。
///
/// 按 `done()` 分轮次：第 N 次 chat 返回第 N 组（两个 done 之间）。
class MockProvider extends Provider {
  final List<ProviderEvent> _responses;
  int _callCount = 0;

  MockProvider(this._responses);

  @override
  String get name => 'mock';

  int get callCount => _callCount;

  @override
  Stream<ProviderEvent> chat({
    required List<Message> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    _callCount++;
    if (_responses.isEmpty) {
      // 永远挂起——用于 _HangingProvider 取代此路径
      await Future.delayed(const Duration(minutes: 10));
      return;
    }
    // 按 done() 分隔轮次：找到第 N 组
    var doneIdx = -1;
    var target = 0;
    for (var i = 0; i < _responses.length; i++) {
      if (_responses[i].kind == ProviderEventKind.done) {
        target++;
        if (target == _callCount) {
          doneIdx = i;
          break;
        }
      }
    }
    if (doneIdx >= 0) {
      // 找到目标轮次：yield 该组所有事件（含 done）
      var start = 0;
      var seen = 0;
      for (var i = 0; i <= doneIdx; i++) {
        if (_responses[i].kind == ProviderEventKind.done) seen++;
        if (seen == _callCount - 1 && i > 0) { start = i + 1; break; }
        if (_callCount == 1 && i == 0) { start = 0; break; }
      }
      // 简化：从上一个 done 之后开始，到当前 done
      var prevDone = -1;
      var count = 0;
      for (var i = 0; i < _responses.length; i++) {
        if (_responses[i].kind == ProviderEventKind.done) {
          count++;
          if (count == _callCount - 1) prevDone = i;
          if (count == _callCount) {
            // yield prevDone+1 .. i
            for (var j = prevDone + 1; j <= i; j++) {
              yield _responses[j];
            }
            return;
          }
        }
      }
    }
    // 没有 done 标记：第1次 yield 全部，第2+次只返回 done
    if (_callCount == 1) {
      for (final e in _responses) {
        yield e;
      }
      return;
    }
    yield ProviderEvent.done();
  }
}

void testProvider() {
  group('Provider (Mock)', () {
    test('返回预设的文本响应', () async {
      final provider = MockProvider([ProviderEvent.content('你好！')]);
      final events = await provider.chat(messages: [Message.user('hi')]).toList();
      expect(events.length, 1);
      expect(events[0].text, '你好！');
    });

    test('返回工具调用', () async {
      final calls = [ToolCall(id: 'c1', name: 'get_courses', arguments: '{}')];
      final provider = MockProvider([ProviderEvent.toolCalls(calls)]);
      final events = await provider.chat(messages: [Message.user('查课程')]).toList();
      expect(events.length, 1);
      expect(events[0].toolCalls?.length, 1);
      expect(events[0].toolCalls![0].name, 'get_courses');
    });

    test('跟踪调用次数', () async {
      final provider = MockProvider([ProviderEvent.content('ok')]);
      await provider.chat(messages: []).toList();
      await provider.chat(messages: []).toList();
      expect(provider.callCount, 2);
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 13. ZJU 数据源测试
// ═══════════════════════════════════════════════════════════

class MockZjuDataSource extends ZjuDataSource {
  @override
  Future<List<ZjuCourse>> getCourses() async => [
        ZjuCourse(id: 1, name: '数据结构', teacher: '张老师', isActive: true),
        ZjuCourse(id: 2, name: '操作系统', teacher: '李老师', isActive: true),
      ];

  @override
  Future<ZjuScoreResult?> getScores() async => ZjuScoreResult(
        fivePointGpa: 4.5,
        fourPointThreeGpa: 4.0,
        fourPointGpa: 3.9,
        hundredPointGpa: 88.5,
        totalCredits: 120,
        courseCount: 30,
      );

  @override
  Future<List<ZjuClassroomCourse>> getClassroomCourses() async => [];

  @override
  Future<ZjuEcardResult?> getEcardBalance() async =>
      ZjuEcardResult(balance: 123.45);

  @override
  Future<List<ZjuTodo>> getTodos() async => [
        ZjuTodo(id: '1', title: '数据结构作业', deadline: '2025-07-01'),
      ];

  @override
  Future<List<ZjuExam>> getExams() async => [
        ZjuExam(name: '期末考试', startTime: DateTime(2025, 7, 10)),
      ];

  @override
  Future<List<ZjuNotification>> getNotifications() async => [];

  @override
  Future<List<ZjuTimetableEntry>> getTimetable() async => [];
}

void testZjuTools() {
  group('ZJU 工具', () {
    late ZjuDataSource mock;

    setUp(() {
      mock = MockZjuDataSource();
    });

    test('get_courses 返回课程列表', () async {
      final tool = ZjuCoursesTool(mock);
      final result = await tool.execute({});
      expect(result, contains('数据结构'));
      expect(result, contains('操作系统'));
      expect(result, contains('2'));
    });

    test('get_scores 返回 GPA', () async {
      final tool = ZjuScoresTool(mock);
      final result = await tool.execute({});
      expect(result, contains('4.5'));
      expect(result, contains('3.9'));
      expect(result, contains('4.0'));
      expect(result, contains('88.5'));
    });

    test('ecard_balance 返回余额', () async {
      final tool = ZjuEcardTool(mock);
      final result = await tool.execute({});
      expect(result, contains('123.45'));
    });

    test('get_todos 返回待办', () async {
      final tool = ZjuTodosTool(mock);
      final result = await tool.execute({});
      expect(result, contains('数据结构作业'));
    });

    test('get_exams 返回考试', () async {
      final tool = ZjuExamsTool(mock);
      final result = await tool.execute({});
      expect(result, contains('期末考试'));
    });

    test('空数据源不崩溃', () async {
      final empty = _EmptyDataSource();
      final tool = ZjuCoursesTool(empty);
      final result = await tool.execute({});
      expect(result, isNotEmpty);
    });
  });
}

class _EmptyDataSource extends ZjuDataSource {
  @override Future<List<ZjuCourse>> getCourses() async => [];
  @override Future<ZjuScoreResult?> getScores() async => null;
  @override Future<List<ZjuClassroomCourse>> getClassroomCourses() async => [];
  @override Future<ZjuEcardResult?> getEcardBalance() async => null;
  @override Future<List<ZjuTodo>> getTodos() async => [];
  @override Future<List<ZjuExam>> getExams() async => [];
  @override Future<List<ZjuNotification>> getNotifications() async => [];
  @override Future<List<ZjuTimetableEntry>> getTimetable() async => [];
}

// ═══════════════════════════════════════════════════════════
// 14. 端到端：Agent + Mock Provider
// ═══════════════════════════════════════════════════════════

void testAgentE2e() {
  group('Agent 端到端（Mock Provider）', () {
    test('文本回复：输入→LLM→文本输出', () async {
      final provider = MockProvider([
        ProviderEvent.content('你有 6 门课程'),
        ProviderEvent.usage(TokenUsage(promptTokens: 50, completionTokens: 10, totalTokens: 60)),
        ProviderEvent.done(),
      ]);
      final registry = Registry();
      registry.register(MockTool(toolName: 'get_courses'));
      final session = Session();
      final sink = StreamEventSink();

      final agent = Agent(
        provider: provider,
        registry: registry,
        session: session,
        sink: EventSink.discard,
      );

      final events = await agent.run(input: '有哪些课程？').toList();

      // 验证事件流包含关键事件
      expect(events.any((e) => e.kind == EventKind.turnStarted), true);
      expect(events.any((e) => e.kind == EventKind.text), true);
      expect(events.any((e) => e.kind == EventKind.turnDone), true);
      expect(session.messages.length >= 2, true); // user + assistant
    });

    test('工具调用：输入→LLM→工具→结果→文本', () async {
      final provider = MockProvider([
        ProviderEvent.toolCalls([
          ToolCall(id: 'c1', name: 'get_courses', arguments: '{}'),
        ]),
        ProviderEvent.usage(TokenUsage(promptTokens: 50, completionTokens: 5, totalTokens: 55)),
        ProviderEvent.done(),
        // 第二轮：工具结果反馈给 LLM 后的回复
        ProviderEvent.content('查询到 2 门课程'),
        ProviderEvent.done(),
      ]);
      final registry = Registry();
      registry.register(MockTool(toolName: 'get_courses', mockResult: {'count': 2}));
      final session = Session();
      final sink = StreamEventSink();

      final agent = Agent(
        provider: provider,
        registry: registry,
        session: session,
        sink: EventSink.discard,
      );

      final events = await agent.run(input: '查课程').toList();

      // 验证工具被调用
      expect(events.any((e) => e.kind == EventKind.toolDispatch), true);
      expect(events.any((e) => e.kind == EventKind.toolResult), true);
    });

    test('取消运行', () async {
      // 使用永不完结的 StreamController 模拟卡住的 Provider
      final sc = StreamController<ProviderEvent>();
      final provider = _HangingProvider(sc);
      final registry = Registry();
      final session = Session();

      final agent = Agent(
        provider: provider,
        registry: registry,
        session: session,
        sink: EventSink.discard,
      );

      // 异步启动，然后在 chat 卡住时 cancel
      final runFuture = agent.run(input: '测试').toList();
      // 给 agent 一点时间进入 chat()
      await Future.delayed(const Duration(milliseconds: 50));
      // cancel 后再关闭 stream 让 agent 能退出来
      agent.cancel();
      sc.close();

      final events = await runFuture.timeout(
        const Duration(seconds: 5),
        onTimeout: () => [],
      );
      expect(events.any((e) => e.kind == EventKind.turnDone), true);
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 主入口
// ═══════════════════════════════════════════════════════════

void main() {
  testMessageModel();
  testToolSystem();
  testSession();
  testCompose();
  testEventSystem();
  testMemory();
  testOutputStyle();
  testEvidence();
  testCompactor();
  testGate();
  testStormBreaker();
  testProvider();
  testZjuTools();
  testAgentE2e();
}
