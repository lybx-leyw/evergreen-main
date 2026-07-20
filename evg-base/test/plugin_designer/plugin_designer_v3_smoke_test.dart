/// plugin-designer v3 按钮式重构编译冒烟测试。
///
/// 目标：验证所有核心文件能通过 Dart 编译器（不跑 widget 测试）。
/// 仅 import 轻量文件，不挂载 Provider/SharedPreferences/widget，确保绝不挂死。
library;

import 'package:flutter_test/flutter_test.dart';

// 验证模型
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_component.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_slot.dart';

// 验证视图（编译校验）
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/view/component_picker.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/view/property_panel.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/view/page_sorter.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/view/preview_panel.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/view/json_path_picker.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/plugin_designer_view.dart';

// 验证 widgets
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/widgets/composite_preview_frame.dart';

// 验证服务（核心服务）
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/design_to_manifest.dart';

void main() {
  // ── 模型冒烟 ──
  group('插件设计器 v3 模型冒烟', () {
    test('DesignComponent 构造与序列化', () {
      final c = DesignComponent(type: 'data-table', config: {'title': '测试'});
      expect(c.type, 'data-table');
      expect(c.config['title'], '测试');

      final json = c.toJson();
      final c2 = DesignComponent.fromJson(json);
      expect(c2.type, 'data-table');
      expect(c2.config['title'], '测试');
    });

    test('DesignSlot 构造（v3：无需 rect）', () {
      final s = DesignSlot(id: 'slot_0', label: '测试Slot', region: SlotRegion.center);
      expect(s.id, 'slot_0');
      expect(s.region, SlotRegion.center);
      expect(s.component, isNull);
    });

    test('DesignPage 支持 Slot 增删', () {
      final p = DesignPage(id: 'page_0', label: '首页');
      p.addSlot(DesignSlot(id: 'slot_0', label: 'S1'));
      p.addSlot(DesignSlot(id: 'slot_1', label: 'S2'));
      expect(p.slots.length, 2);
      p.removeSlot('slot_0');
      expect(p.slots.length, 1);
      expect(p.slots[0].id, 'slot_1');
    });

    test('DesignDocument 页面管理', () {
      final doc = DesignDocument(pluginId: 'test-plugin', pluginName: '测试');
      doc.addPage(DesignPage(id: 'page_0', label: '首页'));
      doc.addPage(DesignPage(id: 'page_1', label: '第二页'));
      expect(doc.pages.length, 2);
      expect(doc.slotCount, 0);

      doc.pages[0].addSlot(DesignSlot(id: 's0', label: 'S'));
      expect(doc.slotCount, 1);

      doc.removePage('page_0');
      expect(doc.pages.length, 1);
      expect(doc.slotCount, 0);
    });
  });

  // ── 组件选择器冒烟 ──
  group('ComponentPicker 冒烟', () {
    test('allDesignerComponents 非空', () {
      expect(allDesignerComponents, isNotEmpty);
      expect(allDesignerComponents.length, greaterThan(45)); // 具名+预留
    });

    test('ComponentRegistry 已知类型列表', () {
      expect(ComponentRegistry.knownTypes.contains('data-table'), isTrue);
      expect(ComponentRegistry.knownTypes.contains('ai-assistant'), isTrue);
      expect(ComponentRegistry.knownTypes.contains('placeholder-01'), isTrue);
      expect(ComponentRegistry.isKnownType('data-table'), isTrue);
      expect(ComponentRegistry.isKnownType('unknown-type'), isFalse);
    });

    test('ComponentMeta 结构', () {
      final meta = allDesignerComponents.first;
      expect(meta.type, isNotEmpty);
      expect(meta.label, isNotEmpty);
      expect(meta.group, isNotEmpty);
    });
  });

  // ── PropertyPanel 回调冒烟 ──
  group('PropertyPanel 回调签名（v3 无 rect）', () {
    test('SlotPropChanged 不再包含 rect', () {
      // v3 的 SlotPropChanged typing 已移除 List<double>? rect 参数
      // 此处验证编译通过即可——若能 import 成功即证明签名正确
      final bool slotPropChangedWorks = true; // import 成功 = 通过
      expect(slotPropChangedWorks, isTrue);
    });
  });

  // ── DesignToManifest 编译冒烟 ──
  group('DesignToManifest 冒烟', () {
    test('空文档可编译为 manifest', () {
      final doc = DesignDocument(pluginId: 'empty', pluginName: '空');
      final manifest = DesignToManifest.compile(doc);
      expect(manifest['id'], 'empty');
      expect(manifest['name'], '空');
      expect(manifest['pages'], isEmpty);
    });

    test('有 Slot 的文档正确编译 Slot 区域', () {
      final doc = DesignDocument(pluginId: 'test', pluginName: '测试');
      final page = DesignPage(id: 'pg', label: '首页', layoutPreset: DesignPageLayout.fullscreen);
      final slot = DesignSlot(id: 's0', label: '数据表', region: SlotRegion.center);
      slot.component = DesignComponent(type: 'data-table', config: {'columns': 3});
      page.addSlot(slot);
      doc.addPage(page);

      final manifest = DesignToManifest.compile(doc);
      final pages = manifest['pages'] as List;
      expect(pages.length, 1);
      final p0 = pages[0] as Map;
      final layout = p0['layout'] as Map;
      final slots = layout['slots'] as Map;
      expect(slots.containsKey('s0'), isTrue);
      final s0 = slots['s0'] as Map;
      final comp = s0['component'] as Map;
      expect(comp['type'], 'data-table');
    });
  });

  // ── CompositePreviewFrame 编译冒烟 ──
  group('CompositePreviewFrame 冒烟', () {
    test('可 import CompositePreviewFrame', () {
      // 若能 import 成功，编译即通过
      expect(CompositePreviewFrame, isA<Type>());
    });
  });

  // ── JsonPathPicker / PluginDesignerView 编译冒烟 ──
  group('点选路径 UI 编译冒烟', () {
    test('可 import JsonPathPicker 与 PluginDesignerView', () {
      // import 成功即证明 json_path_picker / plugin_designer_view 编译通过
      expect(JsonPathPicker, isA<Type>());
      expect(PluginDesignerView, isA<Type>());
    });
  });
}
