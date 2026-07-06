/// Chat 控制器视图——统一的 AI 聊天界面。
///
/// 单一 [ConsumerStatefulWidget]，直接订阅事件流，通过 [ref.watch] 驱动渲染。
/// 合并了原 ChatControllerView + ChatView + AiAssistantSlotWidget 的三层架构，
/// 消除 props 传递链路。通过 `embedded` 参数统一全页面和 slot 内嵌两种形态。
///
/// 职责：
/// 1. 订阅 [agentEventStreamProvider] 事件流（全屏模式）
/// 2. 通过 [AgentAssembly] 管理隔离 Agent 实例（嵌入模式）
/// 3. 将 [AgentEvent] 实时渲染为消息气泡
/// 4. 会话管理（创建/切换/删除/重命名）
/// 5. 工作区文件面板
/// 6. 全局记忆入口
/// 7. EventBus 栏间通信（嵌入模式 + pageEventBus 非 null）
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_base/core/config/config.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/controller/controller.dart' show ControllerState;
import 'package:evergreen_base/core/agent/agent_factory.dart';
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/agent/agent_runtime.dart' show webSearchEnabledProvider, deepThinkingEnabledProvider, agentRuntimeProvider;
import 'package:evergreen_base/providers.dart' show agentControllerProvider;
import 'package:evergreen_base/core/agent/session_manager.dart';
import 'package:evergreen_base/renderer/widgets/models.dart';
import 'package:evergreen_base/renderer/widgets/markdown_renderer.dart';
import 'package:evergreen_base/renderer/widgets/workspace_drawer.dart';
import 'package:evergreen_base/renderer/shared/theme_provider.dart';
import 'file_viewer.dart';
import 'global_memory_view.dart';
import 'skill_management_view.dart';

/// 当前视图的消息列表（全屏模式）。
final _chatMessagesProvider = StateNotifierProvider<_LocalChatMessagesNotifier, List<ChatMessage>>((ref) => _LocalChatMessagesNotifier());

/// Chat 范式统一控制器视图——全屏 / 嵌入两用。
///
/// | 模式 | embedded | agentConfig | 行为 |
/// |------|----------|------------|------|
/// | 全屏 | false (默认) | null | Scaffold + 会话管理 + 全局 AgentRuntime |
/// | 嵌入(全局Agent) | true | null | 紧凑列布局，复用全局 AgentRuntime |
/// | 嵌入(隔离Agent) | true | Map (config) | 紧凑列布局 + AgentAssembly 隔离实例 + EventBus |
class ChatControllerView extends ConsumerStatefulWidget {
  final ModuleDescriptor descriptor;

  /// 嵌入模式：true 时无 Scaffold/AppBar/Drawer，适合 CompositeView slot。
  final bool embedded;

  /// 紧凑模式：true 时进一步精简 UI（适合窄栏）。
  final bool compact;

  /// 页级事件总线（嵌入式栏间实时通信，PLAN_NOW §9.4）。
  final PageEventBus? pageEventBus;

  /// Agent 配置（嵌入模式时创建隔离 AgentAssembly，来自 manifest.json slots.*.config）。
  final Map<String, dynamic>? agentConfig;

  /// 栏位键名（嵌入模式时标识自身，用于 EventBus 回环检测）。
  final String? slotKey;

  /// AI 助手字体缩放比例（1.0 = 默认大小）。
  /// 影响：AI 回复文字、用户消息文字、AI/用户头像大小均按此比例缩放。
  final double fontScale;

  const ChatControllerView({
    super.key,
    required this.descriptor,
    this.embedded = false,
    this.compact = false,
    this.pageEventBus,
    this.agentConfig,
    this.slotKey,
    this.fontScale = 1.0,
  });

  @override
  ConsumerState<ChatControllerView> createState() => _ChatControllerViewState();
}

