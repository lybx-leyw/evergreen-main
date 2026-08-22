/// DataDiff 差异引擎测试。
///
/// 覆盖：Map/List/标量/字符串差异、易变字段忽略、摘要文本。

import 'package:test/test.dart';

import '../data_diff.dart';

void main() {
  group('computeDataDiff', () {
    test('相同数据无变化', () {
      final d = computeDataDiff({'a': 1}, {'a': 1});
      expect(d.hasChanges, isFalse);
    });

    test('Map 新增 key', () {
      final d = computeDataDiff({'a': 1}, {'a': 1, 'b': 2});
      expect(d.added, 1);
      expect(d.addedItems, ['b']);
      expect(d.summarize(), contains('新增 1 项'));
    });

    test('Map 移除 key', () {
      final d = computeDataDiff({'a': 1, 'b': 2}, {'a': 1});
      expect(d.removed, 1);
      expect(d.removedItems, ['b']);
    });

    test('标量变化', () {
      final d = computeDataDiff({'score': 80}, {'score': 90});
      expect(d.changed, 1);
      expect(d.changedItems.first, contains('score'));
      expect(d.summarize(), contains('更新 1 项'));
    });

    test('嵌套 Map 递归统计', () {
      final d = computeDataDiff(
        {'gpa': {'five': 3.5, 'four': 3.2}},
        {'gpa': {'five': 3.8, 'four': 3.2}},
      );
      expect(d.changed, 1);
      expect(d.hasChanges, isTrue);
    });

    test('List 新增元素（优先用标题字段做标签）', () {
      final d = computeDataDiff(
        [
          {'name': '高数', 'id': 1}
        ],
        [
          {'name': '高数', 'id': 1},
          {'name': '线代', 'id': 2}
        ],
      );
      expect(d.added, 1);
      expect(d.addedItems, ['线代']);
    });

    test('List 移除元素', () {
      final d = computeDataDiff(
        [
          {'name': '高数'},
          {'name': '线代'}
        ],
        [
          {'name': '高数'}
        ],
      );
      expect(d.removed, 1);
      expect(d.removedItems, ['线代']);
    });

    test('易变字段变化不算变更', () {
      final d = computeDataDiff(
        {'data': {'v': 1}, 'ts': 'a'},
        {'data': {'v': 1}, 'ts': 'b'},
      );
      expect(d.hasChanges, isFalse);
    });

    test('列表元素仅时间戳不同不算新增/移除', () {
      final d = computeDataDiff(
        [
          {'name': '高数', 'ts': '1'}
        ],
        [
          {'name': '高数', 'ts': '2'}
        ],
      );
      expect(d.hasChanges, isFalse);
    });

    test('字符串内容变化', () {
      final d = computeDataDiff('旧内容', '新内容');
      expect(d.changed, 1);
      expect(d.hasChanges, isTrue);
    });

    test('类型变化（int → string）', () {
      final d = computeDataDiff({'v': 1}, {'v': '1'});
      expect(d.changed, 1);
    });

    test('null 与空串视为有变化', () {
      final d = computeDataDiff('abc', '');
      expect(d.hasChanges, isTrue);
    });

    test('summarize 包含计数与示例', () {
      final d = computeDataDiff(
        [
          {'name': '高数'}
        ],
        [
          {'name': '高数'},
          {'name': '线代'},
          {'name': '英语'}
        ],
      );
      final s = d.summarize();
      expect(s, contains('新增 2 项'));
      expect(s, contains('线代'));
      expect(s, contains('英语'));
    });

    test('变更条目示例上限截断', () {
      final before = {
        for (var i = 0; i < 10; i++) 'k$i': i,
      };
      final after = {
        for (var i = 0; i < 10; i++) 'k$i': i + 1,
      };
      final d = computeDataDiff(before, after);
      expect(d.changed, 10);
      expect(d.changedItems.length, DataDiff.kMaxDiffDetailItems);
    });
  });
}
