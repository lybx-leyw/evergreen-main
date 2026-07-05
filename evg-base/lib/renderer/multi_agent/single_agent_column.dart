/// 独立智能体列——自包含的 Agent 对话组件。
///
/// 通过 [AgentAssembly.fromConfig] 工厂创建隔离的 Agent 实例，
/// 而非手动构建 Dio→Provider→Registry→Controller 栈。
///
/// ## PLAN_NOW 整合
/// - [AgentAssembly] 负责: 工具白名单、记忆隔离、Skill筛选、预设解析
/// - 本组件负责: UI渲染、事件处理、会话切换
///
/// 用于 [MultiAgentView] 的每一栏。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/agent/agent.dart' as agent;
import '../../core/agent/agent_factory.dart';
import '../../core/agent/memory/file_memory_store.dart';
import '../../core/agent/skill/skill.dart';

/// 单栏独立智能体配置。
class AgentColumnConfig {
  final String id; // 唯一标识（如 "p0-c0"）
  final String name; // 显示名称
  final String apiKey; // DeepSeek API Key

  // ── AgentAssembly 依赖 ──
  /// 共享的 LLM Provider（同 API Key，复用连接）。
  final agent.Provider? sharedProvider;

  /// 全局 Skill 索引（AgentAssembly 从中按 skills.mode 筛选）。
  final SkillIndex? globalSkillIndex;

  /// 全局记忆存储（MemoryAgent 写入位置）。
  final FileMemoryStore? globalMemoryStore;

  /// PLAN_NOW §五 ai-assistant 配置（含 preset）。
  final Map<String, dynamic> aiConfig;

  const AgentColumnConfig({
    required this.id,
    required this.name,
    required this.apiKey,
    this.sharedProvider,
    this.globalSkillIndex,
    this.globalMemoryStore,
    this.aiConfig = const {},
  });
}

/// 单栏自包含智能体。
class SingleAgentColumn extends StatefulWidget {
  final AgentColumnConfig config;

  const SingleAgentColumn({super.key, required this.config});

  @override
  State<SingleAgentColumn> createState() => _SingleAgentColumnState();
}

class _SingleAgentColumnState extends State<SingleAgentColumn> {
  // ── AgentAssembly（PLAN_NOW 工厂） ──
  AgentAssembly? _assembly;

  // ── 便捷引用（指向 assembly 内部组件） ──
  agent.Controller? get _controller => _assembly?.controller;
  agent.StreamEventSink? get _sink => _assembly?.eventSink;
  agent.Session? get _session => _assembly?.session;

  // ── UI 状态 ──
  final List<_ChatMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _isStreaming = false;
  String _statusText = '';
  Timer? _statusTimer;
  int _statusSeconds = 0;
  StreamSubscription<agent.AgentEvent>? _eventSub;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ── 会话 ──
  List<agent.Session> _sessionList = [];
  String _activeSessionId = '';

  String get _title => widget.config.name;

  @override
  void initState() {
    super.initState();
    _initAgent();
  }

  void _initAgent() {
    final cfg = widget.config;

    // 确保全局依赖可用
    if (cfg.sharedProvider == null) {
      debugPrint('[SingleAgentColumn] ⚠️ ${cfg.id}: sharedProvider 未提供，Agent 不可用');
      return;
    }
    if (cfg.globalSkillIndex == null) {
      debugPrint('[SingleAgentColumn] ⚠️ ${cfg.id}: globalSkillIndex 未提供');
      return;
    }
    if (cfg.globalMemoryStore == null) {
      debugPrint('[SingleAgentColumn] ⚠️ ${cfg.id}: globalMemoryStore 未提供');
      return;
    }

    // 使用 PLAN_NOW AgentAssembly 工厂创建隔离 Agent
    // 替代原有的手动构建 Dio→Provider→Registry→Controller 栈
    try {
      _assembly = AgentAssembly.fromConfig(
        moduleId: 'multi-agent/${cfg.id}',
        config: cfg.aiConfig,
        sharedProvider: cfg.sharedProvider!,
        globalSkillIndex: cfg.globalSkillIndex!,
        globalMemoryStore: cfg.globalMemoryStore!,
      );
      debugPrint('[SingleAgentColumn] ✅ ${cfg.id}: AgentAssembly 创建成功');
      debugPrint('[SingleAgentColumn] ${cfg.id}:'
          ' tools=${_assembly!.registry.enabled().length}'
          ' skills=${_assembly!.skillIndex.all().length}'
          ' memory=${_assembly!.memory != null}');
    } catch (e, st) {
      debugPrint('[SingleAgentColumn] ❌ ${cfg.id}: AgentAssembly 创建失败: $e');
      debugPrint('[SingleAgentColumn] stack: $st');
      return;
    }

    // 订阅事件流
    _eventSub = _assembly!.eventSink.stream.listen(_onAgentEvent);
  }

