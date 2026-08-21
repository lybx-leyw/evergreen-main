// 测试：主题创作中心「会话-面板双向绑定」改造（对齐 html-creator CanvasManager I1）。
//
// 覆盖点：
// 1. ThemePanelMeta / ThemeInstanceMeta 序列化 round-trip（instanceId/themeId 绑定字段）
// 2. 路径约定：panels/{panelId}/instances/{instanceId}/session.json
// 3. ThemePanelManager —— 一面板一实例（ensureInstance 幂等、实例 ID == 主题 ID）/
//    实例会话隔离 / 删面板连带实例与会话全清 / 重命名不改 id 不丢历史 /
//    重启（新 manager）恢复同一实例
// 4. 旧数据迁移 —— 老 drafts/*.json → 面板；老 chats/chat.json → 实例会话
//    （补写 panelId/instanceId 双向字段 + 草稿快照），且幂等不重复建面板
// 5. ThemeAiService —— switchPanel 保存/恢复（断点续做）、实例隔离不串消息、
//    孤儿会话不恢复并清理、记忆命名空间按实例隔离、rebindInstanceId 落盘新路径
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/renderer/templates/theme_creator_modle/models/theme_draft.dart';
import 'package:evergreen_base/renderer/templates/theme_creator_modle/services/theme_ai_service.dart';
import 'package:evergreen_base/renderer/templates/theme_creator_modle/services/theme_panel_manager.dart';

/// 合法 8 色草稿（导出/序列化基准）。
Map<String, dynamic> _fullColors() => {
      'background': '#0D1117',
      'surface': '#161B22',
      'border': '#30363D',
      'text': '#C9D1D9',
      'textSecondary': '#8B949E',
      'accent': '#58A6FF',
      'error': '#FF7B72',
      'others': '#8B949E',
    };

