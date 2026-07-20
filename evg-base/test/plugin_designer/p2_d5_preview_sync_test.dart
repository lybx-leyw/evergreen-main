/// P2 PreviewSyncService 防抖同步测试 (D5)。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/preview_sync_service.dart';

void main() {
  group('P2 PreviewSyncService 防抖 (D5)', () {
    test('300ms 防抖：快速连续调用只触发一次刷新与写入', () async {
      final dir = await Directory.systemTemp.createTemp('preview_sync_');
      int refreshCount = 0;
      final svc = PreviewSyncService(dir.path, (_) => refreshCount++);

      final doc = DesignDocument(pluginId: 'demo', pluginName: 'Demo');
      doc.addPage(DesignPage(id: 'p0', label: '首页'));

      // 300ms 内连续 3 次同步
      svc.sync(doc);
      svc.sync(doc);
      svc.sync(doc);

      // 等待防抖窗口过去
      await Future.delayed(const Duration(milliseconds: 400));

      expect(refreshCount, 1, reason: '防抖应仅触发一次刷新');

      final file = File(p.join(dir.path, 'demo', 'module', 'manifest.json'));
      expect(await file.exists(), isTrue, reason: 'manifest 应被写入');

      svc.dispose();
      await dir.delete(recursive: true);
    });

    test('syncNow 立即同步（不受防抖影响）', () async {
      final dir = await Directory.systemTemp.createTemp('preview_sync_now_');
      int refreshCount = 0;
      final svc = PreviewSyncService(dir.path, (_) => refreshCount++);

      final doc = DesignDocument(pluginId: 'demo2', pluginName: 'Demo2');
      await svc.syncNow(doc);
      expect(refreshCount, 1);

      final file = File(p.join(dir.path, 'demo2', 'module', 'manifest.json'));
      expect(await file.exists(), isTrue);

      svc.dispose();
      await dir.delete(recursive: true);
    });
  });
}
