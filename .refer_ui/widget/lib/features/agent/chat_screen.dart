/// Agent Chat Screen — AI 教学助手聊天界面。
///
/// 通过 Riverpod 连接 Agent Controller，实时渲染事件流。
/// 支持流式文本、工具调用可视化、思考过程展示。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:evergreen_multi_tools/core/config/app_config.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import '../../../widgets/mindmap_widget.dart';

import '../../../core/agent/event.dart' as agent_event;
import '../../../core/agent/message.dart' as agent_msg;
import 'providers/agent_provider.dart';
import '../../../core/agent/controller/controller.dart' show ControllerState;
import '../../../core/agent/memory/memory_agent.dart' show MemoryAgent;
import '../../../core/agent/memory/file_memory_store.dart' show FileMemoryStore;
import '../../../core/agent/memory/memory.dart' show Memory, MemoryStore, MemoryType;
import 'screens/global_memory_screen.dart';
import 'screens/skill_manager_screen.dart';
import '../../../core/network/dio_client.dart' show dioClientProvider;
import '../../../core/services/ocr_pipeline.dart' show OcrPipeline;
import '../../core/utils/greenix_path.dart';
import '../../../core/config/app_config.dart' show AppConfig;

/// AI 聊天主界面。
class AgentChatScreen extends ConsumerStatefulWidget {
  const AgentChatScreen({super.key});

