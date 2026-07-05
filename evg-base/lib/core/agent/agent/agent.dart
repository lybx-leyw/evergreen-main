/// Agent 主循环 — 对应 reasonix/internal/agent/agent.go。
library;

import 'dart:async';
import 'dart:convert';

import '../message.dart';
import '../tool.dart';
import '../event.dart';
import '../provider.dart';
import '../compact/compact.dart';
import 'session.dart';
import 'compose.dart';

// ═══════ AgentOptions ═══════

/// Agent 配置。
class AgentOptions {
  final int maxSteps;
  final double temperature;
  final int contextWindow;
  final double softCompactRatio;
  final double compactRatio;
  final double compactForceRatio;
  final int recentKeep;

  const AgentOptions({
    this.maxSteps = 50,
    this.temperature = 0.0,
    this.contextWindow = 0,
    this.softCompactRatio = 0.5,
    this.compactRatio = 0.8,
    this.compactForceRatio = 0.95,
    this.recentKeep = 10,
  });
}

// ═══════ Gate ═══════

/// 权限门控接口。对应 Go 的 agent.Gate。
abstract class Gate {
  /// 检查工具调用是否允许。返回 (allow, reason)，allow=false 时 reason 反馈给模型。
  Future<(bool allow, String reason)> check(
      String toolName, Map<String, dynamic> args, bool readOnly);
}

// ═══════ ToolHooks ═══════

/// 工具钩子接口。对应 Go 的 agent.ToolHooks。
abstract class ToolHooks {
  /// 工具调用前。返回 (block, message)，block=true 阻止调用。
  Future<(bool block, String message)> preToolUse(
      String name, Map<String, dynamic> args);

  /// 工具调用后。
  Future<void> postToolUse(String name, Map<String, dynamic> args, String result);
}

// ═══════ StormBreaker ═══════

/// 风暴抑制器——重复失败/成功的工具调用自动压制。对应 Go 的 agent.applyStormBreaker。
class StormBreaker {
  String _lastSig = '';
  int _count = 0;
  final int threshold;
  final Map<String, int> _repeatSuccessCounts = {};

  StormBreaker({this.threshold = 3});

  /// 记录一次调用结果，返回是否应被压制。
  bool record(String toolName, String? error) {
    final sig = '$toolName:${error ?? "success"}';
    if (error != null) {
      if (sig == _lastSig) { _count++; } else { _lastSig = sig; _count = 1; }
      return _count >= threshold;
    }
    _repeatSuccessCounts[toolName] = (_repeatSuccessCounts[toolName] ?? 0) + 1;
    _lastSig = '';
    _count = 0;
    return (_repeatSuccessCounts[toolName] ?? 0) >= 2;
  }

  void reset() { _lastSig = ''; _count = 0; _repeatSuccessCounts.clear(); }
}

// ═══════ ReadinessResult ═══════

/// 最终检查结果。
class ReadinessResult {
  final bool passed;
  final String reason;
  const ReadinessResult({required this.passed, this.reason = ''});
  factory ReadinessResult.pass() => const ReadinessResult(passed: true);
  factory ReadinessResult.block(String reason) => ReadinessResult(passed: false, reason: reason);
}

// ═══════ FinalReadiness ═══════

/// 最终检查——验证模型输出是否完整。对应 Go 的 agent.finalReadinessCheck。
class FinalReadiness {
  int blockCount = 0;
  final int maxBlocks;
  FinalReadiness({this.maxBlocks = 3});

  ReadinessResult check({required bool usedAnyTool, required bool hasVisibleAnswer}) {
    if (!usedAnyTool) return ReadinessResult.pass();
    if (!hasVisibleAnswer) { blockCount++; return ReadinessResult.block('模型输出了空的回答'); }
    if (blockCount >= maxBlocks) return ReadinessResult.block('最终检查失败 $maxBlocks 次，强制终止');
    return ReadinessResult.pass();
  }

  void reset() { blockCount = 0; }
}

// ═══════ Agent ═══════

/// Agent 主类——驱动一轮对话交互。
class Agent {
  final Provider _provider;
  final Registry _registry;
  final Session _session;
  final AgentOptions _options;
  final EventSink _sink;

  // 可选组件
  Gate? _gate;
  ToolHooks? _hooks;
  StormBreaker _stormBreaker = StormBreaker();
  FinalReadiness _readiness = FinalReadiness();
  Compactor? _compactor;

  // EventSink（由 Controller 传入，当前通过 return stream 输出事件）
  // 保留字段以备未来需要直接向 sink 发射事件

  // 运行时状态
  bool _cancelled = false;
  int _step = 0;

