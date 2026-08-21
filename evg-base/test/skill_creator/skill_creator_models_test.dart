// Skill 创作数据模型序列化 round-trip 测试（不涉文件系统）。
//
// 覆盖：
// 1. SearchTask / MaterialItem / WorkflowEvent / SkillCreatorWorkflow /
//    SkillCreatorPanelMeta / SkillCreatorInstanceMeta / SkillCreatorSession
//    toJson → fromJson 完整往返；
// 2. 枚举解析容错（未知值回退默认）；
// 3. workflow.log 事件追加。
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/renderer/templates/skill_creator_modle/models/skill_creator_models.dart';

void main() {
  group('SearchTask round-trip', () {
    test('完整字段往返', () {
      final t = SearchTask(
        id: 'task_1',
        source: SearchSource.arxiv,
        query: 'rag retrieval augmented generation survey',
        status: TaskStatus.done,
        verdict: TaskVerdict.pass,
        feedback: '材料相关，通过',
        resultSummary: '找到 3 篇相关论文',
        materialIds: ['mat_1', 'mat_2'],
        attempts: 2,
      );
      final restored = SearchTask.fromJson(t.toJson());
      expect(restored.id, 'task_1');
      expect(restored.source, SearchSource.arxiv);
      expect(restored.query, contains('rag'));
      expect(restored.status, TaskStatus.done);
      expect(restored.verdict, TaskVerdict.pass);
      expect(restored.feedback, contains('通过'));
      expect(restored.materialIds, ['mat_1', 'mat_2']);
      expect(restored.attempts, 2);
    });

    test('未知枚举回退默认（source→web, verdict→none）', () {
      final restored = SearchTask.fromJson({
        'id': 't',
        'source': 'unknown_source',
        'verdict': 'unknown_verdict',
      });
      expect(restored.source, SearchSource.web);
      expect(restored.verdict, TaskVerdict.none);
      expect(restored.status, TaskStatus.pending);
    });
  });

  group('MaterialItem round-trip', () {
    test('完整字段往返', () {
      final m = MaterialItem(
        id: 'mat_1',
        source: SearchSource.books,
        title: 'Deep Learning',
        url: 'https://example.com/dl.pdf',
        type: 'book',
        localPath: '/ws/agents/task/materials/dl.pdf',
        textPath: '/ws/materials/mat_1.txt',
        authors: 'Goodfellow',
        year: '2016',
        summary: '深度学习经典教材',
        readability: 'ok',
      );
      final restored = MaterialItem.fromJson(m.toJson());
      expect(restored.source, SearchSource.books);
      expect(restored.title, 'Deep Learning');
      expect(restored.localPath, contains('dl.pdf'));
      expect(restored.textPath, contains('mat_1.txt'));
      expect(restored.authors, 'Goodfellow');
      expect(restored.readability, 'ok');
    });

    test('可空字段缺省', () {
      final m = MaterialItem(
        id: 'm',
        source: SearchSource.web,
        title: 't',
        url: 'u',
        type: 'article',
      );
      final restored = MaterialItem.fromJson(m.toJson());
      expect(restored.localPath, isNull);
      expect(restored.authors, isNull);
      expect(restored.readability, 'ok');
    });
  });

  group('WorkflowEvent round-trip', () {
    test('时间戳与等级', () {
      final e = WorkflowEvent(
        at: DateTime(2026, 8, 1, 10, 30),
        level: 'negotiation',
        phase: 'accepting',
        message: '返工：方向不对',
        agentId: 'task_2',
      );
      final restored = WorkflowEvent.fromJson(e.toJson());
      expect(restored.at.year, 2026);
      expect(restored.level, 'negotiation');
      expect(restored.phase, 'accepting');
      expect(restored.message, contains('返工'));
      expect(restored.agentId, 'task_2');
    });
  });

  group('SkillCreatorWorkflow round-trip', () {
    test('任务/材料/事件/导出路径完整往返', () {
      final wf = SkillCreatorWorkflow(
        phase: SkillCreatorPhase.integrating,
        resumePhase: SkillCreatorPhase.collecting,
        requirement: '创建论文速读 skill',
        round: 1,
        tasks: [
          SearchTask(id: 't1', source: SearchSource.arxiv, query: 'q1'),
        ],
        materials: [
          MaterialItem(
              id: 'm1',
              source: SearchSource.arxiv,
              title: 'p1',
              url: 'u1',
              type: 'paper'),
        ],
        reportPath: '/ws/report.md',
        draftSkillPath: '/ws/draft.md',
        exportPath: '/ws/export.md',
      )..log('info', '开始');
      wf.log('negotiation', '返工', agentId: 't1');

      final restored = SkillCreatorWorkflow.fromJson(wf.toJson());
      expect(restored.phase, SkillCreatorPhase.integrating);
      expect(restored.resumePhase, SkillCreatorPhase.collecting);
      expect(restored.requirement, contains('论文'));
      expect(restored.round, 1);
      expect(restored.tasks.length, 1);
      expect(restored.materials.length, 1);
      expect(restored.reportPath, '/ws/report.md');
      expect(restored.draftSkillPath, '/ws/draft.md');
      expect(restored.exportPath, '/ws/export.md');
      expect(restored.events.length, 2);
      expect(restored.events.last.level, 'negotiation');
      expect(restored.events.last.agentId, 't1');
    });

    test('task()/material() 查找', () {
      final wf = SkillCreatorWorkflow(
        tasks: [SearchTask(id: 't1', source: SearchSource.web, query: 'q')],
        materials: [
          MaterialItem(
              id: 'm1',
              source: SearchSource.web,
              title: 'x',
              url: 'u',
              type: 'article')
        ],
      );
      expect(wf.task('t1')?.query, 'q');
      expect(wf.task('nope'), isNull);
      expect(wf.material('m1')?.title, 'x');
      expect(wf.material('nope'), isNull);
    });
  });

  group('面板/实例/会话 round-trip', () {
    test('SkillCreatorPanelMeta round-trip', () {
      final meta = SkillCreatorPanelMeta(
        id: 'skill_panel_1',
        name: '我的面板',
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 2),
        instanceId: 'skill_panel_1',
      );
      final restored = SkillCreatorPanelMeta.fromJson(meta.toJson());
      expect(restored.id, 'skill_panel_1');
      expect(restored.name, '我的面板');
      expect(restored.instanceId, 'skill_panel_1');
      expect(restored.createdAt.year, 2026);
    });

    test('SkillCreatorInstanceMeta round-trip（实例 ID == 面板 ID）', () {
      final inst = SkillCreatorInstanceMeta(
        id: 'skill_panel_1',
        name: '实例一',
        panelId: 'skill_panel_1',
      );
      final restored = SkillCreatorInstanceMeta.fromJson(inst.toJson());
      expect(restored.id, 'skill_panel_1');
      expect(restored.panelId, 'skill_panel_1');
      expect(restored.name, '实例一');
    });

    test('SkillCreatorSession round-trip（消息 + 工作流快照）', () {
      final session = SkillCreatorSession(
        agentSession: [
          {'role': 'user', 'content': '需求'},
          {'role': 'assistant', 'content': '计划'},
        ],
        uiMessages: [
          {'role': 'user', 'text': '需求'},
          {'role': 'ai', 'text': '开始'},
        ],
        workflow: SkillCreatorWorkflow(
          phase: SkillCreatorPhase.collecting,
          requirement: '需求',
        ),
      );
      final restored = SkillCreatorSession.fromJson(session.toJson());
      expect(restored.agentSession.length, 2);
      expect(restored.agentSession.last['content'], '计划');
      expect(restored.uiMessages.length, 2);
      expect(restored.workflow.phase, SkillCreatorPhase.collecting);
    });
  });

  group('工具函数', () {
    test('searchSourceLabel 映射', () {
      expect(searchSourceLabel(SearchSource.arxiv), contains('arXiv'));
      expect(searchSourceLabel(SearchSource.web), contains('通用'));
      expect(searchSourceLabel(SearchSource.books), contains('书籍'));
    });

    test('decodeJsonMap 容错', () {
      expect(decodeJsonMap('{"a": 1}')['a'], 1);
      expect(decodeJsonMap('not json'), isEmpty);
      expect(decodeJsonMap('[1,2]'), isEmpty);
    });
  });
}
