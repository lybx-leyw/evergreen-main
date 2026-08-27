/// Chat 控制器视图——统一的 AI 聊天界面。
///
/// 渲染层参考 [cp_evergreen_push] 的 AgentChatScreen 视觉风格：
/// - MarkdownBody + 数学公式 + 思维导图代码块
/// - 彩色 chip 标签式思考过程（🧠/🔧/✅/📋）
/// - 脉冲动画状态指示灯
/// - FilterChip 模式切换
/// - 文件附件 OCR
///
/// 保留所有现有功能：工作区/嵌入模式/EventBus/工具管理/多会话/5档思考。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_base/core/config/config.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/controller/controller.dart' show ControllerState;
import 'package:evergreen_base/core/agent/agent_factory.dart';
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/core/agent/agent_runtime.dart'
    show webSearchEnabledProvider, deepThinkingEnabledProvider,
         reasoningEffortProvider, validReasoningEfforts, agentRuntimeProvider;
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/providers.dart' show agentControllerProvider;
import 'package:evergreen_base/core/agent/session_manager.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/components/shared/workspace_file_download.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/models.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/mindmap_widget.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/workspace_drawer.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/system_drawer_section.dart';

import 'package:evergreen_base/renderer/page/file_viewer.dart';
import 'package:evergreen_base/renderer/page/global_memory_view.dart';
import 'package:evergreen_base/renderer/page/skill_management_view.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/interaction/chat/session_branch.dart';

/// AI 助手工作区的统一模块 id——Agent 写入端（agent_factory / main 等）
/// 与 UI 读取端（工作区抽屉 [WorkspaceDrawer]）都通过 [greenixWorkspaceDir] 指向同一目录。
///
/// 之所以抽出为公开常量：当 AI 助手以 slot 形式嵌入其它宿主模块（如 `showcase-v4`）时，
/// `widget.descriptor.id` 是宿主模块 id 而非 `ai-assistant`，若直接用它扫描工作区会命中空目录、
/// 表现为"似乎没有文件"（见 showcase-v4 反馈：slot 版工作区错误导航）。所有读写必须统一走本常量。
const String aiAssistantWorkspaceModuleId = 'ai-assistant';

// ── AgentAssembly 多会话数据结构 ──

/// 已保存的 AgentAssembly 会话快照。
class _AssemblySessionData {
  final String id;
  String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;

  _AssemblySessionData({
    required this.id,
    this.title = '新对话',
    required this.messages,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// 当前视图的消息列表（全屏模式）。
final _chatMessagesProvider =
    StateNotifierProvider<_LocalChatMessagesNotifier, List<ChatMessage>>(
        (ref) => _LocalChatMessagesNotifier());

/// 后台 tool 进程数（Task 三决策 3.2 UI 侧）——响应式计数，由
/// [_ChatControllerViewState._refreshBgProcessCount] 定时/事件刷新。
/// 数据源是 core 全局单例 [agent.agentProcessRegistry]（agent.dart barrel 已导出）。
final _bgProcessCountProvider =
    StateProvider<int>((ref) => agent.agentProcessRegistry.activeNames().length);

/// Chat 范式统一控制器视图——全屏 / 嵌入两用。
///
/// | 模式 | embedded | agentConfig | 行为 |
/// |------|----------|------------|------|
/// | 全屏 | false (默认) | null | Scaffold + 会话管理 + 全局 AgentRuntime |
/// | 嵌入(全局Agent) | true | null | 紧凑列布局，复用全局 AgentRuntime |
/// | 嵌入(隔离Agent) | true | Map (config) | 紧凑列布局 + AgentAssembly 隔离实例 + EventBus |

/// 将 [disabled] 工具集合应用到 [registry]，使「工具管理」面板的开关对
/// 使用该注册表的 Agent 真正生效。
///
/// 旧实现：面板只更新全局 [toolRegistryProvider] 与 [toolDisabledProvider]，
/// 但嵌入 Agent（如 /showcase-v4 的 ai-assistant 槽位）使用 [AgentAssembly]
/// 自建的隔离注册表，从不读取禁用集合 → 面板开关是摆设。此函数把禁用集合
/// 同步过去：先全量启用（保证「重新启用」也生效），再按集合关闭。
void applyToolDisabledSetToRegistry(agent.Registry registry, Set<String> disabled) {
  for (final t in registry.all()) {
    registry.enable(t.name);
  }
  for (final name in disabled) {
    if (registry.has(name)) registry.disable(name);
  }
}

/// 将「联网搜索」开关状态应用到注册表：开启 → 启用 `web_search`/`web_fetch`；
/// 关闭 → 禁用二者。`enable`/`disable` 对未注册名安全（仅操作 `_disabled` 集合），
/// 因此即使 `web_fetch` 在当前注册表未注册也不报错。
///
/// 旧实现：全屏 AI 助手的「联网搜索」开关（`webSearchEnabledProvider`）只更新
/// provider，而 main.dart 构建的全局 `toolRegistry`（全屏助手实际使用的注册表）
/// 从未监听它 → 开关对 `web_search` 工具毫无影响（开关是摆设）。本函数把它挂钩过去。
void applyWebSearchEnabledToRegistry(agent.Registry registry, bool enabled) {
  if (enabled) {
    registry.enable('web_search');
    registry.enable('web_fetch');
  } else {
    registry.disable('web_search');
    registry.disable('web_fetch');
  }
}

class ChatControllerView extends ConsumerStatefulWidget {
  final ModuleDescriptor descriptor;
  final bool embedded;
  final bool compact;
  final PageEventBus? pageEventBus;
  final Map<String, dynamic>? agentConfig;
  final String? slotKey;
  final double fontScale;
  /// 来自路由 query 的 AI 预填 prompt（classroom-modle 的 AI 笔记按钮带入）。
  final String? initialPrompt;

  const ChatControllerView({
    super.key,
    required this.descriptor,
    this.embedded = false,
    this.compact = false,
    this.pageEventBus,
    this.agentConfig,
    this.slotKey,
    this.fontScale = 1.0,
    this.initialPrompt,
  });

  @override
  ConsumerState<ChatControllerView> createState() =>
      _ChatControllerViewState();
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

  // ── AgentAssembly 多会话 ──
  final List<ChatMessage> _embeddedMessages = [];
  bool _embeddedInitialized = false;
  String _embeddedError = '';
  /// 已保存的会话列表（不含当前活跃会话）。
  final List<_AssemblySessionData> _assemblySavedSessions = [];
  /// 当前活跃会话 ID。
  String _assemblyActiveSessionId = '';
  /// 当前活跃会话标题（根据首条用户消息自动更新）。
  String _localSessionTitle = 'AI 助手';
  /// 当前会话是否已自动命名（仅对首条用户消息触发一次）。
  bool _assemblySessionAutoTitled = false;
  String _localEffort = 'medium';
  bool get _usingAssembly => _assembly != null;

  // ── 嵌入模式：EventBus 栏间通信 ──
  List<StreamSubscription<SlotEvent>>? _eventBusSubs;

  // ── 文件附件 ──
  String? _attachedFileName;

  /// 附件复制进工作区后的相对路径（Task 四决策 4.1）。null = 复制失败或未复制。
  String? _attachedRelPath;

  /// 附件复制进工作区失败的原因（成功为 null）。
  String? _attachedImportError;
  bool _attaching = false;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isRunning && mounted) setState(() => _elapsedSeconds++);
      // 后台 tool 进程数响应式刷新（Task 三决策 3.2 UI 侧）——复用既有 1s 定时器，
      // 不新增 Timer；计数变化才写 provider，避免无谓重建。
      if (mounted) _refreshBgProcessCount();
    });

    // 修复：把「联网搜索」开关（webSearchEnabledProvider）真正挂钩到全局工具
    // 注册表（toolRegistryProvider，全屏 AI 助手实际使用的注册表）。
    // 此前该开关只更新 provider，而 main.dart 的 toolRegistry 没有监听它，
    // 导致 联网搜索 切换对 web_search 工具毫无影响（开关是摆设）。
    // fireImmediately 让初始状态（默认关闭）也生效：web_search 默认禁用。
    ref.listenManual(webSearchEnabledProvider, (_, enabled) {
      applyWebSearchEnabledToRegistry(
        ref.read(toolRegistryProvider),
        enabled,
      );
    }, fireImmediately: true);

    if (widget.agentConfig != null) {
      // 有 agentConfig → 始终用 AgentAssembly（会话隔离 + 全局记忆共享）
      _initEmbeddedAgent();
    } else {
      Future.microtask(() => _subscribeToEvents());
    }