void main() {
  group('元数据序列化', () {
    test('ThemePanelMeta round-trip（instanceId/themeId/selectedDraftId）', () {
      final meta = ThemePanelMeta(
        id: 'theme_panel_1',
        name: '我的面板',
        instanceId: 'my_theme',
        themeId: 'my_theme',
        selectedDraftId: 'my_theme',
      );
      final restored = ThemePanelMeta.fromJson(meta.toJson());
      expect(restored.id, 'theme_panel_1');
      expect(restored.name, '我的面板');
      expect(restored.instanceId, 'my_theme');
      expect(restored.themeId, 'my_theme');
      expect(restored.selectedDraftId, 'my_theme');
    });

    test('无绑定时 toJson 不含 instanceId/themeId 键', () {
      final meta = ThemePanelMeta(id: 'p2', name: 'x');
      final json = meta.toJson();
      expect(json.containsKey('instanceId'), isFalse);
      expect(json.containsKey('themeId'), isFalse);
      expect(ThemePanelMeta.fromJson(json).instanceId, isNull);
      expect(ThemePanelMeta.fromJson(json).themeId, isNull);
    });

    test('ThemeInstanceMeta round-trip（id/panelId 不可变字段）', () {
      final inst =
          ThemeInstanceMeta(id: 'my_theme', name: '我的实例', panelId: 'theme_panel_1');
      final restored = ThemeInstanceMeta.fromJson(inst.toJson());
      expect(restored.id, 'my_theme');
      expect(restored.name, '我的实例');
      expect(restored.panelId, 'theme_panel_1');
    });
  });

  group('会话文件路径约定', () {
    test('面板 meta/草稿/实例会话路径按约定分层', () {
      // 路径分隔符跨平台（Windows 为 \，POSIX 为 /），用 p.join 构造期望，
      // 与实现同源（theme_panel_manager.dart 也走 p.join），避免硬编码 / 在 Windows 失败。
      expect(panelDir('theme_panel_abc'),
          contains(p.join('panels', 'theme_panel_abc')));
      expect(panelMetaPath('theme_panel_abc'),
          contains(p.join('panels', 'theme_panel_abc', 'meta.json')));
      expect(panelDraftPath('theme_panel_abc'),
          contains(p.join('panels', 'theme_panel_abc', 'draft.json')));
      expect(instanceSessionsPath('theme_panel_abc', 'my-theme'),
          contains(p.join(
              'panels', 'theme_panel_abc', 'instances', 'my-theme', 'session.json')));
    });
  });

  group('ThemePanelManager 一面板一实例', () {
    late Directory tmp;
    late ThemePanelManager mgr;

    String sessionPathOf(String panelId, String instanceId) =>
        p.join(tmp.path, 'panels', panelId, 'instances', instanceId, 'session.json');

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('theme_panel_mgr_');
      mgr = ThemePanelManager(rootDir: tmp.path);
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('ensureInstance 幂等：同一面板返回同一实例 id，且 == 主题 id', () {
      final data = mgr.createPanel(
          name: '实例面板', seedDraft: ThemeDraft(id: 'my_theme', name: '我的主题'));
      final pid = data.meta.id;

      final first = mgr.ensureInstance(pid);
      final second = mgr.ensureInstance(pid);
      expect(first.id, second.id, reason: '同一面板重复 ensure 必须返回同一实例 id');
      expect(first.id, 'my_theme', reason: '实例 id 直接与草稿/主题 id 对齐');
      expect(first.panelId, pid);

      // 锚点已回写面板 meta，themeId 与 instanceId 不得分叉
      final meta = mgr.loadPanel(pid)!.meta;
      expect(meta.instanceId, first.id);
      expect(meta.themeId, first.id, reason: 'meta.themeId 与 meta.instanceId 不得分叉');
      expect(mgr.tryLoadInstanceOf(pid)?.id, first.id);
    });

    test('不同面板实例隔离，会话互不干扰', () {
      final a = mgr.createPanel(
          name: '面板A', seedDraft: ThemeDraft(id: 'theme_a', name: 'A'));
      final b = mgr.createPanel(
          name: '面板B', seedDraft: ThemeDraft(id: 'theme_b', name: 'B'));
      final ia = mgr.ensureInstance(a.meta.id);
      final ib = mgr.ensureInstance(b.meta.id);
      expect(ia.id, isNot(ib.id));
      expect(sessionPathOf(a.meta.id, ia.id),
          isNot(sessionPathOf(b.meta.id, ib.id)));

      // 各写一份会话
      File(sessionPathOf(a.meta.id, ia.id)).parent.createSync(recursive: true);
      File(sessionPathOf(a.meta.id, ia.id)).writeAsStringSync(
          '{"panelId":"${a.meta.id}","instanceId":"${ia.id}","agentSession":[]}');
      File(sessionPathOf(b.meta.id, ib.id)).parent.createSync(recursive: true);
      File(sessionPathOf(b.meta.id, ib.id)).writeAsStringSync(
          '{"panelId":"${b.meta.id}","instanceId":"${ib.id}","agentSession":[]}');

      expect(File(sessionPathOf(a.meta.id, ia.id)).existsSync(), isTrue);
      expect(File(sessionPathOf(b.meta.id, ib.id)).existsSync(), isTrue);
      expect(mgr.sessionMessageCountOf(a.meta.id), 0);
    });

    test('删除面板：实例与会话文件一并删除，另一面板不受影响', () {
      final a = mgr.createPanel(name: '保留面板');
      final b = mgr.createPanel(name: '删面板');
      final ia = mgr.ensureInstance(a.meta.id);
      final ib = mgr.ensureInstance(b.meta.id);
      File(sessionPathOf(a.meta.id, ia.id)).parent.createSync(recursive: true);
      File(sessionPathOf(a.meta.id, ia.id))
          .writeAsStringSync('{"panelId":"${a.meta.id}","instanceId":"${ia.id}"}');
      File(sessionPathOf(b.meta.id, ib.id)).parent.createSync(recursive: true);
      File(sessionPathOf(b.meta.id, ib.id))
          .writeAsStringSync('{"panelId":"${b.meta.id}","instanceId":"${ib.id}"}');

      mgr.deletePanel(b.meta.id);

      expect(mgr.listPanels().where((x) => x.id == b.meta.id), isEmpty);
      expect(File(sessionPathOf(b.meta.id, ib.id)).existsSync(), isFalse,
          reason: '删面板 = 实例与会话一并清理');
      expect(mgr.listInstances().where((r) => r.instance.panelId == b.meta.id),
          isEmpty);
      // 保留面板及其会话不受影响
      expect(mgr.listPanels().where((x) => x.id == a.meta.id), isNotEmpty);
      expect(File(sessionPathOf(a.meta.id, ia.id)).existsSync(), isTrue);
    });

    test('重命名面板/实例：id 不变、会话不丢', () {
      final data = mgr.createPanel(
          name: '改名面板', seedDraft: ThemeDraft(id: 'fixed_theme', name: '固定'));
      final pid = data.meta.id;
      final inst = mgr.ensureInstance(pid);
      final sp = sessionPathOf(pid, inst.id);
      File(sp).parent.createSync(recursive: true);
      File(sp).writeAsStringSync(
          '{"panelId":"$pid","instanceId":"${inst.id}","agentSession":[{"role":"user","content":"hi"}]}');

      mgr.renamePanel(pid, '新面板名');

      final after = mgr.ensureInstance(pid);
      expect(after.id, inst.id, reason: '重命名不改变实例 id');
      expect(after.name, '新面板名', reason: '重命名同步实例名');
      expect(mgr.loadPanel(pid)!.meta.name, '新面板名');
      expect(File(sp).existsSync(), isTrue, reason: '重命名不丢会话');
    });

    test('重启恢复：新 manager 实例列出同一面板、返回同一实例、草稿不丢', () {
      final data = mgr.createPanel(
          name: '重启面板', seedDraft: ThemeDraft(id: 'restart_theme', name: '重启'));
      final pid = data.meta.id;
      final inst = mgr.ensureInstance(pid);

      // 模拟重启：用同一 root 新建 manager
      final mgr2 = ThemePanelManager(rootDir: tmp.path);
      expect(mgr2.listPanels().map((x) => x.id), contains(pid));
      expect(mgr2.ensureInstance(pid).id, inst.id,
          reason: '重启后进入面板返回同一实例 id');
      expect(mgr2.loadPanel(pid)!.draft?.id, 'restart_theme');
      expect(mgr2.loadPanel(pid)!.meta.instanceId, inst.id);
    });
  });

  group('旧数据迁移', () {
    late Directory tmp;
    late ThemePanelManager mgr;

    /// 模拟老版数据：drafts/*.json + chats/chat.json。
    void seedLegacyData() {
      final draftsDir = Directory(p.join(tmp.path, 'drafts'));
      draftsDir.createSync(recursive: true);
      File(p.join(draftsDir.path, 'old_theme.json')).writeAsStringSync(jsonEncode({
        'id': 'old_theme',
        'name': '老主题',
        'colors': _fullColors(),
      }));
      final chatsDir = Directory(p.join(tmp.path, 'chats'));
      chatsDir.createSync(recursive: true);
      File(p.join(chatsDir.path, 'chat.json')).writeAsStringSync(jsonEncode([
        {'role': 'user', 'content': '做一个深色主题', 'at': '2026-01-01T00:00:00'},
        {
          'role': 'assistant',
          'content': '已生成主题「老主题」：{"id":"old_theme"}',
          'at': '2026-01-01T00:00:01'
        },
      ]));
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('theme_panel_migrate_');
      mgr = ThemePanelManager(rootDir: tmp.path);
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('老草稿 → 面板；老聊天 → 实例会话（补写双向字段 + 草稿快照）', () {
      seedLegacyData();
      mgr.migrateLegacyIfNeeded();

      // 每个老草稿一个面板，实例 id == 草稿 id
      final panels = mgr.listPanels();
      expect(panels.length, 1);
      final panel = panels.first;
      expect(mgr.loadPanel(panel.id)!.draft?.id, 'old_theme');
      final inst = mgr.ensureInstance(panel.id);
      expect(inst.id, 'old_theme', reason: '实例 id 与草稿/主题 id 对齐');

      // 聊天迁入实例会话：双向字段 + agentSession + uiMessages + 草稿快照
      final sp = p.join(
          tmp.path, 'panels', panel.id, 'instances', inst.id, 'session.json');
      final session = jsonDecode(File(sp).readAsStringSync()) as Map<String, dynamic>;
      expect(session['panelId'], panel.id);
      expect(session['instanceId'], inst.id);
      expect((session['agentSession'] as List).length, 2);
      expect((session['uiMessages'] as List).length, 2);
      expect((session['draftSnapshot'] as Map)['id'], 'old_theme');

      // chat.json 已归档（防重复迁移，不删用户数据）
      expect(File(p.join(tmp.path, 'chats', 'chat.json')).existsSync(), isFalse);
      expect(File(p.join(tmp.path, 'chats', 'chat.json.migrated')).existsSync(),
          isTrue);
    });

    test('迁移幂等：重复调用不重复建面板、不重复迁聊天', () {
      seedLegacyData();
      mgr.migrateLegacyIfNeeded();
      final n1 = mgr.listPanels().length;
      final panels1 = mgr.listPanels();

      // 再次迁移（含新 manager 模拟重启）
      final mgr2 = ThemePanelManager(rootDir: tmp.path);
      mgr2.migrateLegacyIfNeeded();
      expect(mgr2.listPanels().length, n1, reason: '标记文件防重复建面板');
      expect(mgr2.listPanels().map((x) => x.id),
          panels1.map((x) => x.id).toList());
    });

    test('老面板无 instanceId：ensureInstance 由草稿 id 派生并自愈创建实例', () {
      // 手工构造老面板（meta 无 instanceId，草稿有 id）
      final pid = 'theme_panel_old';
      final dir = Directory(p.join(tmp.path, 'panels', pid));
      dir.createSync(recursive: true);
      File(p.join(dir.path, 'meta.json'))
          .writeAsStringSync(jsonEncode({'id': pid, 'name': '老面板'}));
      File(p.join(dir.path, 'draft.json')).writeAsStringSync(jsonEncode({
        'id': 'old_id',
        'name': '老草稿',
        'colors': {},
      }));

      final inst = mgr.ensureInstance(pid);
      expect(inst.id, 'old_id', reason: '实例 id 由草稿 id 派生');
      expect(mgr.loadPanel(pid)!.meta.instanceId, 'old_id');
      expect(mgr.tryLoadInstanceOf(pid)?.id, 'old_id');
    });
  });

  group('ThemeAiService 会话保存/恢复/隔离', () {
    late Directory tmp;

    String sessionPathOf(String panelId, String instanceId) =>
        p.join(tmp.path, 'panels', panelId, 'instances', instanceId, 'session.json');

    ThemeAiService makeService() {
      final s = ThemeAiService(apiKey: 'test-key');
      s.resolveSessionsPath = (pid, iid) => sessionPathOf(pid, iid);
      return s;
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('theme_ai_session_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('switchPanel + addRound → 新服务实例恢复同一历史（断点续做）', () async {
      final s1 = makeService();
      await s1.switchPanel('theme_panel_a', instanceId: 'theme_a');
      s1.addRound(user: '做一个暖色主题', assistant: '已生成主题「暖」：{"id":"warm"}');
      s1.addRound(user: '再亮一点', assistant: '已生成主题「暖2」');
      expect(s1.sessionMessageCount, 4);

      // 模拟重启：新服务实例，同一会话路径
      final s2 = makeService();
      await s2.switchPanel('theme_panel_a', instanceId: 'theme_a');
      expect(s2.restoredFromSession, isTrue, reason: '重启后恢复历史（断点续作）');
      expect(s2.sessionMessageCount, 4);
      expect(s2.uiMessages.length, 4);
      expect(s2.uiMessages.first['role'], 'user');
      expect(s2.uiMessages.first['text'], '做一个暖色主题');
    });

    test('不同面板/实例历史完全隔离，切换不串消息', () async {
      final s = makeService();
      await s.switchPanel('theme_panel_a', instanceId: 'theme_a');
      s.addRound(user: 'A 的指令', assistant: 'A 的结果');
      expect(s.sessionMessageCount, 2);

      // 切到 B：先保存 A，再清空，B 无历史
      await s.switchPanel('theme_panel_b', instanceId: 'theme_b');
      expect(s.uiMessages, isEmpty, reason: '切换后旧实例消息必须清空');
      expect(s.sessionMessageCount, 0);

      // 切回 A：恢复 A 的历史，不混入 B 的消息
      await s.switchPanel('theme_panel_a', instanceId: 'theme_a');
      expect(s.uiMessages.length, 2, reason: '回到 A 恢复其历史');
      expect(s.uiMessages.first['text'], 'A 的指令');
    });

    test('孤儿会话（panelId/instanceId 不匹配）不恢复并清理', () async {
      final sp = sessionPathOf('theme_panel_a', 'theme_a');
      File(sp).parent.createSync(recursive: true);
      File(sp).writeAsStringSync(jsonEncode({
        'panelId': 'theme_panel_other', // ← 面板不匹配
        'instanceId': 'theme_a',
        'agentSession': [
          {'role': 'user', 'content': '孤儿'}
        ],
      }));

      final s = makeService();
      await s.switchPanel('theme_panel_a', instanceId: 'theme_a');
      expect(s.restoredFromSession, isFalse, reason: '孤儿会话不承认');
      expect(s.sessionMessageCount, 0);
      expect(s.uiMessages, isEmpty);
      expect(File(sp).existsSync(), isFalse, reason: '孤儿会话被清理');
    });

    test('记忆存储命名空间按实例隔离', () async {
      final s = makeService();
      await s.switchPanel('theme_panel_a', instanceId: 'theme_a');
      expect(s.memoryNamespace, 'theme_creator_theme_a');
      await s.switchPanel('theme_panel_b', instanceId: 'theme_b');
      expect(s.memoryNamespace, 'theme_creator_theme_b');
      expect(s.memoryStore, isNotNull);
    });

    test('rebindInstanceId：会话落盘到新实例路径（ID 对齐不丢历史）', () async {
      final s = makeService();
      await s.switchPanel('theme_panel_a', instanceId: 'theme_a');
      s.addRound(user: 'hi', assistant: 'result');

      s.rebindInstanceId('theme_a_v2');
      expect(s.instanceId, 'theme_a_v2');

      final newSp = sessionPathOf('theme_panel_a', 'theme_a_v2');
      expect(File(newSp).existsSync(), isTrue,
          reason: '对齐后会话按新实例 id 落盘');
      final data = jsonDecode(File(newSp).readAsStringSync()) as Map<String, dynamic>;
      expect(data['instanceId'], 'theme_a_v2');
      expect(data['panelId'], 'theme_panel_a');
    });
  });
}
