/// P0 基础设施测试 —— 插件创作流模型序列化 + 编译器。
///
/// 验证:
/// 1. DesignDocument / DesignPage / DesignSlot / DesignComponent 序列化/反序列化
/// 2. DesignToManifest 编译器输出标准 manifest.json 结构
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/models/design_slot.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/models/design_component.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/services/design_to_manifest.dart';

void main() {
  group('P0 编排模型序列化', () {
    test('DesignComponent 序列化/反序列化', () {
      final comp = DesignComponent(
        type: 'chart',
        config: {'title': '测试图表', 'chartType': 'bar'},
      );
      final json = comp.toJson();
      expect(json['type'], 'chart');
      expect(json['config']['title'], '测试图表');

      final restored = DesignComponent.fromJson(json);
      expect(restored.type, 'chart');
      expect(restored.config['chartType'], 'bar');
    });

    test('DesignComponent 空 config 不序列化', () {
      final comp = DesignComponent(type: 'markdown');
      final json = comp.toJson();
      expect(json.containsKey('config'), isFalse);
    });

    test('DesignSlot 序列化/反序列化', () {
      final slot = DesignSlot(
        id: 'slot_0',
        region: SlotRegion.center,
        rect: [10, 20, 300, 200],
        label: '内容区',
      );
      final json = slot.toJson();
      expect(json['id'], 'slot_0');
      expect(json['region'], 'center');
      expect(json['rect'], [10.0, 20.0, 300.0, 200.0]);

      final restored = DesignSlot.fromJson(json);
      expect(restored.id, 'slot_0');
      expect(restored.region, SlotRegion.center);
    });

    test('DesignPage 序列化/反序列化', () {
      final page = DesignPage(
        id: 'page_0',
        label: '首页',
        layoutPreset: LayoutPreset.grid,
      );
      page.addSlot(DesignSlot(id: 'slot_0', region: SlotRegion.top));

      final json = page.toJson();
      expect(json['id'], 'page_0');
      expect(json['slots'].length, 1);
      expect(json['slots'][0]['id'], 'slot_0');

      final restored = DesignPage.fromJson(json);
      expect(restored.slots.length, 1);
      expect(restored.findSlot('slot_0'), isNotNull);
      expect(restored.findSlot('not_exist'), isNull);
    });

    test('DesignDocument 序列化/反序列化', () {
      final doc = DesignDocument(
        pluginId: 'test-plugin',
        pluginName: '测试插件',
        icon: 'science',
      );
      doc.addPage(DesignPage(id: 'page_0', label: '第一页'));
      doc.pages[0].addSlot(DesignSlot(
        id: 'slot_0',
        component: DesignComponent(type: 'chart', config: {'title': '图表'}),
      ));

      final json = doc.toJson();
      expect(json['plugin_id'], 'test-plugin');
      expect(json['plugin_name'], '测试插件');
      expect(json['pages'].length, 1);

      final restored = DesignDocument.fromJson(json);
      expect(restored.pluginId, 'test-plugin');
      expect(restored.pages.length, 1);
      expect(restored.pages[0].slots.length, 1);
    });

    test('DesignDocument 增删页面', () {
      final doc = DesignDocument(pluginId: 'test');
      doc.addPage(DesignPage(id: 'page_0'));
      doc.addPage(DesignPage(id: 'page_1'));
      expect(doc.pageCount, 2);

      doc.removePage('page_0');
      expect(doc.pageCount, 1);
      expect(doc.pages[0].id, 'page_1');
    });

    test('DesignPage 增删 Slot', () {
      final page = DesignPage(id: 'page_0');
      page.addSlot(DesignSlot(id: 'slot_a'));
      page.addSlot(DesignSlot(id: 'slot_b'));
      expect(page.slots.length, 2);

      page.removeSlot('slot_a');
      expect(page.slots.length, 1);
      expect(page.slots[0].id, 'slot_b');
    });

    test('DesignDocument slotCount 统计', () {
      final doc = DesignDocument(pluginId: 'test');
      doc.addPage(DesignPage(id: 'page_0'));
      doc.pages[0].addSlot(DesignSlot(id: 'a'));
      doc.pages[0].addSlot(DesignSlot(id: 'b'));
      doc.addPage(DesignPage(id: 'page_1'));
      doc.pages[1].addSlot(DesignSlot(id: 'c'));
      expect(doc.slotCount, 3);
    });
  });

  group('P0 DesignToManifest 编译器', () {
    test('空文档生成最小 manifest', () {
      final doc = DesignDocument(pluginId: 'min-plugin', pluginName: '最小');
      final manifest = DesignToManifest.compile(doc);

      expect(manifest['schemaVersion'], '2.0');
      expect(manifest['id'], 'min-plugin');
      expect(manifest['name'], '最小');
      expect(manifest['pages'], isEmpty);
    });

    test('单页单 Slot 生成完整 manifest', () {
      final doc = DesignDocument(
        pluginId: 'my-plugin',
        pluginName: '我的插件',
        icon: 'code',
        description: '测试插件',
        route: '/my-plugin',
      );
      final page = DesignPage(
        id: 'page_0',
        label: '主页面',
        layoutPreset: LayoutPreset.fullscreen,
      );
      page.addSlot(DesignSlot(
        id: 'slot_0',
        label: '内容',
        region: SlotRegion.center,
        component: DesignComponent(type: 'markdown', config: {'content': '# Hello'}),
      ));
      doc.addPage(page);

      final manifest = DesignToManifest.compile(doc);
      expect(manifest['id'], 'my-plugin');
      expect(manifest['icon'], 'code');

      final pages = manifest['pages'] as List;
      expect(pages.length, 1);

      final p0 = pages[0] as Map;
      expect(p0['id'], 'page_0');
      expect(p0['label'], '主页面');

      final layout = p0['layout'] as Map;
      expect(layout['type'], 'fullscreen');

      final slots = layout['slots'] as Map;
      expect(slots.containsKey('slot_0'), isTrue);

      final s0 = slots['slot_0'] as Map;
      expect(s0['component']['type'], 'markdown');
    });

    test('多页多 Slot 输出正确', () {
      final doc = DesignDocument(pluginId: 'multi', pluginName: '多页');
      for (var i = 0; i < 3; i++) {
        final page = DesignPage(id: 'page_$i', label: '页面$i');
        page.addSlot(DesignSlot(id: 'top', region: SlotRegion.top));
        page.addSlot(DesignSlot(id: 'center', region: SlotRegion.center));
        doc.addPage(page);
      }

      final manifest = DesignToManifest.compile(doc);
      final pages = manifest['pages'] as List;
      expect(pages.length, 3);
      final p0 = pages[0]['layout']['slots'] as Map;
      expect(p0.length, 2);
    });
  });
}