  Agent({
    required Provider provider,
    required Registry registry,
    required Session session,
    required EventSink sink,
    AgentOptions? options,
    Gate? gate,
    ToolHooks? hooks,
  })  : _provider = provider,
        _registry = registry,
        _session = session,
        _sink = sink,
        _options = options ?? const AgentOptions(),
        _gate = gate,
        _hooks = hooks {
    if (_options.contextWindow > 0) {
      _compactor = Compactor(
        llm: _provider,
        contextWindow: _options.contextWindow,
        softRatio: _options.softCompactRatio,
        compactRatio: _options.compactRatio,
        forceRatio: _options.compactForceRatio,
        recentKeep: _options.recentKeep,
      );
    }
  }

  // ── 配置方法 ──

  void setGate(Gate? gate) => _gate = gate;
  void setHooks(ToolHooks? hooks) => _hooks = hooks;

  /// 取消当前运行。
  void cancel() => _cancelled = true;

  // ── 主循环 ──

  /// 运行一轮 Agent 交互。
  ///
  /// [input] — 用户输入。
  /// [systemPrompt] — 可选的系统提示词覆盖。
  /// [toolHint] — 可选的工具使用指引覆盖。
  /// [memoryContext] — 可选的记忆上下文。
  Stream<AgentEvent> run({
    required String input,
    String? systemPrompt,
    String? toolHint,
    String memoryContext = '',
  }) async* {
    _cancelled = false;
    _stormBreaker.reset();
    _readiness.reset();
    _step = 0;

    print('[Agent:D] Run() started input="$input" tools=${_registry.enabled().length}');
    // 发射 TurnStarted 事件
    yield AgentEvent.turnStarted();

    // 追加用户消息
    _session.add(Message.user(input));
    print('[Agent:D] user message added, session now ${_session.messages.length} messages');

    // ── 主循环 ──
    bool usedAnyTool = false;

    for (_step = 0; _options.maxSteps <= 0 || _step < _options.maxSteps; _step++) {
      print('[Agent:D] === Step $_step ===');
      if (_cancelled) {
        print('[Agent:D] cancelled');
        _session.add(Message.assistant('[已取消]'));
        yield AgentEvent.turnDone();
        return;
      }

      // ⓪ Context compaction — AI 驱动压缩中间对话，保留关键事实
      if (_compactor != null && !usedAnyTool) {
        final (should, trigger, _) = _compactor!.check(_session);
        if (should) {
          print('[Agent:D] compacting ($trigger)...');
          _compactor!.setMemoryContext(memoryContext);
          await _compactor!.compact(_session, trigger);
          print('[Agent:D] compacted — ${_session.messages.length} msgs remain');
        }
      }

      // ① Compose — 构造消息
      final tools = _registry.enabled();
      print('[Agent:D] compose() tools=${tools.length} session_msgs=${_session.messages.length}');
      final messages = compose(
        systemPrompt: systemPrompt ?? defaultSystemPrompt,
        tools: tools,
        session: _session,
        memoryContext: memoryContext,
        toolHint: toolHint ?? defaultToolHint,
      );
      final toolSchemas = toolsToSchemas(tools);
      print('[Agent:D] composed ${messages.length} messages, ${toolSchemas.length} tool schemas');

      // ② LLM Call — 流式调用
      print('[Agent:D] calling _provider.chat()...');
      StringBuffer textBuf = StringBuffer();
      StringBuffer reasoningBuf = StringBuffer();
      List<ToolCall>? pendingCalls;
      bool gotAnyEvent = false;

      await for (final event in _provider.chat(
        messages: messages,
        tools: toolSchemas,
      )) {
        gotAnyEvent = true;
        switch (event.kind) {
          case ProviderEventKind.content:
            textBuf.write(event.text ?? '');
            yield AgentEvent.text(event.text ?? '');
          case ProviderEventKind.reasoning:
            final reasoningText = event.text;
            if (reasoningText != null && reasoningText.isNotEmpty) {
              reasoningBuf.write(reasoningText);
              yield AgentEvent.reasoning(reasoningText);
            }
          case ProviderEventKind.toolCalls:
            pendingCalls = event.toolCalls;
            print('[Agent:D] ✅ received ${pendingCalls!.length} tool calls from LLM');
          case ProviderEventKind.usage:
            if (event.usage != null) {
              _session.accumulateUsage(event.usage!);
              yield AgentEvent.usage(event.usage!);
            }
          case ProviderEventKind.error:
            print('[Agent:D] ❌ Provider error: ${event.error}');
            yield AgentEvent.notice(
                'API 错误: ${event.error}', level: NoticeLevel.warn);
          case ProviderEventKind.done:
            break;
        }
      }

      if (!gotAnyEvent) {
        print('[Agent:D] ❌ No events from provider! LLM call returned empty stream.');
      }

      final text = textBuf.toString();
      final reasoning = reasoningBuf.toString();
      print('[Agent:D] LLM result: textLen=${text.length} reasoningLen=${reasoning.length}'
          ' toolCalls=${pendingCalls?.length ?? 0}');

      // ③ 记录 assistant 消息
      if (pendingCalls != null && pendingCalls!.isNotEmpty) {
        _session.add(Message.assistantTool(pendingCalls!));
        usedAnyTool = true;
        print('[Agent:D] added ${pendingCalls!.length} tool calls to session');
      } else if (text.isNotEmpty) {
        _session.add(Message.assistant(text, reasoning: reasoning));
        print('[Agent:D] added assistant text to session');
      } else {
        _session.add(Message.assistant(''));
        print('[Agent:D] ⚠️ empty assistant message added');
      }

      // 发射完整的 Message 事件
      yield AgentEvent.message(text: text, reasoning: reasoning);

      // ④ 执行工具调用
      if (pendingCalls != null && pendingCalls!.isNotEmpty) {
        print('[Agent:D] === Executing ${pendingCalls!.length} tool call(s) ===');
        for (final call in pendingCalls!) {
          print('[Agent:D]   tool: ${call.name} id=${call.id} argsLen=${call.arguments.length}');
          if (_cancelled) break;

          // 风暴抑制检查（仅压制写工具的重复循环，只读工具不受限）
          final stormTool = _registry.get(call.name);
          if (stormTool != null && !stormTool.readOnly && _stormBreaker.record(call.name, null)) {
            final blockMsg = '[storm breaker: 工具 "${call.name}" 被抑制——连续调用次数过多]';
            _session.add(Message.toolResult(call.id, blockMsg));
            yield AgentEvent.toolResult(ToolEventPayload(
              id: call.id,
              name: call.name,
              arguments: call.arguments,
              error: blockMsg,
            ));
            continue;
          }

          // 门控检查
          if (_gate != null) {
            Map<String, dynamic> args;
            try {
              args = jsonDecode(call.arguments) as Map<String, dynamic>;
            } catch (_) {
              args = {};
            }
            final tool = stormTool ?? _registry.get(call.name);
            final (allow, reason) = await _gate!.check(
              call.name,
              args,
              tool?.readOnly ?? true,
            );
            if (!allow) {
              _session.add(Message.toolResult(call.id, '[blocked: $reason]'));
              yield AgentEvent.toolResult(ToolEventPayload(
                id: call.id,
                name: call.name,
                arguments: call.arguments,
                error: reason,
              ));
              continue;
            }
          }

          // Pre-hook
          if (_hooks != null) {
            Map<String, dynamic> args;
            try {
              args = jsonDecode(call.arguments) as Map<String, dynamic>;
            } catch (_) {
              args = {};
            }
            final (block, msg) = await _hooks!.preToolUse(call.name, args);
            if (block) {
              _session.add(Message.toolResult(call.id, '[hook blocked: $msg]'));
              yield AgentEvent.toolResult(ToolEventPayload(
                id: call.id,
                name: call.name,
                arguments: call.arguments,
                error: msg,
              ));
              continue;
            }
          }

          // 发射 ToolDispatch 事件
          print('[Agent:D]   dispatching ${call.name}...');
          yield AgentEvent.toolDispatch(ToolEventPayload(
            id: call.id,
            name: call.name,
            arguments: call.arguments,
            readOnly: _registry.get(call.name)?.readOnly ?? true,
          ));

          // 执行工具
          print('[Agent:D]   calling registry.call(${call.name})...');
          final stopwatch = Stopwatch()..start();
          final result = await _registry.call(call.name, call.arguments);
          stopwatch.stop();
          print('[Agent:D]   ✅ ${call.name} completed in ${stopwatch.elapsedMilliseconds}ms'
              ' resultLen=${result.length}');

          // 记录工具结果
          _session.add(Message.toolResult(call.id, result));

          // 发射 ToolResult 事件
          yield AgentEvent.toolResult(ToolEventPayload(
            id: call.id,
            name: call.name,
            arguments: call.arguments,
            output: result,
          ));

          // Post-hook
          if (_hooks != null) {
            Map<String, dynamic> args;
            try {
              args = jsonDecode(call.arguments) as Map<String, dynamic>;
            } catch (_) {
              args = {};
            }
            await _hooks!.postToolUse(call.name, args, result);
          }
        }

        // 有工具调用 → 继续循环
        continue;
      }

      // ⑤ Final Readiness — 最终检查
      final readiness = _readiness.check(
        usedAnyTool: usedAnyTool,
        hasVisibleAnswer: text.trim().isNotEmpty,
      );

      if (!readiness.passed) {
        if (_readiness.blockCount >= _readiness.maxBlocks) {
          yield AgentEvent.notice(
              '最终检查失败 ${_readiness.maxBlocks} 次，强制终止',
              level: NoticeLevel.warn);
          break;
        }
        yield AgentEvent.notice(readiness.reason, level: NoticeLevel.warn);
        // 追加重试消息
        _session.add(Message.user('[重试] $readiness.reason'));
        continue;
      }

      // 通过 → 结束本轮
      break;
    }

    // 发射 TurnDone 事件
    yield AgentEvent.turnDone();
  }

  /// 当前会话。
  Session get session => _session;

  /// 当前步骤数。
  int get currentStep => _step;
}
