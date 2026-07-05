/// Controller 会话驱动器 — 对应 reasonix/internal/control/controller.go。
library;

import 'dart:async';

import 'package:evergreen_base/core/agent/event.dart';
import 'package:evergreen_base/core/agent/message.dart';
import 'package:evergreen_base/core/agent/tool.dart';
import 'package:evergreen_base/core/agent/provider.dart';
import 'package:evergreen_base/core/agent/agent/agent.dart';
import 'package:evergreen_base/core/agent/agent/session.dart';
import 'package:evergreen_base/core/agent/agent/compose.dart';
import 'package:evergreen_base/core/agent/memory/facade.dart';
import 'package:evergreen_base/core/agent/memory/memory_agent.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';

enum ControllerState { idle, running, awaitingApproval }

// ═══════ Controller ═══════

/// 前端与 Agent 之间的桥梁。管理 Send → Run → Events 生命周期。
class Controller {
  final Provider _provider;
  final Registry _registry;
  final EventSink _sink;

  Session _session;
  Agent? _currentAgent;
  StreamSubscription<AgentEvent>? _eventSub;
  ControllerState _state = ControllerState.idle;
  bool _disposed = false;

  // 系统提示词配置
  String _systemPrompt = defaultSystemPrompt;
  String _toolHint = defaultToolHint;
  String _memoryContext = '';

  /// 记忆门面——自动构建 memory context。
  final MemoryFacade? _memory;

  /// 记忆分析 Agent——每轮对话后异步提取用户特质。
  final MemoryAgent? _memoryAgent;

  /// Skill 索引——注入到 system prompt 中。
  final String _skillIndexText;

  /// 当前激活的 Skill（name → body）。
  final Map<String, String> _activeSkills = {};

  /// Skill 索引引用——用于 activateSkill/deactivateSkill 查找。
  final SkillIndex? _skillIndex;

  bool _globalMemoryReadThisTurn = false;

  // 批准回调
  Completer<bool>? _approvalCompleter;

  Controller({
    required Provider provider,
    required Registry registry,
    required EventSink sink,
    Session? session,
    MemoryFacade? memory,
    MemoryAgent? memoryAgent,
    String skillIndexText = '',
    SkillIndex? skillIndex,
  })  : _provider = provider,
        _registry = registry,
        _sink = sink,
        _session = session ?? Session(),
        _memory = memory,
        _memoryAgent = memoryAgent,
        _skillIndexText = skillIndexText,
        _skillIndex = skillIndex;

  // ── 属性 ──

  ControllerState get state => _state;
  Session get session => _session;
  Provider get provider => _provider;
  Registry get registry => _registry;
  EventSink get sink => _sink;

  bool get isRunning => _state == ControllerState.running;
  bool get isIdle => _state == ControllerState.idle;

  // ── 配置 ──

  void setSystemPrompt(String prompt) => _systemPrompt = prompt;
  void setToolHint(String hint) => _toolHint = hint;
  @Deprecated('Use MemoryFacade instead — set controller.memory in constructor')
  void setMemoryContext(String context) => _memoryContext = context;

  // ── Skill 激活/停用 ──

  /// 激活指定 Skill。其 body 将注入到 system prompt 中。
  ///
  /// 供渲染层在打开 chat 模块时调用。返回 true 表示成功激活。
  bool activateSkill(String id) {
    if (_skillIndex == null) return false;
    final skill = _skillIndex!.get(id);
    if (skill == null) return false;

    _activeSkills[id] = skill.body;
    _sink.emit(AgentEvent.notice('已激活技能: ${skill.name}'));
    return true;
  }

  /// 停用指定 Skill。其 body 从 system prompt 中移除。
  ///
  /// 供渲染层在关闭 chat 模块时调用。返回 true 表示成功停用。
  bool deactivateSkill(String id) {
    if (_skillIndex == null) return false;
    final removed = _activeSkills.remove(id);
    if (removed != null) {
      _sink.emit(AgentEvent.notice('已停用技能: $id'));
      return true;
    }
    return false;
  }

