// agent_trace_recorder 测试（Phase 3 · C1-C5 数据层）。
//
// 覆盖：
// 1. 初始空状态 / clear()
// 2. round 分组：turnStarted→turnDone 成轮，事件归类
// 3. recordTool 摘要 + [error] 标记（C3）
// 4. recordThink 时长
// 5. recordReply 预览 ≤500 + UTF-8 字节数
// 6. 环形缓冲：超上限丢最旧（含 open round 内淘汰）
// 7. JSONL 落盘：schema_version/seq/ts/kind（trajectory 风格）
// 8. JSONL 单行 50KB 保护 + 整体 1MB 保护停写
// 9. 事件流订阅兜底：reasoning→message 自动产 think+reply
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/renderer/components/shared/trace/agent_trace_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('trace_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  StreamController<agent.AgentEvent> newStream() =>
      StreamController<agent.AgentEvent>.broadcast();

  group('round 分组', () {
    test('初始为空：rounds 空 / totalEvents 0', () {
      final r = AgentTraceRecorder();
      expect(r.rounds, isEmpty);
      expect(r.totalEvents, 0);
      expect(r.hasOpenRound, isFalse);
    });

    test('turnStarted→turnDone 形成一个 round，事件归类正确', () async {
      final r = AgentTraceRecorder();
      final ctrl = newStream();
      r.attach(ctrl.stream);

      ctrl.add(agent.AgentEvent.turnStarted());
      await Future<void>.delayed(Duration.zero); // 等 turnStarted 投递（broadcast 微任务）
      r.recordTool('run_python_scraper', 'code=...', '3 行 / 120 字符 / ok');
      ctrl.add(agent.AgentEvent.reasoning('先看日志…'));
      ctrl.add(agent.AgentEvent.message(
          text: '爬虫已跑通', reasoning: '先看日志…'));
      ctrl.add(agent.AgentEvent.turnDone());
      await Future<void>.delayed(Duration.zero);

      final rounds = r.rounds;
      expect(rounds, hasLength(1));
      expect(rounds.first.index, 1);
      expect(rounds.first.duration.inMilliseconds, greaterThanOrEqualTo(0));
      // tool + think + reply = 3 事件
      expect(rounds.first.eventCount, 3);
      final kinds =
          rounds.first.events.map((e) => e.runtimeType).toList();
      expect(kinds, contains(TraceToolEvent));
      expect(kinds, contains(TraceThinkEvent));
      expect(kinds, contains(TraceReplyEvent));
      expect(r.totalEvents, 3);

      // 新一轮 → Round 2
      ctrl.add(agent.AgentEvent.turnStarted());
      ctrl.add(agent.AgentEvent.turnDone());
      await Future<void>.delayed(Duration.zero);
      expect(r.rounds, hasLength(2));
      expect(r.rounds.last.index, 2);
      expect(r.hasOpenRound, isFalse);

      await ctrl.close();
      r.dispose();
    });

    test('recordTool 在无 open round 时懒开轮次', () {
      final r = AgentTraceRecorder();
      r.recordTool('ask', '(无参数)', '用户回答：选 A');
      expect(r.hasOpenRound, isTrue);
      expect(r.totalEvents, 1);
    });
  });

  group('三类事件字段', () {
    test('recordTool 摘要 + isError → [error] 标记（C3）', () {
      final r = AgentTraceRecorder();
      r.recordTool('run_terminal_command', 'python scraper.py',
          '2 行 / 80 字符 / ❌ Traceback', isError: true);
      r.recordTool('ask', '(无参数)', '1 行 / 30 字符 / 用户回答', isError: false);
      final events = r.rounds.first.events;
      final toolErr = events.first as TraceToolEvent;
      expect(toolErr.isError, isTrue);
      expect(toolErr.tool, 'run_terminal_command');
      expect(toolErr.argsSummary, 'python scraper.py');
      expect(toolErr.resultSummary, contains('Traceback'));
      final toolOk = events.last as TraceToolEvent;
      expect(toolOk.isError, isFalse);
    });

    test('recordThink 保留时长', () {
      final r = AgentTraceRecorder();
      r.recordThink(const Duration(milliseconds: 4200));
      final e = r.rounds.first.events.single as TraceThinkEvent;
      expect(e.elapsed, const Duration(milliseconds: 4200));
    });

    test('recordReply 预览 ≤500 + UTF-8 字节数', () {
      final r = AgentTraceRecorder();
      // 中文：'你好' UTF-8 = 6 字节
      r.recordReply('你好，爬虫已跑通', utf8.encode('你好，爬虫已跑通').length);
      final e = r.rounds.first.events.single as TraceReplyEvent;
      expect(e.byteCount, utf8.encode('你好，爬虫已跑通').length);

      // 超 500 字符 → 截断 + '…'
      final long = 'x' * 600;
      r.recordReply(long, utf8.encode(long).length);
      final e2 = r.rounds.last.events.last as TraceReplyEvent;
      expect(e2.preview.length, 501); // 500 + 省略号
      expect(e2.preview.endsWith('…'), isTrue);
      expect(e2.byteCount, 600);
    });

    test('事件流兜底：reasoning→message 自动产生 think+reply', () async {
      final r = AgentTraceRecorder();
      final ctrl = newStream();
      r.attach(ctrl.stream);
      ctrl.add(agent.AgentEvent.turnStarted());
      ctrl.add(agent.AgentEvent.reasoning('分析日志'));
      ctrl.add(agent.AgentEvent.message(
          text: '✅ 爬虫执行成功', reasoning: '分析日志'));
      ctrl.add(agent.AgentEvent.turnDone());
      await Future<void>.delayed(Duration.zero);

      final events = r.rounds.first.events;
      final think =
          events.whereType<TraceThinkEvent>().single;
      expect(think.preview, '分析日志');
      final reply = events.whereType<TraceReplyEvent>().single;
      expect(reply.preview, '✅ 爬虫执行成功');
      expect(reply.byteCount, utf8.encode('✅ 爬虫执行成功').length);

      await ctrl.close();
      r.dispose();
    });
  });

  group('环形缓冲', () {
    test('超上限丢最旧事件', () {
      final r = AgentTraceRecorder(maxEvents: 5);
      for (var i = 0; i < 7; i++) {
        r.recordTool('tool_$i', 'a', 'r', isError: i.isOdd);
      }
      expect(r.totalEvents, 5);
      final events = r.rounds.first.events;
      expect(events, hasLength(5));
      // 最旧的 tool_0 / tool_1 被淘汰
      expect((events.first as TraceToolEvent).tool, 'tool_2');
      expect((events.last as TraceToolEvent).tool, 'tool_6');
    });
  });

  group('JSONL 落盘（trajectory 风格 + 大小保护）', () {
    test('记录 schema_version/seq/ts/kind', () {
      final path = pJoin(tmp.path, 'trace.jsonl');
      final r = AgentTraceRecorder(jsonlPath: path);
      r.recordTool('run_python_scraper', 'code', 'ok');
      r.recordThink(const Duration(seconds: 2));
      r.recordReply('你好', 6);
      r.flushJsonl();

      final lines = File(path).readAsLinesSync();
      expect(lines, hasLength(3));
      final first = jsonDecode(lines[0]) as Map<String, dynamic>;
      expect(first['schema_version'], 1);
      expect(first['seq'], 1);
      expect(first['ts'], isA<int>());
      expect(first['kind'], 'tool');
      expect(first['tool'], 'run_python_scraper');
      expect(first['is_error'], false);
      final third = jsonDecode(lines[2]) as Map<String, dynamic>;
      expect(third['kind'], 'reply');
      expect(third['bytes'], 6);

      r.dispose();
    });

    test('单行超限截断（50KB 保护）', () {
      final path = pJoin(tmp.path, 'trace.jsonl');
      final r = AgentTraceRecorder(
          jsonlPath: path, maxJsonlLineBytes: 64);
      r.recordTool('tool', 'a', 'r' * 1000);
      r.flushJsonl();
      final line = File(path).readAsLinesSync().single;
      expect(line.length, lessThanOrEqualTo(66)); // 64 + '…}'
      r.dispose();
    });

    test('整体超限停写（1MB 保护）', () {
      final path = pJoin(tmp.path, 'trace.jsonl');
      final r = AgentTraceRecorder(
          jsonlPath: path, maxJsonlBytes: 1500);
      // 第一批 ~10 条（~1.2KB）→ 写入
      for (var i = 0; i < 10; i++) {
        r.recordTool('tool_$i', 'args', 'result');
      }
      r.flushJsonl();
      final sizeAfterBatch1 = File(path).lengthSync();
      expect(sizeAfterBatch1, greaterThan(1000));
      expect(sizeAfterBatch1, lessThan(1500));
      // 第二批 → 累计超 1500 → 停写
      for (var i = 0; i < 10; i++) {
        r.recordTool('tool_$i', 'args', 'result');
      }
      r.flushJsonl();
      expect(File(path).lengthSync(), sizeAfterBatch1);
      // 后续事件也不再写
      r.recordTool('tool_x', 'a', 'r');
      r.flushJsonl();
      expect(File(path).lengthSync(), sizeAfterBatch1);
      r.dispose();
    });

    test('不设路径 → 不落盘', () {
      final r = AgentTraceRecorder();
      r.recordTool('tool', 'a', 'r');
      r.flushJsonl();
      r.dispose(); // 不抛异常即可
    });
  });

  group('clear', () {
    test('清空全部轮次与事件', () {
      final r = AgentTraceRecorder();
      r.recordTool('a', 'a', 'r');
      r.recordReply('hi', 2);
      expect(r.totalEvents, 2);
      r.clear();
      expect(r.rounds, isEmpty);
      expect(r.totalEvents, 0);
      expect(r.hasOpenRound, isFalse);
    });
  });
}

String pJoin(String dir, String name) => '$dir${Platform.pathSeparator}$name';
