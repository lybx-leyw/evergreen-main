/// v5P Gap: SlotDescriptor 嵌套解析 + _buildSlotTree 渲染测试。
///
/// 目的：在秒级反馈中覆盖嵌套布局全链路，不依赖 flutter run 全量 app。
@TestOn('vm')
library;

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ════════════════════════════════════════════════════════════════
  // 解析层测试 — 确认 SlotDescriptor.fromJson 能正确解析嵌套结构
  // ════════════════════════════════════════════════════════════════

  group('SlotDescriptor 嵌套解析', () {
    test('纯原子 slot → isContainer = false, isAtomic = true', () {
      final json = {
        'component': {'type': 'markdown', 'config': {'content': 'hello'}},
      };
      final slot = SlotDescriptor.fromJson(json);
      expect(slot.isContainer, false);
      expect(slot.isAtomic, true);
      expect(slot.component!.type, 'markdown');
    });

    test('纯容器 slot（children 非空）→ isContainer = true, isAtomic = false', () {
      final json = {
        'children': [
          {'component': {'type': 'stat-tile', 'config': {'title': 'A'}}},
          {'component': {'type': 'stat-tile', 'config': {'title': 'B'}}},
        ],
      };
      final slot = SlotDescriptor.fromJson(json);
      expect(slot.isContainer, true);
      expect(slot.isAtomic, false);
      expect(slot.children!.length, 2);
      expect(slot.children![0].component!.type, 'stat-tile');
    });

    test('容器+自有组件 → isContainer=true, isAtomic=true', () {
      final json = {
        'component': {'type': 'markdown', 'config': {'content': 'header'}},
        'children': [
          {'component': {'type': 'stat-tile', 'config': {'title': 'A'}}},
        ],
      };
      final slot = SlotDescriptor.fromJson(json);
      expect(slot.isContainer, true);
      expect(slot.isAtomic, true);
      expect(slot.component!.type, 'markdown');
      expect(slot.children!.length, 1);
    });

    test('children 空数组 → isContainer = false（兼容旧 manifest）', () {
      final json = {
        'children': [],
        'component': {'type': 'markdown', 'config': {'content': 'x'}},
      };
      final slot = SlotDescriptor.fromJson(json);
      expect(slot.isContainer, false);
      expect(slot.isAtomic, true);
    });

    test('allComponentTypes 递归收集所有后代组件类型', () {
      final json = <String, dynamic>{
        'children': <dynamic>[
          <String, dynamic>{'component': <String, dynamic>{'type': 'stat-tile', 'config': <String, dynamic>{}}},
          <String, dynamic>{
            'children': <dynamic>[
              <String, dynamic>{'component': <String, dynamic>{'type': 'chart', 'config': <String, dynamic>{}}},
            ],
          },
        ],
        'component': <String, dynamic>{'type': 'markdown', 'config': <String, dynamic>{}},
      };
      final slot = SlotDescriptor.fromJson(json);
      final types = slot.allComponentTypes;
      // 顺序：自身 → children 按深度优先递归
      expect(types, containsAll(['markdown', 'stat-tile', 'chart']));
      expect(types.length, 3);
    });

    test('容器 slot 携带 layout 子节点排布方式', () {
      final json = {
        'children': [
          {'component': {'type': 'stat-tile', 'config': {'title': 'A'}}},
        ],
        'layout': {'type': 'flex', 'direction': 'row'},
      };
      final slot = SlotDescriptor.fromJson(json);
      expect(slot.layout, isNotNull);
      expect(slot.layout!.type, 'flex');
    });

    test('容器无 layout → 缺省 flex column', () {
      final json = {
        'children': [
          {'component': {'type': 'stat-tile', 'config': {'title': 'A'}}},
        ],
      };
      final slot = SlotDescriptor.fromJson(json);
      // 无 layout 时缺省为 null，buildContainer 用 const LayoutDescriptor(type:'flex') 兜底
      expect(slot.layout, isNull);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 展示 v5 manifest 解析验证
  // ════════════════════════════════════════════════════════════════

  group('showcase-v5 manifest 解析', () {
    late Map<String, dynamic> moduleJson;

    setUp(() {
      moduleJson = {
        'id': 'showcase-v5',
        'type': 'module',
        'name': '展示大厅 v5',
        'pages': [
          {
            'id': 'nested',
            'label': '嵌套布局',
            'layout': {
              'type': 'flex',
              'preset': {'direction': 'column'},
              'slots': {
                // 原子 slot → 解释性 markdown
                'nested-desc': {
                  'component': {
                    'type': 'markdown',
                    'config': {'content': '# 嵌套布局演示\n容器内3个stat-tile横排'},
                  },
                },
                // 容器 slot → 3 个 stat-tile 横排
                'kpi-row': {
                  'children': [
                    {
                      'component': {
                        'type': 'stat-tile',
                        'config': {'title': '课程数', 'value': '6'},
                      },
                    },
                    {
                      'component': {
                        'type': 'stat-tile',
                        'config': {'title': '平均分', 'value': '87'},
                      },
                    },
                    {
                      'component': {
                        'type': 'stat-tile',
                        'config': {'title': '通过率', 'value': '100%'},
                      },
                    },
                  ],
                  'layout': {'type': 'flex', 'direction': 'row'},
                },
              },
            },
          },
        ],
      };
    });

    test('ModuleDescriptor 解析页面+slot', () {
      final d = ModuleDescriptor.fromJson(moduleJson);
      expect(d.id, 'showcase-v5');
      expect(d.pages.length, 1);

      final page = d.pages[0];
      expect(page.id, 'nested');
      expect(page.layout.slots.length, 2);

      final keys = page.layout.slots.keys.toList();
      expect(keys, containsAll(['nested-desc', 'kpi-row']));
    });

    test('kpi-row 容器 slot 正确解析 children', () {
      final d = ModuleDescriptor.fromJson(moduleJson);
      final page = d.pages[0];
      final kpiRow = page.layout.slots['kpi-row']!;

      expect(kpiRow.isContainer, true);
      expect(kpiRow.isAtomic, false); // 无自身 component
      expect(kpiRow.children!.length, 3);

      final types = kpiRow.children!.map((c) => c.component!.type).toList();
      expect(types, ['stat-tile', 'stat-tile', 'stat-tile']);
    });

    test('kpi-row 子 slot 的 stat-tile config 正确', () {
      final d = ModuleDescriptor.fromJson(moduleJson);
      final page = d.pages[0];
      final kpiRow = page.layout.slots['kpi-row']!;

      expect(kpiRow.children![0].component!.config['title'], '课程数');
      expect(kpiRow.children![1].component!.config['value'], '87');
    });
  });
}