  @override
  ConsumerState<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends ConsumerState<AgentChatScreen>
    with SingleTickerProviderStateMixin {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<agent_event.AgentEvent>? _eventSub;

  // ── 状态指示灯 ──
  String _statusText = '';
  String _currentTool = '';
  int _elapsedSeconds = 0;
  late Timer _elapsedTimer;
  late AnimationController _pulseAnim;
  bool _isRunning = false;

  // ── 流式更新节流 ──
  int _textThrottleCount = 0;

  bool _hasBubble = false; // 是否已创建初始气泡

  // ── 文件上传 ──
  String? _attachedFilePath;
  String? _attachedFileName;
  String? _attachedFileOcrText;
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
    });
    Future.microtask(() => _subscribeToEvents());
  }

  @override
  void dispose() {
    _elapsedTimer.cancel();
    _pulseAnim.dispose();
    _eventSub?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startIndicator() {
    setState(() {
      _isRunning = true;
      _elapsedSeconds = 0;
      _currentTool = '';
      _statusText = '思考中...';
    });
    _pulseAnim.repeat(reverse: true);
  }

  void _stopIndicator() {
    setState(() => _isRunning = false);
    _pulseAnim.stop();
    _pulseAnim.reset();
  }

  // ── 单轮对话累积（按时序拼接：思考 + 工具 + 结果 → 一条 AI 消息） ──
  final StringBuffer _pendingTimeline = StringBuffer();
  final StringBuffer _pendingAnswer = StringBuffer();
  String? _currentTurnUserText;

  void _subscribeToEvents() {
    debugPrint('[Chat:D] _subscribeToEvents() started');
    final runtime = ref.read(agentRuntimeProvider);
    final messagesNotifier = ref.read(chatMessagesProvider.notifier);

    _eventSub?.cancel();
    debugPrint('[Chat:D] subscribing to runtime.events stream...');
    _eventSub = runtime.events.listen((event) {
      debugPrint('[Chat:D] event received: kind=${event.kind.name}'
          ' textLen=${event.text?.length ?? 0}'
          ' tool=${event.tool?.name ?? "-"}'
          ' error=${event.error ?? "-"}');
      if (!mounted) return;

      switch (event.kind) {
        case agent_event.EventKind.turnStarted:
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(controllerStateProvider.notifier).state = ControllerState.running;
            }
          });
          _startIndicator();
          break;

        case agent_event.EventKind.reasoning:
          if (event.reasoning != null) {
            _pendingTimeline.write(event.reasoning);
            if (!_hasBubble) {
              _hasBubble = true;
              messagesNotifier.replaceLastAssistant('_thinking_');
            } else {
              _textThrottleCount++;
              if (_textThrottleCount >= 8) {
                messagesNotifier.replaceLastAssistant(_buildCombinedMessage());
                _textThrottleCount = 0;
              }
            }
          }
          break;

        case agent_event.EventKind.toolDispatch:
          if (event.tool != null) {
            // 工具调用前：将已累积的文本刷新到时间线（这些不是最终答案）
            _flushAnswerToTimeline();
            final isRead = event.tool!.name == 'read_global_memory';
            final isWrite = event.tool!.name == 'write_global_memory';
            final isMemoryTool = isRead || isWrite;
            final isSkillTool = event.tool!.name == 'run_skill' ||
                                event.tool!.name == 'list_skills';
            final icon = isMemoryTool ? '🧠' : isSkillTool ? '📋' : '🔧';
            final label = isRead ? '回忆ing' : isWrite ? '记忆ing' : isSkillTool ? '加载 Skill' : '调用';
            _pendingTimeline.writeln('\n$icon $label ${isMemoryTool ? '' : event.tool!.name}');
            setState(() {
              _currentTool = event.tool!.name;
              _statusText = isMemoryTool
                  ? '$icon ${isRead ? "回忆ing" : "记忆ing"}...'
                  : isSkillTool
                      ? '📋 ${event.tool!.name}...'
                      : '调用 ${event.tool!.name}...';
            });
            if (!_hasBubble) {
              _hasBubble = true;
              messagesNotifier.replaceLastAssistant(_buildCombinedMessage());
            } else {
              messagesNotifier.replaceLastAssistant(_buildCombinedMessage());
            }
          }
          break;

        case agent_event.EventKind.toolResult:
          if (event.tool != null) {
            final isRead = event.tool!.name == 'read_global_memory';
            final isWrite = event.tool!.name == 'write_global_memory';
            final isMemoryTool = isRead || isWrite;
            final isSkillTool = event.tool!.name == 'run_skill' ||
                                event.tool!.name == 'list_skills';
            final output = (event.tool!.output ?? event.tool!.error ?? '').trim();

            if (isMemoryTool || isSkillTool) {
              final icon = isMemoryTool ? '🧠' : '📋';
              _pendingTimeline.writeln('\n$icon **${event.tool!.name}** 结果：\n');
              const maxLines = 15;
              final lines = output.split('\n');
              if (lines.length > maxLines) {
                _pendingTimeline.writeln('${lines.take(maxLines).join('\n')}\n');
                _pendingTimeline.writeln('$icon _...完整内容已加载（共 ${lines.length} 行）_');
              } else {
                _pendingTimeline.writeln('$output\n');
              }
            } else {
              final preview = output.length > 200 ? '${output.substring(0, 200)}...' : output;
              _pendingTimeline.writeln('\n✅ ${event.tool!.name} → $preview');
            }
            messagesNotifier.replaceLastAssistant(_buildCombinedMessage());
            setState(() {
              _currentTool = '';
              if (isRead) _statusText = '🧠 回忆完成';
              else if (isWrite) _statusText = '🧠 记忆完成';
              else if (isSkillTool) _statusText = '📋 Skill 已加载';
              else _statusText = '处理结果...';
            });
          }
          break;

        case agent_event.EventKind.text:
          if (event.text != null) {
            _pendingAnswer.write(event.text);
            // 第一个 token 立刻创建气泡，后续节流
            if (!_hasBubble) {
              _hasBubble = true;
              messagesNotifier.replaceLastAssistant(_buildCombinedMessage());
            } else {
              _textThrottleCount++;
              if (_textThrottleCount >= 10 ||
                  event.text!.contains('。') ||
                  event.text!.contains('！') ||
                  event.text!.contains('？')) {
                messagesNotifier.replaceLastAssistant(_buildCombinedMessage());
                _textThrottleCount = 0;
              }
            }
          }
          break;

        case agent_event.EventKind.message:
          break;

        case agent_event.EventKind.turnDone:
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(controllerStateProvider.notifier).state = ControllerState.idle;
            }
          });
          // 最终合成完整消息
          messagesNotifier.replaceLastAssistant(
            _buildCombinedMessage(),
          );
          _stopIndicator();
          // 后台异步：MemoryAgent 按奥尔波特特质理论提取用户特质+关键事实
          final userText = _currentTurnUserText ?? '';
          final assistantText = _pendingAnswer.toString();
          if (userText.isNotEmpty && assistantText.isNotEmpty && mounted) {
            final provider = ref.read(agentRuntimeProvider).controller.provider;
            final memAgent = MemoryAgent(provider, greenixMemoriesDir);
            unawaited(memAgent.analyze(
              userText,
              assistantText,
              '${DateTime.now().year}年${DateTime.now().month}月',
            ).then((result) {
              final (added, updated, removed) = result;
              final notices = <String>[];
              if (added > 0) notices.add('新增 $added 条');
              if (updated > 0) notices.add('更新 $updated 条');
              if (removed > 0) notices.add('移除 $removed 条');
              if (notices.isNotEmpty) {
                final msg = '🧠 记忆已更新：${notices.join('，')}';
                messagesNotifier.addNotice(msg);
              }
            }));
          }
          // 自动保存会话
          final currentId = ref.read(activeSessionIdProvider);
          if (currentId != null) {
            ref.read(saveCurrentSessionProvider)(currentId);
          }
          break;

        default:
          break;
      }

      // 自动滚动到底部
      Future.microtask(() {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  /// 选择文件（图片/PDF），OCR 后拼接问题发送。
  void _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp', 'tiff', 'webp', 'pdf'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final path = file.path;
      if (path == null) return;

      setState(() {
        _attachedFilePath = path;
        _attachedFileName = file.name;
        _attaching = true;
      });

      // OCR（后台处理，用户无感知）
      final ocrText = await _ocrFile(path);
      if (ocrText == null) {
        setState(() => _attaching = false);
        return;
      }

      // 保存 OCR 结果，不污染输入框
      setState(() {
        _attachedFileOcrText = ocrText;
        _attaching = false;
      });
    } catch (e) {
      print('[Chat] 文件处理失败: $e');
      setState(() => _attaching = false);
    }
  }

  /// 对文件运行 OCR，返回合并文本。
  /// 两级降级由 OcrPipeline 统一处理。
  Future<String?> _ocrFile(String filePath) async {
    final dio = ref.read(dioClientProvider);
    final pipeline = OcrPipeline(dio);
    return await pipeline.recognizeFile(filePath);
  }

  /// 将 _pendingAnswer 内容刷新到时间线（工具调用前的文本不是最终答案）。
  void _flushAnswerToTimeline() {
    if (_pendingAnswer.isNotEmpty) {
      _pendingTimeline.write(_pendingAnswer.toString());
      _pendingAnswer.clear();
    }
  }

  /// 将时间线（思考 + 工具调用 + 结果，按时序）和最终回答合并为一条消息。
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

  Future<void> _sendMessage() async {
    var text = _inputController.text.trim();
    debugPrint('[Chat:D] _sendMessage() text="$text"');
    if (text.isEmpty && _attachedFileName == null) return;
    if (ref.read(controllerStateProvider) == ControllerState.running) {
      debugPrint('[Chat:D] already running, ignoring');
      return;
    }

    // 没有活动会话时自动创建
    if (ref.read(activeSessionIdProvider) == null) {
      debugPrint('[Chat:D] no active session, auto-creating...');
      ref.read(createSessionProvider)('新对话');
    }

    // 有附件时，后台拼接 OCR 内容（用户看不见）
    String displayText = text;
    if (_attachedFileName != null && _attachedFileOcrText != null) {
      displayText = text.isNotEmpty ? text : '(文件)';
      displayText += '\n\n[用户上传了文件: ${_attachedFileName}]';
      final realMsg = text.isNotEmpty
          ? '用户上传了一个文件: ${_attachedFileName}\n'
              '以下是该文件的OCR识别结果，可能存在：\n'
              '- 错别字（如"雷爱"应为"热爱"）\n'
              '- 数字错误（如"40%6"应为"40%"）\n'
              '- 乱码符号\n'
              '请基于上下文理解文件内容后继续阅读用户需求。\n\n'
              '【OCR内容】\n$_attachedFileOcrText\n\n'
              '用户需求: $text'
          : '用户上传了一个文件: ${_attachedFileName}\n'
              '以下是该文件的OCR识别结果，可能存在：\n'
              '- 错别字（如"雷爱"应为"热爱"）\n'
              '- 数字错误（如"40%6"应为"40%"）\n'
              '- 乱码符号\n'
              '请基于上下文理解文件内容后继续阅读。\n\n'
              '【OCR内容】\n$_attachedFileOcrText';
      text = realMsg;
    }

    final runtime = ref.read(agentRuntimeProvider);
    debugPrint('[Chat:D] runtime controller state=${runtime.controller.state}');
    final messagesNotifier = ref.read(chatMessagesProvider.notifier);

    // 用 displayText 展示给用户（含附件图标标记）
    messagesNotifier.addUser(displayText);

    // ⚠️ 在 clear 之前捕获用户原文（否则 MemoryAgent 收到空字符串永远不会运行）
    final userTextCapture = _inputController.text;
    _inputController.clear();

    // 清空附件状态
    setState(() {
      _attachedFilePath = null;
      _attachedFileName = null;
      _attachedFileOcrText = null;
    });

    // 注入全局记忆到 Controller（MemoryAgent 管理的跨会话 key facts）
    final store = FileMemoryStore(greenixMemoriesDir);
    final memCtx = await store.buildContextString();
    if (memCtx.isNotEmpty) {
      runtime.controller.setMemoryContext('## 全局记忆 (跨会话持久化)\n\n$memCtx');
    }

    // 重置渲染状态（从 turnStarted 移到这里，避免清掉 auto-read 记忆展示）
    _pendingTimeline.clear();
    _pendingAnswer.clear();
    _textThrottleCount = 0;
    _hasBubble = false;
    _currentTurnUserText = userTextCapture;

    // 用 text（含 OCR）发送给 AI
    debugPrint('[Chat:D] calling controller.send()...');
    runtime.controller.send(text);
    debugPrint('[Chat:D] controller.send() returned');
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);
    final sessionTitle = ref.watch(activeSessionTitleProvider);

    return Scaffold(
      drawer: _SessionDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(sessionTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            tooltip: 'Skill 管理',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SkillManagerScreen(),
              ));
            },
          ),
          if (messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空对话',
              onPressed: () {
                ref.read(chatMessagesProvider.notifier).clear();
                ref.read(agentRuntimeProvider).controller.newSession();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return _MessageBubble(message: messages[index]);
                    },
                  ),
          ),

          // 输入区域
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '我是你的 AI 教学助手',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
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
        _inputController.text = text;
        _sendMessage();
      },
    );
  }

  Widget _buildInputBar() {
    final runtime = ref.read(agentRuntimeProvider);
    final isRunning = ref.watch(controllerStateProvider) == ControllerState.running;
    final webSearch = ref.watch(webSearchEnabledProvider);
    final deepThinking = ref.watch(deepThinkingEnabledProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 状态指示灯
            if (_isRunning)
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (context, _) {
                  final opacity = 0.4 + _pulseAnim.value * 0.6;
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: opacity * 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12, height: 12,
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
              ),
            // 模式切换按钮行
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  _ToggleChip(
                    icon: Icons.language,
                    label: '联网搜索',
                    value: webSearch,
                    onChanged: (v) =>
                        ref.read(webSearchEnabledProvider.notifier).state = v,
                    activeColor: const Color(0xFF1565C0),
                  ),
                  const SizedBox(width: 8),
                  _ToggleChip(
                    icon: Icons.auto_awesome,
                    label: '深度思考',
                    value: deepThinking,
                    onChanged: (v) =>
                        ref.read(deepThinkingEnabledProvider.notifier).state = v,
                    activeColor: const Color(0xFF7B1FA2),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            // 输入行
            Row(
              children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                enabled: !isRunning,
                decoration: InputDecoration(
                  hintText: isRunning ? 'AI 正在思考...' : '输入你的问题...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: isRunning ? null : (_) => _sendMessage(),
                minLines: 1,
                maxLines: 4,
              ),
            ),
            // 附件状态
            if (_attachedFileOcrText != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: _attachedFileName ?? '文件',
                  child: Chip(
                    avatar: const Icon(Icons.insert_drive_file, size: 16),
                    label: Text(
                      (_attachedFileName ?? '文件').length > 12
                          ? '...${(_attachedFileName ?? '文件').substring((_attachedFileName ?? '文件').length - 12)}'
                          : _attachedFileName ?? '文件',
                      style: const TextStyle(fontSize: 12),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setState(() {
                      _attachedFilePath = null;
                      _attachedFileName = null;
                      _attachedFileOcrText = null;
                    }),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ),
            IconButton(
              onPressed: _attaching ? null : _pickFile,
              icon: _attaching
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file),
              tooltip: '上传图片或PDF',
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              onPressed: isRunning
                  ? () => runtime.controller.cancel()
                  : () => _sendMessage(),
              icon: Icon(isRunning ? Icons.stop : Icons.send),
              tooltip: isRunning ? '停止' : '发送',
            ),
          ], // end Row children
        ), // end Row (input)
      ], // end Column children
      ), // end Column
    ), // end SafeArea
  ); // end Container
  }
}

