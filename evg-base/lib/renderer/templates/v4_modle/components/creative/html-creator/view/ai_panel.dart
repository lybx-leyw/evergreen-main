/// 底部 AI 面板 —— 指令输入 + 流式输出 + 工具调用可见。
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/services/html_ai_service.dart';

/// AI 生成回调参数。
class AiGeneratedResult {
  final String? html;
  final String? css;
  final String? js;
  const AiGeneratedResult({this.html, this.css, this.js});
}

typedef OnAiGenerated = void Function({String? html, String? css, String? js});

class AiPanel extends StatefulWidget {
  final HtmlAiService aiService;
  final String htmlContent;
  final String cssContent;
  final String jsContent;
  final String? selectedDataSource;
  final String? dataPreview;
  final OnAiGenerated? onGenerated;

  /// 当前画布名（绑定态 UI：AI 会话归属哪个画布）。
  final String? canvasName;

  const AiPanel({
    super.key,
    required this.aiService,
    required this.htmlContent,
    this.cssContent = '',
    this.jsContent = '',
    this.selectedDataSource,
    this.dataPreview,
    this.onGenerated,
    this.canvasName,
  });

  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];
  StreamSubscription<HtmlAiEvent>? _sub;
  String? _lastCanvasId;

  @override
  void initState() {
    super.initState();
    _sub = widget.aiService.events.listen(_onAiEvent);
    _restoreUiMessages();
  }

  @override
  void didUpdateWidget(covariant AiPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 画布切换后恢复 UI 消息
    if (widget.aiService.canvasId != _lastCanvasId) {
      _lastCanvasId = widget.aiService.canvasId;
      _restoreUiMessages();
    }
  }

  void _restoreUiMessages() {
    final msgs = widget.aiService.uiMessages;
    if (msgs == null || msgs.isEmpty) return;
    _messages.clear();
    for (final m in msgs) {
      _messages.add(_ChatMessage(
        role: m['role'] as String? ?? 'ai',
        text: m['text'] as String? ?? '',
        reasoning: m['reasoning'] as String?,
      ));
    }
    _lastCanvasId = widget.aiService.canvasId;
    debugPrint('[AiPanel] 📂 恢复 UI 消息: ${_messages.length} 条');
  }

  @override
  void dispose() {
    _sub?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onAiEvent(HtmlAiEvent e) {
    setState(() {
      if (e.status == HtmlAiStatus.thinking && _messages.isNotEmpty &&
          _messages.last.role == 'ai') {
        _messages.last.text = e.text ?? '';
        _messages.last.reasoning = e.reasoning;
      } else if (e.status == HtmlAiStatus.executing && e.toolName != null) {
        _messages.add(_ChatMessage(role: 'tool', text: '🔧 ${e.toolName}'));
      } else if (e.status == HtmlAiStatus.done) {
        if (_messages.isNotEmpty && _messages.last.role == 'ai') {
          _messages.last.text = e.text ?? '';
        }
        _extractCodeBlocks(e.text ?? '');
        _syncUiMessages(); // 持久化 UI 消息
      } else if (e.status == HtmlAiStatus.error) {
        _messages.add(_ChatMessage(role: 'error', text: '❌ ${e.error}'));
      }
    });
    _scrollToBottom();
  }

  void _syncUiMessages() {
    widget.aiService.uiMessages = _messages
        .map((m) => {'role': m.role, 'text': m.text, if (m.reasoning != null) 'reasoning': m.reasoning})
        .toList();
  }

  /// 从 AI 回复中提取 HTML/CSS/JS 代码块。
  void _extractCodeBlocks(String text) {
    String? html;
    String? css;
    String? js;

    // 提取 ```html ... ```
    final htmlMatch = RegExp(r'```html\n([\s\S]*?)```', multiLine: true).firstMatch(text);
    if (htmlMatch != null) html = htmlMatch.group(1)!.trim();

    // 提取 ```css ... ```
    final cssMatch = RegExp(r'```css\n([\s\S]*?)```', multiLine: true).firstMatch(text);
    if (cssMatch != null) css = cssMatch.group(1)!.trim();

    // 提取 ```js ... ``` 或 ```javascript ... ```
    final jsMatch = RegExp(r'```(?:js|javascript)\n([\s\S]*?)```', multiLine: true).firstMatch(text);
    if (jsMatch != null) js = jsMatch.group(1)!.trim();

    if (html != null || css != null || js != null) {
      widget.onGenerated?.call(html: html, css: css, js: js);
    }
  }

  void _send() {
    final instruction = _inputController.text.trim();
    if (instruction.isEmpty) return;

    _messages.add(_ChatMessage(role: 'user', text: instruction));
    _messages.add(_ChatMessage(role: 'ai', text: ''));
    _inputController.clear();
    _syncUiMessages(); // 用户消息即时持久化

    final ctx = HtmlAiContext(
      htmlContent: widget.htmlContent,
      selectedDataSource: widget.selectedDataSource,
      dataPreview: widget.dataPreview,
      userInstruction: _buildFullInstruction(instruction),
    );

    widget.aiService.send(ctx);
    _scrollToBottom();
  }

  /// 构建完整的用户指令，包含当前 CSS/JS 上下文。
  String _buildFullInstruction(String instruction) {
    final buf = StringBuffer();
    buf.writeln(instruction);
    if (widget.cssContent.isNotEmpty) {
      buf.writeln('\n## 当前 CSS\n```css\n${widget.cssContent}\n```');
    }
    if (widget.jsContent.isNotEmpty) {
      buf.writeln('\n## 当前 JS\n```javascript\n${widget.jsContent}\n```');
    }
    return buf.toString();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildMessages()),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final status = widget.aiService.status;
    final icon = switch (status) {
      HtmlAiStatus.thinking => Icons.psychology,
      HtmlAiStatus.executing => Icons.build,
      HtmlAiStatus.error => Icons.error,
      _ => Icons.auto_awesome,
    };
    final label = switch (status) {
      HtmlAiStatus.thinking => 'AI 思考中...',
      HtmlAiStatus.executing => 'AI 执行中...',
      HtmlAiStatus.error => 'AI 出错',
      _ => 'AI 助手',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(icon, size: 14, color: status == HtmlAiStatus.thinking ? Colors.deepPurple : null),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          // ── 绑定态：会话归属画布 + 消息数 + 断点续作标记（T1）──
          const SizedBox(width: 8),
          _buildBindingBadge(),
          const Spacer(),
          if (status == HtmlAiStatus.thinking || status == HtmlAiStatus.executing)
            TextButton(onPressed: () => widget.aiService.cancel(), child: const Text('取消', style: TextStyle(fontSize: 11))),
          TextButton(onPressed: () { setState(() => _messages.clear()); widget.aiService.reset(); }, child: const Text('重置', style: TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  /// 当前画布绑定态徽标：画布名 · N 条消息 · 断点续作（若有历史）。
  Widget _buildBindingBadge() {
    final theme = Theme.of(context);
    final name = widget.canvasName;
    final count = widget.aiService.sessionMessageCount;
    final resumed = widget.aiService.restoredFromSession;
    final chips = <Widget>[];
    if (name != null && name.isNotEmpty) {
      chips.add(_badgeChip(theme, Icons.palette_outlined, name, tooltip: 'AI 会话绑定画布'));
    }
    if (resumed) {
      chips.add(_badgeChip(theme, Icons.history, '$count 条 · 续作', tooltip: '已恢复该画布历史会话，AI 将断点续作'));
    } else if (count > 0) {
      chips.add(_badgeChip(theme, Icons.forum_outlined, '$count 条', tooltip: '当前画布会话消息数'));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chips.length; i++) ...[if (i > 0) const SizedBox(width: 4), chips[i]],
      ],
    );
  }

  Widget _badgeChip(ThemeData theme, IconData icon, String text, {required String tooltip}) {
    final resumed = text.contains('续作');
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: resumed
              ? Colors.amber.withValues(alpha: 0.18)
              : theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: resumed ? Colors.amber.shade800 : theme.colorScheme.primary),
            const SizedBox(width: 3),
            Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: resumed ? Colors.amber.shade900 : theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: _messages.length,
      itemBuilder: (ctx, i) => _buildBubble(_messages[i]),
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    final theme = Theme.of(context);
    final isUser = msg.role == 'user';
    final isTool = msg.role == 'tool';
    final isError = msg.role == 'error';

    if (isTool) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(msg.text, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
      );
    }

    if (isError) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
        child: Text(msg.text, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isUser ? theme.colorScheme.primaryContainer : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (msg.reasoning != null && msg.reasoning!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
              child: Text(msg.reasoning!, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
            ),
          SelectableText(
            msg.text.isNotEmpty ? msg.text : (isUser ? '' : '...'),
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  bool get _isBusy {
    final s = widget.aiService.status;
    return s == HtmlAiStatus.thinking || s == HtmlAiStatus.executing;
  }

  Widget _buildInput() {
    final busy = _isBusy;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 忙碌状态提示条
          if (busy)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.aiService.status == HtmlAiStatus.executing
                          ? 'AI 正在执行工具操作，请稍候...'
                          : 'AI 正在思考中，请稍候...',
                      style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.aiService.cancel(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('取消', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          // 输入行
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  enabled: !busy,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: busy ? 'AI 正在工作中，请等待当前任务完成...' : '告诉 AI 你要做什么... (如: 帮我做一个数据表格)',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    isDense: true,
                    filled: busy,
                    fillColor: busy ? Colors.grey.shade100 : null,
                  ),
                  onSubmitted: (_) { if (!busy) _send(); },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: busy ? null : _send,
                color: busy ? Colors.grey : Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String role; // user / ai / tool / error
  String text;
  String? reasoning;

  _ChatMessage({required this.role, required this.text, this.reasoning});
}
