/// 会话分支（fork）纯逻辑 —— Task 六 Bug 7「撤回 → edit/branch」的 renderer 侧辅助。
///
/// 全部函数纯 Dart、零 Flutter 依赖，可独立 `dart test`（见 `renderer/test/`）。
///
/// 分支组定义（与 `docs/superpowers/specs/2026-08-26-AI-assistant-improvement.md`
/// Task 六一致）：某会话的「分支族」= 自身 + 父会话 + 同父兄弟 + 子分支。
/// 旧会话（无 parentId 且无子会话）的分支族大小为 1 → UI 不显示分支切换
/// （缺省零行为变化）。
library;

import 'package:evergreen_base/core/agent/agent/session.dart';

/// 计算某会话的分支族（自身 + 父会话 + 同父兄弟 + 子分支），按
/// [_compareBranchOrder] 排序。找不到该会话返回空列表。
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

/// 当前会话在分支族中的 1-based 序号；不在族内返回 0。
int branchIndexIn(List<Session> group, String sessionId) {
  final i = group.indexWhere((s) => s.id == sessionId);
  return i < 0 ? 0 : i + 1;
}

/// 分支切换：当前序号向前（next=false）或向后（next=true）移一步（环绕）。
/// 返回目标会话 id；分支族大小 <= 1 或当前会话不在族内返回 null。
String? branchSwitchTo(
  List<Session> group,
  String sessionId, {
  required bool next,
}) {
  if (group.length <= 1) return null;
  final i = group.indexWhere((s) => s.id == sessionId);
  if (i < 0) return null;
  final j = next
      ? (i + 1) % group.length
      : (i - 1 + group.length) % group.length;
  return group[j].id;
}
