/// 会话合并 — 同步中心「包含则删小 / 路径分化都保留」合并语义。
///
/// 契约：`docs/superpowers/specs/egsync-sync-center-spec-v1.md` §七（parent_id / fork_turn
/// 元数据 + §7.2 合并语义）。本文件为 t-C4（core-agent）实施落点，供导入端（t-C3
/// core-module）调用；导出端（t-C2）不参与合并。
library;

import 'dart:convert';

import 'agent/session.dart';
import 'message.dart';

// ═══════ SessionMergeResult ═══════

/// 会话合并结果。
class SessionMergeResult {
  /// 合并后保留的会话清单（按 updatedAt 降序，与 [FileSessionStore.listAll] 一致）。
  final List<Session> merged;

  /// 被删除的会话 id（含同 id 冲突中被吞掉的一方）。
  final List<String> deletedSessionIds;

  /// 保留会话 id → 保留原因（人读，供日志/UI 展示）。
  final Map<String, String> keepReasons;

  /// 被删除会话 id → 删除原因（人读，供日志/UI 展示）。
  final Map<String, String> deletedReasons;

  const SessionMergeResult({
    required this.merged,
    required this.deletedSessionIds,
    required this.keepReasons,
    required this.deletedReasons,
  });
}

// ═══════ mergeSessions ═══════

/// 合并本地会话与导入会话，返回保留清单 + 删除清单 + 原因。
///
/// 判定标准（egsync 契约 §7.2，前缀比较为最终判定、parent 元数据为充分条件）：
/// 1. **同 id 归并**：内容相等 → 保留本地（导入 no-op）；一方是另一方前缀 → 保留更长；
///    内容分化（互不为前缀）→ 保留本地（同文件不可共存，本地为准）。
/// 2. **完全包含（删小）**：A.messages 是 B.messages 的**严格前缀**（A 更短且逐条相等）
///    → 删 A 保留 B。纯续写子会话（parent_id=B、fork_turn=null、A=B+追加）自然满足
///    "B ⊆ A"，按前缀判定删 B 留 A（与契约"删小的"一致）。
/// 3. **路径分化（都保留）**：A 与 B 共享前缀但尾部不同（fork_turn 分叉、独立树、或无
///    元数据的同前缀不同尾）→ 互不为前缀，两个都保留。
/// 4. **空会话保护**：messages 为空的全新会话不参与删除（保留）。
/// 5. **无元数据兜底**：旧数据（无 parent_id/fork_turn）同样按前缀比较判定。
SessionMergeResult mergeSessions(List<Session> local, List<Session> imported) {
  final pool = <String, _PoolEntry>{};
  final deletedIds = <String>[];
  final deletedReasons = <String, String>{};

  void absorb(Session s, {required bool isLocal}) {
    final existing = pool[s.id];
    if (existing == null) {
      pool[s.id] = _PoolEntry(session: s, isLocal: isLocal);
      return;
    }
    // ── 同 id 冲突 ──
    final a = existing.session;
    if (_messagesEqual(a.messages, s.messages)) {
      // 内容相等：保留先见者（本地优先），导入同内容 no-op
      existing.reason = '同 id 内容相等（去重 no-op），保留既有副本';
      return;
    }
    if (_isStrictPrefix(a.messages, s.messages)) {
      // 本地是导入的前缀 → 保留更长（导入），本地入删除清单
      deletedIds.add(a.id);
      deletedReasons[a.id] = '同 id 冲突：本地是导入会话的前缀，删除本地保留导入（更长）';
      pool[s.id] = _PoolEntry(session: s, isLocal: isLocal,
          reason: '同 id 冲突：导入会话更长（本地是其前缀），保留导入');
    } else if (_isStrictPrefix(s.messages, a.messages)) {
      // 导入是本地的前缀 → 保留本地，导入入删除清单
      deletedIds.add(s.id);
      deletedReasons[s.id] = '同 id 冲突：导入是本地会话的前缀，删除导入保留本地（更长）';
      existing.reason = '同 id 冲突：本地会话更长（导入是其前缀），保留本地';
    } else {
      // 分化：保留本地；导入同 id 副本入删除清单（同文件不可共存，导入端按结果落盘）
      deletedIds.add(s.id);
      deletedReasons[s.id] = '同 id 冲突：内容分化，保留本地，丢弃导入副本';
      existing.reason = '同 id 冲突：内容分化，保留本地';
    }
  }

  for (final s in local) {
    absorb(s, isLocal: true);
  }
  for (final s in imported) {
    absorb(s, isLocal: false);
  }

  // ── 跨会话包含消除：保留「不被任何其他会话严格包含」的极大元 ──
  final entries = pool.values.toList();
  final kept = <_PoolEntry>[];
  for (final entry in entries) {
    final a = entry.session;
    if (a.messages.isEmpty) {
      // 空会话保护：全新会话（尚未对话）不参与删除
      kept.add(entry);
      entry.reason ??= '空会话（新建未使用），保留';
      continue;
    }
    String? containedIn;
    for (final other in entries) {
      if (identical(other, entry)) continue;
      if (_isStrictPrefix(a.messages, other.session.messages)) {
        containedIn = other.session.id;
        break;
      }
    }
    if (containedIn != null) {
      entry.containedIn = containedIn;
      deletedIds.add(a.id);
      deletedReasons[a.id] = '完全包含：消息是 "$containedIn" 的严格前缀（删小保大）';
    } else {
      kept.add(entry);
      entry.reason ??= '独立会话（未被任何其他会话包含），保留';
    }
  }

  kept.sort((x, y) => y.session.updatedAt.compareTo(x.session.updatedAt));
  final keepReasons = <String, String>{
    for (final e in kept) e.session.id: e.reason ?? '保留',
  };

  return SessionMergeResult(
    merged: kept.map((e) => e.session).toList(),
    deletedSessionIds: deletedIds,
    keepReasons: keepReasons,
    deletedReasons: deletedReasons,
  );
}

// ═══════ 内部工具 ═══════

/// 池条目：会话 + 来源标记 + 保留/删除原因。
class _PoolEntry {
  final Session session;
  final bool isLocal;
  String? reason; // 保留原因（kept 时）
  String? containedIn; // 被包含于哪个会话 id（deleted 时）

  _PoolEntry({required this.session, required this.isLocal, this.reason});
}

/// A.messages 是否为 B.messages 的严格前缀（A 更短且逐条相等）。
///
/// 逐条相等按序列化 JSON 比较（role/content/reasoning_content/tool_calls/tool_call_id/
/// name 全字段），保证跨设备回放判定一致。
bool _isStrictPrefix(List<Message> a, List<Message> b) {
  if (a.isEmpty || a.length >= b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_sameMessage(a[i], b[i])) return false;
  }
  return true;
}

bool _messagesEqual(List<Message> a, List<Message> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_sameMessage(a[i], b[i])) return false;
  }
  return true;
}

bool _sameMessage(Message a, Message b) =>
    jsonEncode(a.toJson()) == jsonEncode(b.toJson());
