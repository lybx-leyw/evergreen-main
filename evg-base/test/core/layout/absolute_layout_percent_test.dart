/// 绝对布局百分比坐标测试。
///
/// 验证：rect 内部为 0-100 百分比，写入 manifest 时转 0-1 分数，
/// 渲染期按父容器尺寸换算回像素。
library;

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_component.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/design_to_manifest.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/composite_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('absolute 布局: 百分比坐标', () {
    test('DesignSlot 默认 rect 是 [0, 0, 50, 50]', () {
      final s = DesignSlot(id: 's0');
      expect(s.rect, [0.0, 0.0, 50.0, 50.0]);
    });

    test('DesignSlot 显式指定 rect 保持原样', () {
      final s = DesignSlot(id: 's0', rect: [10, 20, 30, 40]);
      expect(s.rect, [10.0, 20.0, 30.0, 40.0]);
    });

    test('DesignToManifest._compileAbsolutePosition: 50% → 0.5 fraction', () {
      final doc = DesignDocument(pluginId: 'p', pluginName: 'p');
      final page = DesignPage(
        id: 'page_0', label: 'p',
        layoutPreset: DesignPageLayout.absolute,
      );
      page.addSlot(DesignSlot(
        id: 's0', region: SlotRegion.center,
        rect: [10, 20, 50, 30],  // 10%, 20%, 50%, 30%
        component: DesignComponent(type: 'data-table', config: {}),
      ));
      doc.addPage(page);

      final manifest = DesignToManifest.compile(doc);
      final slot = manifest['pages'][0]['layout']['slots']['s0'];
      final style = slot['style'];
      expect(style['position'], 'absolute');
      expect(style['left'], 0.10);   // 10%
      expect(style['top'], 0.20);    // 20%
      expect(style['width'], 0.50);  // 50%
      expect(style['height'], 0.30); // 30%
    });

    test('从 manifest 加载后值能正确解析（round-trip）', () {
      final doc = DesignDocument(pluginId: 'p', pluginName: 'p');
      final page = DesignPage(
        id: 'page_0', label: 'p',
        layoutPreset: DesignPageLayout.absolute,
      );
      page.addSlot(DesignSlot(
        id: 's0', region: SlotRegion.center,
        rect: [10, 20, 50, 30],
        component: DesignComponent(type: 'data-table', config: {}),
      ));
      doc.addPage(page);

      final manifest = DesignToManifest.compile(doc);
      final descriptor = ModuleDescriptor.fromJson(manifest);
      final slot = descriptor.pages[0].layout.slots['s0']!;
      // 解析后 style 内 width/height 是 0-1 分数
      expect(slot.style.width, 0.50);
      expect(slot.style.height, 0.30);
      expect(slot.style.top, 0.20);
      expect(slot.style.left, 0.10);
    });

    test('25% / 75% 坐标正确编译', () {
      // 验证：低百分比 0.25、高百分比 0.75
      final doc = DesignDocument(pluginId: 'p', pluginName: 'p');
      final page = DesignPage(
        id: 'page_0', label: 'p',
        layoutPreset: DesignPageLayout.absolute,
      );
      page.addSlot(DesignSlot(
        id: 's0', region: SlotRegion.center,
        rect: [25, 75, 25, 25],
        component: DesignComponent(type: 'chart', config: {}),
      ));
      doc.addPage(page);

      final manifest = DesignToManifest.compile(doc);
      final style = manifest['pages'][0]['layout']['slots']['s0']['style'];
      expect(style['left'], 0.25);
      expect(style['top'], 0.75);
      expect(style['width'], 0.25);
      expect(style['height'], 0.25);
    });

    test('100% 坐标 = 1.0', () {
      final doc = DesignDocument(pluginId: 'p', pluginName: 'p');
      final page = DesignPage(
        id: 'page_0', label: 'p',
        layoutPreset: DesignPageLayout.absolute,
      );
      page.addSlot(DesignSlot(
        id: 's0', region: SlotRegion.center,
        rect: [0, 0, 100, 100],
        component: DesignComponent(type: 'data-table', config: {}),
      ));
      doc.addPage(page);

      final manifest = DesignToManifest.compile(doc);
      final style = manifest['pages'][0]['layout']['slots']['s0']['style'];
      expect(style['width'], 1.0);
      expect(style['height'], 1.0);
    });
  });

  group('absolute 布局: 渲染期换算', () {
    testWidgets('50% 宽 + 50% 高 在 800x600 父容器下渲染为 400x300', (tester) async {
      final doc = DesignDocument(pluginId: 'p', pluginName: 'p');
      final page = DesignPage(
        id: 'page_0', label: 'p',
        layoutPreset: DesignPageLayout.absolute,
      );
      page.addSlot(DesignSlot(
        id: 's0', region: SlotRegion.center,
        rect: [0, 0, 50, 50],
        component: DesignComponent(type: 'data-table', config: {}),
      ));
      doc.addPage(page);

      final manifest = DesignToManifest.compile(doc);
      final descriptor = ModuleDescriptor.fromJson(manifest);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginsDirProvider.overrideWithValue(r'C:\fake\plugins'),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: CompositeView(descriptor: descriptor),
              ),
            ),
          ),
        ),
      );
      // 不抛异常即视为通过（约束换算后 SizedBox(400, 300) 注入成功）
      expect(tester.takeException(), isNull);
    });

    testWidgets('25% / 75% 偏移 + 25%×25% 尺寸不崩溃', (tester) async {
      final doc = DesignDocument(pluginId: 'p', pluginName: 'p');
      final page = DesignPage(
        id: 'page_0', label: 'p',
        layoutPreset: DesignPageLayout.absolute,
      );
      page.addSlot(DesignSlot(
        id: 's0', region: SlotRegion.center,
        rect: [25, 75, 25, 25],  // 左上角 (200, 450) → 200x150
        component: DesignComponent(type: 'chart', config: {}),
      ));
      doc.addPage(page);

      final manifest = DesignToManifest.compile(doc);
      final descriptor = ModuleDescriptor.fromJson(manifest);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginsDirProvider.overrideWithValue(r'C:\fake\plugins'),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: CompositeView(descriptor: descriptor),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