class _ChatControllerViewState extends ConsumerState<ChatControllerView>
    with SingleTickerProviderStateMixin {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  StreamSubscription<agent.AgentEvent>? _eventSub;

  // ── 流式累积 ──
  final StringBuffer _pendingAnswer = StringBuffer();
  final StringBuffer _pendingTimeline = StringBuffer();
  String? _currentTurnUserText;
  bool _hasBubble = false;
  int _textThrottleCount = 0;
  final Set<String> _seenNotices = {};

  // ── 状态指示灯 ──
  String _statusText = '';
  String _currentTool = '';
  int _elapsedSeconds = 0;
  late Timer _elapsedTimer;
  late AnimationController _pulseAnim;
  bool _isRunning = false;

  // ── 嵌入模式：隔离 Agent ──
  AgentAssembly? _assembly;
  agent.Controller? get _embeddedCtrl => _assembly?.controller;
  StreamSubscription<agent.AgentEvent>? _embeddedEventSub;

  // ── 嵌入模式：本地消息列表（不依赖全局 provider）──
  final List<ChatMessage> _embeddedMessages = [];

  // ── 嵌入模式：初始化状态 ──
  bool _embeddedInitialized = false;
  String _embeddedError = '';

  // ── 嵌入模式：EventBus 栏间通信 ──
  List<StreamSubscription<SlotEvent>>? _eventBusSubs;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isRunning && mounted) setState(() => _elapsedSeconds++);
    });
    if (widget.embedded && widget.agentConfig != null) {
      // 嵌入模式 + 隔离 Agent → 异步初始化 AgentAssembly
      _initEmbeddedAgent();
    } else {
      // 全屏模式（或嵌入但复用全局 Agent）
      Future.microtask(() => _subscribeToEvents());
    }
  }

  @override
  void dispose() {
    _elapsedTimer.cancel();
    _pulseAnim.dispose();
    _eventSub?.cancel();
    _embeddedEventSub?.cancel();
    for (final sub in _eventBusSubs ?? <StreamSubscription>[]) {
      sub.cancel();
    }
    _assembly?.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  // ── 状态灯控制 ──

  void _startIndicator() {
    setState(() {
      _isRunning = true;
      _elapsedSeconds = 0;
      _currentTool = '';
      _statusText = '思考中...';
    });
    _pulseAnim.repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(controllerStateProvider.notifier).state = ControllerState.running;
      }
    });
  }

  void _stopIndicator() {
    setState(() => _isRunning = false);
    _pulseAnim.stop();
    _pulseAnim.reset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(controllerStateProvider.notifier).state = ControllerState.idle;
      }
    });
  }

  // ── 事件流订阅 ──

  void _subscribeToEvents() {
    // 嵌入模式 + 隔离 Agent → 使用 AgentAssembly 的事件流
    if (widget.embedded && _assembly != null) {
      _subscribeToEmbeddedEvents();
      return;
    }

    debugPrint('[Chat:D] _subscribeToEvents() started');
    final runtime = ref.read(agentEventStreamProvider);
    final messagesNotifier = ref.read(_chatMessagesProvider.notifier);

    _eventSub?.cancel();
    _eventSub = runtime.listen((event) {
      debugPrint('[Chat:D] event kind=${event.kind.name}'
          ' textLen=${event.text?.length ?? 0}'
          ' tool=${event.tool?.name ?? "-"}');
      if (!mounted) return;

      switch (event.kind) {
        case agent.EventKind.turnStarted:
          _startIndicator();
          break;

        case agent.EventKind.reasoning:
          if (event.reasoning != null) {
            _pendingTimeline.write(event.reasoning);
            _maybeUpdateBubble(messagesNotifier);
          }
          break;

        case agent.EventKind.text:
          if (event.text != null) {
            _pendingAnswer.write(event.text);
            _textThrottleCount++;
            if (!_hasBubble ||
                _textThrottleCount >= 10 ||
                event.text!.contains('。') ||
                event.text!.contains('！') ||
                event.text!.contains('？') ||
                event.text!.contains('\n')) {
              _maybeUpdateBubble(messagesNotifier);
              _textThrottleCount = 0;
            }
          }
          break;

        case agent.EventKind.toolDispatch:
          if (event.tool != null) {
            _flushAnswerToTimeline();
            final name = event.tool!.name;
            final isRead = name == 'read_global_memory';
            final isWrite = name == 'write_global_memory';
            final isMemoryTool = isRead || isWrite;
            final isSkillTool = name == 'run_skill' || name == 'list_skills';
            final icon = isMemoryTool ? '🧠' : isSkillTool ? '📋' : '🔧';
            final label = isRead
                ? '回忆ing'
                : isWrite
                    ? '记忆ing'
                    : isSkillTool
                        ? '加载 Skill'
                        : '调用';
            _pendingTimeline.writeln(
                '\n$icon $label ${isMemoryTool ? '' : name}');
            setState(() {
              _currentTool = name;
              _statusText = isMemoryTool
                  ? '$icon ${isRead ? "回忆ing" : "记忆ing"}...'
                  : isSkillTool
                      ? '📋 $name...'
                      : '调用 $name...';
            });
            _maybeUpdateBubble(messagesNotifier);
          }
          break;

        case agent.EventKind.toolResult:
          if (event.tool != null) {
            final name = event.tool!.name;
            final isRead = name == 'read_global_memory';
            final isWrite = name == 'write_global_memory';
            final isMemoryTool = isRead || isWrite;
            final isSkillTool = name == 'run_skill' || name == 'list_skills';
            final output =
                (event.tool!.output ?? event.tool!.error ?? '').trim();

            if (isMemoryTool || isSkillTool) {
              final icon = isMemoryTool ? '🧠' : '📋';
              _pendingTimeline
                  .writeln('\n$icon **$name** 结果：\n');
              const maxLines = 15;
              final lines = output.split('\n');
              if (lines.length > maxLines) {
                _pendingTimeline
                    .writeln('${lines.take(maxLines).join('\n')}\n');
                _pendingTimeline.writeln(
                    '$icon _...完整内容已加载（共 ${lines.length} 行）_');
              } else {
                _pendingTimeline.writeln('$output\n');
              }
            } else {
              final preview = output.length > 200
                  ? '${output.substring(0, 200)}...'
                  : output;
              _pendingTimeline.writeln('\n✅ $name → $preview');
            }
            messagesNotifier.replaceLastAssistant(_buildCombinedMessage());
            setState(() {
              _currentTool = '';
              _statusText = isRead
                  ? '🧠 回忆完成'
                  : isWrite
                      ? '🧠 记忆完成'
                      : isSkillTool
                          ? '📋 Skill 已加载'
                          : '处理结果...';
            });
          }
          break;

        case agent.EventKind.message:
          break;

        case agent.EventKind.turnDone:
          if (!mounted) return;
          messagesNotifier.replaceLastAssistant(_buildCombinedMessage());
          _stopIndicator();
          // 自动保存会话（.then 非阻塞 + 错误追踪，Stream.listen 不支持 async callback）
          final currentId = ref.read(activeSessionIdProvider);
          if (currentId != null) {
            debugPrint('[Chat:TURN_DONE] saving session id=$currentId');
            ref.read(saveCurrentSessionProvider)(currentId).then((_) {
              debugPrint('[Chat:TURN_DONE] save OK for id=$currentId');
            }).catchError((e, st) {
              debugPrint('[Chat:TURN_DONE] save FAILED for id=$currentId: $e\n$st');
            });
          }
          break;

        case agent.EventKind.notice:
          final notice = event.text ?? '';
          if (notice.isNotEmpty && _seenNotices.add(notice)) {
            if (_isRunning &&
                (notice.contains('思考') || notice.contains('正在'))) {
              break;
            }
            if (notice.contains('记忆') || notice.contains('技能')) {
              messagesNotifier.addNotice(notice);
            }
          }
          break;

        default:
          break;
      }

      // 自动滚底
      Future.microtask(() {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  void _maybeUpdateBubble(_LocalChatMessagesNotifier notifier) {
    _hasBubble = true;
    notifier.replaceLastAssistant(_buildCombinedMessage());
  }

  void _flushAnswerToTimeline() {
    if (_pendingAnswer.isNotEmpty) {
      _pendingTimeline.write(_pendingAnswer.toString());
      _pendingAnswer.clear();
    }
  }

  String _buildCombinedMessage() {
    final timeline = _pendingTimeline.toString().trim();
    final answer = _pendingAnswer.toString().trim();

    final buf = StringBuffer();
    if (timeline.isNotEmpty) {
      buf.writeln(':::reasoning');
      buf.writeln(timeline);
      buf.writeln(':::');
      if (answer.isNotEmpty) buf.writeln();
    }
    buf.write(answer);
    return buf.toString().trim();
  }

  // ── 会话同步 ──

  /// 从 [agentControllerProvider] 的 session 中加载消息到 UI 状态。
  /// ✅ 修复：使用 agentControllerProvider.session（main.dart 中注入的实际 session），
  /// 而非 agentRuntimeProvider.session（agent_runtime.dart 中独立的 session 副本）。
  void _syncMessagesFromRuntime() {
    debugPrint('[Chat:SYNC] _syncMessagesFromRuntime() START');
    final ctrl = ref.read(agentControllerProvider);
    final session = ctrl.session;
    debugPrint('[Chat:SYNC] session.id=${session.id} messages=${session.messages.length}');
    final notifier = ref.read(_chatMessagesProvider.notifier);
    notifier.clear();
    for (final m in session.messages) {
      if (m.content.isEmpty) continue;
      if (m.isUser) {
        notifier.addUser(m.content);
      } else if (m.isAssistant) {
        notifier.addAssistant(
          _contentWithReasoning(m.reasoningContent, m.content),
        );
      }
    }
    debugPrint('[Chat:SYNC] _syncMessagesFromRuntime loaded ${session.messages.length} msgs → notifier has ${notifier.state.length}');
  }

  static String _contentWithReasoning(String reasoning, String content) {
    if (reasoning.isEmpty) return content;
    final buf = StringBuffer();
    buf.writeln(':::reasoning');
    buf.writeln(reasoning);
    buf.writeln(':::');
    if (content.isNotEmpty) buf.writeln();
    buf.write(content);
    return buf.toString().trim();
  }

  // ── 发送消息 ──

  void _editUserMessage(int msgIndex) {
    final messages = ref.read(_chatMessagesProvider);
    if (msgIndex < 0 || msgIndex >= messages.length) return;
    final msg = messages[msgIndex];
    if (!msg.isUser) return;

    final text = msg.content;
    debugPrint('[Chat:D] _editUserMessage index=$msgIndex text="$text"');

    // ✅ 从 Session（后端消息组合器）中删除该消息及其后续所有回复
    final ctrl = ref.read(agentControllerProvider);
    // 找到 Session 中对应的 user 消息位置（Session 消息比 UI 消息多 system prompt）
    // 需要计算偏移量：Session.messages[0] = system prompt
    final sessionMessages = ctrl.session.messages;
    // 找到 Session 中第 msgIndex 条非 system 的 user 消息
    int sessionUserIdx = -1;
    int userCount = 0;
    for (int i = 0; i < sessionMessages.length; i++) {
      if (sessionMessages[i].role == agent.Role.user) {
        if (userCount == _countUserMessagesBefore(messages, msgIndex)) {
          sessionUserIdx = i;
          break;
        }
        userCount++;
      }
    }
    if (sessionUserIdx >= 0) {
      debugPrint('[Chat:D] removing Session messages from index $sessionUserIdx');
      ctrl.session.removeFrom(sessionUserIdx);
    }

    // ✅ 从 UI 消息列表中删除该消息及其后续所有回复
    ref.read(_chatMessagesProvider.notifier).removeFrom(msgIndex);

    // 填入输入框
    _inputCtrl.text = text;
    _inputCtrl.selection = TextSelection.collapsed(offset: text.length);
    FocusScope.of(context).requestFocus();
  }

  /// 计算 messages 列表中 msgIndex 之前有多少条 user 消息。
  int _countUserMessagesBefore(List<ChatMessage> messages, int msgIndex) {
    int count = 0;
    for (int i = 0; i < msgIndex && i < messages.length; i++) {
      if (messages[i].isUser) count++;
    }
    return count;
  }

  Future<void> _regenerate() async {
    if (_isRunning) return;
    debugPrint('[Chat:D] _regenerate() called');

    final messages = ref.read(_chatMessagesProvider);
    if (messages.isEmpty) return;

    // ✅ 从 Session（后端消息组合器）中删除最后一轮对话
    final ctrl = ref.read(agentControllerProvider);
    final lastUserContent = ctrl.session.removeLastTurn();
    if (lastUserContent == null) {
      debugPrint('[Chat:D] _regenerate: no user message in session');
      return;
    }
    debugPrint('[Chat:D] _regenerate: removed last turn from session, userContent="$lastUserContent"');

    // ✅ 从 UI 消息列表中删除最后一轮
    final notifier = ref.read(_chatMessagesProvider.notifier);
    notifier.removeLastTurn();

    // 重新发送
    _editUserText(lastUserContent);
    await _sendMessage();
  }

  /// 仅设置输入框文本（不删除消息历史），用于 _regenerate 流程。
  void _editUserText(String text) {
    _inputCtrl.text = text;
    _inputCtrl.selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    debugPrint('[Chat:D] _sendMessage() text="$text" embedded=${widget.embedded}');
    if (text.isEmpty) return;

    // 嵌入模式 + 隔离 Agent
    if (widget.embedded && _embeddedCtrl != null) {
      if (_isRunning) return;
      _sendEmbedded(text);
      return;
    }

    if (ref.read(controllerStateProvider) == ControllerState.running) return;

    // ✅ 自动创建会话：当 activeSessionId 为 null 时，先创建再发送
    if (ref.read(activeSessionIdProvider) == null) {
      debugPrint('[Chat:D] no active session, auto-creating...');
      ref.read(createSessionProvider)(null);
      debugPrint('[Chat:D] auto-created session: ${ref.read(activeSessionIdProvider)}');
    }

    final messagesNotifier = ref.read(_chatMessagesProvider.notifier);
    messagesNotifier.addUser(text);
    _inputCtrl.clear();

    // 重置渲染状态
    _pendingTimeline.clear();
    _pendingAnswer.clear();
    _textThrottleCount = 0;
    _hasBubble = false;
    _currentTurnUserText = text;
    _seenNotices.clear();

    final ctrl = ref.read(agentControllerProvider);
    ctrl.send(text);
  }

  /// 嵌入模式下发送消息到隔离的 AgentAssembly。
  void _sendEmbedded(String text) {
    final ctrl = _embeddedCtrl;
    if (ctrl == null) return;

    setState(() {
      _embeddedMessages.add(ChatMessage(role: 'user', content: text));
      _isRunning = true;
      _statusText = '思考中...';
    });
    _startIndicator();
    _inputCtrl.clear();

    _pendingTimeline.clear();
    _pendingAnswer.clear();
    _textThrottleCount = 0;
    _hasBubble = false;
    _seenNotices.clear();

    ctrl.send(text);
  }

  // ── 嵌入模式：初始化隔离 AgentAssembly ──

  Future<void> _initEmbeddedAgent() async {
    final cfg = widget.agentConfig;
    if (cfg == null) return;

    final moduleId = '${widget.descriptor.id}/${widget.slotKey ?? "embedded"}';

    try {
      // 1. 加载 API Key
      final prefs = await SharedPreferences.getInstance();
      final apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY');
      if (apiKey.isEmpty) {
        if (mounted) setState(() {
          _embeddedError = '未配置 API Key';
          _embeddedInitialized = true;
        });
        return;
      }

      // 2. 创建共享 Provider
      final provider = agent.DeepSeekProvider(
        dio: Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        )),
        apiKey: apiKey,
      );

      // 3. 读取 Riverpod 全局依赖
      final skillIdx = ref.read(skillIndexProvider);
      final memStore = ref.read(memoryStoreProvider);

      // 4. 创建隔离 AgentAssembly
      _assembly = AgentAssembly.fromConfig(
        moduleId: moduleId,
        config: cfg,
        sharedProvider: provider,
        globalSkillIndex: skillIdx,
        globalMemoryStore: memStore,
      );
      debugPrint('[ChatCtrl:E] AgentAssembly "$moduleId" 创建成功'
          ' tools=${_assembly!.registry.enabled().length}'
          ' skills=${_assembly!.skillIndex.all().length}');
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _embeddedError = 'Agent 初始化失败: $e';
          _embeddedInitialized = true;
        });
      }
      debugPrint('[ChatCtrl:E] 创建失败: $e\n$st');
      return;
    }

    // 5. 订阅 AgentAssembly 事件流
    _subscribeToEmbeddedEvents();

    // 6. 订阅 EventBus（栏间通信）
    _setupEmbeddedEventBus(moduleId);

    if (mounted) setState(() => _embeddedInitialized = true);
  }

  // ── 嵌入模式：订阅隔离 Agent 事件流 ──

  void _subscribeToEmbeddedEvents() {
    final eventSink = _assembly?.eventSink;
    if (eventSink == null) return;

    _embeddedEventSub?.cancel();
    _embeddedEventSub = eventSink.stream.listen(_onEmbeddedAgentEvent);
    debugPrint('[ChatCtrl:E] 已订阅 AgentAssembly 事件流');
  }

  void _onEmbeddedAgentEvent(agent.AgentEvent event) {
    if (!mounted) return;

    switch (event.kind) {
      case agent.EventKind.turnStarted:
        setState(() { _statusText = '思考中...'; });
        _startIndicator();
        break;

      case agent.EventKind.reasoning:
        if (event.reasoning != null) {
          _pendingTimeline.write(event.reasoning);
          _maybeUpdateEmbeddedBubble();
        }
        break;

      case agent.EventKind.text:
        if (event.text != null) {
          _pendingAnswer.write(event.text);
          _textThrottleCount++;
          if (!_hasBubble ||
              _textThrottleCount >= 10 ||
              event.text!.contains('。') ||
              event.text!.contains('！') ||
              event.text!.contains('？') ||
              event.text!.contains('\n')) {
            _maybeUpdateEmbeddedBubble();
            _textThrottleCount = 0;
          }
        }
        break;

      case agent.EventKind.toolDispatch:
        if (event.tool != null) {
          setState(() {
            _currentTool = event.tool!.name;
            _statusText = '🔧 ${event.tool!.name}';
          });
          _pendingTimeline.writeln('\n🔧 调用 ${event.tool!.name}');
          _maybeUpdateEmbeddedBubble();
        }
        break;

      case agent.EventKind.toolResult:
        if (event.tool != null) {
          final ok = event.tool!.error == null;
          setState(() => _statusText = ok ? '✅ ${event.tool!.name}' : '❌ ${event.tool!.name}');
          final output = (event.tool!.output ?? event.tool!.error ?? '').trim();
          final preview = output.length > 200 ? '${output.substring(0, 200)}...' : output;
          _pendingTimeline.writeln('\n✅ ${event.tool!.name} → $preview');
          _replaceLastEmbeddedAssistant(_buildCombinedMessage());
        }
        break;

      case agent.EventKind.turnDone:
        if (!mounted) return;
        _replaceLastEmbeddedAssistant(_buildCombinedMessage());
        _stopIndicator();
        break;

      case agent.EventKind.notice:
        if (event.text != null && event.text!.isNotEmpty) {
          setState(() => _statusText = 'ℹ ${event.text}');
        }
        break;

      default:
        break;
    }

    // 自动滚底
    Future.microtask(() {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _maybeUpdateEmbeddedBubble() {
    _hasBubble = true;
    _replaceLastEmbeddedAssistant(_buildCombinedMessage());
  }

  void _replaceLastEmbeddedAssistant(String text) {
    if (_embeddedMessages.isNotEmpty && _embeddedMessages.last.role == 'assistant') {
      _embeddedMessages[_embeddedMessages.length - 1] =
          ChatMessage(role: 'assistant', content: text);
    } else {
      _embeddedMessages.add(ChatMessage(role: 'assistant', content: text));
    }
    if (mounted) setState(() {});
  }

  // ── 嵌入模式：EventBus 栏间通信 ──

  void _setupEmbeddedEventBus(String assemblyId) {
    final bus = widget.pageEventBus;
    if (bus == null) return;

    // 嵌入模式 + 有 EventBus → 自动订阅栏间学习事件
    const defaultEvents = ['answer_wrong', 'card_forgotten', 'word_completed'];
    debugPrint('[ChatCtrl:E:$assemblyId] EventBus subscribes: $defaultEvents');

    _eventBusSubs = [];
    for (final eventName in defaultEvents) {
      final sub = bus.on(eventName).listen((evt) {
        if (evt.sourceSlot == widget.slotKey) return; // 不回环
        _autoTriggerOnEvent(evt, assemblyId);
      });
      _eventBusSubs!.add(sub);
    }
  }

  /// 收到栏间事件时，自动向 Agent 发送分析指令（分栏共享）。
  void _autoTriggerOnEvent(SlotEvent evt, String assemblyId) {
    final ctrl = _embeddedCtrl;
    if (ctrl == null || _isRunning) return;

    String? prompt;
    switch (evt.event) {
      case 'answer_wrong':
        final word = (evt.data['word'] as String?) ?? '';
        final meaning = (evt.data['meaning'] as String?) ?? '';
        final input = (evt.data['input'] as String?) ?? '';
        if (word.isEmpty) return;
        prompt = '用户拼写 "$word" 时写成了 "$input"。'
            '请用中文分析该单词的词根词缀、联想记忆法和例句帮助记忆。词义：$meaning';
        break;
      case 'card_forgotten':
        final word = (evt.data['word'] as String?) ?? '';
        final meaning = (evt.data['meaning'] as String?) ?? '';
        if (word.isEmpty) return;
        prompt = '用户在闪卡复习中对 "$word" 点了忘记。'
            '请提供该单词的词根词缀分析、趣味记忆法和例句。词义：$meaning';
        break;
      case 'word_completed':
        final total = evt.data['total'];
        final correct = evt.data['correct'];
        final wrong = evt.data['wrong'];
        if (total != null) {
          prompt = '用户刚完成了一轮学习：总计 $total 个单词，正确 $correct 个，错误 $wrong 个。'
              '请给出简要鼓励和建议。';
        }
        break;
      default:
        return;
    }

    if (prompt == null) return;
    debugPrint('[ChatCtrl:E:$assemblyId] 🚀 自动触发分析: $prompt');

    setState(() {
      _embeddedMessages.add(ChatMessage(role: 'user', content: '[系统自动] $prompt'));
      _isRunning = true;
      _statusText = '分析中...';
    });
    _startIndicator();
    _scrollToBottom();
    ctrl.send(prompt);
  }

  // ── 嵌入模式：紧凑 UI ──

  Widget _buildEmbeddedContent() {
    final theme = Theme.of(context);
    final messages = widget.embedded && widget.agentConfig != null
        ? _embeddedMessages
        : ref.watch(_chatMessagesProvider);

    return ClipRect(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 状态栏
          if (_isRunning) _buildCompactStatusBar(theme),

          // 消息列表——使用 Expanded + shrinkWrap:true 的 ListView 适应父容器高度
          // 注意：父容器是 SizedBox(height:400)，此 Expanded 占据剩余空间
          Expanded(
            child: messages.isEmpty
                ? _buildEmbeddedEmptyState(theme)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final lastAsstIdx = messages.lastIndexWhere((m) => m.isAssistant);
                      return _MessageBubble(
                        message: msg,
                        fontScale: widget.fontScale,
                        messageIndex: index,
                        onEdit: msg.isUser
                            ? () => _editUserMessage(index)
                            : null,
                        onRegenerate: msg.isAssistant && index == lastAsstIdx
                            ? _regenerate
                            : null,
                      );
                    },
                  ),
          ),

          // 输入栏（紧凑版）
          _buildEmbeddedInputBar(theme),
        ],
      ),
    );
  }

  Widget _buildEmbeddedEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.psychology_outlined, size: 32,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 6),
          Text('就绪，输入消息...',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildCompactStatusBar(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: theme.brightness == Brightness.dark
          ? Colors.blueGrey.shade900
          : Colors.blue.shade50,
      child: Row(
        children: [
          const SizedBox(width: 8, height: 8,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentTool.isNotEmpty ? '$_statusText' : _statusText,
              style: TextStyle(
                fontSize: 11,
                color: theme.brightness == Brightness.dark
                    ? Colors.blue.shade200
                    : Colors.blue.shade700,
              ),
            ),
          ),
          if (_elapsedSeconds > 0)
            Text('${_elapsedSeconds}s',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildEmbeddedInputBar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              enabled: !_isRunning,
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: _isRunning ? '回复中...' : '输入消息...',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
              ),
              maxLines: 2,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              _isRunning ? Icons.stop : Icons.send,
              size: 18,
              color: isDark ? Colors.blue.shade300 : Colors.blue.shade600,
            ),
            onPressed: _isRunning
                ? () { _embeddedCtrl?.cancel(); }
                : () => _sendMessage(),
          ),
        ],
      ),
    );
  }

  // ── 构建 ──

  @override
  Widget build(BuildContext context) {
    // 嵌入模式：等待初始化
    if (widget.embedded) {
      if (widget.agentConfig != null && !_embeddedInitialized) {
        // 正在初始化 AgentAssembly
        return const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      if (_embeddedError.isNotEmpty) {
        return SizedBox(
          height: 120,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber, size: 28, color: Colors.orange),
                const SizedBox(height: 8),
                Text(_embeddedError,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        );
      }
      // 嵌入模式 → 紧凑布局（无 Scaffold/AppBar/Drawer）
      return _buildEmbeddedContent();
    }

    // ── 全屏模式 ──
    // ── 会话切换时同步 UI 消息 ──
    ref.listen<String?>(activeSessionIdProvider, (prev, next) {
      if (prev == next) return;
      _syncMessagesFromRuntime();
    });

    final messages = ref.watch(_chatMessagesProvider);
    final theme = Theme.of(context);
    final workspace = widget.descriptor.workspace;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: '会话历史',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(
          ref.watch(activeSessionTitleProvider),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        actions: [
          if (workspace != null)
            IconButton(
              icon: const Icon(Icons.folder_outlined),
              tooltip: '工作区',
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            tooltip: '技能管理',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SkillManagementView()),
            ),
          ),
        ],
      ),
      drawer: _buildHistoryDrawer(context, theme),
      endDrawer: workspace != null
          ? Drawer(
              child: WorkspaceDrawer(
                workspace: workspace,
                moduleId: widget.descriptor.id,
                onFileTap: (file) {
                  _scaffoldKey.currentState?.closeEndDrawer();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => FileViewer(file: file)),
                  );
                },
              ),
            )
          : null,
      body: Column(
        children: [
          // ── 消息列表 ──
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final lastAsstIdx = messages.lastIndexWhere((m) => m.isAssistant);
                      return _MessageBubble(
                        message: msg,
                        fontScale: widget.fontScale,
                        messageIndex: index,
                        onEdit: msg.isUser
                            ? () => _editUserMessage(index)
                            : null,
                        onRegenerate: msg.isAssistant && index == lastAsstIdx
                            ? _regenerate
                            : null,
                      );
                    },
                  ),
          ),

          // ── 状态指示灯 ──
          if (_isRunning) _buildStatusBar(theme),

          // ── 输入栏 ──
          _buildInputBar(theme),
        ],
      ),
    );
  }

  // ── 状态指示灯 ──

  Widget _buildStatusBar(ThemeData theme) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, _) {
        final opacity = 0.4 + _pulseAnim.value * 0.6;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: opacity * 0.15),
            border: Border(
              top: BorderSide(color: Colors.blue.withValues(alpha: 0.1)),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentTool.isNotEmpty
                      ? '$_statusText (${_elapsedSeconds}s)'
                      : '$_statusText (${_elapsedSeconds}s)',
                  style: const TextStyle(fontSize: 12, color: Colors.blue),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 输入栏 ──

  Widget _buildInputBar(ThemeData theme) {
    final isRunning = ref.watch(controllerStateProvider) == ControllerState.running;
    final webSearch = ref.watch(webSearchEnabledProvider);
    final deepThink = ref.watch(deepThinkingEnabledProvider);
    final hasWorkspace = widget.descriptor.workspace != null;

    return Container(
      decoration: BoxDecoration(
        color: context.componentColor('input', 'bg') ?? theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: context.componentColor('input', 'border') ?? theme.dividerColor,
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 工具栏按钮行 ──
            Row(
              children: [
                if (hasWorkspace)
                  _ToggleChip(
                    icon: Icons.folder_outlined,
                    label: '工作区',
                    value: false,
                    onChanged: (_) => _scaffoldKey.currentState?.openEndDrawer(),
                    activeColor: const Color(0xFF1565C0),
                  ),
                if (hasWorkspace) const SizedBox(width: 4),
                _ToggleChip(
                  icon: Icons.language,
                  label: '联网搜索',
                  value: webSearch,
                  onChanged: (v) =>
                      ref.read(webSearchEnabledProvider.notifier).state = v,
                  activeColor: const Color(0xFF1565C0),
                ),
                const SizedBox(width: 4),
                _ToggleChip(
                  icon: Icons.auto_awesome,
                  label: '深度思考',
                  value: deepThink,
                  onChanged: (v) =>
                      ref.read(deepThinkingEnabledProvider.notifier).state = v,
                  activeColor: const Color(0xFF7B1FA2),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  tooltip: '技能管理',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SkillManagementView()),
                    );
                  },
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: '清空对话',
                  onPressed: () {
                    ref.read(_chatMessagesProvider.notifier).clear();
                    ref.read(agentControllerProvider).newSession();
                  },
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // ── 输入行 ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    enabled: !isRunning,
                    decoration: InputDecoration(
                      hintText:
                          isRunning ? 'AI 正在思考...' : '输入你的问题...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: isRunning ? null : (_) => _sendMessage(),
                    minLines: 1,
                    maxLines: 4,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: isRunning
                      ? () => ref.read(agentControllerProvider).cancel()
                      : () => _sendMessage(),
                  icon: Icon(isRunning ? Icons.stop : Icons.send),
                  tooltip: isRunning ? '停止' : '发送',
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 空状态 ──

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '我是你的 AI 教学助手',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            '我可以帮你查课程、成绩、待办、考试...\n也可以陪你讨论学习问题',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _suggestionChip('有哪些课程？'),
              _suggestionChip('我的成绩'),
              _suggestionChip('最近的待办'),
              _suggestionChip('考试日程'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _suggestionChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        _inputCtrl.text = text;
        _sendMessage();
      },
    );
  }

  // ── 左侧抽屉：对话历史 ──

  Widget _buildHistoryDrawer(BuildContext context, ThemeData theme) {
    return Drawer(
      width: 300,
      child: _ConversationHistoryPanel(
        moduleId: widget.descriptor.id,
        onSessionTap: () => _scaffoldKey.currentState?.closeDrawer(),
        onGlobalMemory: () {
          _scaffoldKey.currentState?.closeDrawer();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const GlobalMemoryView()),
          );
        },
      ),
    );
  }
}