    // v5P：classroom-modle 的「生成 AI 笔记」按钮经路由 query 预填的 prompt，
    // 打开 AI 助手即自动发送（复用全局 AI）。
    if (widget.initialPrompt != null && widget.initialPrompt!.trim().isNotEmpty) {
      _inputCtrl.text = widget.initialPrompt!;
      Future.microtask(() {
        if (mounted) _sendMessage();
      });
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

  /// 刷新「后台 tool 进程数」provider（计数变化才写，避免无谓重建）。
  void _refreshBgProcessCount() {
    final n = agent.agentProcessRegistry.activeNames().length;
    if (ref.read(_bgProcessCountProvider) != n) {
      ref.read(_bgProcessCountProvider.notifier).state = n;
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
    if (widget.embedded && _assembly != null) {
      _subscribeToEmbeddedEvents();
      return;
    }

    final runtime = ref.read(agentEventStreamProvider);
    final messagesNotifier = ref.read(_chatMessagesProvider.notifier);

    _eventSub?.cancel();
    _eventSub = runtime.listen((event) {
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
            // show_file4u：注入文件卡片标记（Task 七 9.2），
            // 由 _MessageBubble 解析渲染「预览 + 下载」卡片。
            _handleShowFile4u(event.tool!);
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
            _pendingTimeline
                .writeln('\n$icon $label ${isMemoryTool ? '' : name}');
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
            final isSkillTool =
                name == 'run_skill' || name == 'list_skills';
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

        case agent.EventKind.turnDone:
          if (!mounted) return;
          messagesNotifier.replaceLastAssistant(_buildCombinedMessage());
          _stopIndicator();
          final currentId = ref.read(activeSessionIdProvider);
          if (currentId != null) {
            ref.read(saveCurrentSessionProvider)(currentId).catchError((_) {});
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

  // ── show_file4u 文件卡片（Task 七 9.2） ──

  /// 解析 show_file4u 工具参数（`arguments` 原始 JSON）→ 工作区相对路径。
  /// 工具名不符 / 参数非法 / 无 file_path 时静默返回 null（缺省零行为变化）。
  String? _parseShowFile4uPath(agent.ToolEventPayload tool) {
    if (tool.name != 'show_file4u') return null;
    try {
      final decoded = jsonDecode(tool.arguments);
      if (decoded is! Map<String, dynamic>) return null;
      final raw = decoded['file_path'];
      if (raw is! String || raw.trim().isEmpty) return null;
      return raw.trim();
    } catch (_) {
      return null;
    }
  }

  /// show_file4u 事件处理：把文件卡片标记注入待展示内容，由 [_MessageBubble]
  /// 解析渲染卡片（点击预览 → [FileViewer]，下载 → 共享固定目录下载函数）。
  /// 文件不存在 / 参数非法时静默跳过——工具侧会给模型返回错误，UI 不渲染破损卡片。
  void _handleShowFile4u(agent.ToolEventPayload tool) {
    final rel = _parseShowFile4uPath(tool);
    if (rel == null) return;
    final full = p.join(greenixWorkspaceDir(aiAssistantWorkspaceModuleId), rel);
    if (!File(full).existsSync()) return;
    if (_pendingAnswer.toString().contains('[📄 工作区文件: $rel]')) return; // 同文件防重复
    _pendingAnswer.write('\n[📄 工作区文件: $rel]');
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

  void _syncMessagesFromRuntime() {
    final ctrl = ref.read(agentControllerProvider);
    final session = ctrl.session;
    final notifier = ref.read(_chatMessagesProvider.notifier);
    notifier.clear();
    // R3 会话树：UI user 消息序号即轮次深度（loopId），据此填充分支切换条
    // 信息（siblingsOf/branchIndexIn 纯函数，零 Flutter 依赖）。
    var userOrdinal = 0;
    for (final m in session.messages) {
      if (m.content.isEmpty) continue;
      if (m.isUser) {
        final siblings = siblingsOf(session, userOrdinal);
        notifier.addUser(
          m.content,
          loopId: userOrdinal,
          branchCount: siblings.isEmpty ? null : siblings.length,
          branchIndex:
              siblings.isEmpty ? null : branchIndexIn(session, userOrdinal),
        );
        userOrdinal++;
      } else if (m.isAssistant) {
        notifier.addAssistant(
          _contentWithReasoning(m.reasoningContent, m.content),
        );
      }
    }
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

  // ── 编辑 & 重新生成 ──

  void _editUserMessage(int msgIndex) {
    // AgentAssembly 模式：编辑本地消息
    if (_usingAssembly) {
      if (msgIndex < 0 || msgIndex >= _embeddedMessages.length) return;
      final msg = _embeddedMessages[msgIndex];
      if (!msg.isUser) return;
      final text = msg.content;

      // UI 列表（仅 user/assistant 气泡）与 Agent Session（含 tool_call/tool_result
      // 消息）索引不对齐，必须按"第 N 个 user 消息"在两侧分别定位后再移除。
      // 计算 msgIndex 对应 UI 列表中的第几个 user 消息。
      int userOrdinal = 0;
      for (int i = 0; i <= msgIndex; i++) {
        if (_embeddedMessages[i].isUser) userOrdinal++;
      }
      final ctrl = _embeddedCtrl;
      if (ctrl != null) {
        final sessMsgs = ctrl.session.messages;
        int sessionUserIdx = -1;
        int count = 0;
        for (int i = 0; i < sessMsgs.length; i++) {
          if (sessMsgs[i].role == agent.Role.user) {
            count++;
            if (count == userOrdinal) {
              sessionUserIdx = i;
              break;
            }
          }
        }
        if (sessionUserIdx >= 0) {
          ctrl.session.removeFrom(sessionUserIdx);
        }
      }

      // 移除 UI 列表该 user 消息及其之后所有消息（与全屏模式 removeFrom 语义一致）
      _embeddedMessages.removeRange(msgIndex, _embeddedMessages.length);
      _inputCtrl.text = text;
      _inputCtrl.selection = TextSelection.collapsed(offset: text.length);
      FocusScope.of(context).requestFocus();
      if (mounted) setState(() {});
      return;
    }

    final messages = ref.read(_chatMessagesProvider);
    if (msgIndex < 0 || msgIndex >= messages.length) return;
    final msg = messages[msgIndex];
    if (!msg.isUser) return;

    // ── edit/branch 语义（R3 会话树形分支）──
    // 不再删除旧历史、不再新建会话：以该 user 消息所在轮为分叉点，在同一
    // 会话内 forkRound 出空 sibling（旧分支完整保留，可经分支切换条切回），
    // 原文回填输入框供编辑，发送后由轮次感知 Session.add 写入新分支。
    // 分叉是纯会话层操作，不触碰工作区文件（rewind/edit 不撤销工作区变更）。
    final ctrl = ref.read(agentControllerProvider);
    final session = ctrl.session;
    // 该 user 消息的轮次深度：UI 列表 user 序号即 loopId（每轮恰含一条
    // user 消息，见 session.dart 轮次边界约定）。
    final loopId = _countUserMessagesBefore(messages, msgIndex);
    final text = _stripAttachmentMarker(msg.content);
    if (!session.forkRound(loopId, text)) return;

    // 树内分叉：同一会话、不改变 activeSessionId —— 显式重建消息列表并
    // 保存新活动路径（双写一致：messages 与 tree 同步落盘）。
    _syncMessagesFromRuntime();
    ref.read(saveCurrentSessionProvider)(session.id);

    // 回填原文供编辑（剥离附件标记，避免把 [📎 …] 伪标记当正文重发）。
    _inputCtrl.text = text;
    _inputCtrl.selection = TextSelection.collapsed(offset: text.length);
    FocusScope.of(context).requestFocus();
  }

  /// 剥离用户消息末尾的附件标记 `[📎 ...]`（与 [_MessageBubble] 的展示逻辑一致）。
  static String _stripAttachmentMarker(String content) {
    final m = RegExp(r'\[📎 .+?\]$').firstMatch(content);
    if (m == null) return content;
    return content.substring(0, content.length - m.group(0)!.length).trim();
  }

  int _countUserMessagesBefore(List<ChatMessage> messages, int msgIndex) {
    int count = 0;
    for (int i = 0; i < msgIndex && i < messages.length; i++) {
      if (messages[i].isUser) count++;
    }
    return count;
  }

  /// R3 会话树：树内切换兄弟分支（左右环绕）。
  ///
  /// 切换不改变 activeSessionId（同一会话）：显式重建消息列表并保存新活动
  /// 路径（双写一致），随后滚到最新。
  void _switchBranchAt(int loopId, {required bool next}) {
    final ctrl = ref.read(agentControllerProvider);
    final session = ctrl.session;
    final target = switchSibling(session, loopId, next: next);
    if (target == null) return;
    _syncMessagesFromRuntime();
    ref.read(saveCurrentSessionProvider)(session.id);
    _scrollToBottom();
  }

  /// 渲染单条消息：气泡 + （user 消息所在轮有分支时）下方分支切换条
  /// 「◀ i/n ▶」（R3：切换条在消息下面，不是会话名下面）。
  Widget _buildMessageItem(ChatMessage msg, int index, List<ChatMessage> messages) {
    final lastAsstIdx = messages.lastIndexWhere((m) => m.isAssistant);
    final bubble = _MessageBubble(
      message: msg,
      fontScale: widget.fontScale,
      messageIndex: index,
      onEdit: msg.isUser ? () => _editUserMessage(index) : null,
      onRegenerate:
          msg.isAssistant && index == lastAsstIdx ? _regenerate : null,
    );
    final branchCount = msg.branchCount;
    if (!msg.isUser || branchCount == null || branchCount <= 1) {
      return bubble; // 无分叉 / 旧直线数据：零行为变化
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bubble,
        _BranchSwitcherBar(
          branchIndex: msg.branchIndex ?? 1,
          branchCount: branchCount,
          onPrev: () => _switchBranchAt(msg.loopId ?? 0, next: false),
          onNext: () => _switchBranchAt(msg.loopId ?? 0, next: true),
        ),
      ],
    );
  }

  /// 格式化日期为简短展示（今日 → 时间，昨日 → "昨天"，其他 → 月/日）。
  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff == 1) {
      return '昨天';
    } else {
      return '${dt.month}/${dt.day}';
    }
  }

  Future<void> _regenerate() async {
    if (_isRunning) return;

    // AgentAssembly 模式：从本地消息列表中找最后一条用户消息
    if (_usingAssembly) {
      if (_embeddedMessages.isEmpty) return;
      final lastUserIdx = _embeddedMessages.lastIndexWhere((m) => m.isUser);
      if (lastUserIdx < 0) return;
      // 剥离附件标记（[📎 …]），避免把伪标记当正文回填到编辑框。
      final text = _stripAttachmentMarker(_embeddedMessages[lastUserIdx].content);
      // 删除最后一条 assistant 回复 + 最后一条 user
      if (_embeddedMessages.isNotEmpty && _embeddedMessages.last.isAssistant) {
        _embeddedMessages.removeLast();
      }
      if (_embeddedMessages.isNotEmpty && _embeddedMessages.last.isUser) {
        _embeddedMessages.removeLast();
      }
      // 从 session 中移除最后一轮
      _embeddedCtrl?.session.removeLastTurn();
      _editUserText(text);
      if (mounted) setState(() {});
      await _sendMessage();
      return;
    }

    final messages = ref.read(_chatMessagesProvider);
    if (messages.isEmpty) return;
    final ctrl = ref.read(agentControllerProvider);
    final session = ctrl.session;
    final lastUserIdx = messages.lastIndexWhere((m) => m.isUser);
    if (lastUserIdx < 0) return;
    // R3：非破坏性重新生成——以最后一轮为分叉点开 sibling（旧回复完整保留
    // 在树中，可经分支切换条切回），原文本回填后重发。纯会话层操作，
    // 不触碰工作区。
    final loopId = _countUserMessagesBefore(messages, lastUserIdx);
    final text = _stripAttachmentMarker(messages[lastUserIdx].content);
    if (!session.forkRound(loopId, text)) return;
    _syncMessagesFromRuntime();
    ref.read(saveCurrentSessionProvider)(session.id);
    _editUserText(text);
    await _sendMessage();
  }

  void _editUserText(String text) {
    _inputCtrl.text = text;
    _inputCtrl.selection = TextSelection.collapsed(offset: text.length);
  }

  // ── 文件附件 ──

  Future<void> _pickFile() async {
    try {
      final result = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: [
          'jpg', 'jpeg', 'png', 'bmp', 'tiff', 'webp', 'pdf',
          'txt', 'md', 'json', 'csv', 'py', 'dart',
        ],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final path = file.path;
      if (path == null) return;

      setState(() {
        _attachedFileName = file.name;
        _attachedRelPath = null;
        _attachedImportError = null;
        _attaching = true;
      });

      // Task 四决策 4.1：上传任意文件 = 字节拷贝到 AI 助手工作区
      // （二进制/文本通吃；同名自动加时间戳/序号防覆盖；PathSandbox 校验）。
      // 发送时不再内联全文——AI 通过 read_file / ocr_file 读取工作区文件。
      final importResult = await agent.importToWorkspace(
        sourcePath: path,
        workspaceDir: greenixWorkspaceDir(aiAssistantWorkspaceModuleId),
      );
      if (!mounted) return;
      setState(() {
        _attachedRelPath = importResult.ok ? importResult.relativePath : null;
        _attachedImportError = importResult.ok ? null : importResult.error;
        _attaching = false;
      });
      if (!importResult.ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('文件未能复制到工作区：${importResult.error}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _attaching = false);
    }
  }

  // ── 发送消息 ──

  Future<void> _sendMessage() async {
    var text = _inputCtrl.text.trim();
    if (text.isEmpty && _attachedFileName == null) return;

    // Task 四决策 4.1：附件不再内联全文——发给 AI 的是「文件已入工作区」的位置提示，
    // 气泡（displayText）保持 `[📎 文件名]` 文件夹伪装，用户看到「上传文件给 AI 看」的体感。
    // 双轨：sendText（真实发给 AI 的 user message）与 displayText（UI 气泡）分离。
    String sendText = text;
    String displayText = text;
    final attachedName = _attachedFileName;
    if (attachedName != null) {
      if (text.isEmpty) text = '(文件)';
      final rel = _attachedRelPath;
      if (rel != null && rel.isNotEmpty) {
        sendText = '用户上传了文件: $attachedName，已保存到 AI 助手工作区：$rel。\n'
            '请阅读该文件后回答：文本文件请用 read_file 工具读取；'
            '图片/PDF 或扫描件请调用 ocr_file 工具识别内容。'
            '${text != '(文件)' ? '\n\n用户需求: $text' : ''}';
      } else {
        sendText = '用户上传了文件: $attachedName，但未能复制到工作区'
            '${_attachedImportError != null ? '（$_attachedImportError）' : ''}。'
            '${text != '(文件)' ? '\n\n用户需求: $text' : ''}';
      }
      displayText = '$text\n\n[📎 $attachedName]';
    }

    // AgentAssembly 模式（嵌入/全屏均可用）
    if (_embeddedCtrl != null) {
      if (_isRunning) return;
      _sendEmbedded(sendText, bubbleText: displayText);
      return;
    }

    if (ref.read(controllerStateProvider) == ControllerState.running) return;

    if (ref.read(activeSessionIdProvider) == null) {
      ref.read(createSessionProvider)(null);
    }

    final messagesNotifier = ref.read(_chatMessagesProvider.notifier);
    // R3 会话树：新 user 消息的分支切换条信息——发送后所在轮 = 当前 user 序号
    // （分叉续写时该轮已是活动 sibling，切换条立即可用；普通续写无兄弟 → null）。
    final session = ref.read(agentControllerProvider).session;
    final userOrdinal =
        messagesNotifier.state.where((m) => m.isUser).length;
    final siblings = siblingsOf(session, userOrdinal);
    messagesNotifier.addUser(
      displayText,
      loopId: userOrdinal,
      branchCount: siblings.isEmpty ? null : siblings.length,
      branchIndex:
          siblings.isEmpty ? null : branchIndexIn(session, userOrdinal),
    );
    _inputCtrl.clear();

    _pendingTimeline.clear();
    _pendingAnswer.clear();
    _textThrottleCount = 0;
    _hasBubble = false;
    _currentTurnUserText = sendText;
    _seenNotices.clear();

    setState(() {
      _attachedFileName = null;
      _attachedRelPath = null;
      _attachedImportError = null;
    });

    final webSearch = ref.read(webSearchEnabledProvider);
    final ctrl = ref.read(agentControllerProvider);
    ctrl.send(webSearch ? _withWebSearchDirective(sendText) : sendText);
  }

  /// 为「联网搜索」开启时的用户消息追加指令，确保 Agent 实际调用 web_search
  /// 工具（仅改变发给 Agent 的文本，不污染对话气泡的展示文本）。
  String _withWebSearchDirective(String text) =>
      '$text\n\n[联网搜索] 用户已开启联网搜索。请优先调用 web_search 工具获取'
      '最新、实时的信息后再回答；若问题涉及时效性内容（天气、新闻、股价、'
      '实时数据等），必须使用联网搜索。';

  // ── 嵌入模式：发送 ──

  /// 嵌入模式：发送。[text] 是发给 AI 的 user message；[bubbleText] 为 UI 气泡
  /// 展示文本（Task 四决策 4.1 附件双轨：缺省同 [text]，附件时为「用户文本 +
  /// [📎 文件名]」文件夹伪装）。
  void _sendEmbedded(String text, {String? bubbleText}) {
    final ctrl = _embeddedCtrl;
    if (ctrl == null) return;
    final bubble = bubbleText ?? text;
    setState(() {
      _embeddedMessages.add(ChatMessage(role: 'user', content: bubble));
      // 首条用户消息自动命名（仅一次）
      if (!_assemblySessionAutoTitled && _embeddedMessages.where((m) => m.isUser).length == 1) {
        final t = bubble.replaceAll('\n', ' ').trim();
        _localSessionTitle = t.length > 30 ? '${t.substring(0, 30)}...' : t;
        _assemblySessionAutoTitled = true;
      }
    });
    _startIndicator();
    _inputCtrl.clear();
    _pendingTimeline.clear();
    _pendingAnswer.clear();
    _textThrottleCount = 0;
    _hasBubble = false;
    _seenNotices.clear();
    final webSearch = ref.read(webSearchEnabledProvider);
    ctrl.send(webSearch ? _withWebSearchDirective(text) : text);
  }

  // ── 嵌入模式：初始化隔离 AgentAssembly ──

  Future<void> _initEmbeddedAgent() async {
    final cfg = widget.agentConfig;
    if (cfg == null) return;

    final moduleId =
        '${widget.descriptor.id}/${widget.slotKey ?? "embedded"}';

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY');
      if (apiKey.isEmpty) {
        if (mounted) {
          setState(() {
            _embeddedError = '未配置 API Key';
            _embeddedInitialized = true;
          });
        }
        return;
      }

      final model = getSetting(prefs, 'DEEPSEEK_MODEL');
      final baseUrl = getSetting(prefs, 'DEEPSEEK_BASE_URL');
      // A5 断链②接线：嵌入 Agent 创建时传入初始 thinking/effort——
      // 设置（DEEPSEEK_THINKING / DEEPSEEK_REASONING_EFFORT）优先，
      // effort 缺失/非法回退 UI 档位 _localEffort（与 AgentAssembly 面板一致）。
      final thinkingEnabled =
          getSetting(prefs, 'DEEPSEEK_THINKING').toLowerCase() != 'false';
      final effortSetting = getSetting(prefs, 'DEEPSEEK_REASONING_EFFORT');
      final initialEffort = validReasoningEfforts.contains(effortSetting)
          ? effortSetting
          : _localEffort;

      final provider = agent.DeepSeekProvider(
        dio: Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        )),
        apiKey: apiKey,
        model: model.isNotEmpty ? model : 'deepseek-v4-flash',
        baseUrl: baseUrl,
        thinking: thinkingEnabled ? 'enabled' : 'disabled',
      );
      if (initialEffort == 'off') {
        provider.setThinking('disabled');
      }
      provider.setReasoningEffort(initialEffort);

      final skillIdx = ref.read(skillIndexProvider);
      final memStore = ref.read(memoryStoreProvider);

      // 注入标准工具集（与全局 AgentRuntime 一致），preset 的 tools 策略再过滤。
      // 修复：此前未传 seedTools，导致嵌入 Agent 注册表为空、无法工具调用循环。
      final seedTools = AgentAssembly.buildStandardTools(
        globalStore: memStore,
        provider: provider,
        skillIndex: skillIdx,
        orchestrator: ref.read(dataOrchestratorProvider),
        // Task 四决策 4.2：嵌入 Agent 同样获得 ocr_file / check_ocr_ready 工具，
        // OCR Key 从设置读取（缺省回退环境变量）。
        ocrApiKey: getSetting(prefs, 'DEEPSEEK_OCR_API_KEY'),
      );

      final assembly = AgentAssembly.fromConfig(
        moduleId: moduleId,
        config: cfg,
        sharedProvider: provider,
        globalSkillIndex: skillIdx,
        globalMemoryStore: memStore,
        seedTools: seedTools,
      );

      // 修复：把用户禁用的工具集合同步到嵌入 Agent 的隔离注册表，
      // 否则「工具管理」面板的开关对嵌入 Agent 不生效（摆设）。
      applyToolDisabledSetToRegistry(
        assembly.controller.registry,
        ref.read(toolDisabledProvider),
      );
      // web_search 由 webSearchEnabledProvider 统一驱动，同步进嵌入注册表，
      // 使其与输入栏芯片/浮窗保持一致（反馈 125948）。
      applyWebSearchEnabledToRegistry(
        assembly.controller.registry,
        ref.read(webSearchEnabledProvider),
      );
      _assembly = assembly;
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _embeddedError = 'Agent 初始化失败: $e';
          _embeddedInitialized = true;
        });
      }
      return;
    }

    _subscribeToEmbeddedEvents();
    _setupEmbeddedEventBus(moduleId);

    // 设置初始会话 ID
    _assemblyActiveSessionId = _assembly!.controller.session.id;
    _assemblySessionAutoTitled = false;

    if (mounted) setState(() => _embeddedInitialized = true);
  }

  // ── AgentAssembly 多会话管理 ──

  /// 保存当前活跃会话到已保存列表，返回保存后的索引。
  void _saveCurrentAssemblySession({String? autoTitle}) {
    if (_embeddedMessages.isEmpty) return;
    final title = autoTitle ?? _localSessionTitle;
    // 查找是否已存在相同 ID 的会话（更新而非追加）
    final existingIdx = _assemblySavedSessions.indexWhere(
        (s) => s.id == _assemblyActiveSessionId);
    final data = _AssemblySessionData(
      id: _assemblyActiveSessionId,
      title: title,
      messages: List.from(_embeddedMessages),
    );
    if (existingIdx >= 0) {
      _assemblySavedSessions[existingIdx] = data;
    } else {
      _assemblySavedSessions.add(data);
    }
  }

  /// 切换到指定已保存的会话。
  void _switchAssemblySession(int index) {
    if (index < 0 || index >= _assemblySavedSessions.length) return;
    if (_isRunning) _embeddedCtrl?.cancel();

    // 保存当前会话
    _saveCurrentAssemblySession();

    // 加载目标会话
    final target = _assemblySavedSessions.removeAt(index);
    _embeddedCtrl?.newSession();
    _assemblyActiveSessionId = _embeddedCtrl!.session.id;

    // 恢复消息到 UI 和 Controller session
    for (final msg in target.messages) {
      if (msg.isUser) {
        final agentMsg = agent.Message.user(msg.content);
        _embeddedCtrl!.session.add(agentMsg);
      } else if (msg.isAssistant) {
        final agentMsg = agent.Message.assistant(msg.content);
        _embeddedCtrl!.session.add(agentMsg);
      }
    }

    setState(() {
      _embeddedMessages.clear();
      _embeddedMessages.addAll(target.messages);
      _localSessionTitle = target.title;
      _assemblyActiveSessionId = _embeddedCtrl!.session.id;
      _assemblySessionAutoTitled = target.title != '新对话';
    });
    _scrollToBottom();
  }

  /// 新建 AgentAssembly 会话（保存当前后创建新的）。
  void _newAssemblySession() {
    if (_isRunning) _embeddedCtrl?.cancel();
    _saveCurrentAssemblySession();
    _embeddedCtrl?.newSession();
    setState(() {
      _embeddedMessages.clear();
      _assemblyActiveSessionId = _embeddedCtrl!.session.id;
      _localSessionTitle = 'AI 助手';
      _assemblySessionAutoTitled = false;
    });
  }

  /// 删除已保存的会话。
  void _deleteAssemblySession(int index) {
    if (index < 0 || index >= _assemblySavedSessions.length) return;
    _assemblySavedSessions.removeAt(index);
    if (mounted) setState(() {});
  }

  void _subscribeToEmbeddedEvents() {
    final eventSink = _assembly?.eventSink;
    if (eventSink == null) return;
    _embeddedEventSub?.cancel();
    _embeddedEventSub = eventSink.stream.listen(_onEmbeddedAgentEvent);
  }

  void _onEmbeddedAgentEvent(agent.AgentEvent event) {
    if (!mounted) return;

    switch (event.kind) {
      case agent.EventKind.turnStarted:
        setState(() => _statusText = '思考中...');
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
          // show_file4u：注入文件卡片标记（Task 七 9.2，嵌入模式同款）。
          _handleShowFile4u(event.tool!);
          _pendingTimeline.writeln('\n🔧 调用 ${event.tool!.name}');
          _maybeUpdateEmbeddedBubble();
        }
        break;

      case agent.EventKind.toolResult:
        if (event.tool != null) {
          final ok = event.tool!.error == null;
          setState(() => _statusText =
              ok ? '✅ ${event.tool!.name}' : '❌ ${event.tool!.name}');
          final output =
              (event.tool!.output ?? event.tool!.error ?? '').trim();
          final preview =
              output.length > 200 ? '${output.substring(0, 200)}...' : output;
          _pendingTimeline.writeln('\n✅ ${event.tool!.name} → $preview');
          _replaceLastEmbeddedAssistant(_buildCombinedMessage());
        }
        break;

      case agent.EventKind.turnDone:
        if (!mounted) return;
        _replaceLastEmbeddedAssistant(_buildCombinedMessage());
        _stopIndicator();
        // 回合完成后保存当前会话（就地更新标题）
        _saveCurrentAssemblySession(autoTitle: _localSessionTitle);
        break;

      case agent.EventKind.notice:
        if (event.text != null && event.text!.isNotEmpty) {
          setState(() => _statusText = 'ℹ ${event.text}');
        }
        break;

      default:
        break;
    }

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
    if (_embeddedMessages.isNotEmpty &&
        _embeddedMessages.last.role == 'assistant') {
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

    const defaultEvents = [
      'answer_wrong',
      'card_forgotten',
      'word_completed'
    ];
    _eventBusSubs = [];
    for (final eventName in defaultEvents) {
      final sub = bus.on(eventName).listen((evt) {
        if (evt.sourceSlot == widget.slotKey) return;
        _autoTriggerOnEvent(evt, assemblyId);
      });
      _eventBusSubs!.add(sub);
    }
  }

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

    setState(() {
      _embeddedMessages.add(
          ChatMessage(role: 'user', content: '[系统自动] $prompt'));
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
    final workspace = widget.descriptor.workspace;
    final cfg = widget.agentConfig ?? const {};

    return ClipRect(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 工具栏（嵌入模式对齐全屏 AppBar 功能）──
          _buildEmbeddedToolbar(theme, workspace, cfg),
          if (_isRunning) _buildCompactStatusBar(theme),
          Expanded(
            child: messages.isEmpty
                ? _buildEmbeddedEmptyState(theme)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    itemCount: messages.length,
                    itemBuilder: (context, index) =>
                        _buildMessageItem(messages[index], index, messages),
                  ),
          ),
          _buildEmbeddedInputBar(theme),
        ],
      ),
    );
  }

  // ── 嵌入模式：工具栏（底部弹出替代抽屉）──

  Widget _buildEmbeddedToolbar(ThemeData theme, dynamic workspace, Map<String, dynamic> cfg) {
    final isDark = theme.brightness == Brightness.dark;
    final showMultiSession = cfg['multi_session'] != false; // 默认 true
    final showGlobalMemory = cfg['global_memory'] != false;  // 默认 true

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          if (showMultiSession)
            _ToolbarIconButton(
              icon: Icons.chat_bubble_outline,
              tooltip: '会话历史',
              onTap: () => _showSessionSheet(context),
            ),
          if (showGlobalMemory)
            _ToolbarIconButton(
              icon: Icons.memory,
              tooltip: '全局记忆',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GlobalMemoryView()),
              ),
            ),
          _ToolbarIconButton(
            icon: Icons.auto_fix_high,
            tooltip: '技能管理',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SkillManagementView()),
            ),
          ),
          if (workspace != null && workspace.enabled)
            _ToolbarIconButton(
              icon: Icons.folder_outlined,
              tooltip: '工作区',
              onTap: () => _showWorkspaceSheet(context, workspace),
            ),
          _ToolbarIconButton(
            icon: Icons.handyman_outlined,
            tooltip: '工具选项',
            onTap: () => _showToolsPopup(context),
          ),
          // Task 三决策 3.2：后台 tool 进程入口（嵌入紧凑工具栏，图标式）。
          _ToolbarIconButton(
            icon: Icons.ad_units,
            tooltip: '后台 tool 进程',
            onTap: () => _showProcessesPopup(context),
          ),
          const Spacer(),
          if (cfg['multi_session'] != false)
            IconButton(
              icon: const Icon(Icons.add, size: 16),
              tooltip: '新建会话',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                if (widget.embedded && widget.agentConfig != null) {
                  _newAssemblySession();
                } else {
                  ref.read(createSessionProvider)(null);
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            tooltip: '清空对话',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              if (widget.embedded && widget.agentConfig != null) {
                _newAssemblySession();
              } else {
                ref.read(_chatMessagesProvider.notifier).clear();
                ref.read(agentControllerProvider).newSession();
              }
            },
          ),
        ],
      ),
    );
  }

  bool get _isEmbedded => widget.embedded;

  void _showSessionSheet(BuildContext context) {
    final theme = Theme.of(context);

    // ── AgentAssembly 模式：隔离会话管理，不读取全局 session provider ──
    if (_usingAssembly) {
      _showEmbeddedSessionSheet(context, theme);
      return;
    }

    // ── 全屏模式：使用全局 session provider ──
    final sessionsAsync = ref.read(sessionListProvider);
    final activeId = ref.read(activeSessionIdProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.85,
          minChildSize: 0.3,
          builder: (ctx, scrollCtrl) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: theme.colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('对话历史', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.add, size: 20), tooltip: '新建会话',
                        onPressed: () { ref.read(createSessionProvider)(null); Navigator.pop(ctx); },
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: sessionsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    error: (e, _) => Center(child: Text('加载失败: $e')),
                    data: (sessions) {
                      if (sessions.isEmpty) return Center(child: Text('暂无对话', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)));
                      return ListView.builder(
                        controller: scrollCtrl,
                        itemCount: sessions.length,
                        itemBuilder: (_, i) {
                          final s = sessions[i];
                          final isActive = s.id == activeId;
                          // R3 会话树：会话行分支标签 = 树内分支计数（旧 A6
                          // fork 数据走 branchFamilyOf 兜底）。
                          final branchCount = branchLabelCount(sessions, s);
                          return ListTile(
                            selected: isActive,
                            selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                            title: Text(s.title.isEmpty ? '新对话' : s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${s.messages.length} 条消息${branchCount > 1 ? ' · 分支 $branchCount' : ''}', style: const TextStyle(fontSize: 12)),
                            dense: true,
                            onTap: () { ref.read(switchSessionProvider)(s.id); Navigator.pop(ctx); },
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_horiz, size: 16),
                              color: theme.colorScheme.surfaceContainerLowest,
                              onSelected: (action) {
                                if (action == 'rename') _showRenameSheet(ctx, s.id, s.title);
                                else if (action == 'delete') ref.read(deleteSessionProvider)(s.id);
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
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.memory, size: 18, color: theme.colorScheme.tertiary),
                  title: const Text('全局记忆', style: TextStyle(fontSize: 13)),
                  dense: true,
                  onTap: () { Navigator.pop(ctx); Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GlobalMemoryView())); },
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 嵌入模式会话面板——隔离于全屏 AI 助手的全局会话列表。
  void _showEmbeddedSessionSheet(BuildContext context, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.8,
          minChildSize: 0.3,
          builder: (ctx, scrollCtrl) => SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖动条
                Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: theme.colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 16),
                Icon(Icons.chat_bubble_outline, size: 32, color: theme.colorScheme.primary),
                const SizedBox(height: 8),
                Text('会话管理', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('当前组件实例的会话独立于全屏 AI 助手',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 20),
                // 当前会话信息
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.chat, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_localSessionTitle,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 新建会话
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _newAssemblySession();
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建会话'),
                  ),
                ),
                if (_assemblySavedSessions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  ..._assemblySavedSessions.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final s = entry.value;
                    final msgCount = s.messages
                        .where((m) => m.isUser || m.isAssistant)
                        .length;
                    return ListTile(
                      leading: const Icon(Icons.history, size: 18),
                      title: Text(s.title, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                          '$msgCount 条消息 · ${_formatDate(s.createdAt)}',
                          style: const TextStyle(fontSize: 11)),
                      dense: true,
                      onTap: () {
                        Navigator.pop(ctx);
                        _switchAssemblySession(idx);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16),
                        onPressed: () => _deleteAssemblySession(idx),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 12),
                const Divider(),
                ListTile(
                  leading: Icon(Icons.memory, size: 18, color: theme.colorScheme.tertiary),
                  title: const Text('全局记忆（共享）', style: TextStyle(fontSize: 13)),
                dense: true,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GlobalMemoryView()));
                },
              ),
            ],
          ),
        ),
      );
    },
  );
  }

  void _showRenameSheet(BuildContext ctx, String id, String currentTitle) {
    final ctrl = TextEditingController(text: currentTitle);
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: '输入新名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('取消')),
          TextButton(onPressed: () { if (ctrl.text.trim().isNotEmpty) ref.read(renameSessionProvider)(id, ctrl.text.trim()); Navigator.pop(dCtx); }, child: const Text('确认')),
        ],
      ),
    );
  }

  void _showWorkspaceSheet(BuildContext context, dynamic workspace) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.85,
          minChildSize: 0.3,
          builder: (ctx, scrollCtrl) {
            return WorkspaceDrawer(
              workspace: workspace,
              moduleId: aiAssistantWorkspaceModuleId,
              onFileTap: (file) {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => FileViewer(file: file)));
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmbeddedEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.psychology_outlined,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.4)),
          const SizedBox(height: 6),
          Text('就绪，输入消息...',
              style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildCompactStatusBar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: theme.colorScheme.primaryContainer,
      child: Row(
        children: [
          const SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentTool.isNotEmpty ? _statusText : _statusText,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          if (_elapsedSeconds > 0)
            Text('${_elapsedSeconds}s',
                style: TextStyle(fontSize: 10, color: theme.colorScheme.onPrimaryContainer)),
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
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.handyman_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant),
            tooltip: '工具选项',
            onPressed: () => _showToolsPopup(context),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              enabled: !_isRunning,
              style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: _isRunning ? '回复中...' : '输入消息...',
                hintStyle:
                    TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
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
              color: theme.colorScheme.primary,
            ),
            onPressed: _isRunning
                ? () => _embeddedCtrl?.cancel()
                : () => _sendMessage(),
          ),
        ],
      ),
    );
  }

  // ── 全屏模式构建 ──

  @override
  Widget build(BuildContext context) {
    // 嵌入模式
    if (widget.embedded) {
      if (widget.agentConfig != null && !_embeddedInitialized) {
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
                const Icon(Icons.warning_amber,
                    size: 28, color: Colors.orange),
                const SizedBox(height: 8),
                Text(_embeddedError,
                    style:
                        TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        );
      }
      return _buildEmbeddedContent();
    }

    // AgentAssembly 全屏模式（独立会话 + 全局记忆共享）
    if (_usingAssembly) {
      return _buildAssemblyFullScaffold();
    }

    // ── 全屏模式 ──
    ref.listen<String?>(activeSessionIdProvider, (prev, next) {
      if (prev == next) return;
      _syncMessagesFromRuntime();
      // Bug 8：切换/分叉/新建会话后自动滑到最新（_scrollToBottom 内置
      // postFrameCallback）。长会话 ListView 懒加载下 maxScrollExtent 首次估算
      // 可能偏小，延迟再滚一次确保到底。
      _scrollToBottom();
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _scrollToBottom();
      });
    });

    final messages = ref.watch(_chatMessagesProvider);
    final theme = Theme.of(context);
    final workspace = widget.descriptor.workspace;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: '会话历史',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ref.watch(activeSessionTitleProvider),
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // R3 会话树：分支切换条不再放在会话名下面，改在分叉的 user
            // 消息下方渲染（见 _buildMessageItem / _BranchSwitcherBar）。
          ],
        ),
        centerTitle: false,
        actions: [
          if (workspace != null)
            IconButton(
              icon: const Icon(Icons.folder_outlined),
              tooltip: '工作区',
              onPressed: () =>
                  _scaffoldKey.currentState?.openEndDrawer(),
            ),
          IconButton(
            icon: const Icon(Icons.handyman_outlined),
            tooltip: '工具选项',
            onPressed: () => _showToolsPopup(context),
          ),
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            tooltip: '技能管理',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const SkillManagementView()),
            ),
          ),
        ],
      ),
      drawer: _buildHistoryDrawer(context, theme),
      endDrawer: workspace != null
          ? Drawer(
              child: WorkspaceDrawer(
                workspace: workspace,
                moduleId: aiAssistantWorkspaceModuleId,
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
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) =>
                        _buildMessageItem(messages[index], index, messages),
                  ),
          ),
          if (_isRunning) _buildStatusBar(theme),
          _buildInputBar(theme),
        ],
      ),
    );
  }

  // ── AgentAssembly 全屏模式 Scaffold ──
  /// 使用本地状态（_embeddedMessages, _localSessionTitle 等）构建完整
  /// Scaffold，与全局 AgentRuntime 解耦，保持会话隔离 + 全局记忆共享。
  Widget _buildAssemblyFullScaffold() {
    final messages = _embeddedMessages;
    final theme = Theme.of(context);
    final workspace = widget.descriptor.workspace;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: '会话历史',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(
          _localSessionTitle,
          style:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        actions: [
          if (workspace != null)
            IconButton(
              icon: const Icon(Icons.folder_outlined),
              tooltip: '工作区',
              onPressed: () =>
                  _scaffoldKey.currentState?.openEndDrawer(),
            ),
          IconButton(
            icon: const Icon(Icons.handyman_outlined),
            tooltip: '工具选项',
            onPressed: () => _showToolsPopup(context),
          ),
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            tooltip: '技能管理',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const SkillManagementView()),
            ),
          ),
        ],
      ),
      drawer: _buildAssemblyHistoryDrawer(context, theme),
      endDrawer: workspace != null
          ? Drawer(
              child: WorkspaceDrawer(
                workspace: workspace,
                moduleId: aiAssistantWorkspaceModuleId,
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
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) =>
                        _buildMessageItem(messages[index], index, messages),
                  ),
          ),
          if (_isRunning) _buildStatusBar(theme),
          _buildAssemblyInputBar(theme),
        ],
      ),
    );
  }

  // ── AgentAssembly 全屏模式：左侧抽屉 ──

  Widget _buildAssemblyHistoryDrawer(BuildContext context, ThemeData theme) {
    return Drawer(
      width: 300,
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 48, 8, 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              border: Border(
                bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 0.5),
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
                  icon: const Icon(Icons.add_comment, size: 20),
                  tooltip: '新建对话',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _newAssemblySession();
                    _scaffoldKey.currentState?.closeDrawer();
                  },
                ),
              ],
            ),
          ),
          // 当前活跃会话
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.chat, size: 20,
                      color: theme.colorScheme.primary),
                  title: Text(
                    _localSessionTitle,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${_embeddedMessages.where((m) => m.isUser || m.isAssistant).length} 条消息 · 独立会话',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                const Divider(),
                // 全局记忆入口
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.psychology_outlined, size: 20),
                  title: const Text('全局记忆（共享）'),
                  subtitle: const Text('跨插件共享的知识库'),
                  onTap: () {
                    _scaffoldKey.currentState?.closeDrawer();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const GlobalMemoryView()),
                    );
                  },
                ),
              ],
            ),
          ),
          // 已保存会话列表
          if (_assemblySavedSessions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('${_assemblySavedSessions.length} 个已保存会话',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _assemblySavedSessions.length,
                itemBuilder: (context, index) {
                  final s = _assemblySavedSessions[index];
                  final msgCount = s.messages
                      .where((m) => m.isUser || m.isAssistant)
                      .length;
                  return ListTile(
                    leading: const Icon(Icons.history, size: 18),
                    title: Text(s.title,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '$msgCount 条消息 · ${_formatDate(s.createdAt)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    dense: true,
                    onTap: () {
                      _switchAssemblySession(index);
                      _scaffoldKey.currentState?.closeDrawer();
                    },
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 16),
                      color: theme.colorScheme.surfaceContainerLowest,
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'delete', child: Text('删除')),
                      ],
                      onSelected: (action) {
                        if (action == 'delete')
                          _deleteAssemblySession(index);
                      },
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            Expanded(
              child: Center(
                child: Text('暂无已保存的对话',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            ),
          ],
          const Divider(height: 1),
          // 清空当前对话
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(Icons.delete_outline,
                size: 20, color: Colors.red.shade400),
            title: Text('清空当前对话',
                style: TextStyle(color: Colors.red.shade400)),
            onTap: () {
              _newAssemblySession();
              _scaffoldKey.currentState?.closeDrawer();
            },
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '会话独立于全屏 AI 助手',
              style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          // 系统功能分区：原 AI 视图窄轨（ModeRail）按钮收进此抽屉。
          const SystemDrawerSection(),
        ],
      ),
    );
  }

  // ── AgentAssembly 全屏模式：输入栏 ──

  Widget _buildAssemblyInputBar(ThemeData theme) {
    // 竖版（手机窄屏）：输入栏紧凑化，减少竖向占用。
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
          : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
              color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 模式切换按钮行（窄屏可水平滚动，避免右侧溢出）
            Padding(
              padding: EdgeInsets.only(bottom: compact ? 4 : 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  if (widget.descriptor.workspace != null) ...[
                    _ToggleChip(
                      icon: Icons.folder_outlined,
                      label: '工作区',
                      value: false,
                      onChanged: (_) =>
                          _scaffoldKey.currentState?.openEndDrawer(),
                      activeColor: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                  ],
                  _ToggleChip(
                    icon: Icons.language,
                    label: '联网搜索',
                    value: ref.watch(webSearchEnabledProvider),
                    onChanged: (v) => _setWebSearchEnabled(v, ref),
                    activeColor: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  _EffortSelector(
                    effort: _localEffort,
                    onChanged: (v) {
                      setState(() => _localEffort = v);
                      // A5 断链②接线：同时驱动嵌入 Agent 的 provider
                      // （_embeddedCtrl.provider 即 _initEmbeddedAgent 传入的共享
                      // DeepSeekProvider 实例），使档位真实作用于请求参数。
                      final ctrl = _embeddedCtrl;
                      if (ctrl != null && ctrl.provider is agent.DeepSeekProvider) {
                        final provider = ctrl.provider as agent.DeepSeekProvider;
                        if (v == 'off') {
                          provider.setThinking('disabled');
                          provider.setReasoningEffort('off');
                        } else {
                          provider.setThinking('enabled');
                          provider.setReasoningEffort(v);
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  _ToggleChip(
                    icon: Icons.handyman_outlined,
                    label: '工具',
                    value: false,
                    onChanged: (_) => _showToolsPopup(context),
                    activeColor: const Color(0xFF2E7D32),
                  ),
                  const SizedBox(width: 6),
                  // Task 三决策 3.2：后台 tool 进程计数入口（点击弹窗管理）。
                  const _BgProcessChip(),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    tooltip: '技能管理',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) =>
                              const SkillManagementView()),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.delete_outline, size: 18),
                    tooltip: '清空对话',
                    onPressed: _newAssemblySession,
                    visualDensity: VisualDensity.compact,
                  ),
                  ],
                ),
              ),
            ),
            // 输入行
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    enabled: !_isRunning,
                    decoration: InputDecoration(
                      hintText: _isRunning
                          ? 'AI 正在思考...'
                          : '输入你的问题...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: compact ? 14 : 20,
                        vertical: compact ? 8 : 12,
                      ),
                      filled: true,
                      fillColor: theme
                          .colorScheme.surfaceContainerHighest,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted:
                        _isRunning ? null : (_) => _sendMessage(),
                    minLines: 1,
                    maxLines: 4,
                  ),
                ),
                // 附件状态
                if (_attachedFileName != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Tooltip(
                      message: _attachedFileName ?? '文件',
                      child: Chip(
                        avatar: const Icon(
                            Icons.insert_drive_file,
                            size: 16),
                        label: Text(
                          (_attachedFileName ?? '文件').length > 12
                              ? '...${(_attachedFileName ?? '文件').substring((_attachedFileName ?? '文件').length - 12)}'
                              : _attachedFileName ?? '文件',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onDeleted: () {
                          setState(() {
                            _attachedFileName = null;
                            _attachedRelPath = null;
                            _attachedImportError = null;
                          });
                        },
                        deleteIcon: const Icon(Icons.close,
                            size: 14),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4),
                      ),
                    ),
                  ),
                if (_attaching)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2)),
                  )
                else
                  IconButton(
                    icon: Icon(Icons.attach_file,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant),
                    tooltip: '上传文件',
                    onPressed: _pickFile,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    _isRunning ? Icons.stop : Icons.send,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  tooltip: _isRunning ? '停止' : '发送',
                  onPressed: _isRunning
                      ? () => _embeddedCtrl?.cancel()
                      : () => _sendMessage(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 工具管理面板 ──

  /// 以「浮窗」形式展示 Agent 工具选项，而非底部抽屉。
  ///
  /// 旧实现用 [showModalBottomSheet] + [DraggableScrollableSheet]：面板完全上拉到
  /// [DraggableScrollableSheet.maxChildSize] 后，拖拽手势识别器会抢占指针，
  /// 内部 [Switch]/[ListTile] 的 tap 事件被吞掉，导致开关点不了（反馈 125948 Part 1）。
  /// 改为 [showDialog] + [Dialog] 浮动卡片后不再有任何拖拽手势拦截，开关全部可点击。
  void _showToolsPopup(BuildContext context) {
    final registry = ref.read(toolRegistryProvider);
    final tools = registry.all()
      ..sort((a, b) => a.name.compareTo(b.name));
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final disabled = ref.watch(toolDisabledProvider);
            final webSearchOn = ref.watch(webSearchEnabledProvider);
            // web_search 的开关由 webSearchEnabledProvider 统一驱动（与输入栏
            // 「联网搜索」芯片共用同一响应式真相源），其余工具由 toolDisabledProvider
            // 决定。两者分开取，确保芯片 ↔ 浮窗实时双向同步。
            bool isToolOn(String name) =>
                name == 'web_search' ? webSearchOn : !disabled.contains(name);
            final enabledCount = tools.where((t) => isToolOn(t.name)).length;
            return Dialog(
              insetPadding: const EdgeInsets.all(24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 440, maxHeight: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Icon(Icons.handyman_outlined,
                              size: 20,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Agent 工具选项',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(
                                      fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text('$enabledCount/${tools.length} 已启用',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme
                                      .colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    const Divider(),
                    Flexible(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: tools.length,
                        itemBuilder: (ctx, index) {
                          final tool = tools[index];
                          final isEnabled = isToolOn(tool.name);
                          final toolIsEssential =
                              isEssentialTool(tool.name);
                          final isWebSearch = tool.name == 'web_search';
                          return _ToolTile(
                            name: tool.name,
                            description: tool.description,
                            readOnly: tool.readOnly,
                            enabled: isEnabled,
                            isEssential: toolIsEssential,
                            onToggle: (v) {
                              // web_search 由 webSearchEnabledProvider 统一驱动，
                              // 与输入栏「联网搜索」芯片共用同一响应式真相源，保证
                              // 浮窗开关 ↔ 芯片 实时双向同步（反馈 125948）。
                              if (isWebSearch) {
                                _setWebSearchEnabled(v, ref);
                                return;
                              }
                              if (!v && toolIsEssential) {
                                _confirmDisableEssential(
                                    ctx, tool.name, () {
                                  _applyToggle(registry, tool.name, v,
                                      disabled, ref);
                                });
                                return;
                              }
                              _applyToggle(registry, tool.name, v,
                                  disabled, ref);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static const _essentialWarnings = <String, String>{
    'read_global_memory': 'Agent 将无法读取跨会话记忆，\n失去个性化上下文和用户偏好。',
    'write_global_memory': 'Agent 将无法记住你的偏好和特质，\n所有对话结束后信息丢失。',
    'read_file': 'Agent 将无法访问工作区中的文件，\n无法读取代码、文档等内容。',
    'write_file': 'Agent 将无法创建或编辑工作区中的文件，\n无法保存任何产出。',
  };

  void _confirmDisableEssential(
      BuildContext ctx, String toolName, VoidCallback onConfirm) {
    final warning =
        _essentialWarnings[toolName] ?? '该工具是 Agent 基础功能的一部分。';
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber,
                color: Colors.amber.shade700, size: 24),
            const SizedBox(width: 8),
            const Text('确认禁用核心工具',
                style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('「$toolName」是 Agent 的基础功能工具：',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.red.withValues(alpha: 0.15)),
              ),
              child: Text(warning,
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.red.shade700)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              onConfirm();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            child: const Text('仍然禁用'),
          ),
        ],
      ),
    );
  }

  void _applyToggle(agent.Registry registry, String name, bool enable,
      Set<String> disabled, WidgetRef r) {
    final prefs = r.read(sharedPreferencesProvider);
    final newDisabled = Set<String>.from(disabled);
    if (enable) {
      registry.enable(name);
      newDisabled.remove(name);
    } else {
      registry.disable(name);
      newDisabled.add(name);
    }
    prefs.setString('tool_disabled', newDisabled.join(','));
    r.read(toolDisabledProvider.notifier).state = newDisabled;

    // 同步到嵌入 Agent 的隔离注册表（如 /showcase-v4 的 ai-assistant 槽位），
    // 使面板开关对嵌入 Agent 实时生效，而非只对全局 Agent 生效。
    // 注：web_search 不在此处理（由 _setWebSearchEnabled 统一驱动，避免双真相源）。
    final embedded = _assembly?.controller.registry;
    if (embedded != null) {
      applyToolDisabledSetToRegistry(embedded, newDisabled);
    }
  }

  /// 设置「联网搜索」开关的统一入口，是 web_search 工具启用态的**唯一响应式
  /// 真相源**（与输入栏「联网搜索」芯片共用 webSearchEnabledProvider）。
  ///
  /// 同时把改动落到：① 全局 toolRegistryProvider；② 嵌入 Agent 的隔离注册表，
  /// 让输入栏芯片与「工具选项」浮窗的 web_search 开关在任一端改变后都即时一致
  /// （反馈 125948：芯片 ↔ 浮窗 双向实时同步）。
  ///
  /// web_search 不再写入 toolDisabledProvider，避免「双真相源」脱节。
  void _setWebSearchEnabled(bool enabled, WidgetRef ref) {
    ref.read(webSearchEnabledProvider.notifier).state = enabled;
    // 从禁用集合剔除 web_search，保持单一真相源。
    final cleanDisabled =
        Set<String>.from(ref.read(toolDisabledProvider))..remove('web_search');
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString('tool_disabled', cleanDisabled.join(','));
    ref.read(toolDisabledProvider.notifier).state = cleanDisabled;

    applyWebSearchEnabledToRegistry(ref.read(toolRegistryProvider), enabled);
    final embedded = _assembly?.controller.registry;
    if (embedded != null) {
      applyWebSearchEnabledToRegistry(embedded, enabled);
    }
  }

  /// 应用思考档位（Task 五 Bug 6 / A5 断链①运行期接线）：
  /// ① 写全局 [reasoningEffortProvider]（UI 响应式真相源）；
  /// ② 经 [agentProviderProvider]（app_bootstrap 注入的主 DeepSeekProvider，
  /// 类型即 DeepSeekProvider，无需降级）同步 setThinking/setReasoningEffort，
  /// 使档位真实作用于请求参数（agent_runtime 的 reasoningEffortProvider 监听
  /// 只服务于 agentRuntimeProvider 自建实例，主路径不依赖它——见 A5 报告 §五-1）；
  /// ③ 对齐 agent_runtime L169-176 的系统提示词强化（effortDescriptions）——
  /// 主 Controller 创建时未自定义 systemPrompt，同步安全。
  void _applyEffort(String v, WidgetRef ref) {
    ref.read(reasoningEffortProvider.notifier).state = v;
    final p = ref.read(agentProviderProvider);
    if (v == 'off') {
      p.setThinking('disabled');
      p.setReasoningEffort('off');
    } else {
      p.setThinking('enabled');
      p.setReasoningEffort(v);
    }
    final ctrl = ref.read(agentControllerProvider);
    if (v == 'off') {
      ctrl.setSystemPrompt(agent.defaultSystemPrompt);
    } else {
      const effortDescriptions = <String, String>{
        'low': '请简要思考后回答。',
        'medium': '请适度思考后回答。',
        'high': '请深入思考后再回答。',
        'max': '请做最全面的思考，考虑多种方案和边界情况后再回答。',
      };
      ctrl.setSystemPrompt(agent.defaultSystemPrompt +
          '\n\n深度思考模式：$v 级。${effortDescriptions[v] ?? ''}');
    }
  }

  // ── 状态指示灯 ──

  Widget _buildStatusBar(ThemeData theme) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, _) {
        final opacity = 0.4 + _pulseAnim.value * 0.6;
        // 竖版（手机窄屏）：状态条紧凑化。
        final compact = MediaQuery.sizeOf(context).width < 600;
        return Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: compact ? 2 : 6),
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 4 : 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: opacity * 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const SizedBox(
                  width: 12,
                  height: 12,
                  child:
                      CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentTool.isNotEmpty
                      ? '$_statusText (${_elapsedSeconds}s)'
                      : '$_statusText (${_elapsedSeconds}s)',
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.primary),
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
    final isRunning =
        ref.watch(controllerStateProvider) == ControllerState.running;
    final webSearch = ref.watch(webSearchEnabledProvider);
    final effort = ref.watch(reasoningEffortProvider);
    final hasWorkspace = widget.descriptor.workspace != null;
    // 竖版（手机窄屏）：输入栏紧凑化，减少竖向占用。
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Container(
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
          : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
              color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 模式切换按钮行（窄屏可水平滚动，避免右侧溢出）
            Padding(
              padding: EdgeInsets.only(bottom: compact ? 4 : 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasWorkspace) ...[
                      _ToggleChip(
                        icon: Icons.folder_outlined,
                        label: '工作区',
                        value: false,
                        onChanged: (_) =>
                            _scaffoldKey.currentState?.openEndDrawer(),
                        activeColor: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                    ],
                    _ToggleChip(
                      icon: Icons.language,
                      label: '联网搜索',
                      value: webSearch,
                      onChanged: (v) => _setWebSearchEnabled(v, ref),
                      activeColor: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    _EffortSelector(
                      effort: effort,
                      onChanged: (v) => _applyEffort(v, ref),
                    ),
                    const SizedBox(width: 6),
                    _ToggleChip(
                      icon: Icons.handyman_outlined,
                      label: '工具',
                      value: false,
                      onChanged: (_) => _showToolsPopup(context),
                      activeColor: const Color(0xFF2E7D32),
                    ),
                    const SizedBox(width: 6),
                    // Task 三决策 3.2：后台 tool 进程计数入口（点击弹窗管理）。
                    const _BgProcessChip(),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      tooltip: '技能管理',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const SkillManagementView()),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.delete_outline, size: 18),
                      tooltip: '清空对话',
                      onPressed: () {
                        ref
                            .read(_chatMessagesProvider.notifier)
                            .clear();
                        ref
                            .read(agentControllerProvider)
                            .newSession();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
            // 输入行
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    enabled: !isRunning,
                    decoration: InputDecoration(
                      hintText: isRunning
                          ? 'AI 正在思考...'
                          : '输入你的问题...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: compact ? 14 : 20,
                        vertical: compact ? 8 : 12,
                      ),
                      filled: true,
                      fillColor: theme
                          .colorScheme.surfaceContainerHighest,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted:
                        isRunning ? null : (_) => _sendMessage(),
                    minLines: 1,
                    maxLines: 4,
                  ),
                ),
                // 附件状态
                if (_attachedFileName != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Tooltip(
                      message: _attachedFileName ?? '文件',
                      child: Chip(
                        avatar: const Icon(
                            Icons.insert_drive_file,
                            size: 16),
                        label: Text(
                          (_attachedFileName ?? '文件').length > 12
                              ? '...${(_attachedFileName ?? '文件').substring((_attachedFileName ?? '文件').length - 12)}'
                              : _attachedFileName ?? '文件',
                          style: const TextStyle(fontSize: 12),
                        ),
                        deleteIcon:
                            const Icon(Icons.close, size: 16),
                        onDeleted: () => setState(() {
                          _attachedFileName = null;
                          _attachedRelPath = null;
                          _attachedImportError = null;
                        }),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4),
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: _attaching ? null : _pickFile,
                  icon: _attaching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
                        )
                      : const Icon(Icons.attach_file),
                  tooltip: '上传文件',
                  visualDensity: compact ? VisualDensity.compact : null,
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  onPressed: isRunning
                      ? () =>
                          ref.read(agentControllerProvider).cancel()
                      : () => _sendMessage(),
                  icon:
                      Icon(isRunning ? Icons.stop : Icons.send),
                  tooltip: isRunning ? '停止' : '发送',
                  style: IconButton.styleFrom(
                    backgroundColor:
                        theme.colorScheme.primary,
                    foregroundColor:
                        theme.colorScheme.onPrimary,
                  ),
                  visualDensity: compact ? VisualDensity.compact : null,
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
          Icon(Icons.auto_awesome, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            '我是你的 AI 教学助手',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            '我可以帮你查课程、成绩、待办、考试...\n也可以陪你讨论学习问题',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
      child: Column(
        children: [
          Expanded(
            child: _ConversationHistoryPanel(
              moduleId: widget.descriptor.id,
              onSessionTap: () => _scaffoldKey.currentState?.closeDrawer(),
              onGlobalMemory: () {
                _scaffoldKey.currentState?.closeDrawer();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const GlobalMemoryView()),
                );
              },
            ),
          ),
          // 系统功能分区：原 AI 视图窄轨（ModeRail）按钮收进此抽屉。
          const SystemDrawerSection(),
        ],
      ),
    );
  }
}

// ═══════ 后台 tool 进程管理（Task 三决策 3.2 UI 侧） ═══════

/// 「后台 N 个 tool 进程运行中」按钮的弹窗——列出全部已登记进程（含已退出），
/// 每项显示名称/状态/累积输出摘要（截断 500 字符），可一键结束。
///
/// 复用 [_showToolsPopup] 的 showDialog 模式（避免 bottom sheet 拖拽手势吞点击）。
/// 「结束」直接调 core 全局单例 [agent.agentProcessRegistry.kill]——与内置工具
/// `kill_process`（KillProcessTool，见 core/agent/tools/agent_process_tools.dart）
/// 等价：KillProcessTool 只是对同一注册表 kill 的薄包装，故 renderer 直调注册表
/// 单例简化接线（分层红线例外：A3 已把注册表暴露为 core 顶层单例）。
void _showProcessesPopup(BuildContext context) {
  final theme = Theme.of(context);
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final entries = agent.agentProcessRegistry.entries.toList()
            ..sort((a, b) {
              // 运行中的排前，其余按启动时间倒序。
              if (a.isRunning != b.isRunning) return a.isRunning ? -1 : 1;
              return b.startedAt.compareTo(a.startedAt);
            });
          final running = entries.where((e) => e.isRunning).length;
          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 460, maxHeight: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                    child: Row(
                      children: [
                        Icon(Icons.ad_units,
                            size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('后台 tool 进程（$running 个运行中）',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(dialogCtx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('暂无后台 tool 进程',
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant)),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: entries.length,
                        itemBuilder: (ctx, i) {
                          final e = entries[i];
                          return _ProcessTile(
                            entry: e,
                            onKill: () async {
                              await agent.agentProcessRegistry.kill(e.name);
                              // 「结束」后刷新列表（StatefulBuilder 重建；
                              // 弹窗若已关闭则跳过，避免对已卸载元素 setState）。
                              if (ctx.mounted) setDialogState(() {});
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

// ═══════ _MessageBubble ═══════

class _MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final double fontScale;
  final int? messageIndex;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;

  const _MessageBubble({
    required this.message,
    this.fontScale = 1.0,
    this.messageIndex,
    this.onEdit,
    this.onRegenerate,
  });

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

    final newHasReasoning = newContent.contains(':::reasoning');
    if (newHasReasoning) {
      final oldHasAnswer = _extractAnswer(oldContent).length > 20;
      final newHasAnswer = _extractAnswer(newContent).length > 20;

      if (!oldHasAnswer && !newHasAnswer) {
        if (!_reasoningExpanded) {
          setState(() => _reasoningExpanded = true);
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
        setState(() => _reasoningExpanded = false);
      }
    }
  }

  @override
  void dispose() {
    _thinkingScrollCtrl.dispose();
    super.dispose();
  }

  String _extractAnswer(String content) {
    final m =
        RegExp(r'^:::reasoning\n[\s\S]*?\n:::').firstMatch(content);
    return m == null ? content : content.substring(m.end).trim();
  }

  /// 预处理数学公式：$...$ → 内联代码，$$...$$ → 代码块。
  String _preprocessMath(String text) {
    var result = text.replaceAllMapped(
      RegExp(r'\$\$([\s\S]*?)\$\$'),
      (m) => '```math\n${m.group(1)!.trim()}\n```',
    );
    result = result.replaceAllMapped(
      RegExp(r'(?<!\$)\$([^$\n]+?)\$(?!\$)'),
      (m) => '`math:${m.group(1)!}`',
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isUser = msg.isUser;
    var content = msg.content;

    // 检测文件附件标记
    String? attachedFile;
    final fileTagMatch =
        RegExp(r'\[📎 (.+?)\]$').firstMatch(content);
    if (fileTagMatch != null) {
      attachedFile = fileTagMatch.group(1);
      content = content
          .substring(0, content.length - fileTagMatch.group(0)!.length)
          .trim();
    }

    // 检测 show_file4u 文件卡片标记（Task 七 9.2）——任意位置出现即提取并移除，
    // 由下方 [_WorkspaceFileCard] 渲染「预览 + 下载」卡片。
    String? fileCardRel;
    final fileCardMatch =
        RegExp(r'\[📄 工作区文件: (.+?)\]').firstMatch(content);
    if (fileCardMatch != null) {
      fileCardRel = fileCardMatch.group(1);
      content = content.replaceFirst(fileCardMatch.group(0)!, '').trim();
    }

    // 检测 :::reasoning 标记
    String? reasoningContent;
    String mainContent = content;
    final reasoningMatch =
        RegExp(r'^:::reasoning\n([\s\S]*?)\n:::').firstMatch(content);
    if (reasoningMatch != null) {
      reasoningContent = reasoningMatch.group(1)?.trim();
      mainContent = content.substring(reasoningMatch.end).trim();
    }
    mainContent = _preprocessMath(mainContent);

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
              backgroundColor:
                  Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.auto_awesome,
                  size: 16 * s,
                  color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                        width: 14 * s,
                        height: 14 * s,
                        child: const CircularProgressIndicator(
                            strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text('思考中...',
                        style: TextStyle(
                            fontSize: 13 * s,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
              backgroundColor:
                  Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.auto_awesome,
                  size: 16 * s,
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
                      : Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft:
                        Radius.circular(isUser ? 16 : 4),
                    bottomRight:
                        Radius.circular(isUser ? 4 : 16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── 思考过程（chip 风格折叠） ──
                    if (!isUser && reasoningContent != null)
                      _buildThinkingSection(reasoningContent!, s),

                    // ── 文件卡片（show_file4u，Task 七 9.2） ──
                    if (!isUser && fileCardRel != null)
                      _WorkspaceFileCard(relativePath: fileCardRel!),

                    // ── 文件附件标记 ──
                    if (isUser && attachedFile != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.insert_drive_file,
                                size: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimary
                                    .withValues(alpha: 0.9)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                attachedFile!,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimary
                                        .withValues(alpha: 0.9)),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ── 主内容 ──
                    if (mainContent.isNotEmpty &&
                        mainContent != '_thinking_')
                      isUser
                          ? SelectableText(
                              mainContent,
                              style: TextStyle(
                                  fontSize: 14 * s,
                                  color: Theme.of(context).colorScheme.onPrimary),
                            )
                          : MarkdownBody(
                              data: mainContent
                                  .replaceAll('<br>', '\n')
                                  .replaceAll('<br/>', '\n')
                                  .replaceAll('<br />', '\n'),
                              selectable: true,
                              builders: {
                                'pre': _PreBlockBuilder(
                                  codeBackground: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLow,
                                ),
                                'code': _InlineMathBuilder(),
                              },
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(fontSize: 14 * s),
                                code: TextStyle(
                                  fontSize: 13 * s,
                                  fontFamily: 'monospace',
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLow,
                                  color: const Color(0xFFE53935),
                                ),
                                h1: TextStyle(
                                    fontSize: 20 * s,
                                    fontWeight: FontWeight.bold),
                                h2: TextStyle(
                                    fontSize: 17 * s,
                                    fontWeight: FontWeight.bold),
                                h3: TextStyle(
                                    fontSize: 15 * s,
                                    fontWeight: FontWeight.w600),
                                listBullet:
                                    TextStyle(fontSize: 14 * s),
                                strong: const TextStyle(
                                    fontWeight: FontWeight.bold),
                                em: const TextStyle(
                                    fontStyle:
                                        FontStyle.italic),
                                a: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  decoration:
                                      TextDecoration.underline,
                                ),
                              ),
                            ),

                    // ── 操作按钮 ──
                    if (mainContent.isNotEmpty &&
                        mainContent != '_thinking_')
                      _buildActions(isUser, mainContent, s),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14 * s,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.7),
              child: Icon(Icons.person,
                  size: 16 * s, color: Theme.of(context).colorScheme.onPrimary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThinkingSection(String reasoningContent, double s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCollapsibleHeader(
          expanded: _reasoningExpanded,
          onToggle: () =>
              setState(() => _reasoningExpanded = !_reasoningExpanded),
          icon: Icons.psychology,
          color: const Color(0xFFF57C00),
          title: '思考过程',
          badge: _countTools(reasoningContent),
          scale: s,
        ),
        if (_reasoningExpanded)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 280),
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: Theme.of(context).colorScheme.tertiary),
            ),
            child: SingleChildScrollView(
              controller: _thinkingScrollCtrl,
              padding: const EdgeInsets.all(10),
              child: _buildThinkingContent(reasoningContent, s),
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

  Widget _buildThinkingContent(String text, double s) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines.where((l) => l.trim().isNotEmpty).map((line) {
        final trimmed = line.trim();

        // 记忆工具（🧠）
        if (trimmed.startsWith('🧠')) {
          final isRecall =
              trimmed.contains('回忆') || trimmed.contains('read');
          return _thinkingChip(
            icon: Icons.memory,
            text: isRecall ? '回忆全局记忆' : '写入全局记忆',
            bgColor: const Color(0xFFF3E5F5),
            fgColor: const Color(0xFF7B1FA2),
            scale: s,
          );
        }

        // Skill（📋）
        if (trimmed.startsWith('📋')) {
          return _thinkingChip(
            icon: Icons.auto_stories,
            text: trimmed.replaceAll('📋', '').trim(),
            bgColor: const Color(0xFFE0F2F1),
            fgColor: const Color(0xFF00695C),
            scale: s,
          );
        }

        // 工具调用（🔧）
        if (trimmed.startsWith('🔧')) {
          return _thinkingChip(
            icon: Icons.touch_app,
            text: trimmed.replaceAll('🔧', '').trim(),
            bgColor: const Color(0xFFE3F2FD),
            fgColor: const Color(0xFF1565C0),
            scale: s,
          );
        }

        // 工具结果（✅）
        if (trimmed.startsWith('✅')) {
          return _thinkingChip(
            icon: Icons.check_circle,
            text: trimmed.replaceAll('✅', '').trim(),
            bgColor: const Color(0xFFE8F5E9),
            fgColor: const Color(0xFF1B5E20),
            scale: s,
          );
        }

        // 普通推理文本
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(line,
              style: TextStyle(
                  fontSize: 12 * s,
                  color: const Color(0xFF795548),
                  height: 1.5)),
        );
      }).toList(),
    );
  }

  Widget _thinkingChip({
    required IconData icon,
    required String text,
    required Color bgColor,
    required Color fgColor,
    required double scale,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: fgColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14 * scale, color: fgColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 11 * scale,
                      fontWeight: FontWeight.w700,
                      color: fgColor,
                      fontFamily: 'monospace')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(bool isUser, String content, double s) {
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
                final clean = content.replaceFirst(
                    RegExp(r'^:::reasoning\n[\s\S]*?\n:::\n?'),
                    '');
                Clipboard.setData(
                    ClipboardData(text: clean));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('已复制'),
                      duration: Duration(seconds: 1)),
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
              icon: Icons.edit_outlined,
              tooltip: '编辑（保留原历史，另开分支）',
              size: 12 * s,
              onTap: () => widget.onEdit?.call(),
            ),
          ],
        ],
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
    double scale = 1.0,
  }) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16 * scale, color: color),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                    fontSize: 12 * scale,
                    color: color,
                    fontWeight: FontWeight.w600)),
            if (badge > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$badge',
                    style: TextStyle(
                        fontSize: 11 * scale,
                        color: color,
                        fontWeight: FontWeight.w700)),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
                expanded
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: 16 * scale,
                color: color),
          ],
        ),
      ),
    );
  }
}

