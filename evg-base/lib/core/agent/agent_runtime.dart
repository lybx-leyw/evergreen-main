/// Agent 运行时 — 构造 Provider / Registry / Controller，对外暴露 [agentRuntimeProvider]。
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:evergreen_base/core/config/config.dart';
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/memory/facade.dart';
import 'package:evergreen_base/core/agent/memory/router.dart';
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/core/agent/memory/memory_agent.dart';
import 'package:evergreen_base/core/agent/tool.dart';
import 'package:evergreen_base/core/agent/tools/plugin_bridge.dart';
import 'package:evergreen_base/core/agent/tools/read_global_memory.dart';
import 'package:evergreen_base/core/agent/tools/run_skill.dart';
import 'package:evergreen_base/core/agent/tools/web_search.dart';
import 'package:evergreen_base/core/agent/tools/user_info.dart';
import 'package:evergreen_base/core/agent/tools/read_file.dart';
import 'package:evergreen_base/core/agent/tools/write_file.dart';
import 'package:evergreen_base/core/agent/tools/write_global_memory.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/providers.dart';

// ═══════ AgentRuntime ═══════

/// Controller + 事件流 + 会话的聚合。
class AgentRuntime {
  final agent.Controller controller;
  final agent.StreamEventSink eventSink;
  final agent.Session session;

  AgentRuntime({required this.controller, required this.eventSink, required this.session});

  Stream<agent.AgentEvent> get events => eventSink.stream;
}

/// 全局唯一 Agent Runtime。插件通过 [PluginBridge] 自动发现注册。
final agentRuntimeProvider = Provider<AgentRuntime>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY');
  final model = getSetting(prefs, 'DEEPSEEK_MODEL');

  final provider = agent.DeepSeekProvider(
    dio: Dio(),
    apiKey: apiKey,
    model: model.isNotEmpty ? model : 'deepseek-v4-flash',
  );

  final globalStore = FileMemoryStore(greenixMemoriesDir);

  // Skill 系统
  final skillDir = greenixSkillsDir;
  const bundledSkills = ['acceptance.md'];
  Directory(skillDir).createSync(recursive: true);
  for (final name in bundledSkills) {
    final target = File('$skillDir/$name');
    if (!target.existsSync()) {
      rootBundle.loadString('$skillDir/$name').then((content) {
        target.writeAsStringSync(content);
      }).catchError((_) {});
    }
  }
  final skillIndex = SkillIndex();
  final loader = SkillLoader([skillDir]);
  skillIndex.addAll(loader.loadAll());
  BuiltinSkills.loadInto(skillIndex);

  final registry = agent.Registry();
  for (final t in [
    GetUserInfoTool(),
    ReadGlobalMemoryTool(globalStore),
    WriteGlobalMemoryTool(globalStore),
    ReadFileTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
    WriteFileTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
    RunSkillTool(loader, skillIndex, provider, registry),
    ListSkillsTool(loader, skillIndex),
    WebSearchTool(Dio()),
    WebFetchTool(Dio()),
  ]) {
    if (!registry.has(t.name)) registry.register(t);
  }

  // 插件嫁接桥——自动扫描 plugins/<name>/.exe 并注册
  final pluginsDir = Directory('plugins');
  if (!pluginsDir.existsSync()) pluginsDir.createSync(recursive: true);
  PluginBridge.registerAll(registry, pluginsDir);

  final eventSink = agent.StreamEventSink();
  final session = agent.Session();
  final memoryRouter = MemoryRouter(global: globalStore);
  final memory = MemoryFacade(memoryRouter);

  final memoryAgent = MemoryAgent(provider, greenixMemoriesDir);

  final controller = agent.Controller(
    provider: provider, registry: registry, sink: eventSink,
    session: session, memory: memory, memoryAgent: memoryAgent,
    skillIndexText: skillIndex.indexText(),
    skillIndex: skillIndex,
  );

  // Agent HTTP Server —— 供插件 .exe 桥接到 core/agent
  final httpServer = agent.AgentHttpServer(
    controller: controller,
    eventSink: eventSink,
    session: session,
    registry: registry,
    portFile: '.agent_port',
    memoryStore: globalStore,
    skillIndex: skillIndex,
  );
  httpServer.start(); // fire-and-forget: 异步启动，不阻塞 Provider 构造

  ref.listen<bool>(webSearchEnabledProvider, (prev, enabled) {
    if (enabled) { registry.enable('web_search'); registry.enable('web_fetch'); }
    else { registry.disable('web_search'); registry.disable('web_fetch'); }
  });

  ref.listen<bool>(deepThinkingEnabledProvider, (prev, enabled) {
    provider.setThinking('enabled');
    provider.setReasoningEffort(enabled ? 'max' : 'low');
    controller.setSystemPrompt(agent.defaultSystemPrompt +
        (enabled ? '\n\n用户已开启深度思考模式。请思考更全面之后再回复。' : ''));
  });

  ref.onDispose(() {
    httpServer.stop();
    controller.dispose();
  });
  return AgentRuntime(controller: controller, eventSink: eventSink, session: session);
});

