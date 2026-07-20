/// json_tree 纯 Dart 单元测试 —— 插件设计器「点选数据路径」的树模型。
///
/// 核心契约：树节点携带的 path 必须能被 extractPath 无损解析回对应值
/// （生成 ↔ 解析往返一致），否则点选生成的 dataPath 在渲染期取不到数据。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/renderer/atomic/json_path.dart';
import 'package:evergreen_base/renderer/atomic/json_tree.dart';

void main() {
  group('jsonPathOf 路径生成', () {
    test('字段与下标混合格式', () {
      expect(jsonPathOf(const []), '');
      expect(jsonPathOf(const ['a']), 'a');
      expect(jsonPathOf(const ['a', 'b']), 'a.b');
      expect(jsonPathOf(const ['a', 'b', 0, 'c']), 'a.b[0].c');
      expect(jsonPathOf(const ['results', 'items', 12]), 'results.items[12]');
      expect(jsonPathOf(const ['data', 0, 'rows', 3, 'name']),
          'data[0].rows[3].name');
    });
  });

  group('isExpressibleKey 键合法性', () {
    test('合法键', () {
      expect(isExpressibleKey('a'), isTrue);
      expect(isExpressibleKey('items'), isTrue);
      expect(isExpressibleKey('_private'), isTrue);
      expect(isExpressibleKey('camelCase123'), isTrue);
    });

    test('非法键（extractPath 无法表达）', () {
      expect(isExpressibleKey('a-b'), isFalse); // 含连字符
      expect(isExpressibleKey('a b'), isFalse); // 含空格
      expect(isExpressibleKey('2024'), isFalse); // 数字开头
      expect(isExpressibleKey('a.b'), isFalse); // 含点
      expect(isExpressibleKey('中文键'), isFalse); // 非 ASCII
      expect(isExpressibleKey(''), isFalse);
    });
  });

  group('buildJsonTree 构建', () {
    test('Map 嵌套结构', () {
      final root = buildJsonTree({
        'results': {
          'items': [
            {'name': '甲', 'score': 90},
            {'name': '乙', 'score': 85},
          ],
          'total': 2,
        },
        'ok': true,
      });

      expect(root.kind, JsonNodeKind.map);
      expect(root.path, '');
      expect(root.pathValid, isTrue);
      expect(root.children.length, 2);

      final results = root.children[0];
      expect(results.label, 'results');
      expect(results.path, 'results');
      expect(results.kind, JsonNodeKind.map);

      final items = results.children[0];
      expect(items.path, 'results.items');
      expect(items.kind, JsonNodeKind.list);
      expect(items.summary, '[2 项]');

      final item0 = items.children[0];
      expect(item0.label, '[0]');
      expect(item0.path, 'results.items[0]');

      final name = item0.children[0];
      expect(name.path, 'results.items[0].name');
      expect(name.kind, JsonNodeKind.value);
      expect(name.summary, '"甲"');
    });

    test('List 根节点', () {
      final root = buildJsonTree([1, 2, 3]);
      expect(root.kind, JsonNodeKind.list);
      expect(root.children.length, 3);
      expect(root.children[1].path, '[1]');
      expect(root.children[1].summary, '2');
    });

    test('标量根节点', () {
      final root = buildJsonTree('hello');
      expect(root.kind, JsonNodeKind.value);
      expect(root.summary, '"hello"');
    });

    test('List 超长截断', () {
      final big = List.generate(100, (i) => i);
      final root = buildJsonTree(big, maxListItems: 50);
      expect(root.children.length, 50);
      expect(root.totalChildren, 100);
      expect(root.summary, '[100 项]');
    });

    test('空容器', () {
      final root = buildJsonTree({'empty': <String, dynamic>{}, 'list': []});
      expect(root.children[0].summary, '{0 键}');
      expect(root.children[0].children, isEmpty);
      expect(root.children[1].summary, '[0 项]');
    });

    test('特殊键标记 pathValid=false 且传染子树', () {
      final root = buildJsonTree({
        'a-b': {'c': 1},
        '2024': 5,
        'ok': {'x-y': 2},
      });
      final ab = root.children[0];
      expect(ab.pathValid, isFalse);
      expect(ab.children[0].pathValid, isFalse); // 子节点同样不可选
      expect(root.children[1].pathValid, isFalse); // 数字开头
      expect(root.children[2].pathValid, isTrue);
      expect(root.children[2].children[0].pathValid, isFalse);
    });

    test('null 值摘要', () {
      final root = buildJsonTree({'n': null});
      expect(root.children[0].summary, 'null');
    });
  });

  group('生成路径 ↔ extractPath 往返契约', () {
    test('所有合法节点的 path 均可被 extractPath 解析回原值', () {
      final data = {
        'results': {
          'items': [
            {'name': '甲', 'tags': ['x', 'y']},
            {'name': '乙', 'tags': []},
          ],
          'total': 2,
        },
        'meta': {'page': 1, 'hasMore': false},
      };
      final root = buildJsonTree(data);

      void check(JsonTreeNode node, dynamic expected) {
        if (node.pathValid) {
          if (node.path.isEmpty) {
            expect(extractPath(data, node.path), same(data),
                reason: '根路径应返回全量数据');
          } else {
            expect(extractPath(data, node.path), equals(expected),
                reason: '路径 ${node.path} 往返失败');
          }
        }
        if (node.isContainer) {
          final srcData =
              node.path.isEmpty ? data : extractPath(data, node.path);
          for (var i = 0; i < node.children.length; i++) {
            final child = node.children[i];
            final childExpected =
                srcData is Map ? srcData[child.label] : (srcData as List)[i];
            check(child, childExpected);
          }
        }
      }

      check(root, data);
    });

    test('pathRoundTrip 工具函数', () {
      final data = {
        'a': [
          {'b': 1}
        ]
      };
      final root = buildJsonTree(data);
      expect(pathRoundTrip(data, root), isTrue);
      expect(pathRoundTrip(data, root.children[0]), isTrue); // a
      expect(pathRoundTrip(data, root.children[0].children[0]), isTrue); // a[0]
      expect(pathRoundTrip(data, root.children[0].children[0].children[0]),
          isTrue); // a[0].b
    });
  });

  group('flattenVisible 懒展开', () {
    final data = {
      'a': {'b': {'c': 1}, 'd': 2},
      'e': [1, 2],
    };

    test('默认仅展开根（第一层可见）', () {
      final root = buildJsonTree(data);
      final flat = flattenVisible(root, {});
      // 根 + a + e（容器未展开，子节点不可见）
      expect(flat.map((f) => f.node.label).toList(), ['root', 'a', 'e']);
      expect(flat[0].depth, 0);
      expect(flat[1].depth, 1);
    });

    test('展开集合控制可见性', () {
      final root = buildJsonTree(data);
      final flat = flattenVisible(root, {'a'});
      expect(flat.map((f) => f.node.label).toList(),
          ['root', 'a', 'b', 'd', 'e']);
    });

    test('多层展开', () {
      final root = buildJsonTree(data);
      final flat = flattenVisible(root, {'a', 'a.b', 'e'});
      expect(flat.map((f) => f.node.label).toList(),
          ['root', 'a', 'b', 'c', 'd', 'e', '[0]', '[1]']);
      expect(flat[3].depth, 3); // c
    });
  });

  group('ancestorPaths 祖先链', () {
    test('嵌套路径', () {
      expect(ancestorPaths('a.b[0].c'), {'a', 'a.b', 'a.b[0]'});
      expect(ancestorPaths('results.items'), {'results'});
      expect(ancestorPaths('a'), isEmpty);
      expect(ancestorPaths(''), isEmpty);
      expect(ancestorPaths(null), isEmpty);
      expect(ancestorPaths('data[0].rows'), {'data', 'data[0]'});
    });
  });
}