// ═══════ _WorkspaceFileCard（show_file4u，Task 七 9.2） ═══════

/// `show_file4u` 工具产出的文件卡片——显示文件名 + 大小，
/// 右侧「下载」触发 9.1 的固定目录下载（成功弹窗路径+复制、失败报错），
/// 点击卡片进入 [FileViewer] 预览（不支持预览的类型由 FileViewer 自行兜底）。
class _WorkspaceFileCard extends StatelessWidget {
  /// 工作区相对路径（来自 show_file4u 的 `file_path` 参数）。
  final String relativePath;

  const _WorkspaceFileCard({required this.relativePath});

  /// 相对路径 → 绝对路径 + [WorkspaceFile]（与工作区抽屉同一路径契约）。
  WorkspaceFile _resolveFile() {
    final full =
        p.join(greenixWorkspaceDir(aiAssistantWorkspaceModuleId), relativePath);
    final f = File(full);
    return WorkspaceFile(
      name: relativePath.split('/').last,
      path: full,
      sizeBytes: f.existsSync() ? f.lengthSync() : 0,
    );
  }

  static IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' || 'py' || 'js' || 'ts' => Icons.code,
      'md' || 'txt' => Icons.article,
      'pdf' => Icons.picture_as_pdf,
      'json' || 'yaml' || 'yml' => Icons.data_object,
      'jpg' || 'jpeg' || 'png' || 'gif' || 'svg' || 'bmp' => Icons.image,
      'html' || 'htm' => Icons.html,
      'zip' || 'tar' || 'gz' || 'rar' => Icons.archive,
      _ => Icons.insert_drive_file,
    };
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = _resolveFile();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(_fileIcon(file.name), size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '工作区文件 · ${_formatSize(file.sizeBytes)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // 下载（复用 9.1 固定目录下载；成功弹窗路径+复制，失败报错）
          IconButton(
            icon: const Icon(Icons.download, size: 18),
            tooltip: '下载',
            visualDensity: VisualDensity.compact,
            onPressed: () => _download(context, file),
          ),
          // 预览（FileViewer，同工作区点击文件）
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => FileViewer(file: file)),
            ),
            child: const Text('预览'),
          ),
        ],
      ),
    );
  }

  Future<void> _download(BuildContext context, WorkspaceFile file) async {
    final r = await downloadWorkspaceFile(file);
    if (!context.mounted) return;
    if (r.ok) {
      showWorkspaceDownloadSuccessDialog(context, [r.savedPath!]);
    } else {
      showWorkspaceDownloadErrorSnackBar(context, r.error!);
    }
  }
}

