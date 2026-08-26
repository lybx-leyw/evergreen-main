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
import 'package:evergreen_base/core/agent/tools/agent_process_tools.dart';
import 'package:evergreen_base/core/agent/tools/read_global_memory.dart';
import 'package:evergreen_base/core/agent/tools/run_skill.dart';
import 'package:evergreen_base/core/agent/tools/web_search.dart';
import 'package:evergreen_base/core/agent/tools/user_info.dart';
import 'package:evergreen_base/core/agent/tools/read_file.dart';
import 'package:evergreen_base/core/agent/tools/grep.dart';
import 'package:evergreen_base/core/agent/tools/write_file.dart';
import 'package:evergreen_base/core/agent/tools/head_tail.dart';
import 'package:evergreen_base/core/agent/tools/file_info.dart';
import 'package:evergreen_base/core/agent/tools/write_global_memory.dart';
import 'package:evergreen_base/core/agent/tools/python_runner_tool.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/python_env.dart';
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
  final baseUrl = getSetting(prefs, 'DEEPSEEK_BASE_URL');

  final provider = agent.DeepSeekProvider(
    dio: Dio(),
    apiKey: apiKey,
    model: model.isNotEmpty ? model : 'deepseek-v4-flash',
    // 空值由 Provider 内部回退到官方地址；非空则直连 OpenAI 兼容端点
    baseUrl: baseUrl,
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
  final pluginsDir = resolvePluginsRoot();
  final loader = SkillLoader([
    skillDir,          // .greenix/skills/ — 全局 skill（旧路径兼容）
    pluginsDir,        // plugins/<name>/skill/*.md — 插件专用 skill（统一路径）
  ], disabledSkillIds: SkillLoader.disabledIdsFromPluginStates(pluginsDir),
      pluginsRootForDisabled: pluginsDir);
  skillIndex.addAll(loader.loadAll());
  BuiltinSkills.loadInto(skillIndex);

  final registry = agent.Registry();
  for (final t in [
    GetUserInfoTool(),
    ReadGlobalMemoryTool(globalStore),
    WriteGlobalMemoryTool(globalStore),
    ReadFileTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
    WriteFileTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
    GrepTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
    ReadHeadTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
    ReadTailTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
    FileInfoTool(workspaceDir: greenixWorkspaceDir('ai-assistant')),
    RunSkillTool(loader, skillIndex, provider, registry),
    ListSkillsTool(loader, skillIndex),
    WebSearchTool(Dio()),
    WebFetchTool(Dio()),
    // 后台常驻进程管理工具（Task 三决策 3.2）——与 app_bootstrap /
    // agent_factory 同步注册；共享全局单例 agentProcessRegistry。
    ListProcessesTool(),
    KillProcessTool(),
  ]) {
    if (!registry.has(t.name)) registry.register(t);
  }

  // 注册 Python Runner — 统一解析（PythonInterpreter 同步探测嵌入式 Python，
  // 与 resolvePythonExe 的 greenix 目录优先级一致：未找到嵌入式则不注册）。
  final bundledPython = PythonInterpreter.bundledPathSync();
  if (bundledPython != null) {
    if (!registry.has('python_runner')) {
      registry.register(PythonRunnerTool(
        pythonExePath: bundledPython,
        pythonWorkDir: Directory(bundledPython).parent.path,
        workspaceDir: greenixWorkspaceDir('ai-assistant'),
      ));
    }
  }

  // 插件嫁接桥——自动扫描 plugins/<name>/.exe 并注册
  final pluginsDirObj = Directory(pluginsDir);
  if (!pluginsDirObj.existsSync()) pluginsDirObj.createSync(recursive: true);
  PluginBridge.registerAll(registry, pluginsDirObj);

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

  // ── 深度思考档位（主要入口） ──
  ref.listen<String>(reasoningEffortProvider, (prev, effort) {
    // 同步到旧的 bool provider
    ref.read(deepThinkingEnabledProvider.notifier).state = (effort != 'off');

    if (effort == 'off') {
      provider.setThinking('disabled');
      controller.setSystemPrompt(agent.defaultSystemPrompt);
    } else {
      provider.setThinking('enabled');
      provider.setReasoningEffort(effort);
      final effortDescriptions = <String, String>{
        'low': '请简要思考后回答。',
        'medium': '请适度思考后回答。',
        'high': '请深入思考后再回答。',
        'max': '请做最全面的思考，考虑多种方案和边界情况后再回答。',
      };
      controller.setSystemPrompt(agent.defaultSystemPrompt +
          '\n\n深度思考模式：${effort} 级。${effortDescriptions[effort] ?? ''}');
    }
  });

  // ── 向后兼容：旧 UI 写入 bool 时同步到 effort ──
  ref.listen<bool>(deepThinkingEnabledProvider, (prev, enabled) {
    final currentEffort = ref.read(reasoningEffortProvider);
    if (enabled && currentEffort == 'off') {
      ref.read(reasoningEffortProvider.notifier).state = 'medium';
    } else if (!enabled && currentEffort != 'off') {
      ref.read(reasoningEffortProvider.notifier).state = 'off';
    }
  });

  ref.onDispose(() {
    httpServer.stop();
    controller.dispose();
    // 清理所有常驻 tool 进程（lifetime:"resident"），避免孤儿进程。
    agentProcessRegistry.disposeAll();
  });
  return AgentRuntime(controller: controller, eventSink: eventSink, session: session);
});

// ═══════ 开关 ═══════

final webSearchEnabledProvider = StateProvider<bool>((ref) => false);

/// 深度思考档位——'off' | 'low' | 'medium' | 'high' | 'max'。
///
/// 这是思考深度的主要控制入口。UI 应使用此 provider 替代旧的 bool 开关。
/// 旧的 [deepThinkingEnabledProvider] 保留以向后兼容——写入 bool 会同步到此 provider。
final reasoningEffortProvider = StateProvider<String>((ref) => 'off');

/// 有效的 reasoning_effort 值列表。
const validReasoningEfforts = ['off', 'low', 'medium', 'high', 'max'];

/// 深度思考开关（向后兼容）。
///
/// 新代码应使用 [reasoningEffortProvider]。此 provider 与 [reasoningEffortProvider]
/// 双向同步：写入 true → effort='medium'；写入 false → effort='off'；
/// effort 变化 → 自动更新此 bool。
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