  void _loadSessions() {
    // AgentAssembly 管理自己的 Session，本组件不再维护独立的 SessionStore。
    // 会话管理由 AgentAssembly 内部的 Controller 负责。
    // 本组件仅维护 UI 状态的 _messages 列表。
    final sess = _session;
    if (sess != null && sess.messages.isNotEmpty) {
      _activeSessionId = sess.id;
      _restoreSession(sess);
    }
  }

  void _restoreSession(agent.Session s) {
    _messages.clear();
    for (final m in s.messages) {
      _messages.add(_ChatMessage(
        role: m.role == agent.Role.user ? 'user' : 'assistant',
        content: m.content,
      ));
    }
    setState(() {});
  }

  void _switchSession(agent.Session s) {
    _activeSessionId = s.id;
    _controller?.setSession(s);
    _restoreSession(s);
  }

  void _newSession() {
    final ctrl = _controller;
    if (ctrl == null) return;
    final newSess = agent.Session();
    _activeSessionId = newSess.id;
    ctrl.setSession(newSess);
    _messages.clear();
    _sessionList = [newSess, ..._sessionList];
    setState(() {});
  }

  void _deleteSession(agent.Session s) {
    _sessionList.removeWhere((x) => x.id == s.id);
    if (_activeSessionId == s.id) {
      final ctrl = _controller;
      if (ctrl != null) {
        final newSess = agent.Session();
        _activeSessionId = newSess.id;
        ctrl.setSession(newSess);
      }
      _messages.clear();
    }
    setState(() {});
  }

  // ── 事件处理 ──

  void _onAgentEvent(agent.AgentEvent event) {
    if (!mounted) return;
    switch (event.kind) {
      case agent.EventKind.turnStarted:
        setState(() {
          _statusText = '思考中...';
          _statusSeconds = 0;
        });
        _startStatusTimer();
        break;

      case agent.EventKind.text:
        _updateOrAppendAssistant(event.text ?? '');
        break;

      case agent.EventKind.reasoning:
        // 推理过程，不直接显示到消息气泡中
        break;

      case agent.EventKind.toolDispatch:
        if (event.tool != null) {
          setState(() {
            _statusText = '🔧 ${event.tool!.name}';
            _statusSeconds = 0;
          });
        }
        break;

      case agent.EventKind.toolResult:
        if (event.tool != null) {
          final ok = event.tool!.error == null;
          setState(() => _statusText = ok ? '✅ ${event.tool!.name}' : '❌ ${event.tool!.name}');
        }
        break;

      case agent.EventKind.toolProgress:
        if (event.tool != null) {
          setState(() => _statusText = '⏳ ${event.tool!.name}...');
        }
        break;

      case agent.EventKind.message:
        // 完整消息，可忽略（流式已处理）
        break;

      case agent.EventKind.turnDone:
        setState(() {
          _isStreaming = false;
          _statusText = '';
        });
        _stopStatusTimer();
        if (event.error != null && event.error!.isNotEmpty) {
          setState(() {
            _messages.add(_ChatMessage(
                role: 'assistant', content: '⚠ ${event.error}'));
          });
        }
        // AgentAssembly 管理 session 持久化
        break;

      case agent.EventKind.notice:
        final notice = event.text ?? '';
        if (notice.isNotEmpty) {
          setState(() => _statusText = 'ℹ $notice');
        }
        break;

      case agent.EventKind.phase:
        if (event.text != null && event.text!.isNotEmpty) {
          setState(() => _statusText = '📋 ${event.text}');
        }
        break;

      case agent.EventKind.retrying:
        if (event.retry != null) {
          setState(
              () => _statusText = '🔄 重试 ${event.retry!.attempt}/${event.retry!.maxRetries}: ${event.retry!.reason}');
        }
        break;

      case agent.EventKind.usage:
        // Token 用量，忽略
        break;

      case agent.EventKind.approvalRequest:
      case agent.EventKind.askRequest:
      case agent.EventKind.compactionStarted:
      case agent.EventKind.compactionDone:
      case agent.EventKind.mcpSurfaceReady:
        // 暂不处理的类型
        break;
    }
    _scrollToBottom();
  }

