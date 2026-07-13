/// M2 P3-4 端到端集成测试。
///
/// 一次性验证「组件级 endpoint + 模块级 dataBindings」两条链路在 Dart 端与
/// HTML 端（renderWithData）行为一致（R7 双端一致 / R2 全链路接通）：
///   1. 组件级 `dataSource(endpoint:'orch://<type>')` → 经 DataOrchestrator 拉取
///      → 合并进组件真实 config 字段 → 渲染；
///   2. 模块级 `ModuleDescriptor.dataBindings` → CompositeView 经 orch 拉取
///      → 构建 tableData → 注入 DefaultView；
///   3. HTML 端同一份 orch 经 `HtmlRenderer.renderWithData` 产出含注入数据的 HTML。
///
/// 运行：cd evg-base && flutter test test/m2_data_source_test.dart
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/components/data/card_list_slot.dart';
import 'package:evergreen_base/renderer/page/composite_view.dart';
import 'package:evergreen_base/renderer/page/html_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个带注册类型的假 DataOrchestrator。
DataOrchestrator _fakeOrch(Map<String, dynamic> types) {
  final orch = DataOrchestrator();
  types.forEach((name, data) {
    orch.register(
      DataType<dynamic>(name: name),
      () async => data,
    );
  });
  return orch;
}

/// 包一层 ProviderScope，注入假 orchestrator。
Widget _scope(Widget child, DataOrchestrator orch) => ProviderScope(
      overrides: [dataOrchestratorProvider.overrideWith((ref) => orch)],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M2 端到端：组件级 + 模块级 双链路', () {
    testWidgets('组件级 orch:// 注入 与 模块级 dataBindings 同 orch 跑通',
        (tester) async {
      final orch = _fakeOrch({
        'cards': [
          {'title': '注入卡片A', 'body': '来自orch'},
          {'title': '注入卡片B', 'body': '来自orch'},
        ],
        'myRows': [
          {'name': '注入行A', 'score': 10},
          {'name': '注入行B', 'score': 20},
        ],
      });

      // —— 组件级链路：CardListSlot 经 orch://cards 注入 ——
      final cardSlot = CardListSlot(
        config: ComponentDescriptor(
          type: 'card-list',
          config: {'title': '静态标题'},
          dataSource: const DataSourceDescriptor(endpoint: 'orch://cards'),
        ),
      );
      await tester.pumpWidget(_scope(cardSlot, orch));
      await tester.pumpAndSettle();
      expect(find.text('注入卡片A'), findsWidgets);
      expect(find.text('注入卡片B'), findsWidgets);

      // —— 模块级链路：CompositeView 经 dataBindings 注入 DefaultView ——
      final module = ModuleDescriptor(
        id: 'mod1',
        name: '集成模块',
        dataBindings: [
          DataBindingDescriptor(dataType: 'myRows', display: 'table'),
        ],
      );
      await tester.pumpWidget(_scope(CompositeView(descriptor: module), orch));
      await tester.pumpAndSettle();
      expect(find.text('注入行A'), findsWidgets);
      expect(find.text('注入行B'), findsWidgets);
    });
  });

  group('M2 端到端：HTML 端与 Dart 端一致', () {
    test('renderWithData 产出含注入数据的 HTML（与 Dart 端同源 orch）',
        () async {
      final orch = _fakeOrch({
        'rows': [
          {'c1': '注入行HTML_A'},
          {'c1': '注入行HTML_B'},
        ],
      });

      final manifest = {
        'id': 'm',
        'name': 'M',
        'type': 'standard',
        'pages': [
          {
            'id': 'p1',
            'layout': {
              'type': 'flex',
              'slots': {
                's1': {
                  'component': {
                    'type': 'data-table',
                    'dataSource': {'endpoint': 'orch://rows'},
                    'config': {
                      'columns': ['c1']
                    }
                  }
                }
              }
            }
          }
        ]
      };

      final html = await HtmlRenderer.renderWithData(manifest, orch);
      expect(html, contains('注入行HTML_A'));
      expect(html, contains('注入行HTML_B'));
    });

    test('静态 manifest（无 dataSource）→ 向后兼容静态渲染，不崩', () async {
      final orch = _fakeOrch({});
      final manifest = {
        'id': 'm',
        'name': 'M',
        'type': 'standard',
        'pages': [
          {
            'id': 'p1',
            'layout': {
              'type': 'flex',
              'slots': {
                's1': {
                  'component': {
                    'type': 'data-table',
                    'config': {
                      'columns': ['c1'],
                      'rows': [
                        {'c1': 'STATIC'}
                      ]
                    }
                  }
                }
              }
            }
          }
        ]
      };
      final html = await HtmlRenderer.renderWithData(manifest, orch);
      expect(html, contains('STATIC'));
    });
  });
}
