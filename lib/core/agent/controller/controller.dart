/// Controller — 传输无关的会话驱动器。
///
/// 对应 reasonix/internal/control/controller.go。
/// 前端（Flutter Widget、CLI、HTTP）通过 Controller 驱动 Agent。
/// 所有前端共享同一套生命周期，不重复实现。
library;

import 'dart:async';

import '../event.dart';
import '../message.dart';
import '../tool.dart';
import '../provider.dart';
import '../agent/agent.dart';
import '../agent/session.dart';
import '../agent/compose.dart';
import '../memory/facade.dart';
import '../skill/skill.dart';

/// Controller 状态。
enum ControllerState { idle, running, awaitingApproval }

/// Controller — 前端与 Agent 之间的桥梁。
///
/// 管理会话生命周期：Send → 运行 Agent → 事件流 → 结束。
/// 支持取消、批准、新建会话等操作。
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

  /// 记忆门面——自动构建 memory context（替代手动 setMemoryContext）。
  final MemoryFacade? _memory;

  /// Skill 索引——注入到 system prompt 中。
  final String _skillIndexText;

  // 全局记忆回合内已读标记——阻止同一用户回合内重复读取。
  bool _globalMemoryReadThisTurn = false;

  // 批准回调
  Completer<bool>? _approvalCompleter;

  Controller({
    required Provider provider,
    required Registry registry,
    required EventSink sink,
    Session? session,
    MemoryFacade? memory,
    String skillIndexText = '',
  })  : _provider = provider,
        _registry = registry,
        _sink = sink,
        _session = session ?? Session(),
        _memory = memory,
        _skillIndexText = skillIndexText;

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
  void send(String input) {
    print('[Ctrl:D] send() called input="$input" disposed=$_disposed isRunning=$isRunning');
    if (_disposed) return;
    if (isRunning) {
      _sink.emit(AgentEvent.notice('Agent 正在运行中，请等待完成'));
      return;
    }

    // 新用户回合 → 重置全局记忆已读标记
    _globalMemoryReadThisTurn = false;

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

  /// 在新会话开始时自动读取全局记忆并注入为工具结果。
  ///
  /// 在 Agent.run() 之前调用，将 read_global_memory 的结果作为
  /// 已执行的工具调用注入 session，让模型在首轮就能看到记忆上下文。
  ///
  /// 通过 [_globalMemoryReadThisTurn] 标记确保同一用户回合内只读取一次，
  /// 避免 Greenix 多轮思考/分析中重复触发磁盘 I/O。
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
      // 静默失败——读取全局记忆失败不应阻塞对话
    }
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

      // 🧠 每轮自动读取全局记忆（确保 AI 看到 MemoryAgent 最新写入的内容）
      await _autoReadGlobalMemory();

      // 构建记忆上下文：MemoryFacade 自动合并三 scope + 兼容旧 setMemoryContext
      final autoContext = _memory != null ? await _memory!.buildContext() : '';
      final mergedContext = autoContext.isNotEmpty
          ? '$_memoryContext\n\n$autoContext'.trim()
          : _memoryContext;

      await for (final event in agent.run(
        input: input,
        systemPrompt: '$_systemPrompt\n$_skillIndexText',
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
    } catch (e) {
      print('[Ctrl:D] ❌ _runAgent() threw: $e');
      _sink.emit(AgentEvent.notice('Agent 错误: $e', level: NoticeLevel.warn));
    } finally {
      if (!_disposed) {
        print('[Ctrl:D] _runAgent() finally — setting state=idle');
        _state = ControllerState.idle;
      }
    }
  }
}