// ═══════ _MessageBubble ═══════

class _MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final double fontScale;
  final int? messageIndex; // 消息在列表中的索引，用于撤回/重新生成时定位
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  const _MessageBubble({required this.message, this.fontScale = 1.0, this.messageIndex, this.onEdit, this.onRegenerate});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _reasoningExpanded = false;
  final _thinkingScrollCtrl = ScrollController();

  @override
  void didUpdateWidget(_MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldContent = oldWidget.message.content;
    final newContent = widget.message.content;
    if (oldContent == newContent) return;

    final oldHasReasoning = oldContent.contains(':::reasoning');
    final newHasReasoning = newContent.contains(':::reasoning');

    if (newHasReasoning) {
      final oldHasAnswer = _extractAnswer(oldContent).length > 20;
      final newHasAnswer = _extractAnswer(newContent).length > 20;

      if (!oldHasAnswer && !newHasAnswer) {
        // 思考中：自动展开 + 滚底
        if (!_reasoningExpanded) {
          _reasoningExpanded = true;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_thinkingScrollCtrl.hasClients) return;
          _thinkingScrollCtrl.animateTo(
            _thinkingScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        });
      } else if (!oldHasAnswer && newHasAnswer) {
        // 思考完成：自动折叠
        _reasoningExpanded = false;
      }
    }
  }

  String _extractAnswer(String content) {
    final m = RegExp(r'^:::reasoning\n[\s\S]*?\n:::').firstMatch(content);
    return m == null ? content : content.substring(m.end).trim();
  }

  @override
  void dispose() {
    _thinkingScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isUser = msg.isUser;
    var content = msg.content;

    // 检测 :::reasoning 标记
    String? reasoningContent;
    String mainContent = content;
    final reasoningMatch =
        RegExp(r'^:::reasoning\n([\s\S]*?)\n:::').firstMatch(content);
    if (reasoningMatch != null) {
      reasoningContent = reasoningMatch.group(1)?.trim();
      mainContent = content.substring(reasoningMatch.end).trim();
    }

    // 思考中占位
    if (mainContent == '_thinking_' && !isUser) {
      final s = widget.fontScale;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14 * s,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.auto_awesome, size: 16 * s,
                  color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomRight: const Radius.circular(16),
                    bottomLeft: const Radius.circular(4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 14 * s, height: 14 * s,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('思考中...',
                        style: TextStyle(fontSize: 13 * s, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final s = widget.fontScale;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14 * s,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.auto_awesome, size: 16 * s,
                  color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: isUser
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── 思考过程（折叠）──
                    if (!isUser && reasoningContent != null) ...[
                      _buildThinkingSection(reasoningContent!),
                    ],

                    // ── 主内容 ──
                    if (mainContent.isNotEmpty && mainContent != '_thinking_')
                      isUser
                          ? SelectableText(
                              mainContent,
                              style: TextStyle(
                                  fontSize: 13 * s, color: Colors.white),
                            )
                          : MarkdownRenderer(
                              text: mainContent,
                              useCard: false,
                              padding: EdgeInsets.zero,
                              fontScale: s,
                            ),

                    // ── 操作按钮 ──
                    if (mainContent.isNotEmpty && mainContent != '_thinking_')
                      _buildActions(isUser, mainContent),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14 * s,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
              child: Icon(Icons.person, size: 16 * s, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(bool isUser, String content) {
    final theme = Theme.of(context);
    final s = widget.fontScale;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isUser) ...[
            _ActionButton(
              icon: Icons.content_copy,
              tooltip: '复制',
              size: 12 * s,
              onTap: () {
                final clean = content.replaceFirst(RegExp(r'^:::reasoning\n[\s\S]*?\n:::\n?'), '');
                Clipboard.setData(ClipboardData(text: clean));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                );
              },
            ),
            if (widget.onRegenerate != null)
              _ActionButton(
                icon: Icons.refresh,
                tooltip: '重新生成',
                size: 12 * s,
                onTap: () => widget.onRegenerate?.call(),
              ),
          ],
          if (isUser) ...[
            _ActionButton(
              icon: Icons.undo,
              tooltip: '撤回',
              size: 12 * s,
              onTap: () => widget.onEdit?.call(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThinkingSection(String reasoningContent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 思考过程 header ──
        _buildCollapsibleHeader(
          expanded: _reasoningExpanded,
          onToggle: () => setState(() => _reasoningExpanded = !_reasoningExpanded),
          icon: Icons.psychology,
          color: const Color(0xFFF57C00),
          title: '思考过程',
          badge: _countTools(reasoningContent),
        ),
        if (_reasoningExpanded)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 280),
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFE082)),
            ),
            child: SingleChildScrollView(
              controller: _thinkingScrollCtrl,
              padding: const EdgeInsets.all(10),
              child: _buildThinkingContent(reasoningContent),
            ),
          ),
      ],
    );
  }

  int _countTools(String content) {
    return '🔧'.allMatches(content).length +
        '🧠'.allMatches(content).length +
        '📋'.allMatches(content).length;
  }

  Widget _buildThinkingContent(String text) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines.where((l) => l.trim().isNotEmpty).map((line) {
        final trimmed = line.trim();

        // 记忆工具
        if (trimmed.startsWith('🧠')) {
          final isRecall = trimmed.contains('回忆') || trimmed.contains('read');
          return _thinkingChip(
            icon: Icons.memory,
            text: isRecall ? '回忆全局记忆' : '写入全局记忆',
            bgColor: const Color(0xFFF3E5F5),
            fgColor: const Color(0xFF7B1FA2),
          );
        }

        // Skill
        if (trimmed.startsWith('📋')) {
          return _thinkingChip(
            icon: Icons.auto_stories,
            text: trimmed.replaceAll('📋', '').trim(),
            bgColor: const Color(0xFFE0F2F1),
            fgColor: const Color(0xFF00695C),
          );
        }

        // 工具调用
        if (trimmed.startsWith('🔧')) {
          return _thinkingChip(
            icon: Icons.touch_app,
            text: trimmed.replaceAll('🔧', '').trim(),
            bgColor: const Color(0xFFE3F2FD),
            fgColor: const Color(0xFF1565C0),
          );
        }

        // 工具结果
        if (trimmed.startsWith('✅')) {
          return _thinkingChip(
            icon: Icons.check_circle,
            text: trimmed.replaceAll('✅', '').trim(),
            bgColor: const Color(0xFFE8F5E9),
            fgColor: const Color(0xFF1B5E20),
          );
        }

        // 普通推理
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(line,
              style: TextStyle(
                  fontSize: 12 * widget.fontScale, color: const Color(0xFF795548), height: 1.5)),
        );
      }).toList(),
    );
  }

  Widget _thinkingChip({
    required IconData icon,
    required String text,
    required Color bgColor,
    required Color fgColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: fgColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14 * widget.fontScale, color: fgColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 11 * widget.fontScale,
                      fontWeight: FontWeight.w700,
                      color: fgColor,
                      fontFamily: 'monospace')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsibleHeader({
    required bool expanded,
    required VoidCallback onToggle,
    required IconData icon,
    required Color color,
    required String title,
    int badge = 0,
  }) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16 * widget.fontScale, color: color),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                    fontSize: 12 * widget.fontScale, color: color, fontWeight: FontWeight.w600)),
            if (badge > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$badge',
                    style: TextStyle(
                        fontSize: 11 * widget.fontScale,
                        color: color,
                        fontWeight: FontWeight.w700)),
              ),
            ],
            const SizedBox(width: 4),
            Icon(expanded ? Icons.expand_less : Icons.expand_more,
                size: 16 * widget.fontScale, color: color),
          ],
        ),
      ),
    );
  }
}

