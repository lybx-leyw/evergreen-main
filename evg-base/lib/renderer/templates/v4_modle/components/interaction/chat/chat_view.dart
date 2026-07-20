/// Chat 嵌入式视图——用于 composite 页面的 ai-assistant 插槽。
///
/// 自包含的 ConsumerStatefulWidget，独立管理消息状态，
/// 不与全屏 ChatControllerView 共享消息列表。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/agent/event.dart' as agent;
import 'package:evergreen_base/core/agent/controller/controller.dart' show ControllerState;
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/agent/agent_runtime.dart' show webSearchEnabledProvider, reasoningEffortProvider, validReasoningEfforts;
import 'package:evergreen_base/core/agent/session_manager.dart' show activeSessionIdProvider, createSessionProvider;
import 'package:evergreen_base/renderer/components/shared/widgets/models.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/markdown_renderer.dart';
import 'package:evergreen_base/renderer/app/service/theme/theme_provider.dart';

/// 嵌入式聊天视图的独立消息状态。
final _embeddedChatProvider = StateProvider<List<ChatMessage>>((ref) => []);

/// 嵌入式聊天视图。
///
/// 用于 composite 页面的 `ai-assistant` 组件插槽。
/// 相比全屏 ChatControllerView，省略了会话历史抽屉、工作区面板。
class ChatView extends ConsumerStatefulWidget {
  final ModuleDescriptor descriptor;
  const ChatView({super.key, required this.descriptor});

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  StreamSubscription<agent.AgentEvent>? _eventSub;

  // ── 流式累积 ──
  final StringBuffer _pendingAnswer = StringBuffer();
  final StringBuffer _pendingTimeline = StringBuffer();
  bool _hasBubble = false;
  int _textThrottleCount = 0;

