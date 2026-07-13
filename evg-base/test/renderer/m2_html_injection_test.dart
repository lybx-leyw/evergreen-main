/// M2 P3-2 HTML 端 dataSource 注入等价测试（R7 双端一致）。
///
/// 验证 [HtmlRenderer.renderWithData] 能把 `dataSource` 经 DataOrchestrator
/// 拉取的真实数据注入 HTML 模板（与 Dart 端 DataSourceSlot 同映射）。
///
/// 运行：cd evg-base && flutter test test/renderer/m2_html_injection_test.dart
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/page/html_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HTML data-table 注入 → 真实行出现在 HTML', () async {
    final orch = DataOrchestrator();
    orch.register(
      DataType<dynamic>(name: 'rows'),
      () async => [
        {'name': '注入行HTML_A'},
        {'name': '注入行HTML_B'},
      ],
    );

    final manifest = {
      'schemaVersion': '2.0',
      'type': 'module',
      'id': 'm',
      'name': 'M',
      'pages': [
        {
          'id': 'p',
          'label': 'P',
          'default': true,
          'layout': {
            'type': 'grid',
            'preset': {'columns': 1},
            'slots': {
              'main': {
                'component': {
                  'type': 'data-table',
                  'dataSource': {'endpoint': 'orch://rows'},
                  'config': {
                    'columns': [
                      {'key': 'name', 'label': '名称'}
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
    expect(html, contains('注入行HTML_A'));
    expect(html, contains('注入行HTML_B'));
  });

  test('HTML stat-tile 注入 → 真实 value 出现在 HTML', () async {
    final orch = DataOrchestrator();
    orch.register(
      DataType<dynamic>(name: 'stat'),
      () async => {'value': '99', 'subtitle': '注入副标题'},
    );

    final manifest = {
      'schemaVersion': '2.0',
      'type': 'module',
      'id': 'm',
      'name': 'M',
      'pages': [
        {
          'id': 'p',
          'label': 'P',
          'default': true,
          'layout': {
            'type': 'grid',
            'preset': {'columns': 1},
            'slots': {
              'main': {
                'component': {
                  'type': 'stat-tile',
                  'dataSource': {'endpoint': 'orch://stat'},
                  'config': {'title': 'T'}
                }
              }
            }
          }
        }
      ]
    };

    final html = await HtmlRenderer.renderWithData(manifest, orch);
    expect(html, contains('99'));
    expect(html, contains('注入副标题'));
  });

  test('无 dataSource → HTML 静态渲染（向后兼容）', () async {
    final manifest = {
      'schemaVersion': '2.0',
      'type': 'module',
      'id': 'm',
      'name': 'M',
      'pages': [
        {
          'id': 'p',
          'label': 'P',
          'default': true,
          'layout': {
            'type': 'grid',
            'preset': {'columns': 1},
            'slots': {
              'main': {
                'component': {
                  'type': 'stat-tile',
                  'config': {'title': 'T', 'value': 'STATIC'}
                }
              }
            }
          }
        }
      ]
    };
    final html = await HtmlRenderer.render(manifest);
    expect(html, contains('STATIC'));
  });
}
