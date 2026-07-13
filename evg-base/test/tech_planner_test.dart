/// 组件 #65：AI 技术规划编辑器 — 单元测试与 Widget 冒烟测试。
///
/// 覆盖：
/// - TechDocument 序列化/反序列化
/// - TechAnalysisReport JSON 解析（成功 + 降级路径）
/// - AiDiffProposer 改写提案生成
/// - TechPlannerView Widget 冒烟测试
///
/// 运行：cd evg-base && flutter test test/tech_planner_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_base/renderer/components/document/tech_planner/tech_planner.dart';
import 'package:evergreen_base/renderer/components/document/tech_planner/models/tech_document.dart';
import 'package:evergreen_base/renderer/components/document/tech_planner/models/tech_version.dart';
import 'package:evergreen_base/renderer/components/document/tech_planner/models/trace_record.dart';
import 'package:evergreen_base/renderer/components/document/tech_planner/ai/ai_diff_proposer.dart';
import 'package:evergreen_base/renderer/components/document/tech_planner/ai/ai_tech_skill.dart';
import 'package:evergreen_base/renderer/components/document/tech_planner/ai/ai_web_research.dart';
import 'package:evergreen_base/renderer/components/document/tech_planner/services/doc_trace_service.dart';
import 'package:evergreen_base/renderer/components/document/tech_planner/services/doc_export_service.dart';
import 'package:evergreen_base/renderer/components/document/tech_planner/services/doc_autosave_service.dart';
import 'package:evergreen_base/renderer/components/document/tech_planner/services/repo_config_service.dart';
import 'package:evergreen_base/renderer/components/document/tech_planner/renderTechPlanner.dart';
import 'package:evergreen_base/renderer/components/document/tech_planner/view/ghost_text_overlay.dart';