  // ── 状态指示灯 ──
  bool _isRunning = false;
  String _statusText = '';
  String _currentTool = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _subscribe());
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _subscribe() {
    _eventSub?.cancel();
    _eventSub = ref.read(agentEventStreamProvider).listen((event) {
      if (!mounted) return;
      final notifier = ref.read(_embeddedChatProvider.notifier);

      switch (event.kind) {
        case agent.EventKind.turnStarted:
          setState(() {
            _isRunning = true;
            _statusText = '思考中...';
            _currentTool = '';
          });
          break;

        case agent.EventKind.reasoning:
          if (event.reasoning != null) {
            _pendingTimeline.write(event.reasoning);
            _maybeUpdate(notifier);
          }
          break;

        case agent.EventKind.text:
          if (event.text != null) {
            _pendingAnswer.write(event.text);
            _textThrottleCount++;
            if (!_hasBubble || _textThrottleCount >= 10 ||
                event.text!.contains('。') || event.text!.contains('！') ||
                event.text!.contains('？') || event.text!.contains('\n')) {
              _maybeUpdate(notifier);
              _textThrottleCount = 0;
            }
          }
          break;

        case agent.EventKind.toolDispatch:
          if (event.tool != null) {
            _flushAnswerToTimeline();
            final name = event.tool!.name;
            _pendingTimeline.writeln('\n🔧 调用 ${name}');
            setState(() {
              _currentTool = name;
              _statusText = '调用 $name...';
            });
            _maybeUpdate(notifier);
          }
          break;

        case agent.EventKind.toolResult:
          if (event.tool != null) {
            final output = (event.tool!.output ?? event.tool!.error ?? '').trim();
            final preview = output.length > 200 ? '${output.substring(0, 200)}...' : output;
            _pendingTimeline.writeln('\n✅ ${event.tool!.name} → $preview');
            notifier.replaceLastAssistant(_buildCombined());
            setState(() {
              _currentTool = '';
              _statusText = '处理结果...';
            });
          }
          break;

        case agent.EventKind.turnDone:
          if (!mounted) return;
          notifier.replaceLastAssistant(_buildCombined());
          setState(() => _isRunning = false);
          break;

        default:
          break;
      }

      Future.microtask(() {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut);
        }
      });
    });
  }

  void _maybeUpdate(StateNotifier<List<ChatMessage>> notifier) {
    _hasBubble = true;
    notifier.replaceLastAssistant(_buildCombined());
  }

  void _flushAnswerToTimeline() {
    if (_pendingAnswer.isNotEmpty) {
      _pendingTimeline.write(_pendingAnswer.toString());
      _pendingAnswer.clear();
    }
  }

  String _buildCombined() {
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

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    if (ref.read(controllerStateProvider) == ControllerState.running) return;

    // ✅ 自动创建会话：当 activeSessionId 为 null 时，先创建再发送
    if (ref.read(activeSessionIdProvider) == null) {
      ref.read(createSessionProvider)(null);
    }

    final notifier = ref.read(_embeddedChatProvider.notifier);
    notifier.addUser(text);
    _inputCtrl.clear();

    _pendingTimeline.clear();
    _pendingAnswer.clear();
    _textThrottleCount = 0;
    _hasBubble = false;

    ref.read(agentControllerProvider).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(_embeddedChatProvider);
    final theme = Theme.of(context);
    final isRunning = ref.watch(controllerStateProvider) == ControllerState.running;
    final webSearch = ref.watch(webSearchEnabledProvider);
    final effort = ref.watch(reasoningEffortProvider);

    return Column(
      children: [
        // ── 消息列表 ──
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text('AI 助手', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text('输入消息开始对话',
                          style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) =>
                      _ChatBubble(message: messages[index]),
                ),
        ),

        // ── 状态指示灯 ──
        if (_isRunning)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.blue.withValues(alpha: 0.05),
            child: Row(
              children: [
                const SizedBox(width: 10, height: 10,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text(_statusText,
                    style: const TextStyle(fontSize: 11, color: Colors.blue)),
              ],
            ),
          ),

        // ── 输入栏 ──
        Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          decoration: BoxDecoration(
            color: context.componentColor('input', 'bg') ?? theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                _MiniToggle(
                  icon: Icons.language, label: '联网', value: webSearch,
                  onTap: () =>
                      ref.read(webSearchEnabledProvider.notifier).state = !webSearch,
                ),
                const SizedBox(width: 4),
                _MiniEffortSelector(
                  effort: effort,
                  onChanged: (v) =>
                      ref.read(reasoningEffortProvider.notifier).state = v,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    enabled: !isRunning,
                    decoration: InputDecoration(
                      hintText: '输入消息...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(isRunning ? Icons.stop : Icons.send, size: 18),
                  onPressed: isRunning
                      ? () => ref.read(agentControllerProvider).cancel()
                      : _send,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════ _ChatBubble ═══════

class _ChatBubble extends StatefulWidget {
  final ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  bool _reasoningExpanded = false;

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isUser = msg.isUser;
    var content = msg.content;

    String? reasoning;
    String mainContent = content;
    final m = RegExp(r'^:::reasoning\n([\s\S]*?)\n:::').firstMatch(content);
    if (m != null) {
      reasoning = m.group(1)?.trim();
      mainContent = content.substring(m.end).trim();
    }

    if (mainContent == '_thinking_' && !isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            const SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            const Text('思考中...',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }

    if (mainContent.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 12,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(Icons.auto_awesome, size: 12,
                    color: Theme.of(context).colorScheme.primary),
              ),
            ),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isUser ? 12 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (reasoning != null && !isUser) ...[
                    InkWell(
                      onTap: () => setState(() => _reasoningExpanded = !_reasoningExpanded),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.psychology, size: 12,
                              color: Color(0xFFF57C00)),
                          const SizedBox(width: 4),
                          const Text('思考过程',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFF57C00),
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 4),
                          Icon(
                              _reasoningExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 12,
                              color: const Color(0xFFF57C00)),
                        ],
                      ),
                    ),
                    if (_reasoningExpanded) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(reasoning!,
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF795548),
                                height: 1.4)),
                      ),
                    ],
                    if (reasoning != null) const SizedBox(height: 4),
                  ],
                  isUser
                      ? SelectableText(mainContent,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.white))
                      : MarkdownRenderer(
                          text: mainContent,
                          useCard: false,
                          padding: EdgeInsets.zero,
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════ _MiniToggle ═══════

/// 迷你版思考档位选择器—— chat_view 用。
class _MiniEffortSelector extends StatelessWidget {
  final String effort;
  final ValueChanged<String> onChanged;

  const _MiniEffortSelector({required this.effort, required this.onChanged});

  static const _labels = <String, String>{
    'off': '关', 'low': '低', 'medium': '中', 'high': '高', 'max': '最强',
  };
  static const _levelColor = Color(0xFF7B1FA2);

  @override
  Widget build(BuildContext context) {
    final isOn = effort != 'off';
    return GestureDetector(
      onTap: () => _showMenu(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isOn ? _levelColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOn ? _levelColor.withValues(alpha: 0.4) : Colors.grey.shade400,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 14, color: isOn ? _levelColor : Colors.grey),
            const SizedBox(width: 4),
            Text(
              _labels[effort] ?? '关',
              style: TextStyle(fontSize: 11, color: isOn ? _levelColor : Colors.grey, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    const fullLabels = <String, String>{
      'off': '思考: 关', 'low': '思考: 低', 'medium': '思考: 中',
      'high': '思考: 高', 'max': '思考: 最强',
    };
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx, offset.dy + renderBox.size.height + 4,
        offset.dx + renderBox.size.width, offset.dy + renderBox.size.height + 4,
      ),
      items: validReasoningEfforts.map((level) => PopupMenuItem<String>(
        value: level,
        child: Text(
          fullLabels[level] ?? level,
          style: TextStyle(
            fontWeight: level == effort ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      )).toList(),
    ).then((selected) {
      if (selected != null) onChanged(selected);
    });
  }
}

class _MiniToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final VoidCallback onTap;
  final Color activeColor;

  const _MiniToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.activeColor = const Color(0xFF1565C0),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14,
                  color: value ? activeColor : Colors.grey),
              const SizedBox(width: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: value ? activeColor : Colors.grey,
                      fontWeight: value ? FontWeight.w600 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════ 嵌入式 ChatMessagesNotifier ═══════

extension on StateNotifier<List<ChatMessage>> {
  void addUser(String text) {
    state = [...state, ChatMessage(role: 'user', content: text)];
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
}
