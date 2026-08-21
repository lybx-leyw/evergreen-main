// Skill 创作面板管理器测试（「几个一」规格：一面板一实例一固定 ID +
// 一会话一固定历史 + 断点续做 + 孤儿会话清理）。
//
// 使用注入的临时根目录，不触碰真实 `.greenix`。
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/renderer/templates/skill_creator_modle/models/skill_creator_models.dart';
import 'package:evergreen_base/renderer/templates/skill_creator_modle/services/skill_creator_panel_manager.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('skill_creator_test_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('面板 CRUD', () {
    test('createPanel → listPanels → loadPanel', () {
      final mgr = SkillCreatorPanelManager(rootDir: tmp.path);
      final data = mgr.createPanel(name: '面板一');
      expect(data.meta.id, startsWith('skill_panel_'));
      expect(data.workflow.phase, SkillCreatorPhase.idle);

      final listed = mgr.listPanels();
      expect(listed.length, 1);
      expect(listed.first.id, data.meta.id);

      final loaded = mgr.loadPanel(data.meta.id);
      expect(loaded, isNotNull);
      expect(loaded!.meta.name, '面板一');
    });

    test('renamePanel 不改 id / 实例', () {
      final mgr = SkillCreatorPanelManager(rootDir: tmp.path);
      final data = mgr.createPanel(name: '旧名');
      final inst = mgr.ensureInstance(data.meta.id);

      mgr.renamePanel(data.meta.id, '新名');
      final loaded = mgr.loadPanel(data.meta.id);
      expect(loaded!.meta.name, '新名');
      expect(loaded.meta.id, data.meta.id);
      expect(loaded.meta.instanceId, inst.id);
    });

    test('deletePanel 连带实例与会话全清', () {
      final mgr = SkillCreatorPanelManager(rootDir: tmp.path);
      final data = mgr.createPanel(name: '待删');
      mgr.ensureInstance(data.meta.id);
      mgr.saveSession(
        data.meta.id,
        data.meta.instanceId ?? data.meta.id,
        agentSession: [{'role': 'user', 'content': 'x'}],
        uiMessages: [],
        workflow: SkillCreatorWorkflow(),
      );

      mgr.deletePanel(data.meta.id);
      expect(mgr.listPanels(), isEmpty);
      expect(Directory(p.join(tmp.path, 'panels', data.meta.id)).existsSync(),
          isFalse);
    });
  });

  group('一面板一实例（固定 ID）', () {
    test('ensureInstance 幂等且实例 ID == 面板 ID', () {
      final mgr = SkillCreatorPanelManager(rootDir: tmp.path);
      final data = mgr.createPanel(name: '面板');
      final inst1 = mgr.ensureInstance(data.meta.id);
      expect(inst1.id, data.meta.id); // 固定 ID == 面板 ID

      final inst2 = mgr.ensureInstance(data.meta.id);
      expect(inst2.id, inst1.id);

      final meta = mgr.loadPanel(data.meta.id)!.meta;
      expect(meta.instanceId, data.meta.id); // meta 回写绑定
    });

    test('老面板（无 instanceId）首次加载自动创建实例', () {
      final mgr = SkillCreatorPanelManager(rootDir: tmp.path);
      final data = mgr.createPanel(name: '老面板');
      // 模拟老面板：meta 无 instanceId
      final raw = jsonDecode(File(p.join(tmp.path, 'panels', data.meta.id,
              'meta.json'))
          .readAsStringSync()) as Map<String, dynamic>
        ..remove('instanceId');
      File(p.join(tmp.path, 'panels', data.meta.id, 'meta.json'))
          .writeAsStringSync(jsonEncode(raw));

      final inst = mgr.ensureInstance(data.meta.id);
      expect(inst.id, data.meta.id);
      expect(mgr.loadPanel(data.meta.id)!.meta.instanceId, data.meta.id);
    });
  });

  group('一会话一固定历史 + 断点续做', () {
    test('saveSession → 新 manager restoreSession 恢复（重启不丢）', () {
      final mgr1 = SkillCreatorPanelManager(rootDir: tmp.path);
      final data = mgr1.createPanel(name: '面板');
      final inst = mgr1.ensureInstance(data.meta.id);

      final wf = SkillCreatorWorkflow(
        phase: SkillCreatorPhase.collecting,
        requirement: '需求',
        tasks: [SearchTask(id: 't1', source: SearchSource.arxiv, query: 'q')],
      )..log('info', '开始采集');
      mgr1.saveSession(
        data.meta.id,
        inst.id,
        agentSession: [
          {'role': 'user', 'content': '需求'},
          {'role': 'assistant', 'content': '计划'},
        ],
        uiMessages: [{'role': 'user', 'text': '需求'}],
        workflow: wf,
      );

      // 模拟重启：新 manager
      final mgr2 = SkillCreatorPanelManager(rootDir: tmp.path);
      final session = mgr2.restoreSession(data.meta.id, inst.id);
      expect(session, isNotNull);
      expect(session!.agentSession.length, 2);
      expect(session.uiMessages.length, 1);
      expect(session.workflow.phase, SkillCreatorPhase.collecting);
      expect(session.workflow.task('t1')?.query, 'q');

      // loadPanel 也恢复工作流
      final loaded = mgr2.loadPanel(data.meta.id)!;
      expect(loaded.workflow.phase, SkillCreatorPhase.collecting);
    });

    test('孤儿会话（panelId 不匹配）不恢复并清理', () {
      final mgr = SkillCreatorPanelManager(rootDir: tmp.path);
      final data = mgr.createPanel(name: '面板');
      final inst = mgr.ensureInstance(data.meta.id);

      // 写入 panelId 不一致的会话文件（模拟串台/拷贝）
      final sessionPath =
          p.join(tmp.path, 'panels', data.meta.id, 'instances', inst.id,
              'session.json');
      File(sessionPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'panelId': 'other_panel',
          'instanceId': inst.id,
          'workflow': SkillCreatorWorkflow().toJson(),
        }));

      final restored = mgr.restoreSession(data.meta.id, inst.id);
      expect(restored, isNull);
      expect(File(sessionPath).existsSync(), isFalse); // 已清理
    });

    test('resetSession 清空后 restore 返回 null', () {
      final mgr = SkillCreatorPanelManager(rootDir: tmp.path);
      final data = mgr.createPanel(name: '面板');
      final inst = mgr.ensureInstance(data.meta.id);
      mgr.saveSession(
        data.meta.id,
        inst.id,
        agentSession: [],
        uiMessages: [],
        workflow: SkillCreatorWorkflow(phase: SkillCreatorPhase.done),
      );
      expect(mgr.restoreSession(data.meta.id, inst.id), isNotNull);

      mgr.resetSession(data.meta.id, inst.id);
      expect(mgr.restoreSession(data.meta.id, inst.id), isNull);
    });
  });
}
