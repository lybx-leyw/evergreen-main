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
    ctrl.session.messages.clear();
    ctrl.session.id = session.id;
    ctrl.session.title = title ?? '新对话';
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
    ctrl.session.messages.clear();
    if (target != null) {
      ctrl.session.messages.addAll(target.messages);
      ctrl.session.id = target.id;
      ctrl.session.title = target.title;
      for (final m in target.messages) {
        if (m.content.trim().isEmpty) continue;
        if (m.role == agent.Role.user) msgs.addUser(m.content);
        else if (m.role == agent.Role.assistant) msgs.addAssistant(m.content, reasoning: m.reasoningContent);
      }
      debugPrint('[SESSION:SWITCH] loaded ${target.messages.length} msgs → notifier now has ${msgs.state.length}');
    }
    // 最后才更新 activeSessionId，触发 UI 同步
    ref.read(activeSessionIdProvider.notifier).state = id;
    debugPrint('[SESSION:SWITCH] done. activeId=$id');
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
      ref.read(agentControllerProvider).session.messages.clear();
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