// ═══════ Markdown Builders ═══════

/// 内联数学公式渲染器（`math:...` 语法）。
class _InlineMathBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    final text = element.textContent;
    if (!text.startsWith('math:')) return null;
    final formula = text.substring(5).trim();
    if (formula.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Math.tex(
        formula,
        textStyle: TextStyle(
          fontSize: preferredStyle?.fontSize ?? 14,
          color: preferredStyle?.color,
        ),
      ),
    );
  }
}

/// 代码块构建器：处理 mindmap 和 math 代码块。
class _PreBlockBuilder extends MarkdownElementBuilder {
  /// 普通代码块背景色（由调用方注入主题色，深色模式自动适配）。
  final Color? codeBackground;

  _PreBlockBuilder({this.codeBackground});

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    if (element.children == null || element.children!.isEmpty) {
      return null;
    }
    final codeElem = element.children!.first;
    if (codeElem is! md.Element) return null;

    final classAttr = codeElem.attributes['class'] ?? '';
    final text = codeElem.textContent.trim();
    if (text.isEmpty) return null;

    // mindmap 代码块
    if (classAttr.toLowerCase().contains('mindmap')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: MindMapWidget(text: text),
      );
    }

    // math 代码块（$$...$$ → ```math ... ```）
    if (classAttr.toLowerCase().contains('math')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Math.tex(
            text,
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    // 普通代码块
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: codeBackground ?? const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
            fontSize: 13, fontFamily: 'monospace'),
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

  void _showRenameDialog(BuildContext context, WidgetRef ref, String id,
      String currentTitle) {
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
        content: Text(
            '确定删除 "${title.isEmpty ? "新对话" : title}" 吗？此操作无法撤销。'),
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
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessionsAsync = ref.watch(sessionListProvider);
    final activeId = ref.watch(activeSessionIdProvider);

    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 48, 8, 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            border: Border(
              bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 0.5),
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
                icon: const Icon(Icons.add_comment, size: 20),
                tooltip: '新建对话',
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
                    child:
                        CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => Center(
                child: Text('加载失败: $e',
                    style: theme.textTheme.bodySmall)),
            data: (sessions) {
              if (sessions.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 36,
                          color: theme
                              .colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.3)),
                      const SizedBox(height: 8),
                      Text('暂无对话',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme
                                  .colorScheme.onSurfaceVariant)),
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
                          m.role == agent.Role.user ||
                          m.role == agent.Role.assistant)
                      .length;
                  // R3 会话树：会话行分支标签 = 树内分支计数（旧 A6 fork
                  // 数据走 branchFamilyOf 兜底）。
                  final branchCount = branchLabelCount(sessions, s);
                  return ListTile(
                    selected: isActive,
                    selectedTileColor: theme
                        .colorScheme.primaryContainer
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
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      '$msgCount 条消息 · ${_formatRelativeTime(s.updatedAt)}'
                      '${branchCount > 1 ? ' · 分支 $branchCount' : ''}',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              theme.colorScheme.onSurfaceVariant),
                    ),
                    dense: true,
                    onTap: () {
                      ref.read(switchSessionProvider)(s.id);
                      onSessionTap();
                    },
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz,
                          size: 16),
                      padding: EdgeInsets.zero,
                      color: theme.colorScheme.surfaceContainerLowest,
                      onSelected: (action) {
                        if (action == 'rename') {
                          _showRenameDialog(
                              context, ref, s.id, s.title);
                        } else if (action == 'delete') {
                          _showDeleteDialog(
                              context, ref, s.id, s.title);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'rename',
                            child: Text('重命名')),
                        PopupMenuItem(
                            value: 'delete',
                            child: Text('删除')),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.memory,
              size: 20, color: theme.colorScheme.tertiary),
          title: Text('全局记忆',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text('查看和管理 AI 的记忆',
              style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          dense: true,
          onTap: onGlobalMemory,
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ═══════ _BranchSwitcherBar ═══════

/// R3 会话树分支切换条「◀ i/n ▶」——渲染在**分叉的 user 消息下方**（spec：
/// 消息下面，不是会话名下面）。
///
/// 左右环绕切换同一会话内的兄弟分支（switch 即 i±1，见 session_branch.dart 的
/// [switchSibling]）；切换是纯会话层操作：不改变会话 id、不产生新会话、
/// 不撤销工作区变更。仅在消息所在轮有分支（branchCount > 1）时由
/// [_ChatControllerViewState._buildMessageItem] 渲染。
class _BranchSwitcherBar extends StatelessWidget {
  final int branchIndex;
  final int branchCount;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _BranchSwitcherBar({
    required this.branchIndex,
    required this.branchCount,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onPrev,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.chevron_left, size: 16, color: dim),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '$branchIndex/$branchCount',
              style: TextStyle(
                fontSize: 11,
                color: dim,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          InkWell(
            onTap: onNext,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.chevron_right, size: 16, color: dim),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════ _ToolbarIconButton ═══════

/// 嵌入模式工具栏按钮——圆形背景 + 图标，紧凑排列。
class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarIconButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
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
        child: Icon(icon,
            size: size,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.6)),
      ),
    );
  }
}