/// 模式切换芯片。
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
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: value ? Colors.white : null,
        ),
      ),
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

// ─── 消息气泡 ─────────────────────────────────────────────

class _MessageBubble extends StatefulWidget {
  final agent_msg.Message message;
  const _MessageBubble({required this.message});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _toolContentExpanded = false;
  bool _reasoningExpanded = false;
  final _thinkingScrollController = ScrollController();

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
        // 思考中：自动展开 + 滚到底部
        if (!_reasoningExpanded) {
          setState(() => _reasoningExpanded = true);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_thinkingScrollController.hasClients) {
            _thinkingScrollController.animateTo(
              _thinkingScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });
      } else if (!oldHasAnswer && newHasAnswer) {
        // 思考完成：自动折叠
        if (_reasoningExpanded) {
          setState(() => _reasoningExpanded = false);
        }
      }
    }
  }

  /// 预处理数学公式：$...$ → 内联代码，$$...$$ → 代码块。
  String _preprocessMath(String text) {
    // 块级 $$...$$ → ```math\n...\n```
    var result = text.replaceAllMapped(
      RegExp(r'\$\$([\s\S]*?)\$\$'),
      (m) => '```math\n${m.group(1)!.trim()}\n```',
    );
    // 行内 $...$ → `math:...`
    result = result.replaceAllMapped(
      RegExp(r'(?<!\$)\$([^$\n]+?)\$(?!\$)'),
      (m) => '`math:${m.group(1)!}`',
    );
    return result;
  }

  /// 提取 ::: 标记后的正文。
  String _extractAnswer(String content) {
    final m = RegExp(r'^:::reasoning\n[\s\S]*?\n:::\n?').firstMatch(content);
    return m == null ? content : content.substring(m.end);
  }

  @override
  Widget build(BuildContext context) {
    // 尝试将 message 转为 ChatMessage 以获取额外字段
    final chatMsg = widget.message is ChatMessage ? widget.message as ChatMessage : null;
    final isUser = widget.message.isUser;
    final isToolCall = chatMsg?.isToolCall ?? false;
    final isToolResult = chatMsg?.isToolResultCard ?? false;
    final isTool = isToolCall || isToolResult;
    final hasReasoning = widget.message.reasoningContent.isNotEmpty;
    var content = widget.message.content;

    // 检测文件附件标记 → 替换为图标显示
    String? attachedFile;
    final fileTagMatch = RegExp(r'\[用户上传了文件: (.+?)\]$').firstMatch(content);
    if (fileTagMatch != null) {
      attachedFile = fileTagMatch.group(1);
      content = content.substring(0, content.length - fileTagMatch.group(0)!.length).trim();
    }

    // 检测推理过程标记 :::reasoning...::: → 拆分为思考过程 + 正文
    String? reasoningContent;
    String mainContent = content;
    final reasoningMatch = RegExp(r'^:::reasoning\n([\s\S]*?)\n:::').firstMatch(content);
    if (reasoningMatch != null) {
      reasoningContent = reasoningMatch.group(1)?.trim();
      mainContent = content.substring(reasoningMatch.end).trim();
    }
    // 预处理数学公式：$...$ → `math:...`，$$...$$ → ```math\n...\n```
    mainContent = _preprocessMath(mainContent);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: isToolCall
                  ? const Color(0xFFE3F2FD)
                  : isToolResult
                      ? const Color(0xFFF3E5F5)
                      : Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                isToolCall ? Icons.touch_app :
                isToolResult ? Icons.description :
                Icons.auto_awesome,
                size: 16,
                color: isToolCall ? const Color(0xFF1565C0) :
                       isToolResult ? const Color(0xFF7B1FA2) :
                       Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              child: Container(
              padding: EdgeInsets.fromLTRB(12, isTool ? 8 : 12, 12, isTool ? 8 : 12),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.primary
                    : isToolCall
                        ? const Color(0xFFF5F9FF)
                        : isToolResult
                            ? const Color(0xFFFBF5FF)
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              // 用 Column 展示折叠区块
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [

                  // ── 工具调用卡片（折叠） ──
                  if (isToolCall)
                    _buildCollapsibleSection(
                      expanded: _toolContentExpanded,
                      onToggle: () => setState(() => _toolContentExpanded = !_toolContentExpanded),
                      headerIcon: Icons.touch_app,
                      headerColor: const Color(0xFF1565C0),
                      headerText: '调用了 $content',
                      body: content,
                      isTool: true,
                    ),

                  // ── 工具结果卡片（折叠） ──
                  if (isToolResult)
                    _buildCollapsibleSection(
                      expanded: _toolContentExpanded,
                      onToggle: () => setState(() => _toolContentExpanded = !_toolContentExpanded),
                      headerIcon: Icons.description,
                      headerColor: const Color(0xFF7B1FA2),
                      headerText: '工具结果',
                      body: content,
                      isTool: true,
                    ),

                  // ── 合并的思考过程（折叠：推理 + 工具调用） ──
                  if (!isTool && reasoningContent != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCollapsibleHeader(
                            expanded: _reasoningExpanded,
                            onToggle: () => setState(() => _reasoningExpanded = !_reasoningExpanded),
                            icon: Icons.psychology,
                            color: const Color(0xFFF57C00),
                            title: '思考过程',
                            badge: _countTools(reasoningContent!),
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
                                controller: _thinkingScrollController,
                                padding: const EdgeInsets.all(10),
                                child: _buildThinkingContent(reasoningContent!),
                              ),
                            ),
                        ],
                      ),
                    ),

                  // ── 文件附件标记 ──
                  if (isUser && attachedFile != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.insert_drive_file, size: 16, color: Colors.white.withValues(alpha: 0.9)),
                          const SizedBox(width: 4),
                          Text(
                            attachedFile!,
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9)),
                          ),
                        ],
                      ),
                    ),

                  // ── 思考中占位 ──
                  if (mainContent == '_thinking_' && !isUser)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('思考中...', style: TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                    )
                  else
                  // ── 主内容 ──
                  if (isUser)
                    SelectableText(
                      content,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                    )
                  else if (!isTool)
                    MarkdownBody(
                      data: mainContent
                          .replaceAll('<br>', '\n')
                          .replaceAll('<br/>', '\n')
                          .replaceAll('<br />', '\n'),
                      selectable: true,
                      builders: {
                        'pre': _PreBlockBuilder(),
                        'code': _InlineMathBuilder(),
                      },
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 14),
                        code: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          backgroundColor: Color(0xFFF5F5F5),
                          color: Color(0xFFE53935),
                        ),
                        h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        h2: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        h3: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        listBullet: const TextStyle(fontSize: 14),
                        strong: const TextStyle(fontWeight: FontWeight.bold),
                        em: const TextStyle(fontStyle: FontStyle.italic),
                        a: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
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
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.person, size: 16, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  /// 可折叠区块（含 header + 展开后内容）。
  Widget _buildCollapsibleSection({
    required bool expanded,
    required VoidCallback onToggle,
    required IconData headerIcon,
    required Color headerColor,
    required String headerText,
    required String body,
    bool isTool = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCollapsibleHeader(
          expanded: expanded,
          onToggle: onToggle,
          icon: headerIcon,
          color: headerColor,
          title: headerText,
        ),
        if (expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isTool ? const Color(0xFFF5F5F5) : const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isTool ? const Color(0xFFE0E0E0) : const Color(0xFFFFE082),
              ),
            ),
            child: isTool
                ? SelectableText(
                    body,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Color(0xFF616161),
                      height: 1.4,
                    ),
                  )
                : SelectableText(
                    body,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Color(0xFF795548),
                      height: 1.4,
                    ),
                  ),
          ),
      ],
    );
  }

  /// 渲染思考内容：普通文本 + 工具调用彩色高亮。
  Widget _buildThinkingContent(String text) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines.map((line) {
        final trimmed = line.trim();

        // 记忆工具行（🧠 回忆ing / 记忆ing / read/write 结果头）
        if (trimmed.startsWith('🧠')) {
          final isRecall = trimmed.contains('回忆') || trimmed.contains('read');
          final color = const Color(0xFF7B1FA2);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E5F5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.memory, size: 14, color: Color(0xFF7B1FA2)),
                  const SizedBox(width: 4),
                  Text(
                    isRecall ? '回忆全局记忆' : '写入全局记忆',
                    style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF7B1FA2),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Skill 行（📋 加载 Skill / Skill 结果 / 截断提示）
        if (trimmed.startsWith('📋')) {
          final color = const Color(0xFF00695C);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_stories, size: 14, color: Color(0xFF00695C)),
                  const SizedBox(width: 4),
                  Text(
                    trimmed.replaceAll('📋', '').trim(),
                    style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF00695C),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 工具调用行（蓝色 + 等宽字体）
        if (trimmed.startsWith('🔧')) {
          final name = trimmed.replaceAll('🔧', '').trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.touch_app, size: 14, color: Color(0xFF1565C0)),
                  const SizedBox(width: 4),
                  Text(name, style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1565C0),
                    fontFamily: 'monospace',
                  )),
                ],
              ),
            ),
          );
        }

        // 工具结果行（绿色 + 等宽字体）
        if (trimmed.startsWith('✅')) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2DA44E).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 14, color: Color(0xFF2DA44E)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      trimmed.replaceAll('✅', '').trim(),
                      style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF1B5E20),
                        fontFamily: 'monospace',
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 普通推理文本
        if (line.trim().isEmpty) return const SizedBox(height: 4);
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            line,
            style: const TextStyle(fontSize: 12, color: Color(0xFF795548), height: 1.5),
          ),
        );
      }).toList(),
    );
  }

  /// 统计思考内容中使用的工具数量。
  int _countTools(String content) {
    return '🔧'.allMatches(content).length +
        '🧠'.allMatches(content).length +
        '📋'.allMatches(content).length;
  }

  /// 可折叠区块的 header 行。
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
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}

