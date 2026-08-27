/// Session CRUD Provider。
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/agent_runtime.dart';
import 'package:evergreen_base/providers.dart';

/// 会话持久化存储接口——由插件层实现。
abstract class SessionStoreInterface {
  Future<void> save(agent.Session session);
  agent.Session? load(String id);
  Future<void> delete(String id);
  List<agent.Session> listAll();
}

/// SessionStoreInterface 单例——由外部模块在初始化时 override。
final sessionStoreProvider = Provider<SessionStoreInterface?>((ref) => null);

final activeSessionIdProvider = StateProvider<String?>((ref) => null);

final sessionListProvider = FutureProvider<List<agent.Session>>((ref) async {
  final store = ref.watch(sessionStoreProvider);
  return store?.listAll() ?? [];
});

final createSessionProvider = Provider<void Function(String? title)>((ref) {
  return (String? title) async {
    debugPrint('[SESSION:CREATE] title=$title START');
    final currentId = ref.read(activeSessionIdProvider);
    debugPrint('[SESSION:CREATE] currentId=$currentId');
    if (currentId != null) await ref.read(saveCurrentSessionProvider)(currentId);
    final session = agent.Session(title: title ?? '新对话');
    // ✅ 修复：使用 agentControllerProvider.session（main.dart 中注入的实际 session）
    final ctrl = ref.read(agentControllerProvider);
    ctrl.session.clearMessages();
    ctrl.session.id = session.id;
    ctrl.session.title = title ?? '新对话';
    // 新会话为根会话：重置派生元数据（防上次会话残留的 parent_id/fork_turn）
    ctrl.session.parentId = null;
    ctrl.session.forkTurn = null;
    ref.read(chatMessagesProvider.notifier).clear();
    // 最后才更新 activeSessionId，确保 listener 看到已清空的状态
    ref.read(activeSessionIdProvider.notifier).state = session.id;
    debugPrint('[SESSION:CREATE] new sessionId=${session.id}');
    final store = ref.read(sessionStoreProvider);
    debugPrint('[SESSION:CREATE] store=${store != null ? "present" : "NULL"}');
    if (store != null) {
      await store.save(session);
      ref.invalidate(sessionListProvider);
    }
    debugPrint('[SESSION:CREATE] done');
  };
});

final switchSessionProvider = Provider<void Function(String id)>((ref) {
  return (String id) async {
    debugPrint('[SESSION:SWITCH] id=$id START');
    final currentId = ref.read(activeSessionIdProvider);
    debugPrint('[SESSION:SWITCH] currentId=$currentId');
    if (currentId != null) await ref.read(saveCurrentSessionProvider)(currentId);
    final store = ref.read(sessionStoreProvider);
    debugPrint('[SESSION:SWITCH] store=${store != null ? "present" : "NULL"}');
    final target = store?.load(id);
    debugPrint('[SESSION:SWITCH] target=${target != null ? "present (${target.messages.length} msgs)" : "NULL"}');
    // ✅ 修复：使用 agentControllerProvider.session（main.dart 中注入的实际 session）
    final ctrl = ref.read(agentControllerProvider);
    final msgs = ref.read(chatMessagesProvider.notifier);
    msgs.clear();
    if (target != null) {
      // 整体采纳目标会话（含树与活动路径，双写一致），而非仅拷贝 messages。
      ctrl.session.adoptFrom(target);
      for (final m in target.messages) {
        if (m.content.trim().isEmpty) continue;
        if (m.role == agent.Role.user) msgs.addUser(m.content);
        else if (m.role == agent.Role.assistant) msgs.addAssistant(m.content, reasoning: m.reasoningContent);
      }
      debugPrint('[SESSION:SWITCH] loaded ${target.messages.length} msgs → notifier now has ${msgs.state.length}');
    } else {
      // 目标不存在：清空当前会话（与旧行为一致）。
      ctrl.session.clearMessages();
    }
    // 最后才更新 activeSessionId，触发 UI 同步
    ref.read(activeSessionIdProvider.notifier).state = id;
    debugPrint('[SESSION:SWITCH] done. activeId=$id');
  };
});

