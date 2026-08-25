// 测试：HTML 创作中心画板绑定（T1）+ 会话-实例模型（I1）。
//
// 覆盖点：
// 1. CanvasMeta —— selectedDataSource/pluginId/navSection/instanceId 序列化 round-trip
// 2. canvasSessionsPath —— 旧布局会话路径（T1）；instanceSessionsPath —— 实例会话路径（I1）
// 3. CanvasManager —— 创建/绑定数据源/绑定插件 ID/保存保留绑定/删除清理
// 4. 解绑（bindDataSource null）后 meta 字段消失
// 5. 实例模型 —— ensureInstance 幂等（一画板一实例一固定 id）/ 实例会话隔离 /
//    旧会话迁移补写双向字段 / 重命名实例 id 不变 / 删画板连带实例与会话全清
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/services/canvas_manager.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/services/html_export_service.dart'
    show htmlPluginIdError;

void main() {
  group('CanvasMeta 序列化', () {
    test('selectedDataSource/pluginId/instanceId round-trip', () {
      final meta = CanvasMeta(
        id: 'canvas_1',
        name: '用户面板',
        pluginId: 'user-dashboard',
        navSection: '自定义',
        selectedDataSource: 'users',
        instanceId: 'instance_1',
      );
      final restored = CanvasMeta.fromJson(meta.toJson());
      expect(restored.id, 'canvas_1');
      expect(restored.name, '用户面板');
      expect(restored.pluginId, 'user-dashboard');
      expect(restored.navSection, '自定义');
      expect(restored.selectedDataSource, 'users');
      expect(restored.instanceId, 'instance_1');
    });

    test('无绑定时 toJson 不含 selectedDataSource/instanceId 键', () {
      final meta = CanvasMeta(id: 'c2', name: 'x');
      final json = meta.toJson();
      expect(json.containsKey('selectedDataSource'), isFalse);
      expect(json.containsKey('instanceId'), isFalse);
      expect(CanvasMeta.fromJson(json).selectedDataSource, isNull);
      expect(CanvasMeta.fromJson(json).instanceId, isNull);
    });

    test('旧 meta（无 selectedDataSource/instanceId 字段）读回 null 不崩溃', () {
      final restored = CanvasMeta.fromJson({
        'id': 'old',
        'name': '老画布',
        'pluginId': 'p1',
      });
      expect(restored.selectedDataSource, isNull);
      expect(restored.instanceId, isNull);
      expect(restored.pluginId, 'p1');
    });

    test('InstanceMeta 序列化 round-trip（id/boardId 不可变字段）', () {
      final inst = InstanceMeta(id: 'instance_x', name: '我的实例', boardId: 'canvas_x');
      final restored = InstanceMeta.fromJson(inst.toJson());
      expect(restored.id, 'instance_x');
      expect(restored.name, '我的实例');
      expect(restored.boardId, 'canvas_x');
    });
  });

  group('会话文件路径', () {
    test('旧布局会话路径并入画布目录 canvases/{id}/session.json', () {
      final path = canvasSessionsPath('canvas_abc');
      expect(path, contains(p.join('canvases', 'canvas_abc', 'session.json')));
    });

    test('I1 实例会话路径按实例隔离 canvases/{id}/instances/{iid}/session.json', () {
      final path = instanceSessionsPath('canvas_abc', 'instance_1');
      expect(
        path,
        contains(p.join('canvases', 'canvas_abc', 'instances', 'instance_1', 'session.json')),
      );
    });
  });

  group('CanvasManager 画板绑定生命周期', () {
    test('创建 → 绑定数据源 → 保存保留绑定 → 解绑 → 删除清理', () {
      final mgr = CanvasManager();
      final data = mgr.createCanvas(name: '测试画布', htmlContent: '<div>hi</div>');
      final cid = data.meta.id;
      try {
        // 绑定数据源随画布持久化
        mgr.bindDataSource(cid, 'orders');
        expect(mgr.loadCanvas(cid)?.meta.selectedDataSource, 'orders');

        // 编辑器保存（saveCanvas）不丢绑定、不改插件绑定
        mgr.saveCanvas(cid, name: '改名画布');
        final afterSave = mgr.loadCanvas(cid);
        expect(afterSave?.meta.name, '改名画布');
        expect(afterSave?.meta.selectedDataSource, 'orders');

        // 绑定插件 ID（首次导出）仍可用
        mgr.bindPluginId(cid, 'test-plugin');
        expect(mgr.loadCanvas(cid)?.meta.pluginId, 'test-plugin');

        // 解绑：传 null 后字段消失
        mgr.bindDataSource(cid, null);
        expect(mgr.loadCanvas(cid)?.meta.selectedDataSource, isNull);

        // 会话文件并入画布目录：写入后随画布一起删除
        final sessionFile = File(canvasSessionsPath(cid));
        sessionFile.parent.createSync(recursive: true);
        sessionFile.writeAsStringSync('{"canvasId":"$cid"}');
        expect(sessionFile.existsSync(), isTrue);
      } finally {
        mgr.deleteCanvas(cid);
      }

      // 删除画布：画布目录与会话文件一起消失，列表不再包含
      expect(File(canvasSessionsPath(cid)).existsSync(), isFalse);
      expect(mgr.listCanvases().where((c) => c.id == cid), isEmpty);
    });
  });

  group('I1 实例模型（一会话一份历史记忆）', () {
    test('ensureInstance 幂等：同一画板只分配一个实例 id 且永不改变', () {
      final mgr = CanvasManager();
      final data = mgr.createCanvas(name: '实例画板');
      final cid = data.meta.id;
      try {
        final first = mgr.ensureInstance(cid);
        final second = mgr.ensureInstance(cid);
        expect(first.id, second.id, reason: '同一画板重复 ensure 必须返回同一实例 id');
        expect(first.boardId, cid);
        // 实例 id 锚点已回写画布 meta
        expect(mgr.loadCanvas(cid)?.meta.instanceId, first.id);
        // I1 修订：实例 id 必须等于插件 id
        expect(mgr.loadCanvas(cid)?.meta.pluginId, first.id,
            reason: '实例 id 与插件 id 应该是同一个');
        expect(mgr.loadCanvas(cid)?.meta.instanceId, mgr.loadCanvas(cid)?.meta.pluginId,
            reason: 'meta.instanceId 与 meta.pluginId 不得分叉');
        // tryLoadInstanceOf 读回同一实例
        expect(mgr.tryLoadInstanceOf(cid)?.id, first.id);
      } finally {
        mgr.deleteCanvas(cid);
      }
    });

    test('ensureInstance 派生的绑定 id 必须通过 htmlPluginIdError（bug-0002：画布 5 → "5" 导出失败）', () {
      final mgr = CanvasManager();
      // 纯数字结尾的画布名（用户复现路径）
      final d1 = mgr.createCanvas(name: '画布 5');
      // 纯中文画布名（旧逻辑会落到兜底 my-plugin，多画板冲突）
      final d2 = mgr.createCanvas(name: '我的面板');
      try {
        final id1 = mgr.ensureInstance(d1.meta.id).id;
        final id2 = mgr.ensureInstance(d2.meta.id).id;
        // 绝对不能出现纯数字/中文开头的非法 id（正是 bug-0002 的报错根因）
        expect(htmlPluginIdError(id1), isNull,
            reason: '画布 5 派生的绑定 id($id1) 必须合法，否则导出报 plugin_id 非法: "5"');
        expect(htmlPluginIdError(id2), isNull,
            reason: '纯中文画布派生的绑定 id($id2) 必须合法');
        // 不同画板派生出不同 id（避免 my-plugin 冲突）
        expect(id1, isNot(equals(id2)));
        // 回写 meta 的 pluginId 与实例 id 一致且合法
        expect(mgr.loadCanvas(d1.meta.id)?.meta.pluginId, id1);
        expect(mgr.loadCanvas(d2.meta.id)?.meta.pluginId, id2);
      } finally {
        mgr.deleteCanvas(d1.meta.id);
        mgr.deleteCanvas(d2.meta.id);
      }
    });

    test('旧数据分叉（instance_xxx ≠ pluginId）时自动对齐为插件 id', () {
      final mgr = CanvasManager();
      final data = mgr.createCanvas(name: '分叉画板');
      final cid = data.meta.id;
      try {
        // 模拟旧 bug：meta 中 pluginId 与 instanceId 是不同值，且实例目录/
        // 会话按旧的 instance_xxx 存放。
        mgr.bindPluginId(cid, 'fixed-plugin');
        final oldIid = 'instance_old';
        final oldDir = Directory(instanceDir(cid, oldIid));
        oldDir.createSync(recursive: true);
        File(instanceMetaPath(cid, oldIid)).writeAsStringSync(
            '{"id":"$oldIid","name":"分叉画板","boardId":"$cid"}');
        File(instanceSessionsPath(cid, oldIid)).writeAsStringSync(
            '{"boardId":"$cid","instanceId":"$oldIid","agentSession":{}}');

        // 手动把 meta 改成分叉状态（模拟旧版本落盘结果）
        final metaFile = File('${Directory(instanceDir(cid, oldIid)).parent.parent.path}/meta.json');
        final metaJson = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        metaJson['instanceId'] = oldIid;
        metaFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(metaJson));

        final inst = mgr.ensureInstance(cid);
        expect(inst.id, 'fixed-plugin', reason: '实例 id 应对齐到插件 id');
        expect(mgr.loadCanvas(cid)?.meta.instanceId, 'fixed-plugin');
        expect(mgr.loadCanvas(cid)?.meta.pluginId, 'fixed-plugin');
        // 旧实例目录被迁移/清理，新实例会话存在且双向绑定已修正
        expect(Directory(instanceDir(cid, oldIid)).existsSync(), isFalse,
            reason: '旧的独立实例目录不应残留');
        final migrated = File(instanceSessionsPath(cid, 'fixed-plugin'));
        expect(migrated.existsSync(), isTrue, reason: '历史会话应随实例 id 迁移');
        final session = jsonDecode(migrated.readAsStringSync()) as Map<String, dynamic>;
        expect(session['instanceId'], 'fixed-plugin', reason: '会话文件双向绑定应同步修正');
      } finally {
        mgr.deleteCanvas(cid);
      }
    });

    test('实例会话按实例隔离（instances/{iid}/session.json）且删画板全清', () {
      final mgr = CanvasManager();
      final data = mgr.createCanvas(name: '隔离画板');
      final cid = data.meta.id;
      try {
        final inst = mgr.ensureInstance(cid);
        final sessionPath = instanceSessionsPath(cid, inst.id);
        File(sessionPath).parent.createSync(recursive: true);
        File(sessionPath).writeAsStringSync(
            '{"boardId":"$cid","instanceId":"${inst.id}","agentSession":{}}');
        expect(File(sessionPath).existsSync(), isTrue);
      } finally {
        mgr.deleteCanvas(cid);
      }
      // 删画板 = 删实例目录 + 会话，列表清空
      expect(mgr.listCanvases().where((c) => c.id == cid), isEmpty);
      expect(mgr.listInstances().where((r) => r.instance.boardId == cid), isEmpty);
    });

    test('老画板（无 instanceId）首次加载自动创建实例并迁移旧会话（补写双向字段）', () {
      final mgr = CanvasManager();
      final data = mgr.createCanvas(name: '老画板');
      final cid = data.meta.id;
      try {
        // 模拟 T1 老画板：meta 无 instanceId + 旧布局会话 canvases/{id}/session.json
        final legacy = File(canvasSessionsPath(cid));
        legacy.parent.createSync(recursive: true);
        legacy.writeAsStringSync('{"canvasId":"$cid","agentSession":{"m":1}}');
        expect(mgr.loadCanvas(cid)?.meta.instanceId, isNull);

        // ensureInstance：创建实例 + 迁移旧会话
        final inst = mgr.ensureInstance(cid);
        expect(inst.id, isNotEmpty);
        expect(mgr.loadCanvas(cid)?.meta.instanceId, inst.id);

        // 旧文件被删除，实例会话存在且补写了 boardId/instanceId
        expect(legacy.existsSync(), isFalse);
        final migrated = File(instanceSessionsPath(cid, inst.id));
        expect(migrated.existsSync(), isTrue);
        final json = jsonDecode(migrated.readAsStringSync()) as Map<String, dynamic>;
        expect(json['boardId'], cid);
        expect(json['instanceId'], inst.id);
        expect((json['agentSession'] as Map)['m'], 1, reason: '旧会话内容不丢');
      } finally {
        mgr.deleteCanvas(cid);
      }
    });

    test('重命名实例：名字可改、id 不变、会话不丢', () {
      final mgr = CanvasManager();
      final data = mgr.createCanvas(name: '改名画板');
      final cid = data.meta.id;
      try {
        final inst = mgr.ensureInstance(cid);
        final idBefore = inst.id;
        // 先落一份会话
        final sessionPath = instanceSessionsPath(cid, inst.id);
        File(sessionPath).parent.createSync(recursive: true);
        File(sessionPath).writeAsStringSync('{"boardId":"$cid","instanceId":"${inst.id}"}');

        mgr.renameInstance(cid, inst.id, '新实例名');
        final after = mgr.ensureInstance(cid);
        expect(after.id, idBefore, reason: '重命名不改变实例 id');
        expect(after.name, '新实例名');
        expect(File(sessionPath).existsSync(), isTrue, reason: '重命名不丢会话');
      } finally {
        mgr.deleteCanvas(cid);
      }
    });
  });
}
