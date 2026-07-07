import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/providers.dart';
import '../providers/tutor_provider.dart';

/// Interactive tutoring screen with streaming AI chat.
///
/// Ports the interactive tutoring from app/js/components/notes.js + electron pipeline.
class TutorScreen extends ConsumerStatefulWidget {
  const TutorScreen({super.key});
  @override
  ConsumerState<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends ConsumerState<TutorScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  String _persona = 'liyuwen';
  ProviderSubscription<StreamingChatState>? _streamSub;
  bool _historyLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }

  @override
  void dispose() {
    _streamSub?.close();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 从 SharedPreferences 加载对话历史。
  Future<void> _loadChatHistory() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final raw = prefs.getStringList('tutor_chat_history') ?? [];
      if (raw.isEmpty) return;
      final messages = raw
          .map((s) {
            try {
              return ChatMessage.fromJson(
                  jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<ChatMessage>()
          .toList();
      if (messages.isNotEmpty && mounted) {
        setState(() {
          _messages.addAll(messages);
          _historyLoaded = true;
        });
        _scrollToBottom();
      }
    } catch (_) {
      // 加载历史静默失败
    }
  }

  /// 保存对话历史到 SharedPreferences（最多保留 50 条）。
  Future<void> _saveChatHistory() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      // 只保存最近的 50 条
      final toSave = _messages.length > 50
          ? _messages.sublist(_messages.length - 50)
          : _messages;
      final raw = toSave.map((m) => jsonEncode(m.toJson())).toList();
      await prefs.setStringList('tutor_chat_history', raw);
    } catch (_) {
      // 持久化静默失败
    }
  }

  /// 清空对话历史。
  Future<void> _clearChatHistory() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.remove('tutor_chat_history');
    } catch (_) {}
    setState(() => _messages.clear());
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(streamingChatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('交互式辅导'),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, size: 20),
              tooltip: '清空对话',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清空对话'),
                    content: const Text('确定要清空所有对话记录吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(ctx, rootNavigator: true).pop();
                          _clearChatHistory();
                        },
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                );
              },
            ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'liyuwen', label: Text('黎雨雯')),
              ButtonSegment(value: 'lebus', label: Text('莱布斯')),
            ],
            selected: {_persona},
            onSelectionChanged: (s) => setState(() => _persona = s.first),
            style: ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (chatState.isStreaming ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length && chatState.isStreaming) {
                  return _ChatBubble(
                    isUser: false,
                    text: chatState.content ?? '思考中...',
                    isStreaming: true,
                  );
                }
                final msg = _messages[i];
                return _ChatBubble(
                  isUser: msg.isUser,
                  text: msg.text,
                  reasoning: msg.reasoning,
                );
              },
            ),
          ),
          // Quick actions
          if (_messages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                      label: const Text('开始辅导'),
                      onPressed: () => _sendMessage('start')),
                  ActionChip(
                      label: const Text('随机测验'),
                      onPressed: () => _sendMessage('给我来个小测验')),
                ],
              ),
            ),
          // Input bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: '输入消息或反馈...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _sendMessage(),
                  icon: const Icon(Icons.send),
                  label: const Text('发送'),
                ),
              ],
            ),
          ),
          // Feedback buttons
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _feedbackButton('懂了', '好的懂了'),
                _feedbackButton('不懂', '这里不懂'),
                _feedbackButton('展开', '展开讲讲'),
                _feedbackButton('跳过', '跳过'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _feedbackButton(String label, String feedback) {
    return TextButton(
      onPressed: () => _sendMessage(feedback),
      child: Text(label),
    );
  }

  void _sendMessage([String? text]) {
    final content = (text ?? _messageController.text.trim());
    if (content.isEmpty) return;
    _messageController.clear();

    final userMsg = ChatMessage(isUser: true, text: content);
    setState(() => _messages.add(userMsg));
    _scrollToBottom();
    _saveChatHistory();

    // Build conversation history
    final apiMessages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': _persona == 'liyuwen'
            ? '你是黎雨雯教授，一位耐心细致的女教师。用中文教学，每次回复控制在40-80字，引导学生思考。'
            : '你是莱布斯教授，一位严谨博学的男教授。用中文教学，每次回复控制在40-80字，逻辑严谨，善于启发。',
      },
      for (final msg in _messages)
        {'role': msg.isUser ? 'user' : 'assistant', 'content': msg.text},
    ];

    ref.read(streamingChatProvider.notifier).sendMessage(apiMessages);

    // Register exactly one stream completion listener, replacing any prior one
    _streamSub?.close();
    _streamSub = ref.listenManual(streamingChatProvider, (prev, next) {
      if (!next.isStreaming && next.content != null && next.error == null) {
        _streamSub?.close();
        _streamSub = null;
        setState(() {
          _messages.removeWhere((m) => m.isStreaming);
          _messages.add(ChatMessage(
              isUser: false,
              text: next.content!,
              reasoning: next.reasoning));
        });
        _scrollToBottom();
        _saveChatHistory();
        ref.read(streamingChatProvider.notifier).clear();
      }
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
}

class ChatMessage {
  final bool isUser;
  final String text;
  final String? reasoning;
  final bool isStreaming;

  const ChatMessage({
    required this.isUser,
    required this.text,
    this.reasoning,
    this.isStreaming = false,
  });

  Map<String, dynamic> toJson() => {
        'isUser': isUser,
        'text': text,
        'reasoning': reasoning,
        'isStreaming': isStreaming,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        isUser: json['isUser'] as bool? ?? false,
        text: json['text'] as String? ?? '',
        reasoning: json['reasoning'] as String?,
        isStreaming: json['isStreaming'] as bool? ?? false,
      );
}

class _ChatBubble extends StatelessWidget {
  final bool isUser;
  final String text;
  final String? reasoning;
  final bool isStreaming;

  const _ChatBubble({
    required this.isUser,
    required this.text,
    this.reasoning,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) const Icon(Icons.smart_toy, size: 24),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reasoning != null && reasoning!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(reasoning!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic)),
                    ),
                  Text(text),
                  if (isStreaming)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2)),
                    ),
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser) const Icon(Icons.person, size: 24),
        ],
      ),
    );
  }
}