// ═══════ 开关 ═══════

final webSearchEnabledProvider = StateProvider<bool>((ref) => false);
final deepThinkingEnabledProvider = StateProvider<bool>((ref) => false);

// ═══════ ChatMessage ═══════

class ChatMessage extends agent.Message {
  final bool isToolCall;
  final bool isToolResultCard;

  const ChatMessage({
    required super.role, super.content = '', super.reasoningContent = '',
    super.toolCalls, this.isToolCall = false, this.isToolResultCard = false,
  });
}

class ChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  ChatMessagesNotifier() : super([]);

  void addUser(String text) {
    state = [...state, ChatMessage(role: agent.Role.user, content: text)];
  }

  void addAssistant(String text, {String reasoning = ''}) {
    state = [...state, ChatMessage(
      role: agent.Role.assistant, content: text, reasoningContent: reasoning,
    )];
  }

  /// 替换最后一条 AI 消息（流式场景）。
  void replaceLastAssistant(String text) {
    if (state.isNotEmpty && state.last.role == agent.Role.assistant) {
      final updated = [...state];
      updated[updated.length - 1] = ChatMessage(
        role: agent.Role.assistant, content: text,
      );
      state = updated;
    } else {
      state = [...state, ChatMessage(role: agent.Role.assistant, content: text)];
    }
  }

  /// 移除最后一条 AI 消息（重新生成用）。
  @Deprecated('Use removeLastTurn instead — 需同时清理 Session 中的消息')
  void removeLastAssistant() {
    if (state.isNotEmpty && state.last.role == agent.Role.assistant) {
      state = [...state]..removeLast();
    }
  }

  /// 移除最后一轮对话：从最后一条 user 消息开始的所有消息。
  /// 返回被移除的 user 消息内容，无 user 消息则返回 null。
  String? removeLastTurn() {
    final userIdx = state.lastIndexWhere((m) => m.isUser);
    if (userIdx < 0) return null;
    final userContent = state[userIdx].content;
    state = [...state]..removeRange(userIdx, state.length);
    return userContent;
  }

  /// 移除指定索引及其后的所有消息。
  void removeFrom(int index) {
    if (index < 0 || index >= state.length) return;
    state = [...state]..removeRange(index, state.length);
  }

  /// 添加一条系统通知消息。
  void addNotice(String text) {
    state = [...state, ChatMessage(role: agent.Role.system, content: text)];
  }

  void updateLastAssistant(String text, {String reasoning = ''}) {
    if (state.isEmpty || state.last.role != agent.Role.assistant ||
        state.last.isToolCall || state.last.isToolResultCard) {
      addAssistant(text, reasoning: reasoning);
      return;
    }
    final updated = [...state];
    final last = updated.last;
    updated[updated.length - 1] = ChatMessage(
      role: agent.Role.assistant,
      content: last.content + text,
      reasoningContent: reasoning.isNotEmpty ? reasoning : last.reasoningContent,
    );
    state = updated;
  }

  void addToolCall(String name) {
    state = [...state, ChatMessage(role: agent.Role.assistant, content: name, isToolCall: true)];
  }

  void addToolResult(String name, String output) {
    state = [...state, ChatMessage(
      role: agent.Role.assistant, content: '[$name]\n$output', isToolResultCard: true,
    )];
  }

  void clear() => state = [];
}

final chatMessagesProvider = StateNotifierProvider<ChatMessagesNotifier, List<ChatMessage>>((ref) {
  return ChatMessagesNotifier();
});