void main() {
  // TechDocument
  group('TechDocument', () {
    test('toJson / fromJson roundtrip', () {
      final doc = TechDocument(
        id: 'test-id-1',
        title: '测试技术规划',
        content: '# 架构设计\n使用 Flutter + Riverpod',
        createdAt: DateTime(2026, 7, 11),
        updatedAt: DateTime(2026, 7, 11, 14, 30),
      );
      final json = doc.toJson();
      final restored = TechDocument.fromJson(json);
      expect(restored.id, equals('test-id-1'));
      expect(restored.title, equals('测试技术规划'));
      expect(restored.content, contains('Flutter'));
      expect(restored.createdAt.year, equals(2026));
      expect(restored.updatedAt.hour, equals(14));
    });

    test('fromJson missing fields use defaults', () {
      final restored = TechDocument.fromJson({'id': 'min-id'});
      expect(restored.id, equals('min-id'));
      expect(restored.title, equals('未命名技术规划'));
      expect(restored.content, equals(''));
    });

    test('mutate content and updatedAt', () {
      final doc = TechDocument(id: 'mutable', content: 'old');
      final before = doc.updatedAt;
      doc.content = 'new content';
      doc.updatedAt = before.add(const Duration(milliseconds: 1));
      expect(doc.content, equals('new content'));
      expect(doc.updatedAt.isAfter(before), isTrue);
    });
  });

  // TechAnalysisReport
  group('TechAnalysisReport', () {
    test('fromJsonString parses valid JSON report', () {
      const json = '''
{
  "understanding": "用户希望构建一个跨平台桌面应用",
  "evidence": [
    {"source": "Flutter 官方", "content": "Flutter 3.x 支持 Windows/macOS/Linux",
     "url": "https://flutter.dev"}
  ],
  "blindSpots": ["未考虑跨平台文件系统差异"],
  "newIdeas": ["使用 path_provider 处理路径"],
  "risks": []
}
''';
      final report = TechAnalysisReport.fromJsonString(json);
      expect(report.isEmpty, isFalse);
      expect(report.understanding, contains('跨平台桌面应用'));
      expect(report.evidence.length, equals(1));
      expect(report.evidence.first.source, equals('Flutter 官方'));
      expect(report.evidence.first.content, contains('Windows'));
      expect(report.blindSpots.length, equals(1));
      expect(report.newIdeas.length, equals(1));
      expect(report.risks, isEmpty);
    });

    test('fromJsonString handles empty JSON gracefully', () {
      final report = TechAnalysisReport.fromJsonString('{}');
      expect(report.isEmpty, isTrue);
      expect(report.understanding, isEmpty);
    });

    test('fromJsonString degradation: plain text becomes understanding', () {
      const plainText = '这是一个非 JSON 的纯文本回答';
      final report = TechAnalysisReport.fromJsonString(plainText);
      expect(report.understanding, equals(plainText));
      expect(report.rawResponse, equals(plainText));
      expect(report.evidence, isEmpty);
      expect(report.blindSpots, isEmpty);
    });

    test('fromJsonString handles malformed JSON gracefully', () {
      final report = TechAnalysisReport.fromJsonString('不是 JSON {broken');
      expect(report.understanding, equals('不是 JSON {broken'));
      expect(report.rawResponse, equals('不是 JSON {broken'));
    });

    test('fromJsonString handles nested evidence list correctly', () {
      const json = '''
{
  "understanding": "测试",
  "evidence": [
    {"source": "S1", "content": "C1"},
    {"source": "S2", "content": "C2", "url": "https://example.com"}
  ]
}
''';
      final report = TechAnalysisReport.fromJsonString(json);
      expect(report.evidence.length, equals(2));
      expect(report.evidence[0].source, equals('S1'));
      expect(report.evidence[0].content, equals('C1'));
      expect(report.evidence[1].source, equals('S2'));
      expect(report.evidence[1].url, equals('https://example.com'));
    });

    test('empty() factory returns empty report', () {
      final report = TechAnalysisReport.empty();
      expect(report.isEmpty, isTrue);
      expect(report.understanding, isEmpty);
    });
  });

  // AiDiffProposer
  group('AiDiffProposer', () {
    test('proposeRevision appends appendix', () {
      const original = '# 技术规划\n使用 Flutter';
      final report = TechAnalysisReport(
        understanding: '用户想做跨平台应用',
        evidence: [
          const TechEvidence(
            source: 'Flutter 官方',
            content: 'Flutter 支持多平台',
          ),
        ],
        blindSpots: ['未考虑性能优化', '缺少错误处理方案'],
        newIdeas: ['使用 Isolate 做后台计算'],
        risks: ['Dart 不支持某些底层 API'],
      );
      final result = AiDiffProposer.proposeRevision(original, report);
      expect(result, contains(original));
      expect(result, contains('## 技术调研附录'));
      expect(result, contains('### 注意事项'));
      expect(result, contains('- ⚠️ 未考虑性能优化'));
      expect(result, contains('- ⚠️ 缺少错误处理方案'));
      expect(result, contains('### 可选方案'));
      expect(result, contains('- 💡 使用 Isolate 做后台计算'));
      expect(result, contains('### 技术参考'));
      expect(result, contains('**Flutter 官方**：Flutter 支持多平台'));
      expect(result, contains('### ⚠️ 风险提醒'));
      expect(result, contains('- 🔴 Dart 不支持某些底层 API'));
    });

    test('proposeRevision skips empty sections', () {
      const original = '只有一行';
      final report = TechAnalysisReport(understanding: '简单规划');
      final result = AiDiffProposer.proposeRevision(original, report);
      expect(result, contains(original));
      expect(result, contains('## 技术调研附录'));
      expect(result.contains('### 注意事项'), isFalse);
      expect(result.contains('### 可选方案'), isFalse);
      expect(result.contains('### 技术参考'), isFalse);
      expect(result.contains('### ⚠️ 风险提醒'), isFalse);
    });
  });

  // AI Tech Skill
  group('techAnalysisSkillBody', () {
    test('generates prompt with document content injected', () {
      const docContent = '# 测试\n使用 WebSocket';
      final prompt = techAnalysisSkillBody(docContent);
      expect(prompt, contains('技术设计师'));
      expect(prompt, contains('先相信意图'));
      expect(prompt, contains('"understanding"'));
      expect(prompt, contains('"evidence"'));
      expect(prompt, contains('"blindSpots"'));
      expect(prompt, contains('"newIdeas"'));
      expect(prompt, contains('"risks"'));
      expect(prompt, contains(docContent));
    });

    test('techAnalysisSkillHead contains core principles', () {
      expect(techAnalysisSkillHead, contains('先相信意图'));
      expect(techAnalysisSkillHead, contains('绝不审查与推翻'));
    });
  });

  // AiWebResearch
  group('AiWebResearch.parseSearchOutput', () {
    test('parses standard Bing search output format', () {
      const raw = '''
搜索 "flutter websocket 方案" 的结果:

Flutter WebSocket 通信 - 官方文档
  dart.dev 提供 WebSocket API，支持全双工通信……
  https://dart.dev/guides/websockets

WebSocket vs SSE 技术对比
  详细比较 WebSocket 与 Server-Sent Events 的适用场景和性能差异
  https://example.com/ws-vs-sse
''';
      final items = AiWebResearch.parseSearchOutput(raw);
      expect(items.length, equals(2));

      expect(items[0].title, equals('Flutter WebSocket 通信 - 官方文档'));
      expect(items[0].snippet, contains('dart.dev'));
      expect(items[0].url, equals('https://dart.dev/guides/websockets'));
      expect(items[0].toEvidence().source, equals('Flutter WebSocket 通信 - 官方文档'));
      expect(items[0].toEvidence().url, equals('https://dart.dev/guides/websockets'));

      expect(items[1].title, equals('WebSocket vs SSE 技术对比'));
      expect(items[1].snippet, contains('详细比较'));
      expect(items[1].url, equals('https://example.com/ws-vs-sse'));
    });

    test('returns empty list for empty input', () {
      expect(AiWebResearch.parseSearchOutput(''), isEmpty);
    });

    test('returns empty list for error output', () {
      const errorOutput = '[搜索失败: Connection timed out]';
      expect(AiWebResearch.parseSearchOutput(errorOutput), isEmpty);
    });

    test('handles output without URLs gracefully', () {
      const raw = '''
搜索 "test" 的结果:

无URL结果1
  这是一条没有URL的结果
''';
      final items = AiWebResearch.parseSearchOutput(raw);
      expect(items.length, equals(1));
      expect(items[0].title, equals('无URL结果1'));
      expect(items[0].url, isEmpty);
      expect(items[0].hasUrl, isFalse);
    });

    test('handles multi-snippet lines merged correctly', () {
      const raw = '''
搜索 "docker kubernetes" 的结果:

Docker vs Kubernetes 入门
  Docker 是容器化平台
  Kubernetes 是容器编排工具
  两者常常配合使用
  https://kubernetes.io/docs/
''';
      final items = AiWebResearch.parseSearchOutput(raw);
      expect(items.length, equals(1));
      expect(items[0].snippet, contains('Docker'));
      expect(items[0].snippet, contains('Kubernetes'));
      expect(items[0].snippet, contains('配合使用'));
    });

    test('WebResearchItem.hasUrl returns false for empty url', () {
      final item = WebResearchItem(title: 'test', snippet: 's', url: '');
      expect(item.hasUrl, isFalse);
      expect(item.toEvidence().url, isNull);
    });

    test('WebResearchItem.hasUrl returns true for valid url', () {
      final item = WebResearchItem(title: 'test', snippet: 's', url: 'https://example.com');
      expect(item.hasUrl, isTrue);
      expect(item.toEvidence().url, equals('https://example.com'));
    });
  });

  group('AiWebResearch.buildResearchQueries', () {
    test('extracts Flutter+Riverpod keywords from doc', () {
      const doc = '我们使用 Flutter 作为前端，Riverpod 管理状态，WebSocket 实时通信。';
      final queries = AiWebResearch.buildResearchQueries(doc);
      expect(queries, isNotEmpty);
      // 至少包含一条查询
      expect(queries.any((q) => q.contains('flutter') && q.contains('websocket')), isTrue);
    });

    test('returns empty list for empty document', () {
      expect(AiWebResearch.buildResearchQueries(''), isEmpty);
    });

    test('includes architecture query when doc mentions 架构', () {
      const doc = '系统架构采用微服务模式，使用 Docker 部署。';
      final queries = AiWebResearch.buildResearchQueries(doc);
      expect(queries.any((q) => q.contains('架构') || q.contains('architecture')), isTrue);
    });

    test('includes security query when doc mentions 安全', () {
      const doc = '需要考虑 API 认证安全，使用 JWT。';
      final queries = AiWebResearch.buildResearchQueries(doc);
      expect(queries.any((q) => q.contains('安全')), isTrue);
    });
  });

  group('AiWebResearch formatting', () {
    final sampleItems = [
      const WebResearchItem(
        title: 'Flutter WebSocket',
        snippet: 'Flutter 提供 dart:io WebSocket API',
        url: 'https://dart.dev/guides/websockets',
      ),
      const WebResearchItem(
        title: 'Riverpod 状态管理',
        snippet: 'Riverpod 是编译时安全的依赖注入框架',
        url: 'https://riverpod.dev',
      ),
    ];

    test('formatAsCitationBlock generates Markdown with links', () {
      final block = AiWebResearch.formatAsCitationBlock(sampleItems);
      expect(block, contains('网络调研结果'));
      expect(block, contains('Flutter WebSocket'));
      expect(block, contains('https://dart.dev/guides/websockets'));
      expect(block, contains('Riverpod 状态管理'));
      expect(block, contains('https://riverpod.dev'));
    });

    test('formatAsCitationBlock returns empty for empty items', () {
      expect(AiWebResearch.formatAsCitationBlock([]), isEmpty);
    });

    test('formatAsCompactReference includes URLs', () {
      final ref = AiWebResearch.formatAsCompactReference(sampleItems);
      expect(ref, contains('URL: https://dart.dev/guides/websockets'));
      expect(ref, contains('URL: https://riverpod.dev'));
    });

    test('formatAsCompactReference returns empty for empty items', () {
      expect(AiWebResearch.formatAsCompactReference([]), isEmpty);
    });

    test('toEvidenceList converts correctly', () {
      final evidence = AiWebResearch.toEvidenceList(sampleItems);
      expect(evidence.length, equals(2));
      expect(evidence[0].source, equals('Flutter WebSocket'));
      expect(evidence[0].url, equals('https://dart.dev/guides/websockets'));
      expect(evidence[1].source, equals('Riverpod 状态管理'));
      expect(evidence[1].url, equals('https://riverpod.dev'));
    });
  });

  // Widget smoke tests
  group('TechPlannerView widget smoke', () {
    testWidgets('renders with initial content and title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TechPlannerView(
            initialContent: '# 冒烟测试\n## 第一行',
            title: '测试标题',
            showAiPanel: false,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('测试标题'), findsOneWidget);

      // re_editor 的光标闪烁计时器需要 pump 足够时间以正常结束
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('renders with empty content gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TechPlannerView(
            initialContent: '',
            title: '空文档',
            showAiPanel: false,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('空文档'), findsOneWidget);
      expect(find.text('暂无内容'), findsOneWidget);

      // re_editor 的光标闪烁计时器需要 pump 足够时间以正常结束
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('AiAssistPanel shows empty state with hint', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AiAssistPanel(
            currentMode: AiMode.analyze,
            report: null,
            isLoading: false,
            errorText: null,
            width: 360,
          ),
        ),
      );
      await tester.pump();
      // 新 UI：空白状态显示模式提示
      expect(find.textContaining('分析'), findsWidgets);
      expect(find.textContaining('风险分析'), findsOneWidget);
    });

    testWidgets('AiAssistPanel shows loading state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AiAssistPanel(
            currentMode: AiMode.analyze,
            report: null,
            isLoading: true,
            errorText: null,
            width: 360,
          ),
        ),
      );
      await tester.pump();
      // 新 UI：loading 状态显示模式标签
      expect(find.textContaining('正在分析'), findsOneWidget);
      expect(find.textContaining('调研技术方案'), findsOneWidget);
    });

    testWidgets('AiAssistPanel shows error state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AiAssistPanel(
            report: null,
            isLoading: false,
            errorText: '连接失败：网络错误',
            width: 360,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('连接失败：网络错误'), findsOneWidget);
    });

    testWidgets('AiAssistPanel shows report sections', (tester) async {
      final report = TechAnalysisReport(
        understanding: '用户想搭建一个后端API',
        evidence: [
          const TechEvidence(
            source: 'dart.dev',
            content: 'Dart Shelf 是一个轻量 Web 框架',
          ),
        ],
        blindSpots: ['需要考虑数据库选型'],
        newIdeas: ['使用 Riverpod 管理状态'],
        risks: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AiAssistPanel(
            currentMode: AiMode.analyze,
            report: report,
            isLoading: false,
            errorText: null,
            width: 400,
          ),
        ),
      );
      await tester.pump();
      // 新 UI：四模式面板，analyze 模式显示报告
      expect(find.text('AI 助手'), findsOneWidget);
      expect(find.text('设计理解'), findsOneWidget);
      expect(find.textContaining('搭建一个后端API'), findsOneWidget);
      expect(find.text('可行性支撑'), findsOneWidget);
      expect(find.textContaining('dart.dev'), findsOneWidget);
      expect(find.text('盲区补充'), findsOneWidget);
      expect(find.text('建议'), findsOneWidget);
      // 分析模式是只读的，不应有"应用建议改写"按钮
      expect(find.text('应用建议改写'), findsNothing);
    });
  });

  // ═══════ Phase 2: TechVersion + TraceRecord ═══════

  group('TechVersion', () {
    test('toJson / fromJson roundtrip', () {
      final version = TechVersion(
        id: 'v-1',
        documentId: 'doc-1',
        versionNumber: 1,
        fullContent: '# 标题\n正文内容',
        diffFromPrevious: '',
        changeType: VersionChangeType.manualEdit,
        traceRecordId: 'trace-1',
        description: '初始提交',
        createdAt: DateTime(2026, 7, 11, 12, 0),
      );
      final json = version.toJson();
      expect(json['id'], equals('v-1'));
      expect(json['changeType'], equals('manualEdit'));

      final restored = TechVersion.fromJson(json);
      expect(restored.id, equals('v-1'));
      expect(restored.versionNumber, equals(1));
      expect(restored.changeType, equals(VersionChangeType.manualEdit));
      expect(restored.traceRecordId, equals('trace-1'));
      expect(restored.createdAt.hour, equals(12));
    });

    test('all change types serialize correctly', () {
      for (final t in VersionChangeType.values) {
        final v = TechVersion(
          id: 'v-test', documentId: 'd', versionNumber: 1,
          fullContent: 'content', changeType: t,
        );
        final restored = TechVersion.fromJson(v.toJson());
        expect(restored.changeType, equals(t));
      }
    });
  });

  group('TraceRecord', () {
    test('toJson / fromJson roundtrip', () {
      final record = TraceRecord(
        id: 'trace-1',
        documentId: 'doc-1',
        triggerType: TraceTriggerType.atAiManual,
        contentSnapshot: '原始文档内容',
        userQuery: '请分析 WebSocket 方案',
        researchQueries: ['websocket 最佳实践'],
        createdAt: DateTime(2026, 7, 11, 13, 30),
      );
      final json = record.toJson();
      expect(json['triggerType'], equals('atAiManual'));
      expect(json['researchQueries'], contains('websocket 最佳实践'));

      final restored = TraceRecord.fromJson(json);
      expect(restored.id, equals('trace-1'));
      expect(restored.triggerType, equals(TraceTriggerType.atAiManual));
      expect(restored.userQuery, contains('WebSocket'));
      expect(restored.isCompleted, isFalse);
    });

    test('isCompleted returns true when decision is set', () {
      final json = TraceRecord(
        id: 't', documentId: 'd', triggerType: TraceTriggerType.atAiManual,
        contentSnapshot: 'snap',
        decision: TraceDecision.accepted,
      ).toJson();
      final restored = TraceRecord.fromJson(json);
      expect(restored.isCompleted, isTrue);
    });

    test('all trigger types and decisions serialize correctly', () {
      for (final trigger in TraceTriggerType.values) {
        for (final decision in TraceDecision.values) {
          final r = TraceRecord(
            id: 't', documentId: 'd', triggerType: trigger,
            contentSnapshot: 's', decision: decision,
          );
          final restored = TraceRecord.fromJson(r.toJson());
          expect(restored.triggerType, equals(trigger));
          expect(restored.decision, equals(decision));
        }
      }
    });
  });

  // ═══════ Phase 2: DocTraceService ═══════

  group('DocTraceService', () {
    test('records versions and builds timeline', () {
      final service = DocTraceService(documentId: 'doc-1');
      expect(service.versionCount, equals(0));

      service.recordVersion(fullContent: '# Version 1', description: '初始版本');
      expect(service.versionCount, equals(1));
      expect(service.latestVersion!.fullContent, equals('# Version 1'));

      service.recordVersion(
        fullContent: '# Version 2\n新增内容',
        previousContent: '# Version 1',
        changeType: VersionChangeType.manualEdit,
        description: '新增了一行',
      );
      expect(service.versionCount, equals(2));
      expect(service.versions[1].diffFromPrevious, isNotEmpty);
      expect(service.versions[1].diffFromPrevious, contains('+ 新增内容'));

      // 时间线
      final timeline = service.buildTimeline();
      expect(timeline.length, equals(2));
      expect(timeline[0].changeLabel, equals('初始版本'));
      expect(timeline[1].changeLabel, equals('新增了一行'));
    });

    test('records AI traces linked to versions', () {
      final service = DocTraceService(documentId: 'doc-2');
      service.recordVersion(fullContent: '# doc 2', description: '初始');

      final trace = service.recordTrace(
        triggerType: TraceTriggerType.atAiManual,
        contentSnapshot: '# doc 2',
        userQuery: '分析架构',
      );

      service.recordVersion(
        fullContent: '# doc 2 with AI appendix',
        previousContent: '# doc 2',
        traceRecordId: trace.id,
        changeType: VersionChangeType.aiRevision,
        description: 'AI 改写采纳',
      );

      expect(service.traceRecords.length, equals(1));
      expect(service.versions.length, equals(2));
      expect(service.versions[1].traceRecordId, equals(trace.id));

      // 时间线关联
      final timeline = service.buildTimeline();
      expect(timeline[1].traceRecord, isNotNull);
      expect(timeline[1].traceRecord!.id, equals(trace.id));
    });

    test('recordDecision updates trace status', () {
      final service = DocTraceService(documentId: 'doc-3');
      final trace = service.recordTrace(
        triggerType: TraceTriggerType.atAiManual,
        contentSnapshot: 'snapshot',
      );

      service.recordDecision(trace.id, TraceDecision.accepted);
      final updated = service.traceRecords.first;
      expect(updated.isCompleted, isTrue);
      expect(updated.decision, equals(TraceDecision.accepted));
      expect(updated.completedAt, isNotNull);
    });

    test('recordDiffResult marks diff status', () {
      final service = DocTraceService(documentId: 'doc-4');
      final trace = service.recordTrace(
        triggerType: TraceTriggerType.atAiManual,
        contentSnapshot: 'snapshot',
      );

      service.recordDiffResult(trace.id, allKept: true);
      final updated = service.traceRecords.first;
      expect(updated.diffProposed, isTrue);
      expect(updated.diffAllKept, isTrue);
    });

    test('getVersion returns correct version by number', () {
      final service = DocTraceService(documentId: 'doc-5');
      service.recordVersion(fullContent: 'v1');
      service.recordVersion(fullContent: 'v2');
      service.recordVersion(fullContent: 'v3');

      expect(service.getVersion(1)!.fullContent, equals('v1'));
      expect(service.getVersion(3)!.fullContent, equals('v3'));
      expect(service.getVersion(0), isNull);
      expect(service.getVersion(4), isNull);
    });

    test('exportJson / fromJson roundtrip', () {
      final service = DocTraceService(documentId: 'doc-6');
      service.recordVersion(fullContent: '# test', description: 'v1');
      service.recordTrace(
        triggerType: TraceTriggerType.toolbarAnalyze,
        contentSnapshot: '# test',
      );

      final json = service.exportJson();
      expect(json['documentId'], equals('doc-6'));
      expect((json['versions'] as List).length, equals(1));
      expect((json['traceRecords'] as List).length, equals(1));

      final restored = DocTraceService.fromJson('doc-6', json);
      expect(restored.versionCount, equals(1));
      expect(restored.traceRecords.length, equals(1));
    });
  });

  // ═══════ Phase 2: DocExportService ═══════

  group('DocExportService', () {
    factoryDoc() => TechDocument(
          id: 'export-test',
          title: 'WebSocket 技术方案',
          content: '# 架构设计\n\n使用 Flutter + WebSocket 实现实时通信。\n\n## 技术选型\n- dart:io WebSocket',
          createdAt: DateTime(2026, 7, 11),
          updatedAt: DateTime(2026, 7, 11, 15),
        );

    test('exportMarkdown generates valid markdown', () {
      final doc = factoryDoc();
      final service = DocExportService(document: doc);
      final result = service.exportMarkdown();

      expect(result.format, equals(ExportFormat.markdown));
      expect(result.content, contains('# WebSocket 技术方案'));
      expect(result.content, contains('dart:io WebSocket'));
      expect(result.content, contains('附录'));
      expect(result.byteSize, greaterThan(100));
    });

    test('exportHtml generates valid HTML', () {
      final doc = factoryDoc();
      final service = DocExportService(document: doc);
      final result = service.exportHtml();

      expect(result.format, equals(ExportFormat.html));
      expect(result.content, contains('<!DOCTYPE html>'));
      expect(result.content, contains('<h1>架构设计</h1>'));
      expect(result.content, contains('WebSocket'));
      expect(result.content, contains('附录'));
    });

    test('exportHtml includes trace appendix when traceService available', () {
      final doc = factoryDoc();
      final traceService = DocTraceService(documentId: doc.id);
      traceService.recordVersion(fullContent: doc.content, description: '初始');
      traceService.recordTrace(
        triggerType: TraceTriggerType.atAiManual,
        contentSnapshot: doc.content,
        userQuery: '分析',
      );
      final trace = traceService.recordTrace(
        triggerType: TraceTriggerType.toolbarAnalyze,
        contentSnapshot: doc.content,
        userQuery: '确认方案',
      );
      traceService.recordDecision(trace.id, TraceDecision.accepted);

      final service = DocExportService(document: doc, traceService: traceService);
      final html = service.exportHtml();

      expect(html.content, contains('附录 A'));
      expect(html.content, contains('附录 B'));
      expect(html.content, contains('技术决策记录'));
      expect(html.content, contains('版本数'));
    });

    test('exportPdf reuses HTML content', () {
      final doc = factoryDoc();
      final service = DocExportService(document: doc);
      final result = service.exportPdf();

      expect(result.format, equals(ExportFormat.pdf));
      expect(result.content, contains('<!DOCTYPE html>'));
    });

    test('defaultExtension maps correctly', () {
      final doc = factoryDoc();
      final service = DocExportService(document: doc);

      expect(service.exportMarkdown().defaultExtension, equals('md'));
      expect(service.exportHtml().defaultExtension, equals('html'));
      expect(service.exportPdf().defaultExtension, equals('pdf'));
    });
  });

  // ═══════ Phase 2: RenderTechPlanner ═══════

  group('RenderTechPlanner', () {
    factoryDoc() => TechDocument(
          id: 'render-test',
          title: 'Flutter App 架构',
          content: '# 系统概述\n\n基于 **Flutter** 的跨平台应用。\n\n- 前端：Flutter\n- 状态管理：Riverpod',
          createdAt: DateTime(2026, 7, 11),
          updatedAt: DateTime(2026, 7, 11, 14),
        );

    test('render generates complete HTML document', () {
      final doc = factoryDoc();
      final renderer = RenderTechPlanner(document: doc);
      final html = renderer.render();

      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('<h1>Flutter App 架构</h1>'));
      expect(html, contains('<strong>Flutter</strong>'));
      expect(html, contains('<li>前端：Flutter</li>'));
      expect(html, contains('Evergreen Multi-Tools'));
    });

    test('renderBodyOnly returns content fragment only', () {
      final doc = factoryDoc();
      final renderer = RenderTechPlanner(document: doc);
      final fragment = renderer.renderBodyOnly();

      expect(fragment, contains('<h1>系统概述</h1>'));
      expect(fragment, isNot(contains('<!DOCTYPE html>')));
      expect(fragment, isNot(contains('<head>')));
    });

    test('renders inline markdown correctly', () {
      final doc = TechDocument(
        id: 'inline-test', title: 'Test',
        content: '使用 **bold** 和 *italic* 和 `code` 和 [链接](https://example.com)',
      );
      final renderer = RenderTechPlanner(document: doc);
      final html = renderer.renderBodyOnly();

      expect(html, contains('<strong>bold</strong>'));
      expect(html, contains('<em>italic</em>'));
      expect(html, contains('<code>code</code>'));
      expect(html, contains('<a href="https://example.com"'));
    });

    test('renders code blocks', () {
      final doc = TechDocument(
        id: 'code-test', title: 'Test',
        content: '```dart\nvoid main() {\n  print("hello");\n}\n```',
      );
      final renderer = RenderTechPlanner(document: doc);
      final html = renderer.renderBodyOnly();

      expect(html, contains('<pre><code>'));
      expect(html, contains('print(&quot;hello&quot;)'));
    });

    test('renderWithExportService delegates to DocExportService', () {
      final doc = factoryDoc();
      final renderer = RenderTechPlanner(document: doc);
      final exportService = DocExportService(document: doc);
      final html = renderer.renderWithExportService(exportService);

      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('Flutter App 架构'));
    });
  });

  // ═══════ Phase 2: GhostText ═══════

  group('GhostTextState', () {
    test('empty state has no completion', () {
      const state = GhostTextState.empty;
      expect(state.hasCompletion, isFalse);
      expect(state.completionText, isNull);
      expect(state.isLoading, isFalse);
    });

    test('hasCompletion returns true when text is set', () {
      const state = GhostTextState(completionText: '补全内容');
      expect(state.hasCompletion, isTrue);
    });

    test('hasCompletion returns false for empty string', () {
      const state = GhostTextState(completionText: '');
      expect(state.hasCompletion, isFalse);
    });
  });

  group('GhostTextConfig', () {
    test('default config values', () {
      const config = GhostTextConfig();
      expect(config.color, equals(Colors.white38));
      expect(config.fontSize, equals(14));
    });

    test('custom config values', () {
      const config = GhostTextConfig(
        color: Colors.grey,
        fontSize: 16,
      );
      expect(config.color, equals(Colors.grey));
      expect(config.fontSize, equals(16));
    });
  });

  // ═══════ Phase 2: RepoConfig ═══════

  group('RepoConfig', () {
    test('toJson / fromJson roundtrip', () {
      final config = RepoConfig(
        localPath: r'D:\projects\my-app',
        remoteUrl: 'https://github.com/user/repo',
        validationStatus: RepoValidationStatus.valid,
        lastValidated: DateTime(2026, 7, 11, 16, 0),
        validationMessage: '校验通过',
      );
      final json = config.toJson();
      expect(json['localPath'], equals(r'D:\projects\my-app'));
      expect(json['validationStatus'], equals('valid'));

      final restored = RepoConfig.fromJson(json);
      expect(restored.localPath, equals(config.localPath));
      expect(restored.remoteUrl, equals(config.remoteUrl));
      expect(restored.validationStatus, equals(RepoValidationStatus.valid));
    });

    test('empty config has no valid config', () {
      final config = RepoConfig.empty();
      expect(config.hasValidConfig, isFalse);
      expect(config.localPath, isNull);
      expect(config.validationStatus, equals(RepoValidationStatus.unknown));
    });

    test('hasValidConfig returns true only when valid+path', () {
      final valid = RepoConfig(
        localPath: '/path',
        validationStatus: RepoValidationStatus.valid,
      );
      expect(valid.hasValidConfig, isTrue);

      final noPath = RepoConfig(
        validationStatus: RepoValidationStatus.valid,
      );
      expect(noPath.hasValidConfig, isFalse);

      final invalid = RepoConfig(
        localPath: '/path',
        validationStatus: RepoValidationStatus.invalid,
      );
      expect(invalid.hasValidConfig, isFalse);
    });

    test('copyWith updates fields correctly', () {
      final original = RepoConfig(localPath: '/old');
      final updated = original.copyWith(localPath: '/new');
      expect(updated.localPath, equals('/new'));
      // original unchanged
      expect(original.localPath, equals('/old'));
    });

    test('copyWith clearLocalPath clears the field', () {
      final original = RepoConfig(localPath: '/some/path');
      final cleared = original.copyWith(clearLocalPath: true);
      expect(cleared.localPath, isNull);
    });

    test('all validation statuses serialize/deserialize', () {
      for (final status in RepoValidationStatus.values) {
        final config = RepoConfig(validationStatus: status);
        final json = config.toJson();
        final restored = RepoConfig.fromJson(json);
        expect(restored.validationStatus, equals(status));
      }
    });
  });

  // ═══════ Phase 2: RepoConfigPanel 冒烟测试 ═══════

  group('RepoConfigPanel widget smoke', () {
    testWidgets('renders with default state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RepoConfigPanel(moduleId: 'test-module'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('目标代码仓库'), findsOneWidget);
      expect(find.text('输入仓库绝对路径，如 D:\\projects\\my-app'), findsOneWidget);
    });

    testWidgets('shows pre-filled path from initialConfig', (tester) async {
      final config = RepoConfig(
        localPath: r'D:\existing-project',
        validationStatus: RepoValidationStatus.valid,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepoConfigPanel(
              moduleId: 'test-module',
              initialConfig: config,
            ),
          ),
        ),
      );
      await tester.pump();

      // TextField 已预填路径
      final textField = tester.widget<TextField>(find.byType(TextField).first);
      expect(textField.controller?.text, contains(r'D:\existing-project'));
      // 显示"已校验"标记
      expect(find.text('已校验'), findsOneWidget);
    });
  });

  // ═══════ Phase 2: DocAutoSaveService ═══════

  group('DocAutoSaveService', () {
    test('creates service with module and document IDs', () {
      final service = DocAutoSaveService(
        moduleId: 'test-module',
        documentId: 'doc-123',
      );
      expect(service.moduleId, equals('test-module'));
      expect(service.documentId, equals('doc-123'));
      expect(service.status.status, equals(AutoSaveStatus.idle));
      expect(service.lastSaved, isNull);
    });

    test('start/stop lifecycle is idempotent', () {
      final service = DocAutoSaveService(
        moduleId: 'test-module',
        documentId: 'doc-1',
      );
      // 应该不抛异常
      service.start();
      service.start(); // 重复调用也应安全
      service.stop();
      service.dispose();
    });

    test('onContentChanged does not crash when no disk available', () {
      final service = DocAutoSaveService(
        moduleId: 'test-module',
        documentId: 'doc-1',
      );
      // 在测试环境中调用不应抛异常（磁盘写入可能失败，但不会崩溃）
      service.start();
      expect(
        () => service.onContentChanged('# Test content'),
        returnsNormally,
      );
      service.stop();
    });

    test('status reflects idle initially', () {
      final service = DocAutoSaveService(
        moduleId: 'test-module',
        documentId: 'doc-1',
      );
      final result = service.status;
      expect(result.status, equals(AutoSaveStatus.idle));
    });
  });

  // ═══════ Phase 2: RepoConfigService ═══════

  group('RepoConfigService', () {
    test('creates service with module ID', () {
      final service = RepoConfigService(moduleId: 'test-module');
      expect(service.moduleId, equals('test-module'));
    });

    test('validatePath rejects empty path', () async {
      final service = RepoConfigService(moduleId: 'test-module');
      final result = await service.validatePath('');
      expect(result.validationStatus, equals(RepoValidationStatus.invalid));
      expect(result.validationMessage, contains('不能为空'));
    });

    test('validatePath detects non-existent path', () async {
      final service = RepoConfigService(moduleId: 'test-module');
      final result = await service.validatePath(
          r'C:\NonExistent\Path\12345_Fake_Directory');
      expect(
        result.validationStatus,
        equals(RepoValidationStatus.notFound),
      );
      expect(result.validationMessage, isNotNull);
    });

    test('validatePath handles whitespace-only path', () async {
      final service = RepoConfigService(moduleId: 'test-module');
      final result = await service.validatePath('   ');
      expect(result.validationStatus, equals(RepoValidationStatus.invalid));
    });
  });

  // ═══════ Phase 2: Repo path skill prompt ═══════

  group('techAnalysisSkillBodyWithRepo', () {
    test('injects repo path into prompt', () {
      const docContent = '# 需求\n使用 WebSocket';
      const repoPath = r'D:\projects\my-app';
      final prompt = techAnalysisSkillBodyWithRepo(docContent, repoPath);

      expect(prompt, contains('技术设计师'));
      expect(prompt, contains('先相信意图'));
      expect(prompt, contains(repoPath));
      expect(prompt, contains('先读仓库'));
      expect(prompt, contains(docContent));
      expect(prompt, contains('"repoInsights"'));
    });

    test('prompt contains all required sections', () {
      final prompt = techAnalysisSkillBodyWithRepo('doc', '/repo');
      expect(prompt, contains('## 前置工作'));
      expect(prompt, contains('## 核心原则'));
      expect(prompt, contains('## 工作流程'));
      expect(prompt, contains('## 输出格式'));
      expect(prompt, contains('## 当前技术规划文档'));
    });
  });
}