/// 内联数学公式渲染器（`math:...` 语法）。
class _InlineMathBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    final text = element.textContent;
    if (!text.startsWith('math:')) return null; // 普通代码，走默认渲染
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
  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    if (element.children == null || element.children!.isEmpty) return null;
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

    // 普通代码块：用 SelectableText 安全渲染（避免 flutter_markdown _inlines.isEmpty 崩溃）
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Session Drawer
// ═══════════════════════════════════════════════════════════════════

class _SessionDrawer extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionListProvider);
    final activeId = ref.watch(activeSessionIdProvider);

    return Drawer(
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Row(
              children: [
                Expanded(
                  child: Text('对话历史',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.add_comment),
                  tooltip: '新建对话',
                  onPressed: () {
                    ref.read(createSessionProvider)('新对话');
                    Navigator.of(context).pop(); // close drawer
                  },
                ),
              ],
            ),
          ),
          // Session list
          Expanded(
            child: sessionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败: $e')),
              data: (sessions) {
                if (sessions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text('暂无对话',
                            style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (_, i) {
                    final s = sessions[i];
                    final isActive = s.id == activeId;
                    final subtitle = s.messages.isNotEmpty
                        ? '${s.messages.length} 条消息 · ${_formatDate(s.updatedAt)}'
                        : _formatDate(s.updatedAt);

                    return ListTile(
                      selected: isActive,
                      selectedTileColor:
                          Theme.of(context).colorScheme.primaryContainer
                              .withValues(alpha: 0.4),
                      title: Text(s.title.isEmpty ? '新对话' : s.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight:
                                  isActive ? FontWeight.w600 : null)),
                      subtitle: Text(subtitle,
                          style: const TextStyle(fontSize: 12)),
                      onTap: () {
                        if (!isActive) {
                          ref.read(switchSessionProvider)(s.id);
                        }
                        Navigator.of(context).pop();
                      },
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, size: 18),
                        onSelected: (action) {
                          if (action == 'rename') {
                            _showRenameDialog(context, ref, s.id, s.title);
                          } else if (action == 'delete') {
                            ref.read(deleteSessionProvider)(s.id);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'rename', child: Text('重命名')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('删除')),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // 全局记忆入口
          const Divider(),
          ListTile(
            leading: const Icon(Icons.memory),
            title: const Text('全局记忆', style: TextStyle(fontSize: 13)),
            subtitle: const Text('查看和管理跨会话的特质与事实',
                style: TextStyle(fontSize: 11)),
            dense: true,
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GlobalMemoryScreen(),
              ));
            },
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day}';
  }

  void _showRenameDialog(
      BuildContext context, WidgetRef ref, String id, String currentTitle) {
    final controller = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新标题'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isNotEmpty) {
                ref.read(renameSessionProvider)(id, t);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

