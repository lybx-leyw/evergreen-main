/// R3 会话树形分支纯逻辑测试 —— session_branch.dart（renderer 子包 test/ 下）。
///
/// 运行：cd evg-base/lib/renderer && dart test test/session_branch_test.dart
/// 注意：renderer 子包的 .dart_tool/package_config.json 需将 evergreen_base 的
/// rootUri 指向仓库根（`../../..`，即 evg-base），使 package:evergreen_base/…
/// 解析到真实源码（见 agent_A6_final.md 的测试说明）。
library;

import 'package:evergreen_base/core/agent/agent/session.dart';
import 'package:evergreen_base/core/agent/message.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/interaction/chat/session_branch.dart';
import 'package:test/test.dart';

/// 直线会话（无分叉）：u1/a1/u2/a2。
Session _linear() {
  final s = Session(id: 's', title: 's', updatedAt: DateTime(2026, 1, 1));
  s.add(Message.user('u1'));
  s.add(Message.assistant('a1'));
  s.add(Message.user('u2'));
  s.add(Message.assistant('a2'));
  return s;
}

/// 在轮 1 分叉并续写分支 1（兄弟链长度 2，活动在分支 1）。
Session _forked() {
  final s = _linear();
  s.forkRound(1, 'u2b');
  s.add(Message.user('u2b'));
  s.add(Message.assistant('a2b'));
  return s;
}

void main() {
  group('siblingsOf', () {
    test('直线会话：每轮仅自身一个兄弟', () {
      final s = _linear();
      expect(siblingsOf(s, 0), hasLength(1));
      expect(siblingsOf(s, 1), hasLength(1));
    });

    test('分叉后：分叉轮兄弟链含当前分支与 sibling', () {
      final s = _forked();
      expect(siblingsOf(s, 1), hasLength(2));
      expect(siblingsOf(s, 0), hasLength(1)); // 未分叉轮仍是 1
    });

    test('loopId 越界 / 负数 → 空列表（缺省不渲染切换条）', () {
      final s = _linear();
      expect(siblingsOf(s, -1), isEmpty);
      expect(siblingsOf(s, 99), isEmpty);
    });

    test('loopId 0 → 深度 0 分支链（根轮分叉后长度 > 1）', () {
      final s = _linear();
      s.forkRound(0, 'first2');
      expect(siblingsOf(s, 0), hasLength(2));
    });
  });

  group('branchIndexIn', () {
    test('直线会话 → 1', () {
      final s = _linear();
      expect(branchIndexIn(s, 0), 1);
      expect(branchIndexIn(s, 1), 1);
    });

    test('活动分支序号随切换变化（1-based）', () {
      final s = _forked();
      expect(branchIndexIn(s, 1), 2); // 活动在分支 1
      expect(s.switchRound(1, 0), isTrue);
      expect(branchIndexIn(s, 1), 1);
    });

    test('越界 → 0', () {
      final s = _linear();
      expect(branchIndexIn(s, 99), 0);
    });
  });

  group('nextSiblingIndex / switchSibling', () {
    test('左右环绕切换（switch 即 i±1）', () {
      final s = _forked();
      expect(nextSiblingIndex(s, 1, next: true), 0); // 环绕回分支 0
      expect(nextSiblingIndex(s, 1, next: false), 0); // 回退到分支 0
      expect(switchSibling(s, 1, next: false), 0);
      expect(branchIndexIn(s, 1), 1);
      expect(switchSibling(s, 1, next: true), 1);
      expect(branchIndexIn(s, 1), 2);
    });

    test('无兄弟（直线）→ null，不修改会话', () {
      final s = _linear();
      expect(nextSiblingIndex(s, 1, next: true), isNull);
      expect(switchSibling(s, 1, next: true), isNull);
      expect(s.messages, hasLength(4));
    });

    test('切换后活动路径与消息重建（双写一致）', () {
      final s = _forked();
      expect(s.messages.map((m) => m.content), ['u1', 'a1', 'u2b', 'a2b']);
      switchSibling(s, 1, next: true); // 环绕回分支 0
      expect(s.messages.map((m) => m.content), ['u1', 'a1', 'u2', 'a2']);
    });
  });

  group('treeBranchCount / branchLabelCount', () {
    test('直线会话 → 1（不显示标签）', () {
      expect(treeBranchCount(_linear()), 1);
    });

    test('分叉会话 → 叶子数（分支数）', () {
      expect(treeBranchCount(_forked()), 2);
    });

    test('branchLabelCount：树分叉 → 树内计数', () {
      final s = _forked();
      expect(branchLabelCount([s], s), 2);
    });

    test('branchLabelCount：普通会话 → null', () {
      final s = _linear();
      expect(branchLabelCount([s], s), isNull);
    });

    test('branchLabelCount：旧 A6 fork 数据 → branchFamilyOf 兜底', () {
      final parent = Session(
          id: 'p', title: 'p', updatedAt: DateTime(2026, 1, 1));
      final child = Session(
          id: 'c',
          title: 'c',
          parentId: 'p',
          forkTurn: 2,
          updatedAt: DateTime(2026, 1, 2));
      final all = [parent, child];
      expect(branchLabelCount(all, parent), 2);
      expect(branchLabelCount(all, child), 2);
    });
  });

  group('Legacy branchFamilyOf（旧 A6 fork 数据读兼容兜底）', () {
    test('旧会话（无 parentId 且无子分支）→ 分支族大小 1', () {
      final a = Session(id: 'a', title: 'a', updatedAt: DateTime(2026, 1, 1));
      final b = Session(id: 'b', title: 'b', updatedAt: DateTime(2026, 1, 1));
      expect(branchFamilyOf([a, b], 'a'), hasLength(1));
      expect(branchFamilyOf([a, b], 'a').single.id, 'a');
    });

    test('根会话 → 自身 + 全部子分支', () {
      final root = _linear();
      final c1 = Session(
          id: 'c1', title: 'c1', parentId: 's', forkTurn: 3);
      final c2 = Session(
          id: 'c2', title: 'c2', parentId: 's', forkTurn: 5);
      final group = branchFamilyOf([root, c1, c2], 's');
      expect(group.map((x) => x.id).toSet(), {'s', 'c1', 'c2'});
    });
  });
}
