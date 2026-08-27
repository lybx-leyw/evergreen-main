/// Task 六 Bug 7 分支纯逻辑测试 —— session_branch.dart（renderer 子包 test/ 下）。
///
/// 运行：cd evg-base/lib/renderer && dart test test/session_branch_test.dart
/// 注意：renderer 子包的 .dart_tool/package_config.json 需将 evergreen_base 的
/// rootUri 指向仓库根（`../../..`，即 evg-base），使 package:evergreen_base/…
/// 解析到真实源码（见 agent_A6_final.md 的测试说明）。
library;

import 'package:evergreen_base/core/agent/agent/session.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/interaction/chat/session_branch.dart';
import 'package:test/test.dart';

Session _session(
  String id, {
  String? parentId,
  int? forkTurn,
  DateTime? updatedAt,
}) => Session(
  id: id,
  title: 's-$id',
  parentId: parentId,
  forkTurn: forkTurn,
  updatedAt: updatedAt ?? DateTime(2026, 1, 1),
);

void main() {
  group('branchFamilyOf', () {
    test('旧会话（无 parentId 且无子分支）→ 分支族大小 1', () {
      final all = [_session('a'), _session('b')];
      expect(branchFamilyOf(all, 'a'), hasLength(1));
      expect(branchFamilyOf(all, 'a').single.id, 'a');
    });

    test('根会话 → 组 = 自身 + 全部子分支', () {
      final all = [
        _session('root'),
        _session('c1', parentId: 'root', forkTurn: 3),
        _session('c2', parentId: 'root', forkTurn: 5),
        _session('other'),
      ];
      final group = branchFamilyOf(all, 'root');
      expect(group.map((s) => s.id).toSet(), {'root', 'c1', 'c2'});
    });

    test('子会话 → 组 = 自身 + 父 + 同父兄弟 + 子分支', () {
      final all = [
        _session('parent'),
        _session('sib1', parentId: 'parent', forkTurn: 2),
        _session('me', parentId: 'parent', forkTurn: 4),
        _session('child', parentId: 'me', forkTurn: 6),
        _session('unrelated'),
      ];
      final group = branchFamilyOf(all, 'me');
      expect(group.map((s) => s.id).toSet(), {'parent', 'sib1', 'me', 'child'});
    });

    test('找不到会话 → 空列表', () {
      expect(branchFamilyOf([_session('a')], 'nope'), isEmpty);
    });

    test('排序：父会话优先，子分支按 forkTurn 升序', () {
      final all = [
        _session('parent'),
        _session('c2', parentId: 'parent', forkTurn: 5),
        _session('c1', parentId: 'parent', forkTurn: 3),
      ];
      final group = branchFamilyOf(all, 'parent');
      expect(group.map((s) => s.id).toList(), ['parent', 'c1', 'c2']);
    });
  });

  group('branchIndexIn / branchSwitchTo', () {
    final all = [
      _session('parent'),
      _session('c1', parentId: 'parent', forkTurn: 3),
      _session('c2', parentId: 'parent', forkTurn: 5),
    ];
    final group = branchFamilyOf(all, 'c1');

    test('branchIndexIn：1-based 序号', () {
      expect(branchIndexIn(group, 'parent'), 1);
      expect(branchIndexIn(group, 'c1'), 2);
      expect(branchIndexIn(group, 'c2'), 3);
      expect(branchIndexIn(group, 'nope'), 0);
    });

    test('branchSwitchTo：前进/后退环绕', () {
      expect(branchSwitchTo(group, 'c1', next: true), 'c2');
      expect(branchSwitchTo(group, 'c2', next: true), 'parent'); // 环绕
      expect(branchSwitchTo(group, 'parent', next: false), 'c2'); // 环绕
      expect(branchSwitchTo(group, 'c2', next: false), 'c1');
    });

    test('branchSwitchTo：分支族大小 1 或无匹配 → null', () {
      expect(branchSwitchTo(group, 'nope', next: true), isNull);
      final single = branchFamilyOf([_session('only')], 'only');
      expect(branchSwitchTo(single, 'only', next: true), isNull);
    });
  });
}
