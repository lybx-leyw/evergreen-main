/// 会话树形分支纯逻辑 —— R3（Task 三）会话树形分支的 renderer 侧辅助。
///
/// 全部函数纯 Dart、零 Flutter 依赖，可独立 `dart test`（见 `renderer/test/`）。
///
/// 新语义（R3）：分支不再是「独立会话」，而是同一会话内的轮次树
/// （`agent.Session` 的 `Round` 树，`children` 有序 = 孩子兄弟链）。
/// - [siblingsOf]：某轮（loopId）的兄弟分支链（含当前活动轮）；
/// - [branchIndexIn]：活动轮在兄弟链中的 1-based 序号（「◀ i/n ▶」的 i）；
/// - [nextSiblingIndex] / [switchSibling]：左右环绕切换（switch 即 i±1）；
/// - [treeBranchCount]：树内分支（叶子）计数，供会话历史行标签。
///
/// Legacy 兜底：旧 A6 fork 数据（parent_id/fork_turn 家族，多会话）仍保留
/// [branchFamilyOf] 读兼容（会话历史行标签回退），懒迁移不破坏旧文件。
library;

import 'package:evergreen_base/core/agent/agent/session.dart';

// ═══════ R3 树语义 ═══════

/// 会话中 [loopId] 轮所在的兄弟分支链（含当前活动轮）。
///
/// - loopId 越界 / 会话无树 → 空列表（缺省不渲染切换条，零行为变化）；
/// - loopId == 0 → 深度 0 分支链（`session.roots`，根轮分叉后长度 > 1）。
List<Round> siblingsOf(Session session, int loopId) {
  if (loopId < 0) return const [];
  final path = session.activePath;
  if (loopId >= path.length) return const [];
  if (loopId == 0) return List.of(session.roots);
  return List.of(path[loopId - 1].children);
}

/// 当前活动轮在其兄弟链中的 1-based 序号；不在链中 / 越界返回 0。
int branchIndexIn(Session session, int loopId) {
  final siblings = siblingsOf(session, loopId);
  if (siblings.isEmpty) return 0;
  final path = session.activePath;
  if (loopId >= path.length) return 0;
  final i = siblings.indexOf(path[loopId]);
  return i < 0 ? 0 : i + 1;
}

/// 计算在兄弟链中向前（next=true）/ 向后环绕一步的目标下标（0-based）。
///
/// 兄弟链长度 <= 1 或 loopId 越界 → null（无切换目标）。
int? nextSiblingIndex(Session session, int loopId, {required bool next}) {
  final siblings = siblingsOf(session, loopId);
  if (siblings.length <= 1) return null;
  final path = session.activePath;
  if (loopId >= path.length) return null;
  final i = siblings.indexOf(path[loopId]);
  if (i < 0) return null;
  return next
      ? (i + 1) % siblings.length
      : (i - 1 + siblings.length) % siblings.length;
}

/// 切换：计算目标下标并调用 [Session.switchRound] 重建活动路径与消息。
/// 返回目标下标（0-based）；无切换目标返回 null（不修改会话）。
///
/// 切换是纯会话层操作：不改变会话 id、不产生新会话、不触碰工作区。
int? switchSibling(Session session, int loopId, {required bool next}) {
  final j = nextSiblingIndex(session, loopId, next: next);
  if (j == null) return null;
  session.switchRound(loopId, j);
  return j;
}

/// 树内分支（根到叶路径）数量——会话历史行「分支 n」标签用。
///
/// 无树 / 单路径直线 → 1（不显示标签）；有分叉 → 叶子数（> 1 时显示）。
/// 旧 A6 fork 数据（无树但有 parent_id 家族）由 [branchLabelCount] 走
/// [branchFamilyOf] 兜底。
int treeBranchCount(Session session) {
  var leaves = 0;
  void walk(Round round) {
    if (round.children.isEmpty) {
      leaves++;
      return;
    }
    for (final c in round.children) {
      walk(c);
    }
  }

  for (final r in session.roots) {
    walk(r);
  }
  return leaves;
}

/// 会话历史行分支标签计数：树内分叉优先；旧 A6 fork 数据（parent_id 家族）
/// 走 [branchFamilyOf] 兜底。无分叉返回 null（不显示标签）。
int? branchLabelCount(List<Session> all, Session s) {
  final tree = treeBranchCount(s);
  if (tree > 1) return tree;
  if (s.parentId != null || all.any((x) => x.parentId == s.id)) {
    final family = branchFamilyOf(all, s.id).length;
    if (family > 1) return family;
  }
  return null;
}

// ═══════ Legacy 兜底（旧 A6 fork 数据读兼容）═══════

/// ⚠️ Legacy：旧「分支 = 独立会话」语义的分支族（自身 + 父会话 + 同父兄弟 +
/// 子分支），仅供旧 A6 fork 数据（parent_id/fork_turn）的懒迁移读兼容兜底；
/// R3 起新分叉一律走树内 [siblingsOf] / [switchSibling]。
List<Session> branchFamilyOf(List<Session> all, String sessionId) {
  final current = all.where((s) => s.id == sessionId).firstOrNull;
  if (current == null) return const [];
  final ids = <String>{sessionId};
  final parentId = current.parentId;
  if (parentId != null) {
    // 子会话：父会话 + 同父兄弟（含自身）。
    ids.add(parentId);
    for (final s in all) {
      if (s.parentId == parentId) ids.add(s.id);
    }
  }
  // 根会话（parentId == null）或任意会话：子分支。
  for (final s in all) {
    if (s.parentId == sessionId) ids.add(s.id);
  }
  final group = all.where((s) => ids.contains(s.id)).toList()
    ..sort(_compareBranchOrder);
  return group;
}

/// 分支族内排序：父会话（forkTurn == null）优先，其余按 forkTurn 升序
/// （分叉点越靠后越新），同 forkTurn 按 updatedAt 升序（稳定可预期）。
int _compareBranchOrder(Session a, Session b) {
  final at = a.forkTurn;
  final bt = b.forkTurn;
  if (at == null && bt == null) return a.updatedAt.compareTo(b.updatedAt);
  if (at == null) return -1;
  if (bt == null) return 1;
  if (at != bt) return at.compareTo(bt);
  return a.updatedAt.compareTo(b.updatedAt);
}
