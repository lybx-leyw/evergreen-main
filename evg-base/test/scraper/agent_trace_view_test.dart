// agent_trace_view 测试（Phase 3 · C4 笔记本横线风格视图）。
//
// 覆盖：
// 1. 空态文案
// 2. Round 标题（Round N · 时长 · events）
// 3. 固定宽度前缀列（● tool / ● think / ● reply）
// 4. 三类事件内容渲染
// 5. [error] 红色高亮标记（C3）
import 'package:evergreen_base/renderer/components/shared/trace/agent_trace_recorder.dart';
import 'package:evergreen_base/renderer/components/shared/trace/agent_trace_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(AgentTraceRecorder recorder) => MaterialApp(
        home: Scaffold(
          body: AgentTraceView(recorder: recorder),
        ),
      );

  testWidgets('空态：暂无轨迹提示', (tester) async {
    final recorder = AgentTraceRecorder();
    await tester.pumpWidget(wrap(recorder));
    expect(find.text('暂无轨迹，开始一次对话后自动记录'), findsOneWidget);
    recorder.dispose();
  });

  testWidgets('渲染三类事件 + 前缀列 + Round 标题 + [error] 红标', (tester) async {
    final recorder = AgentTraceRecorder();
    recorder.recordTool('run_python_scraper', 'code=...', '3 行 / 120 字符 / ✅',
        isError: true);
    recorder.recordThink(const Duration(milliseconds: 4200));
    recorder.recordReply('你好，爬虫已跑通', 18);
    await tester.pumpWidget(wrap(recorder));

    // Round 标题（粗线分轮次）
    expect(find.textContaining('Round 1'), findsOneWidget);
    expect(find.textContaining('3 events'), findsOneWidget);

    // 固定宽度前缀列（● tool / ● think / ● reply）
    expect(find.text('● tool'), findsOneWidget);
    expect(find.text('● think'), findsOneWidget);
    expect(find.text('● reply'), findsOneWidget);

    // 工具事件内容 + [error] 标记
    expect(find.textContaining('run_python_scraper'), findsOneWidget);
    expect(find.text('[error]'), findsOneWidget);

    // 思考时长摘要（4200ms → "思考 4.2s"）
    expect(find.textContaining('思考 4.2s'), findsOneWidget);

    // 回复预览 + UTF-8 字节数
    expect(find.textContaining('你好，爬虫已跑通'), findsOneWidget);
    expect(find.textContaining('18 bytes · UTF-8'), findsOneWidget);

    recorder.dispose();
  });

  testWidgets('[error] 标记仅在失败工具上出现', (tester) async {
    final recorder = AgentTraceRecorder();
    recorder.recordTool('ask', '(无参数)', '用户回答', isError: false);
    await tester.pumpWidget(wrap(recorder));
    expect(find.text('[error]'), findsNothing);
    recorder.dispose();
  });

  testWidgets('多轮次渲染：Round 1 / Round 2 分节', (tester) async {
    final recorder = AgentTraceRecorder();
    recorder.recordTool('tool_a', 'a', 'r');
    recorder.recordTool('tool_b', 'b', 'r');
    recorder.recordTool('tool_c', 'c', 'r');
    await tester.pumpWidget(wrap(recorder));
    expect(find.textContaining('Round 1'), findsOneWidget);
    // 事件前缀列数量 = 3 行 tool
    expect(find.text('● tool'), findsNWidgets(3));
    recorder.dispose();
  });
}