  /// 当前激活的 Skill ID 列表。
  List<String> get activeSkillIds => _activeSkills.keys.toList();

  /// 所有激活的 Skill body 拼接文本（用于注入 system prompt）。
  String get _activeSkillBodies {
    if (_activeSkills.isEmpty) return '';
    return _activeSkills.values.join('\n\n---\n\n');
  }

  /// 构建完整 system prompt：基础提示词 + skill 索引 + 激活的 skill bodies。
  String _buildSystemPrompt() {
    final parts = <String>[_systemPrompt];
    if (_skillIndexText.isNotEmpty) parts.add(_skillIndexText);
    final bodies = _activeSkillBodies;
    if (bodies.isNotEmpty) parts.add('## 当前激活的技能\n$bodies');
    if (_attachmentContext.isNotEmpty) parts.add(_attachmentContext);
    return parts.join('\n');
  }

  /// 当前附件的 OCR 上下文（由 send 设置，run 读取后清空）。
  String _attachmentContext = '';

  // ── 会话管理 ──

  /// 创建新会话（保留旧会话历史）。
  void newSession() {
    if (isRunning) cancel();
    _session = Session();
    _currentAgent = null;
    _state = ControllerState.idle;
    _sink.emit(AgentEvent.notice('已创建新会话'));
  }

  /// 替换当前会话（用于恢复历史）。
  void setSession(Session session) {
    if (isRunning) cancel();
    _session = session;
    _state = ControllerState.idle;
  }

  // ── 核心操作 ──

  /// 发送用户消息并启动 Agent 运行。
  ///
  /// [attachments] 可选附件上下文文本（通常为 OCR 处理结果），注入 system prompt。
  void send(String input, {String? attachments}) {
    print('[Ctrl:D] send() called input="$input" disposed=$_disposed isRunning=$isRunning'
        ' attachments=${attachments != null ? "${attachments.length} chars" : "none"}');
    if (_disposed) return;
    if (isRunning) {
      _sink.emit(AgentEvent.notice('Agent 正在运行中，请等待完成'));
      return;
    }

    // New user turn → reset global memory read flag
    _globalMemoryReadThisTurn = false;

    // 设置附件上下文（单轮有效）
    _attachmentContext = attachments ?? '';

    print('[Ctrl:D] creating Agent provider=${_provider.name} tools=${_registry.enabled().length}');
    final agent = Agent(
      provider: _provider,
      registry: _registry,
      session: _session,
      sink: _sink,
    );

    _currentAgent = agent;
    _state = ControllerState.running;
    print('[Ctrl:D] state=running, calling _runAgent...');
    _sink.emit(AgentEvent.notice('思考中...'));

    // 异步运行 Agent
    _runAgent(agent, input);
  }

  Future<void> _autoReadGlobalMemory() async {
    if (_globalMemoryReadThisTurn) return;

    final tool = _registry.get('read_global_memory');
    if (tool == null || !_registry.isEnabled('read_global_memory')) return;

    try {
      final result = await tool.execute({});
      _globalMemoryReadThisTurn = true;
      if (result.isNotEmpty) {
        final callId = 'auto_read_memory_${DateTime.now().millisecondsSinceEpoch}';
        _session.add(Message.assistantTool([
          ToolCall(id: callId, name: 'read_global_memory', arguments: '{}'),
        ]));
        _session.add(Message.toolResult(callId, result));
        _sink.emit(AgentEvent.toolDispatch(ToolEventPayload(
          id: callId,
          name: 'read_global_memory',
          arguments: '{}',
          readOnly: true,
        )));
        _sink.emit(AgentEvent.toolResult(ToolEventPayload(
          id: callId,
          name: 'read_global_memory',
          arguments: '{}',
          output: result,
        )));
      }
    } catch (_) {
      // Silent failure — global memory read errors should not block conversation
    }
  }

