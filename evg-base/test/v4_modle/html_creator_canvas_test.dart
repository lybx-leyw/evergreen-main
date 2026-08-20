// 测试：HTML 创作中心 T1 画板与会话绑定。
//
// 覆盖点：
// 1. CanvasMeta —— selectedDataSource/pluginId/navSection 序列化 round-trip
// 2. canvasSessionsPath —— 会话文件并入画布目录（删画布即删会话）
// 3. CanvasManager —— 创建/绑定数据源/绑定插件 ID/保存保留绑定/删除清理
// 4. 解绑（bindDataSource null）后 meta 字段消失
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/services/canvas_manager.dart';

void main() {
  group('CanvasMeta 序列化', () {
    test('selectedDataSource/pluginId round-trip', () {
      final meta = CanvasMeta(
        id: 'canvas_1',
        name: '用户面板',
        pluginId: 'user-dashboard',
        navSection: '自定义',
        selectedDataSource: 'users',
      );
      final restored = CanvasMeta.fromJson(meta.toJson());
      expect(restored.id, 'canvas_1');
      expect(restored.name, '用户面板');
      expect(restored.pluginId, 'user-dashboard');
      expect(restored.navSection, '自定义');
      expect(restored.selectedDataSource, 'users');
    });

    test('无绑定时 toJson 不含 selectedDataSource 键', () {
      final meta = CanvasMeta(id: 'c2', name: 'x');
      final json = meta.toJson();
      expect(json.containsKey('selectedDataSource'), isFalse);
      expect(CanvasMeta.fromJson(json).selectedDataSource, isNull);
    });

    test('旧 meta（无 selectedDataSource 字段）读回 null 不崩溃', () {
      final restored = CanvasMeta.fromJson({
        'id': 'old',
        'name': '老画布',
        'pluginId': 'p1',
      });
      expect(restored.selectedDataSource, isNull);
      expect(restored.pluginId, 'p1');
    });
  });

  group('会话文件归位', () {
    test('会话路径并入画布目录 canvases/{id}/session.json', () {
      final path = canvasSessionsPath('canvas_abc');
      expect(path, contains('canvases/canvas_abc/session.json'));
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
}