// ═══════ _EffortSelector ═══════

class _EffortSelector extends StatelessWidget {
  final String effort;
  final ValueChanged<String> onChanged;

  const _EffortSelector({required this.effort, required this.onChanged});

  static const _labels = <String, String>{
    'off': '思考: 关',
    'low': '思考: 低',
    'medium': '思考: 中',
    'high': '思考: 高',
    'max': '思考: 最强',
  };

  static const _descriptions = <String, String>{
    'off': '关闭深度思考',
    'low': '快速回答，适合简单问题',
    'medium': '适度思考，日常对话推荐',
    'high': '深入推理，复杂问题适用',
    'max': '全面思考，最复杂场景',
  };

  static const _icons = <String, IconData>{
    'off': Icons.bolt,
    'low': Icons.speed,
    'medium': Icons.auto_awesome,
    'high': Icons.psychology,
    'max': Icons.rocket_launch,
  };

  static const _levelColor = Color(0xFF7B1FA2);

  @override
  Widget build(BuildContext context) {
    final isOn = effort != 'off';
    final color = isOn
        ? _levelColor
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final label = _labels[effort] ?? '思考';

    return FilterChip(
      avatar: Icon(
        _icons[effort] ?? Icons.auto_awesome,
        size: 16,
        color: isOn ? Theme.of(context).colorScheme.onPrimary : color,
      ),
      label: Text(label,
          style: TextStyle(
              fontSize: 12, color: isOn ? Theme.of(context).colorScheme.onPrimary : null)),
      selected: isOn,
      selectedColor: _levelColor,
      checkmarkColor: Theme.of(context).colorScheme.onPrimary,
      showCheckmark: false,
      onSelected: (_) => _showMenu(context),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  void _showMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu<String>(
      context: context,
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        offset.dx + size.width,
        offset.dy + size.height + 4,
      ),
      items: validReasoningEfforts.map((level) {
        final isSelected = level == effort;
        final icon = _icons[level] ?? Icons.auto_awesome;
        final desc = _descriptions[level] ?? '';
        return PopupMenuItem<String>(
          value: level,
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: isSelected ? _levelColor : null),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _labels[level] ?? level,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    if (desc.isNotEmpty)
                      Text(desc,
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check,
                    size: 16,
                    color:
                        Theme.of(context).colorScheme.primary),
            ],
          ),
        );
      }).toList(),
    ).then((selected) {
      if (selected != null) onChanged(selected);
    });
  }
}

