// 验证扁平化分组视图的拖拽重排映射（组间/组内），确保从嵌套 RLV 重构后
// 排序语义与原实现一致，且不会产生跨组错乱。
//
// 重点覆盖此前导致死循环的「单一 RLV + 扁平 item」映射逻辑：
// - 组头拖动 → 新 keys 顺序
// - 同组插件拖动 → 新插件 id 顺序
// - 跨组插件拖动 → 返回 null（忽略，rebuild 复原）
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/marketplace_plugin_info.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/marketplace_slot.dart';

PluginInfo _p(String id, String section, {int order = 50}) => PluginInfo(
      id: id,
      name: id,
      description: '',
      type: 'module',
      dirPath: '',
      isModule: true,
      hasSidebar: false,
      pageCount: 0,
      section: section,
      order: order,
    );

/// 按紧凑字符串表示的 flat 列表构建 FlatItem 列表，便于断言。
/// 语法：'H:A' = 组头 A；'A:p1' = 组 A 内插件 p1。
List<FlatItem> _flat(List<String> tokens) {
  final items = <FlatItem>[];
  var gi = 0;
  String? currentGroup;
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t.startsWith('H:')) {
      currentGroup = t.substring(2);
      items.add(FlatItem.header(currentGroup!, gi++));
    } else {
      final sep = t.indexOf(':');
      final g = t.substring(0, sep);
      final pid = t.substring(sep + 1);
      items.add(FlatItem.plugin(g, gi, _p(pid, g)));
    }
  }
  return items;
}

void main() {
  group('computeGroupReorder（组头拖拽）', () {
    test('把第 0 组拖到第 2 组之后', () {
      // flat: H:A, A:a1, H:B, B:b1, H:C, C:c1
      final flat = _flat(['H:A', 'A:a1', 'H:B', 'B:b1', 'H:C', 'C:c1']);
      final keys = ['A', 'B', 'C'];
      // 把组头 A(索引0) 拖到 C 组头(索引4)之后 → newIndex=5（末尾）
      final res = computeGroupReorder(flat, keys, 0, 5);
      expect(res, ['B', 'C', 'A']);
    });

    test('把第 2 组拖到第 0 组之前', () {
      final flat = _flat(['H:A', 'A:a1', 'H:B', 'B:b1', 'H:C', 'C:c1']);
      final keys = ['A', 'B', 'C'];
      // 把组头 C(索引4) 拖到最前 → newIndex=0
      final res = computeGroupReorder(flat, keys, 4, 0);
      expect(res, ['C', 'A', 'B']);
    });

    test('相邻组交换 A↔B', () {
      final flat = _flat(['H:A', 'A:a1', 'H:B', 'B:b1']);
      final keys = ['A', 'B'];
      // 把组头 A(0) 拖到 B 之后 → newIndex=3（末尾）
      final res = computeGroupReorder(flat, keys, 0, 3);
      expect(res, ['B', 'A']);
    });
  });

  group('computePluginReorder（组内插件拖拽）', () {
    test('同组内把第 1 个插件拖到最后', () {
      final flat = _flat(['H:A', 'A:a1', 'A:a2', 'A:a3']);
      final grouped = {
        'A': [_p('a1', 'A'), _p('a2', 'A'), _p('a3', 'A')]
      };
      // 拖 a1(flat 索引1) 到 a3 之后 → newIndex=4（末尾，移除后插入末位）
      final res = computePluginReorder(flat, grouped, 1, 4);
      expect(res, ['a2', 'a3', 'a1']);
    });

    test('同组内把最后一个插件拖到最前', () {
      final flat = _flat(['H:A', 'A:a1', 'A:a2', 'A:a3']);
      final grouped = {
        'A': [_p('a1', 'A'), _p('a2', 'A'), _p('a3', 'A')]
      };
      // 拖 a3(flat 索引3) 到最前 → newIndex=1（组头 H:A 在索引0，插入其后）
      final res = computePluginReorder(flat, grouped, 3, 1);
      expect(res, ['a3', 'a1', 'a2']);
    });

    test('跨组插件拖拽返回 null（忽略以复原）', () {
      final flat = _flat(['H:A', 'A:a1', 'A:a2', 'H:B', 'B:b1']);
      final grouped = {
        'A': [_p('a1', 'A'), _p('a2', 'A')],
        'B': [_p('b1', 'B')],
      };
      // 把 a2(flat 索引2) 拖到 B 组内 → newIndex=4（落在 B:b1 位置）
      final res = computePluginReorder(flat, grouped, 2, 4);
      expect(res, isNull);
    });
  });
}
