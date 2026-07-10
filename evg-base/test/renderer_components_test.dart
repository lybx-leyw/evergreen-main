/// M1 组件渲染器单元测试（R3 / R4 / R11）。
///
/// 针对本次补齐的全部 HTML 渲染函数，构造真实 config 并断言：
/// 1. 调用不抛异常（编译 + 运行路径正确）；
/// 2. 注入的真实字段值出现在 HTML 中（R4 真实字段渲染）；
/// 3. 输出不含任何写死示例串（R11 字段级适配，禁止写死冒充）。
///
/// 运行：cd evg-base && flutter test test/renderer_components_test.dart
import 'package:evergreen_base/renderer/html/html_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _comp(String type, Map<String, dynamic> config) =>
    {'type': type, 'config': config};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('M1 全部补齐组件：真实字段渲染 + 无写死示例', () {
    final slots = <String, dynamic>{};

    // 每个组件注入带唯一标记的真实字段值。
    slots['divider'] = {
      'component': _comp('divider', {'style': 'dotted', 'margin': 12.0})
    };
    slots['code-editor'] = {
      'component': _comp('code-editor', {
        'language': 'python',
        'content': 'print("M1_CODE_MARKER_42")'
      })
    };
    slots['document'] = {
      'component': _comp('document', {
        'document': {'content': 'M1_DOC_MARKER_X'}
      })
    };
    slots['lottery-wheel'] = {
      'component': _comp('lottery-wheel', {
        'lottery': {
          'title': 'M1_LOTTERY_TITLE',
          'segments': ['M1_SEG_A', 'M1_SEG_B', 'M1_SEG_C']
        }
      })
    };
    slots['kanban'] = {
      'component': _comp('kanban', {
        'columns': [
          {
            'title': 'M1_KB_COL_1',
            'items': [
              {'text': 'M1_KB_ITEM_1', 'tag': 'M1_KB_TAG'}
            ]
          }
        ]
      })
    };
    slots['tree'] = {
      'component': _comp('tree', {
        'root': {
          'label': 'M1_TREE_ROOT',
          'children': [
            {'label': 'M1_TREE_CHILD'}
          ]
        }
      })
    };
    slots['map'] = {
      'component': _comp('map', {
        'map': {
          'center': {'lat': 31.2304, 'lng': 121.4737},
          'markers': [
            {'lat': 31.23, 'lng': 121.47, 'label': 'M1_MAP_MARKER_1'}
          ]
        }
      })
    };
    slots['spreadsheet'] = {
      'component': _comp('spreadsheet', {
        'columns': [
          {'key': 'sku', 'label': 'SKU'},
          {'key': 'name', 'label': '名称'}
        ],
        'rows': [
          {'sku': 'M1_SKU_VAL', 'name': 'M1_ROW_NAME'}
        ]
      })
    };
    slots['presentation'] = {
      'component': _comp('presentation', {
        'slides': [
          {'title': 'M1_SLIDE_TITLE', 'content': 'M1_SLIDE_BODY'}
        ]
      })
    };
    slots['type-check'] = {
      'component': _comp('type-check', {
        'question': 'M1_TC_QUESTION',
        'options': [
          {'text': 'M1_TC_OPT_A', 'correct': true},
          {'text': 'M1_TC_OPT_B', 'correct': false}
        ]
      })
    };
    slots['calendar'] = {
      'component': _comp('calendar', {
        'year': 2026,
        'month': 9,
        'events': [
          {'date': '2026-09-15', 'title': 'M1_CAL_EVENT_1'}
        ]
      })
    };
    slots['mindmap'] = {
      'component': _comp('mindmap', {
        'root': {
          'label': 'M1_MM_ROOT',
          'children': [
            {'label': 'M1_MM_CHILD'}
          ]
        }
      })
    };
    slots['whiteboard'] = {
      'component': _comp('whiteboard', {
        'tools': ['pen', 'eraser', 'undo'],
        'colors': ['#ff0000', '#00ff00'],
        'lineWidth': 5.0
      })
    };
    slots['chart'] = {
      'component': _comp('chart', {
        'chart': {
          'type': 'bar',
          'title': 'M1_CHART_TITLE',
          'data': [
            {'label': 'M1_CHART_LBL', 'value': 42}
          ]
        }
      })
    };
    slots['diff-viewer'] = {
      'component': _comp('diff-viewer', {
        'leftLabel': 'M1_DIFF_LEFT_FILE',
        'rightLabel': 'M1_DIFF_RIGHT_FILE',
        'left': 'M1_DIFF_LEFT_LINE',
        'right': 'M1_DIFF_RIGHT_LINE'
      })
    };
    slots['terminal'] = {
      'component': _comp('terminal', {
        'cwd': 'M1_TERM_CWD',
        'lines': [
          {'prompt': '\$', 'text': 'M1_TERM_LINE_1', 'color': '#58a6ff'}
        ]
      })
    };
    slots['crossword'] = {
      'component': _comp('crossword', {
        'title': 'M1_CW_TITLE',
        'grid': [
          ['A', null],
          ['B', null]
        ],
        'clues': {
          'across': ['M1_CW_CLUE_A'],
          'down': ['M1_CW_CLUE_D']
        }
      })
    };
    slots['pronunciation'] = {
      'component': _comp('pronunciation', {
        'word': 'M1_PRON_WORD',
        'phonetic': '/M1_PRON_PH/',
        'score': 88
      })
    };
    slots['data-dashboard'] = {
      'component': _comp('data-dashboard', {
        'title': 'M1_DD_TITLE',
        'cards': [
          {'title': 'M1_DD_CARD_TITLE', 'value': 'M1_DD_CARD_VAL'}
        ]
      })
    };

    final manifest = {
      'name': 'M1 Renderer Test',
      'schemaVersion': '2.0',
      'pages': [
        {
          'id': 'p1',
          'label': 'P1',
          'layout': {'type': 'flex', 'slots': slots}
        }
      ]
    };

    final html = HtmlRenderer.render(manifest);

    // 基本非空展示
    expect(html, contains('evg-comp'));

    // 每个组件注入的真实字段值必须出现
    const realValues = <String>[
      'dotted',
      'M1_CODE_MARKER_42',
      'M1_DOC_MARKER_X',
      'M1_SEG_A',
      'M1_KB_COL_1',
      'M1_KB_ITEM_1',
      'M1_TREE_ROOT',
      'M1_TREE_CHILD',
      'M1_MAP_MARKER_1',
      'M1_SKU_VAL',
      'M1_ROW_NAME',
      'M1_SLIDE_TITLE',
      'M1_SLIDE_BODY',
      'M1_TC_QUESTION',
      'M1_TC_OPT_A',
      'M1_CAL_EVENT_1',
      'M1_MM_ROOT',
      'M1_MM_CHILD',
      'M1_CHART_LBL',
      '42',
      'M1_DIFF_LEFT_LINE',
      'M1_DIFF_RIGHT_LINE',
      'M1_TERM_CWD',
      'M1_TERM_LINE_1',
      'M1_CW_CLUE_A',
      'M1_CW_CLUE_D',
      'M1_PRON_WORD',
      '88',
      'M1_DD_CARD_TITLE',
      'M1_DD_CARD_VAL',
    ];
    for (final v in realValues) {
      expect(html, contains(v), reason: '真实字段值未出现在渲染结果: $v');
    }

    // R11：禁止任何写死示例串残留
    const banned = <String>[
      'lorem ipsum',
      '占位示例',
      'TODO数据',
      '项目 1',
      '运行中',
      '展示 AI 助手',
      '介绍这个平台',
      'Python 中如何声明列表',
      '哪个关键字用于定义 Python 函数',
      '核心主题',
      '本学期各科目',
      '这是一段示例文档内容',
    ];
    for (final b in banned) {
      expect(html.contains(b), isFalse,
          reason: '渲染结果包含写死示例串: $b');
    }
  });
}
