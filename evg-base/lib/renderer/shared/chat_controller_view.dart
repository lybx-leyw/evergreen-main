/// Chat 控制器视图——统一的 AI 聊天界面。
///
/// 单一 [ConsumerStatefulWidget]，直接订阅事件流，通过 [ref.watch] 驱动渲染。
/// 合并了原 ChatControllerView + ChatView 的双层架构，消除 props 传递链路。
///
/// 职责：
/// 1. 订阅 [agentEventStreamProvider] 事件流
/// 2. 将 [AgentEvent] 实时渲染为消息气泡
/// 3. 会话管理（创建/切换/删除/重命名）
/// 4. 工作区文件面板
/// 5. 全局记忆入口
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/controller/controller.dart' show ControllerState;
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/agent/agent_runtime.dart' show webSearchEnabledProvider, deepThinkingEnabledProvider, agentRuntimeProvider;
import 'package:evergreen_base/core/agent/session_manager.dart';
import 'package:evergreen_base/renderer/widgets/models.dart';
import 'package:evergreen_base/renderer/widgets/markdown_renderer.dart';
import 'package:evergreen_base/renderer/widgets/workspace_drawer.dart';
import 'package:evergreen_base/renderer/shared/theme_provider.dart';
import 'file_viewer.dart';
import 'global_memory_view.dart';
import 'skill_management_view.dart';

/// 当前视图的消息列表。
final _chatMessagesProvider = StateNotifierProvider<ChatMessagesNotifier, List<ChatMessage>>((ref) => ChatMessagesNotifier());

/// Chat 范式统一控制器视图。
class ChatControllerView extends ConsumerStatefulWidget {
  final ModuleDescriptor descriptor;
  const ChatControllerView({super.key, required this.descriptor});

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
    Future.microtask(() => _subscribeToEvents());
  }

  @override
  void dispose() {
    _elapsedTimer.cancel();
    _pulseAnim.dispose();
    _eventSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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
          // 自动保存会话
          final currentId = ref.read(activeSessionIdProvider);
          if (currentId != null) {
            ref.read(saveCurrentSessionProvider)(currentId);
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

  void _maybeUpdateBubble(ChatMessagesNotifier notifier) {
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

  /// 从 [agentRuntimeProvider] 的 session 中加载消息到 UI 状态。
  void _syncMessagesFromRuntime() {
    final runtime = ref.read(agentRuntimeProvider);
    final notifier = ref.read(_chatMessagesProvider.notifier);
    notifier.clear();
    for (final m in runtime.session.messages) {
      if (m.content.isEmpty) continue;
      if (m.isUser) {
        notifier.addUser(m.content);
      } else if (m.isAssistant) {
        notifier.replaceLastAssistant(
          _contentWithReasoning(m.reasoningContent, m.content),
        );
      }
    }
    debugPrint('[Chat:D] _syncMessagesFromRuntime loaded ${runtime.session.messages.length} messages');
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

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    debugPrint('[Chat:D] _sendMessage() text="$text"');
    if (text.isEmpty) return;
    if (ref.read(controllerStateProvider) == ControllerState.running) return;

    // 自动创建会话
    if (ref.read(activeSessionIdProvider) == null) {
      ref.read(createSessionProvider)('新对话');
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

  // ── 构建 ──

  @override
  Widget build(BuildContext context) {
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
                    itemBuilder: (context, index) =>
                        _MessageBubble(message: messages[index]),
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
  const _MessageBubble({required this.message});

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
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.auto_awesome, size: 16,
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
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('思考中...',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.auto_awesome, size: 16,
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
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.white),
                            )
                          : MarkdownRenderer(
                              text: mainContent,
                              useCard: false,
                              padding: EdgeInsets.zero,
                            ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
              child: const Icon(Icons.person, size: 16, color: Colors.white),
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
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF795548), height: 1.5)),
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
            Icon(icon, size: 14, color: fgColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 11,
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
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w600)),
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
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w700)),
              ),
            ],
            const SizedBox(width: 4),
            Icon(expanded ? Icons.expand_less : Icons.expand_more,
                size: 16, color: color),
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
                      '$msgCount 条消息',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    dense: true,
                    onTap: () {
                      ref.read(switchSessionProvider)(s.id);
                      onSessionTap();
                    },
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

// ═══════ ChatMessagesNotifier ═══════

/// 消息列表状态管理器。
class ChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  ChatMessagesNotifier() : super([]);

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
      updated[updated.length - 1] = ChatMessage(
        role: 'assistant',
        content: text,
      );
      state = updated;
    } else {
      state = [...state, ChatMessage(role: 'assistant', content: text)];
    }
  }

  void clear() => state = [];
}