  void _runMemoryAnalysis(String userInput, Session session) {
    final ma = _memoryAgent!;
    // 取最后一条 assistant 消息
    final assistantMsg = session.messages
        .where((m) => m.role == Role.assistant)
        .lastOrNull;
    final assistantText = assistantMsg?.content ?? '';
    if (userInput.isEmpty || assistantText.isEmpty) return;

    final now = DateTime.now();
    unawaited(ma.analyze(
      userInput,
      assistantText,
      '${now.year}年${now.month}月',
    ).then((result) {
      final (added, updated, removed) = result;
      final notices = <String>[];
      if (added > 0) notices.add('新增 $added 条');
      if (updated > 0) notices.add('更新 $updated 条');
      if (removed > 0) notices.add('移除 $removed 条');
      if (notices.isNotEmpty) {
        _sink.emit(AgentEvent.notice('🧠 记忆已更新：${notices.join('，')}'));
      }
    }).catchError((_) {})); // 静默失败
  }

  /// 取消当前运行。
  void cancel() {
    _currentAgent?.cancel();
    _state = ControllerState.idle;
    _approvalCompleter?.completeError('cancelled');
    _approvalCompleter = null;
  }

  /// 批准待审批的操作。
  void approve() {
    _approvalCompleter?.complete(true);
    _approvalCompleter = null;
    _state = ControllerState.running;
  }

  /// 拒绝待审批的操作。
  void reject() {
    _approvalCompleter?.complete(false);
    _approvalCompleter = null;
    _state = ControllerState.running;
  }

  /// 释放资源。
  void dispose() {
    _disposed = true;
    cancel();
    _approvalCompleter?.completeError('disposed');
    _approvalCompleter = null;
  }

  // ── 内部 ──

  Future<void> _runAgent(Agent agent, String input) async {
    print('[Ctrl:D] _runAgent() started input="$input"');
    try {
      int eventCount = 0;

      // Auto-read global memory each round (ensures AI sees latest MemoryAgent writes)
      await _autoReadGlobalMemory();

      // 构建记忆上下文：MemoryFacade 自动合并三 scope + 兼容旧 setMemoryContext
      final autoContext = _memory != null ? await _memory!.buildContext() : '';
      final mergedContext = autoContext.isNotEmpty
          ? '$_memoryContext\n\n$autoContext'.trim()
          : _memoryContext;

      await for (final event in agent.run(
        input: input,
        systemPrompt: _buildSystemPrompt(),
        toolHint: _toolHint,
        memoryContext: mergedContext,
      )) {
        eventCount++;
        print('[Ctrl:D] event #$eventCount kind=${event.kind.name}'
            ' textLen=${event.text?.length ?? 0}'
            ' tool=${event.tool?.name ?? "none"}');

        // 处理需要前端交互的事件
        if (event.kind == EventKind.approvalRequest) {
          _state = ControllerState.awaitingApproval;
          _approvalCompleter = Completer<bool>();
        }

        _sink.emit(event);

        // 让出事件循环：允许 Flutter 在事件之间渲染 UI 帧
        // 否则所有 SSE 事件在同一帧内处理完毕，流式内容无法实时显示
        await Future.delayed(Duration.zero);

        if (event.kind == EventKind.approvalRequest && _approvalCompleter != null) {
          try {
            final approved = await _approvalCompleter!.future;
            if (!approved) agent.cancel();
          } catch (_) {
            agent.cancel();
          }
        }
      }
      print('[Ctrl:D] _runAgent() completed — $eventCount events total');

      // 后台异步：MemoryAgent 按奥尔波特特质理论提取用户特质
      if (_memoryAgent != null) {
        _runMemoryAnalysis(input, _session);
      }
    } catch (e) {
      print('[Ctrl:D] ❌ _runAgent() threw: $e');
      _sink.emit(AgentEvent.notice('Agent 错误: $e', level: NoticeLevel.warn));
    } finally {
      if (!_disposed) {
        print('[Ctrl:D] _runAgent() finally — setting state=idle');
        _state = ControllerState.idle;
      }
      _attachmentContext = ''; // 清除单轮有效的附件上下文
    }
  }
}