  void _updateOrAppendAssistant(String text) {
    if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
      final last = _messages.last;
      _messages[_messages.length - 1] = _ChatMessage(
        role: 'assistant',
        content: last.content + text,
      );
    } else {
      _messages.add(_ChatMessage(role: 'assistant', content: text));
    }
    setState(() {});
  }

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusSeconds = 0;
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _statusSeconds++);
    });
  }

  void _stopStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── 发送消息 ──

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isStreaming) return;
    final ctrl = _controller;
    if (ctrl == null) return;

    _inputCtrl.clear();
    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
      _isStreaming = true;
      _statusText = '思考中...';
      _statusSeconds = 0;
    });
    _startStatusTimer();
    _scrollToBottom();

    ctrl.send(text);
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildAppBar(isDark),
      drawer: _buildDrawer(isDark),
      body: Column(
        children: [
          // 状态栏
          if (_isStreaming) _buildStatusBar(isDark),
          // 消息列表
          Expanded(child: _buildMessageList(isDark)),
          // 输入栏
          _buildInputBar(isDark),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    final color = isDark ? Colors.white70 : Colors.black87;
    return AppBar(
      title: Text(_title, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.menu, size: 18, color: color),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.add_comment_outlined, size: 16, color: color),
          tooltip: '新会话',
          onPressed: _newSession,
        ),
      ],
    );
  }

  Widget _buildDrawer(bool isDark) {
    final color = isDark ? Colors.white70 : Colors.black87;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 18),
                  const SizedBox(width: 8),
                  Text('[$_title] 会话历史', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
                  const Spacer(),
                  IconButton(icon: Icon(Icons.add, size: 18, color: color), onPressed: _newSession, tooltip: '新建会话'),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: _sessionList.isEmpty
                  ? Center(child: Text('暂无会话', style: TextStyle(color: Colors.grey, fontSize: 13)))
                  : ListView.builder(
                      itemCount: _sessionList.length,
                      itemBuilder: (_, i) {
                        final s = _sessionList[i];
                        final active = s.id == _activeSessionId;
                        return ListTile(
                          dense: true,
                          selected: active,
                          title: Text(s.title.isEmpty ? '会话 ${s.id.substring(0, 8)}' : s.title,
                              style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.normal, color: color)),
                          subtitle: Text(_fmtTime(s.updatedAt), style: const TextStyle(fontSize: 10)),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade300),
                            onPressed: () => _deleteSession(s),
                          ),
                          onTap: () {
                            if (s.id != _activeSessionId) _switchSession(s);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: isDark ? Colors.blueGrey.shade900 : Colors.blue.shade50,
      child: Row(
        children: [
          _StatusDot(isStreaming: _isStreaming),
          const SizedBox(width: 8),
          Text(_statusText, style: TextStyle(fontSize: 11, color: isDark ? Colors.blue.shade200 : Colors.blue.shade700)),
          const Spacer(),
          if (_statusSeconds > 0)
            Text('${_statusSeconds}s', style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildMessageList(bool isDark) {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_outlined, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('[$_title] 就绪', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _buildBubble(_messages[i], isDark),
    );
  }

  Widget _buildBubble(_ChatMessage msg, bool isDark) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isUser
              ? (isDark ? Colors.blue.shade700 : Colors.blue.shade100)
              : (isDark ? Colors.grey.shade800 : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(msg.content, style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87)),
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              enabled: !_isStreaming,
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: _isStreaming ? '回复中...' : '输入消息...',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                filled: true,
                fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
              ),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(_isStreaming ? Icons.stop : Icons.send, size: 18,
                color: isDark ? Colors.blue.shade300 : Colors.blue.shade600),
            onPressed: _isStreaming ? () {} : _sendMessage,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _stopStatusTimer();
    _assembly?.dispose(); // AgentAssembly 管理所有 Agent 组件生命周期
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  static String _fmtTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── 辅助类 ──

class _ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  const _ChatMessage({required this.role, required this.content});
}

class _StatusDot extends StatefulWidget {
  final bool isStreaming;
  const _StatusDot({required this.isStreaming});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    if (widget.isStreaming) _anim.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.isStreaming && !_anim.isAnimating) {
      _anim.repeat(reverse: true);
    } else if (!widget.isStreaming) {
      _anim.stop();
      _anim.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim.drive(Tween(begin: 0.3, end: 1.0)),
      child: Container(width: 8, height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: widget.isStreaming ? Colors.blue : Colors.green)),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }
}
