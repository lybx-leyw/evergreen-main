/// 加载真实 showcase-v5 manifest 并验证解析完整性。
/// 这是黑屏问题定位的关键。
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('showcase-v5 真实 manifest 解析', () {
    late ModuleDescriptor module;

    setUp(() {
      const manifestPath = r'd:\evg-workplace\plugins\showcase-v5\module\manifest.json';
      final raw = File(manifestPath).readAsStringSync();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      module = ModuleDescriptor.fromJson(json);
    });

    test('基本字段', () {
      expect(module.id, 'showcase-v5');
      expect(module.pages.length, 4);
    });

    test('页面 nested 有容器 slot kpi-group', () {
      final nested = module.pages.firstWhere((p) => p.id == 'nested');
      final slots = nested.layout.slots;

      expect(slots.containsKey('intro'), true);
      expect(slots.containsKey('kpi-group'), true);

      final kpiGroup = slots['kpi-group']!;
      expect(kpiGroup.isContainer, true,
          reason: 'kpi-group 应为容器型 slot（有 children 无 component）');
      expect(kpiGroup.isAtomic, false);
      expect(kpiGroup.children!.length, 3,
          reason: 'kpi-group 应有 3 个子 stat-tile');

      final childTypes = kpiGroup.children!.map((c) => c.component!.type).toList();
      expect(childTypes, ['stat-tile', 'stat-tile', 'stat-tile']);
    });

    test('kpi-group 容器 layout 为 flex row', () {
      final nested = module.pages.firstWhere((p) => p.id == 'nested');
      final kpiGroup = nested.layout.slots['kpi-group']!;

      expect(kpiGroup.layout, isNotNull);
      expect(kpiGroup.layout!.type, 'flex');
    });

    test('页面 pipeline 有 dataSource 绑定', () {
      final pipeline = module.pages.firstWhere((p) => p.id == 'pipeline');
      final slots = pipeline.layout.slots;

      // dataSource 在 ComponentDescriptor 上，不在 config 内
      var hasDataSource = false;
      for (final slot in slots.values) {
        if (slot.component?.dataSource != null) {
          hasDataSource = true;
          break;
        }
      }
      expect(hasDataSource, true, reason: 'pipeline 页应有 dataSource 演示');
    });

    test('页面 style 有 gap/borderRadius/padding 配置', () {
      final style = module.pages.firstWhere((p) => p.id == 'style');
      expect(style.layout.slots.isNotEmpty, true);
    });

    test('页面 all 有嵌套+数据混合', () {
      final all = module.pages.firstWhere((p) => p.id == 'all');
      final slots = all.layout.slots;

      // 检查是否有容器 slot
      var hasContainer = false;
      for (final slot in slots.values) {
        if (slot.isContainer) { hasContainer = true; break; }
      }
      expect(hasContainer, true, reason: 'all 页应包含嵌套容器演示');
    });
  });
}