// ═══════ _BgProcessChip ═══════

/// 工具区「后台 N」chip——Task 三决策 3.2 的 UI 入口：
/// 显示当前后台 tool 进程数（[_bgProcessCountProvider] 响应式刷新），
/// 点击弹出 [_showProcessesPopup] 管理列表。
class _BgProcessChip extends ConsumerWidget {
  const _BgProcessChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(_bgProcessCountProvider);
    final theme = Theme.of(context);
    final active = n > 0;
    return Tooltip(
      message: '后台 $n 个 tool 进程运行中，点击查看/结束',
      child: FilterChip(
        avatar: Icon(Icons.ad_units,
            size: 16,
            color: active
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant),
        label: Text('后台 $n',
            style: TextStyle(
                fontSize: 12,
                color: active ? theme.colorScheme.onPrimary : null)),
        selected: active,
        selectedColor: theme.colorScheme.primary,
        checkmarkColor: theme.colorScheme.onPrimary,
        showCheckmark: false,
        onSelected: (_) => _showProcessesPopup(context),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ═══════ _ProcessTile ═══════

/// 后台进程列表条目：名称 + 状态（运行中/已退出）+ 累积输出摘要（截断 500
/// 字符）+ 「结束」按钮（仅运行中显示）。
class _ProcessTile extends StatelessWidget {
  final agent.ResidentProcessEntry entry;
  final VoidCallback onKill;

  const _ProcessTile({required this.entry, required this.onKill});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRunning = entry.isRunning;
    final status = isRunning
        ? '运行中'
        : '已退出${entry.exitCode != null ? ' (exit=${entry.exitCode})' : ''}';
    final raw = entry.output.trim();
    final summary =
        raw.length > 500 ? '${raw.substring(0, 500)}…' : raw;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(
          isRunning ? Icons.ad_units : Icons.stop_circle_outlined,
          size: 20,
          color: isRunning
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(status,
                style: TextStyle(
                    fontSize: 11,
                    color: isRunning
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant)),
            if (summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
          ],
        ),
        trailing: isRunning
            ? TextButton(
                onPressed: onKill,
                child: const Text('结束', style: TextStyle(fontSize: 12)),
              )
            : null,
        dense: true,
        visualDensity: VisualDensity.compact,
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
      avatar:
          Icon(icon, size: 16, color: value ? Theme.of(context).colorScheme.onPrimary : activeColor),
      label: Text(label,
          style: TextStyle(
              fontSize: 12, color: value ? Theme.of(context).colorScheme.onPrimary : null)),
      selected: value,
      selectedColor: activeColor,
      checkmarkColor: Theme.of(context).colorScheme.onPrimary,
      showCheckmark: false,
      onSelected: onChanged,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

// ═══════ _LocalChatMessagesNotifier ═══════

class _LocalChatMessagesNotifier
    extends StateNotifier<List<ChatMessage>> {
  _LocalChatMessagesNotifier() : super([]);

  /// [loopId]/[branchCount]/[branchIndex]：R3 会话树分支切换条信息
  /// （缺省 null → 不渲染切换条，零行为变化）。
  void addUser(String text,
      {int? loopId, int? branchCount, int? branchIndex}) {
    state = [
      ...state,
      ChatMessage(
        role: 'user',
        content: text,
        loopId: loopId,
        branchCount: branchCount,
        branchIndex: branchIndex,
      ),
    ];
  }

  void addNotice(String text) {
    state = [...state, ChatMessage(role: 'system', content: text)];
  }

  void replaceLastAssistant(String text) {
    if (state.isNotEmpty && state.last.isAssistant) {
      final updated = [...state];
      updated[updated.length - 1] =
          ChatMessage(role: 'assistant', content: text);
      state = updated;
    } else {
      state = [...state, ChatMessage(role: 'assistant', content: text)];
    }
  }

  void addAssistant(String text) {
    state = [...state, ChatMessage(role: 'assistant', content: text)];
  }

  void removeLastAssistant() {
    if (state.isNotEmpty && state.last.isAssistant) {
      state = [...state]..removeLast();
    }
  }

  String? removeLastTurn() {
    final userIdx = state.lastIndexWhere((m) => m.isUser);
    if (userIdx < 0) return null;
    final userContent = state[userIdx].content;
    state = [...state]..removeRange(userIdx, state.length);
    return userContent;
  }

  void removeFrom(int index) {
    if (index < 0 || index >= state.length) return;
    state = [...state]..removeRange(index, state.length);
  }

  void clear() => state = [];
}

// ═══════ _ToolTile ═══════

class _ToolTile extends StatelessWidget {
  final String name;
  final String description;
  final bool readOnly;
  final bool enabled;
  final bool isEssential;
  final ValueChanged<bool> onToggle;

  const _ToolTile({
    required this.name,
    required this.description,
    required this.readOnly,
    required this.enabled,
    required this.isEssential,
    required this.onToggle,
  });

  static IconData _toolIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('read') || lower.contains('file')) {
      return Icons.file_open;
    }
    if (lower.contains('write') || lower.contains('edit')) {
      return Icons.edit_note;
    }
    if (lower.contains('search') || lower.contains('web')) {
      return Icons.language;
    }
    if (lower.contains('python') ||
        lower.contains('run') ||
        lower.contains('code')) return Icons.code;
    if (lower.contains('memory') || lower.contains('remember')) {
      return Icons.psychology;
    }
    if (lower.contains('skill') || lower.contains('plugin')) {
      return Icons.auto_fix_high;
    }
    if (lower.contains('calculator') || lower.contains('math')) {
      return Icons.calculate;
    }
    if (lower.contains('password') || lower.contains('gen')) {
      return Icons.lock;
    }
    if (lower.contains('convert') || lower.contains('transform')) {
      return Icons.transform;
    }
    if (lower.contains('json') || lower.contains('format')) {
      return Icons.data_object;
    }
    if (lower.contains('url') || lower.contains('encode')) {
      return Icons.link;
    }
    if (lower.contains('text') || lower.contains('string')) {
      return Icons.text_fields;
    }
    if (lower.contains('image') || lower.contains('photo')) {
      return Icons.image;
    }
    if (lower.contains('color')) return Icons.palette;
    if (lower.contains('qr') || lower.contains('barcode')) {
      return Icons.qr_code;
    }
    if (lower.contains('uuid') || lower.contains('id')) {
      return Icons.fingerprint;
    }
    if (lower.contains('unit') || lower.contains('measure')) {
      return Icons.straighten;
    }
    if (lower.contains('timer') || lower.contains('pomodoro')) {
      return Icons.timer;
    }
    if (lower.contains('vocab') || lower.contains('word')) {
      return Icons.spellcheck;
    }
    return Icons.toggle_on;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconData = _toolIcon(name);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled
              ? isEssential
                  ? Colors.amber.withValues(alpha: 0.35)
                  : theme.colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: enabled
              ? (isEssential
                  ? Colors.amber.withValues(alpha: 0.2)
                  : theme.colorScheme.primary.withValues(alpha: 0.15))
              : theme.colorScheme.surfaceContainerLow,
          child: Icon(
            iconData,
            size: 18,
            color: enabled
                ? (isEssential
                    ? Colors.amber.shade700
                    : theme.colorScheme.primary)
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Row(
          children: [
            if (isEssential) ...[
              Text('★ ',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.amber.shade700,
                      fontWeight: FontWeight.bold)),
            ],
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            if (isEssential) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('核心',
                    style: TextStyle(
                        fontSize: 9,
                        color: Color(0xFFB8860B))),
              ),
            ],
            if (readOnly) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('只读',
                    style: TextStyle(
                        fontSize: 9, color: Colors.green)),
              ),
            ],
          ],
        ),
        subtitle: description.length > 60
            ? Text('${description.substring(0, 60)}…',
                style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant))
            : Text(description,
                style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant)),
        trailing: Switch(
          value: enabled,
          onChanged: onToggle,
          activeColor: isEssential
              ? Colors.amber.shade600
              : theme.colorScheme.primary,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