/// ⚠️ **Legacy 入口（R3 起弃用，仅保留旧数据懒迁移读兼容）**：
/// 从已有会话在指定消息索引处分叉出一个**新会话**（「分支 = 独立会话」的旧语义）。
///
/// - 新会话 id 重新生成；`parent_id` = 源会话 id；`fork_turn` = 分叉点索引
///   （0-based，clamp 到 [0, 源消息数]）。
/// - 消息继承源会话 `messages[0..forkTurn)`，之后由用户/模型走新路径（分化）。
/// - 语义见 `docs/superpowers/specs/egsync-sync-center-spec-v1.md` §七：fork_turn 非空
///   且分叉点后消息不同 → 合并时父子**都保留**（路径分化都保留）。
/// - **R3 起新分叉一律走树内 [agent.Session.forkRound]（同一会话），本入口不再
///   被 UI 调用**，保留仅为兼容旧调用方与旧 fork 数据。
final forkSessionProvider =
    Provider<void Function(String sourceId, int forkTurn, {String? title})>((ref) {
  return (String sourceId, int forkTurn, {String? title}) async {
    debugPrint('[SESSION:FORK] sourceId=$sourceId forkTurn=$forkTurn START');
    final currentId = ref.read(activeSessionIdProvider);
    if (currentId != null) await ref.read(saveCurrentSessionProvider)(currentId);
    final store = ref.read(sessionStoreProvider);
    final source = store?.load(sourceId);
    if (source == null) {
      debugPrint('[SESSION:FORK] 源会话不存在: $sourceId');
      return;
    }
    final clampTurn = forkTurn.clamp(0, source.messages.length);
    final child = agent.Session(
      title: title ??
          (source.title.isNotEmpty ? source.title : '新对话'),
      parentId: sourceId,
      forkTurn: clampTurn,
    );
    child.messages.addAll(source.messages.take(clampTurn));
    // 懒迁移：由继承的消息推导单路径树，保证后续树操作（续写/分叉）双写一致。
    child.rebuildTreeFromMessages();
    final ctrl = ref.read(agentControllerProvider);
    ctrl.session.clearMessages();
    ctrl.session.id = child.id;
    ctrl.session.title = child.title;
    ctrl.session.parentId = sourceId;
    ctrl.session.forkTurn = clampTurn;
    ref.read(chatMessagesProvider.notifier).clear();
    for (final m in child.messages) {
      if (m.content.trim().isEmpty) continue;
      if (m.role == agent.Role.user) {
        ref.read(chatMessagesProvider.notifier).addUser(m.content);
      } else if (m.role == agent.Role.assistant) {
        ref.read(chatMessagesProvider.notifier)
            .addAssistant(m.content, reasoning: m.reasoningContent);
      }
    }
    // 最后才更新 activeSessionId，确保 listener 看到已切到子会话
    ref.read(activeSessionIdProvider.notifier).state = child.id;
    if (store != null) {
      await store.save(child);
      ref.invalidate(sessionListProvider);
    }
    debugPrint('[SESSION:FORK] done. childId=${child.id} '
        'msgs=${child.messages.length} forkTurn=$clampTurn');
  };
});

final saveCurrentSessionProvider = Provider<Future<void> Function(String id)>((ref) {
  return (String id) async {
    // ✅ 修复：使用 agentControllerProvider.session（main.dart 中注入的实际 session），
    // 而非 agentRuntimeProvider.session（agent_runtime.dart 中独立的 session 副本）。
    final ctrl = ref.read(agentControllerProvider);
    final session = ctrl.session;
    debugPrint('[SESSION:SAVE] id=$id msgs=${session.messages.length} title="${session.title}"');
    if (session.title.isEmpty || session.title == '新对话') {
      final u = session.messages.where((m) => m.role == agent.Role.user).firstOrNull;
      if (u != null && u.content.isNotEmpty) {
        final t = u.content.replaceAll('\n', ' ').trim();
        session.title = t.length > 30 ? '${t.substring(0, 30)}...' : t;
      }
    }
    final store = ref.read(sessionStoreProvider);
    if (store != null) {
      debugPrint('[SESSION:SAVE] writing to store...');
      await store.save(session);
      ref.invalidate(sessionListProvider);
      debugPrint('[SESSION:SAVE] done for id=$id');
    } else {
      debugPrint('[SESSION:SAVE] SKIP (store is NULL)');
    }
  };
});

final deleteSessionProvider = Provider<void Function(String id)>((ref) {
  return (String id) async {
    if (ref.read(activeSessionIdProvider) == id) {
      // 先清空所有消息状态，再重置 activeSessionId，
      // 确保 listener 回调看到的是已清空的数据。
      ref.read(chatMessagesProvider.notifier).clear();
      ref.read(agentControllerProvider).session.clearMessages();
      ref.read(activeSessionIdProvider.notifier).state = null;
    }
    final store = ref.read(sessionStoreProvider);
    if (store != null) {
      await store.delete(id);
      ref.invalidate(sessionListProvider);
    }
  };
});

final renameSessionProvider = Provider<void Function(String id, String newTitle)>((ref) {
  return (String id, String newTitle) async {
    final store = ref.read(sessionStoreProvider);
    final session = store?.load(id);
    if (session != null) {
      session.title = newTitle;
      await store!.save(session);
      ref.invalidate(sessionListProvider);
    }
  };
});

final activeSessionTitleProvider = Provider<String>((ref) {
  final id = ref.watch(activeSessionIdProvider);
  if (id == null) return 'AI 助手';
  final sessions = ref.watch(sessionListProvider).valueOrNull ?? [];
  final active = sessions.where((s) => s.id == id).firstOrNull;
  return active?.title ?? 'AI 助手';
});