// ═══════ _ConversationHistoryPanel ═══════

class _ConversationHistoryPanel extends ConsumerWidget {
  final String moduleId;
  final VoidCallback onSessionTap;
  final VoidCallback onGlobalMemory;

  const _ConversationHistoryPanel({
    required this.moduleId,
    required this.onSessionTap,
    required this.onGlobalMemory,
  });

  void _showRenameDialog(
      BuildContext context, WidgetRef ref, String id, String currentTitle) {
    final ctrl = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新名称'),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              ref.read(renameSessionProvider)(id, v.trim());
            }
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                ref.read(renameSessionProvider)(id, ctrl.text.trim());
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(
      BuildContext context, WidgetRef ref, String id, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text('确定删除 "${title.isEmpty ? "新对话" : title}" 吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref.read(deleteSessionProvider)(id);
              Navigator.of(ctx).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  static String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessionsAsync = ref.watch(sessionListProvider);
    final activeId = ref.watch(activeSessionIdProvider);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('对话历史',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: '新建会话',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  ref.read(createSessionProvider)(null);
                  onSessionTap();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: sessionsAsync.when(
            loading: () => const Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) =>
                Center(child: Text('加载失败: $e', style: theme.textTheme.bodySmall)),
            data: (sessions) {
              if (sessions.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 36,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.3)),
                      const SizedBox(height: 8),
                      Text('暂无对话',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final s = sessions[index];
                  final isActive = s.id == activeId;
                  final msgCount = s.messages
                      .where((m) =>
                          m.role == agent.Role.user || m.role == agent.Role.assistant)
                      .length;
                  return ListTile(
                    selected: isActive,
                    selectedTileColor: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.3),
                    leading: Icon(
                      isActive
                          ? Icons.chat_bubble
                          : Icons.chat_bubble_outline,
                      size: 18,
                      color: isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      s.title.isEmpty ? '新对话' : s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      '$msgCount 条消息 · ${_formatRelativeTime(s.updatedAt)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    dense: true,
                    onTap: () {
                      ref.read(switchSessionProvider)(s.id);
                      onSessionTap();
                    },
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz, size: 16),
                      padding: EdgeInsets.zero,
                      onSelected: (action) {
                        if (action == 'rename') {
                          _showRenameDialog(context, ref, s.id, s.title);
                        } else if (action == 'delete') {
                          _showDeleteDialog(context, ref, s.id, s.title);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('重命名')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        ListTile(
          leading: Icon(Icons.memory, size: 20, color: theme.colorScheme.tertiary),
          title: Text('全局记忆',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text('查看和管理 AI 的记忆',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          dense: true,
          onTap: onGlobalMemory,
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ═══════ _ActionButton ═══════

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final double size;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    this.size = 12,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: size,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
      ),
    );
  }
}

// ═══════ _ToggleChip ═══════

class _ToggleChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;

  const _ToggleChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      avatar: Icon(icon, size: 16, color: value ? Colors.white : activeColor),
      label: Text(label,
          style: TextStyle(
              fontSize: 12, color: value ? Colors.white : null)),
      selected: value,
      selectedColor: activeColor,
      checkmarkColor: Colors.white,
      showCheckmark: false,
      onSelected: onChanged,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

// ═══════ _LocalChatMessagesNotifier ═══════

/// 本地消息列表状态管理器（使用 models.dart 的 ChatMessage）。
class _LocalChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  _LocalChatMessagesNotifier() : super([]);

  void addUser(String text) {
    state = [...state, ChatMessage(role: 'user', content: text)];
  }

  void addNotice(String text) {
    state = [...state, ChatMessage(role: 'system', content: text)];
  }

  /// 替换最后一条 AI 消息（流式场景）。
  void replaceLastAssistant(String text) {
    if (state.isNotEmpty && state.last.isAssistant) {
      final updated = [...state];
      updated[updated.length - 1] = ChatMessage(role: 'assistant', content: text);
      state = updated;
    } else {
      state = [...state, ChatMessage(role: 'assistant', content: text)];
    }
  }

  /// 追加一条 AI 消息（加载历史多轮对话用）。
  void addAssistant(String text) {
    state = [...state, ChatMessage(role: 'assistant', content: text)];
  }

  /// 移除最后一条 AI 消息（重新生成用）。
  void removeLastAssistant() {
    if (state.isNotEmpty && state.last.isAssistant) {
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

  void clear() => state = [];
}
