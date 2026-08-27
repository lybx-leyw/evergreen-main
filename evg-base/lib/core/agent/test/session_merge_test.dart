/// 会话合并语义测试：包含则删小 / 路径分化都保留（egsync 契约 §7.2）。
library;

import 'package:test/test.dart';

import '../message.dart';
import '../agent/session.dart';
import '../session_merge.dart';

Session _s(
  String id,
  List<Message> msgs, {
  String? parentId,
  int? forkTurn,
  DateTime? updatedAt,
}) {
  final s = Session(
    id: id,
    parentId: parentId,
    forkTurn: forkTurn,
    updatedAt: updatedAt ?? DateTime(2026, 8, 25, 12),
  );
  s.messages.addAll(msgs);
  return s;
}

List<Message> _msgs(List<String> contents) =>
    [for (final c in contents) Message.user(c)];

/// 交替 user/assistant 构造消息（更贴近真实会话）。
List<Message> _conv(List<String> parts) => [
      for (var i = 0; i < parts.length; i++)
        i.isEven ? Message.user(parts[i]) : Message.assistant(parts[i]),
    ];

/// 带树的会话：经轮次感知 [Session.addAll] 建立 Round 树。
Session _treeSession(String id, List<Message> msgs,
    {DateTime? updatedAt}) {
  final s = Session(
    id: id,
    updatedAt: updatedAt ?? DateTime(2026, 8, 25, 12),
  );
  s.addAll(msgs);
  return s;
}

