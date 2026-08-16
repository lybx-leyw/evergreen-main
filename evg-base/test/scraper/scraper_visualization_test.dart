// Phase 2 可视化组件测试：Stepper / Graph / AgentStepIndicator。
//
// 覆盖：
// 1. Stepper：各阶段渲染、当前态、completed 勾选、failed 红叉
// 2. Graph：节点渲染、回退轨迹、refining 轮次角标
// 3. AgentStepIndicator：空闲/思考/调用工具/失败 状态
import 'package:evergreen_base/renderer/components/shared/widgets/agent_step_indicator.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow_graph.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow_stepper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ScraperWorkflowStepper', () {
    testWidgets('渲染 6 个流程阶段名（compact）', (tester) async {
      final w = ScraperWorkflow()..startCapturing();
      await tester.pumpWidget(_wrap(ScraperWorkflowStepper(
        workflow: w,
        compact: true,
      )));
      await tester.pump();
      expect(find.text('抓包'), findsOneWidget);
      expect(find.text('分析'), findsOneWidget);
      expect(find.text('生成'), findsOneWidget);
      expect(find.text('运行'), findsOneWidget);
      expect(find.text('调试'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
    });

    testWidgets('非 compact 模式显示当前阶段标签', (tester) async {
      final w = ScraperWorkflow()..startCapturing();
      await tester.pumpWidget(_wrap(ScraperWorkflowStepper(workflow: w)));
      await tester.pump();
      expect(find.text('抓包中'), findsOneWidget);
    });

    testWidgets('failed 状态显示失败阶段（不崩溃）', (tester) async {
      final w = ScraperWorkflow()
        ..startCapturing()
        ..markFailed('测试失败');
      await tester.pumpWidget(_wrap(ScraperWorkflowStepper(workflow: w)));
      await tester.pump();
      // 不崩溃即通过
      expect(find.byType(ScraperWorkflowStepper), findsOneWidget);
    });

    testWidgets('debugging 状态显示调试轮次徽标（compact）', (tester) async {
      final w = ScraperWorkflow()..startCapturing();
      w.startDebugging();
      w.startDebugging();
      await tester.pumpWidget(_wrap(ScraperWorkflowStepper(
        workflow: w,
        compact: true,
      )));
      await tester.pump();
      expect(find.textContaining('🔧'), findsOneWidget);
    });
  });

  group('ScraperWorkflowGraph', () {
    testWidgets('渲染节点 + refining 角标', (tester) async {
      final w = ScraperWorkflow()
        ..startCapturing()
        ..markDone()
        ..feedbackTriggered();
      await tester.pumpWidget(_wrap(ScraperWorkflowGraph(workflow: w)));
      await tester.pump();
      expect(find.text('工作流'), findsOneWidget);
      expect(find.text('优化第 1 轮'), findsOneWidget);
      expect(find.text('抓包（用户操作）'), findsOneWidget);
      expect(find.text('AI 生成代码'), findsOneWidget);
    });

    testWidgets('回退轨迹渲染（不崩溃）', (tester) async {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(_log('https://a.com/1'));
      w.startAnalyzing();
      w.rollbackTo(ScraperPhase.capturing);
      await tester.pumpWidget(_wrap(ScraperWorkflowGraph(workflow: w)));
      await tester.pump();
      expect(find.text('抓包（用户操作）'), findsOneWidget);
      expect(find.text('回退轨迹'), findsOneWidget); // 图例
    });

    testWidgets('done 状态渲染完成节点', (tester) async {
      final w = ScraperWorkflow()
        ..startCapturing()
        ..markDone();
      await tester.pumpWidget(_wrap(ScraperWorkflowGraph(workflow: w)));
      await tester.pump();
      expect(find.text('✅ 完成'), findsOneWidget);
    });
  });

  group('AgentStepIndicator', () {
    testWidgets('空闲 → 就绪', (tester) async {
      await tester.pumpWidget(_wrap(const AgentStepIndicator(running: false)));
      expect(find.text('就绪'), findsOneWidget);
    });

    testWidgets('运行中无工具 → 思考中', (tester) async {
      await tester.pumpWidget(_wrap(const AgentStepIndicator(running: true)));
      expect(find.text('思考中…'), findsOneWidget);
    });

    testWidgets('调用工具 → 显示工具名与步骤', (tester) async {
      await tester.pumpWidget(_wrap(const AgentStepIndicator(
        running: true,
        currentTool: 'run_python_scraper',
        step: 3,
        maxSteps: 50,
      )));
      expect(find.textContaining('run_python_scraper'), findsOneWidget);
      expect(find.textContaining('第 3/50 步'), findsOneWidget);
    });

    testWidgets('工具失败 → 错误提示', (tester) async {
      await tester.pumpWidget(_wrap(const AgentStepIndicator(
        running: true,
        currentTool: 'run_python_scraper',
        hasError: true,
      )));
      expect(find.textContaining('失败'), findsOneWidget);
    });
  });
}

HttpRequestLog _log(String url) => HttpRequestLog(
      timestamp: DateTime.now(),
      method: 'GET',
      url: url,
    );