void main() {
  group('mergeSessions · 完全包含则删小', () {
    test('前缀包含（无元数据兜底）→ 删 A 保留 B', () {
      final a = _s('A', _msgs(['u1', 'a1']));
      final b = _s('B', _msgs(['u1', 'a1', 'u2', 'a2']));

      final r = mergeSessions([a], [b]);

      expect(r.merged.map((s) => s.id), containsAll(['B']));
      expect(r.deletedSessionIds, contains('A'));
      expect(r.deletedReasons['A'], contains('完全包含'));
      expect(r.keepReasons['B'], contains('独立会话'));
    });

    test('纯续写子会话（parent_id=B, fork_turn=null, B⊆A）→ 删 B 留 A', () {
      final parent = _s('B', _msgs(['u1', 'a1']));
      final child = _s('A', _msgs(['u1', 'a1', 'u2', 'a2']),
          parentId: 'B', forkTurn: null);

      final r = mergeSessions([parent], [child]);

      expect(r.deletedSessionIds, contains('B'));
      expect(r.merged.map((s) => s.id), contains('A'));
      expect(r.deletedReasons['B'], contains('完全包含'));
    });

    test('链式包含 A⊂B⊂C → 仅保留 C', () {
      final a = _s('A', _msgs(['u1']));
      final b = _s('B', _msgs(['u1', 'a1']));
      final c = _s('C', _msgs(['u1', 'a1', 'u2']));

      final r = mergeSessions([a, b], [c]);

      expect(r.merged.map((s) => s.id), ['C']);
      expect(r.deletedSessionIds.toSet(), {'A', 'B'});
    });

    test('空会话保护：空会话不因被包含而删除', () {
      final empty = _s('E', []);
      final full = _s('F', _msgs(['u1', 'a1']));

      final r = mergeSessions([empty], [full]);

      expect(r.merged.map((s) => s.id).toSet(), {'E', 'F'});
      expect(r.deletedSessionIds, isEmpty);
      expect(r.keepReasons['E'], contains('空会话'));
    });
  });

  group('mergeSessions · 路径分化都保留', () {
    test('fork 分叉（parent_id + fork_turn，分叉后不同）→ 两个都保留', () {
      final parent = _s('P', _msgs(['u1', 'a1', 'u2', 'a2']));
      final child = _s('C', _msgs(['u1', 'a1', 'u3', 'a3']),
          parentId: 'P', forkTurn: 2);

      final r = mergeSessions([parent], [child]);

      expect(r.merged.map((s) => s.id).toSet(), {'P', 'C'});
      expect(r.deletedSessionIds, isEmpty);
    });

    test('独立树（双根）→ 都保留', () {
      final a = _s('A', _msgs(['q1']));
      final b = _s('B', _msgs(['q2']));

      final r = mergeSessions([a], [b]);

      expect(r.merged.map((s) => s.id).toSet(), {'A', 'B'});
      expect(r.deletedSessionIds, isEmpty);
    });

    test('同前缀不同尾（无元数据分化）→ 都保留', () {
      final a = _s('A', _msgs(['u1', 'a1', 'x1']));
      final b = _s('B', _msgs(['u1', 'a1', 'y1']));

      final r = mergeSessions([a], [b]);

      expect(r.merged.map((s) => s.id).toSet(), {'A', 'B'});
      expect(r.deletedSessionIds, isEmpty);
    });
  });

  group('mergeSessions · 同 id 冲突', () {
    test('本地更长（导入是其前缀）→ 保留本地', () {
      final local = _s('S', _msgs(['u1', 'a1', 'u2', 'a2']));
      final imported = _s('S', _msgs(['u1', 'a1']));

      final r = mergeSessions([local], [imported]);

      expect(r.merged.single.messages.length, 4);
      expect(r.deletedSessionIds, contains('S'));
      expect(r.deletedReasons['S'], contains('前缀'));
    });

    test('内容相等 → 去重保留一份，无删除', () {
      final local = _s('S', _msgs(['u1', 'a1']));
      final imported = _s('S', _msgs(['u1', 'a1']));

      final r = mergeSessions([local], [imported]);

      expect(r.merged.single.id, 'S');
      expect(r.deletedSessionIds, isEmpty);
      expect(r.keepReasons['S'], contains('相等'));
    });

    test('同 id 内容分化 → 保留本地，导入入删除清单', () {
      final local = _s('S', _msgs(['u1', 'a1', 'x1']));
      final imported = _s('S', _msgs(['u1', 'a1', 'y1']));

      final r = mergeSessions([local], [imported]);

      expect(r.merged.single.id, 'S');
      expect(r.merged.single.messages.last.content, 'x1');
      expect(r.deletedSessionIds, contains('S'));
      expect(r.deletedReasons['S'], contains('分化'));
    });
  });

  group('mergeSessions · 输出形态', () {
    test('merged 按 updatedAt 降序', () {
      final old1 = _s('O1', _msgs(['u1']), updatedAt: DateTime(2026, 1, 1));
      final new1 = _s('N1', _msgs(['v1']), updatedAt: DateTime(2026, 6, 1));
      final newest = _s('NN', _msgs(['w1']), updatedAt: DateTime(2026, 12, 1));

      final r = mergeSessions([old1, new1], [newest]);

      expect(r.merged.map((s) => s.id), ['NN', 'N1', 'O1']);
    });

    test('Session 元数据随合并结果透传（parent_id/fork_turn 往返）', () {
      final parent = _s('P', _msgs(['u1', 'a1']));
      final child = _s('C', _msgs(['u1', 'a1', 'u3']),
          parentId: 'P', forkTurn: 2);

      final r = mergeSessions([parent], [child]);
      final keptChild = r.merged.firstWhere((s) => s.id == 'C');

      expect(keptChild.parentId, 'P');
      expect(keptChild.forkTurn, 2);

      // toJson/fromJson 往返保持字段
      final restored = Session.fromJson(keptChild.toJson());
      expect(restored.parentId, 'P');
      expect(restored.forkTurn, 2);
      expect(restored.messages.length, 3);
    });
  });

  // ═══════ R3 树感知合并 ═══════

  group('mergeSessions · 树感知（R3）', () {
    test('同 id 内容相等 + 树相等 → 去重 no-op，无删除', () {
      final a = _treeSession('S', _conv(['u1', 'a1', 'u2', 'a2']));
      final b = _treeSession('S', _conv(['u1', 'a1', 'u2', 'a2']));

      final r = mergeSessions([a], [b]);

      expect(r.merged.single.messages.length, 4);
      expect(r.deletedSessionIds, isEmpty);
      expect(r.keepReasons['S'], contains('相等'));
    });

    test('同 id 消息相等但树分化（分支差异）→ 保留本地', () {
      // a：在轮 1 分叉出同内容 sibling（消息与 b 相同，但树有 2 个分支）
      final a = _treeSession('S', _conv(['u1', 'a1', 'u2', 'a2']));
      a.forkRound(1, 'u2');
      a.add(Message.user('u2'));
      a.add(Message.assistant('a2'));
      expect(a.roots.first.children, hasLength(2));
      expect(a.messages.map((m) => m.content), ['u1', 'a1', 'u2', 'a2']);
      // b：直线会话，无侧枝
      final b = _treeSession('S', _conv(['u1', 'a1', 'u2', 'a2']));

      final r = mergeSessions([a], [b]);

      expect(r.merged.single.id, 'S');
      expect(r.deletedSessionIds, isEmpty);
      expect(r.keepReasons['S'], contains('树'));
    });

    test('前缀包含 + 树包含 → 删小保大（树感知删除）', () {
      final a = _treeSession('A', _conv(['u1', 'a1']));
      final b = _treeSession('B', _conv(['u1', 'a1', 'u2', 'a2']));

      final r = mergeSessions([a], [b]);

      expect(r.deletedSessionIds, contains('A'));
      expect(r.merged.map((s) => s.id), contains('B'));
      expect(r.deletedReasons['A'], contains('完全包含'));
    });

    test('前缀包含但树不包含（短会话有额外分支）→ 都保留', () {
      // A：活动路径 [u1,a1,u2,a2] + 非空侧枝 [u2b,a2b]
      final a = _treeSession('A', _conv(['u1', 'a1', 'u2', 'a2']));
      a.forkRound(1, 'u2b');
      a.add(Message.user('u2b'));
      a.add(Message.assistant('a2b'));
      a.switchRound(1, 0);
      expect(a.messages.map((m) => m.content), ['u1', 'a1', 'u2', 'a2']);
      expect(a.roots.first.children, hasLength(2));
      // B：A 的续写（无 A 的侧枝）
      final b = _treeSession('B', _conv(['u1', 'a1', 'u2', 'a2', 'u3', 'a3']));

      final r = mergeSessions([a], [b]);

      expect(r.deletedSessionIds, isNot(contains('A')));
      expect(r.merged.map((s) => s.id).toSet(), {'A', 'B'});
    });

    test('同 id 前缀 + 树不包含 → 保留本地（丢弃导入）', () {
      // 本地：较短但有侧枝；导入：较长无侧枝
      final local = _treeSession('S', _conv(['u1', 'a1', 'u2', 'a2']));
      local.forkRound(1, 'u2b');
      local.add(Message.user('u2b'));
      local.add(Message.assistant('a2b'));
      local.switchRound(1, 0);
      final imported = _treeSession('S', _conv(['u1', 'a1', 'u2', 'a2', 'u3', 'a3']));

      final r = mergeSessions([local], [imported]);

      expect(r.merged.single.id, 'S');
      expect(r.merged.single.messages.last.content, 'a2');
      expect(r.deletedSessionIds, contains('S'));
      expect(r.deletedReasons['S'], contains('分化'));
    });

    test('同 id 前缀 + 树包含 → 删小保大（与旧行为一致）', () {
      final local = _treeSession('S', _conv(['u1', 'a1']));
      final imported = _treeSession('S', _conv(['u1', 'a1', 'u2', 'a2']));

      final r = mergeSessions([local], [imported]);

      expect(r.merged.single.messages.length, 4);
      expect(r.deletedSessionIds, contains('S'));
      expect(r.deletedReasons['S'], contains('前缀'));
    });
  });
}
