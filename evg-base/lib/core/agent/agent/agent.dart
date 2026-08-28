/// Agent 主循环 — 对应 reasonix/internal/agent/agent.go。
library;

import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;

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

/// 工具钩子接口。对应 Go 的 agent.ToolHooks（增强版，对齐 reasonix/internal/hook/）。
abstract class ToolHooks {
  /// 可选：匹配的工具名正则（锚定）。"" 或 "*" 匹配全部工具。
  String get match => '';

  /// 工具调用前。返回 (block, message)，block=true 阻止调用。
  Future<(bool block, String message)> preToolUse(
      String name, Map<String, dynamic> args);

  /// 工具调用后（无论成功失败——旧接口，保留兼容）。
  Future<void> postToolUse(String name, Map<String, dynamic> args, String result);

  /// 工具调用失败后（结果以 `[error:` 开头）。
  Future<void> postToolUseFailure(
      String name, Map<String, dynamic> args, String errorResult);
}

// ═══════ StormBreaker ═══════

/// 风暴抑制器——仅对连续失败的工具调用自动压制。
///
/// 规则：
/// - 连续调用同一工具失败（同签名）达到 [threshold] 次 → 触发抑制
/// - 任何一次调用成功 → 重置失败计数，取消抑制
/// - 切换工具（不同签名）→ 重置计数
///
/// 对应 Go 的 agent.applyStormBreaker。
class StormBreaker {
  String _lastSig = '';
  int _failCount = 0;
  final int threshold;

  StormBreaker({this.threshold = 3});

  /// 记录一次调用结果，返回是否应被压制。
  ///
  /// [error] 不为 null 表示失败，[error] 为 null 表示成功。
  /// 只有连续失败达到 threshold 时才返回 true。
  bool record(String toolName, String? error) {
    if (error != null) {
      // ── 失败 ──
      final sig = '$toolName:$error';
      if (sig == _lastSig) {
        _failCount++;
      } else {
        _lastSig = sig;
        _failCount = 1;
      }
      return _failCount >= threshold;
    }
    // ── 成功 → 重置一切 ──
    _lastSig = '';
    _failCount = 0;
    return false;
  }

  void reset() {
    _lastSig = '';
    _failCount = 0;
  }
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

  /// 当前工作区绝对路径（由 Controller 注入，用于 system prompt 告知 AI
  /// 工作区位置——vision 等文件解析工具需要绝对路径）。
  final String? _workspaceDir;

  Agent({
    required Provider provider,
    required Registry registry,
    required Session session,
    required EventSink sink,
    AgentOptions? options,
    Gate? gate,
    ToolHooks? hooks,
    String? workspaceDir,
  })  : _provider = provider,
        _registry = registry,
        _session = session,
        _sink = sink,
        _options = options ?? const AgentOptions(),
        _gate = gate,
        _hooks = hooks,
        _workspaceDir = workspaceDir {
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

  /// 在 system prompt 末尾追加工作区绝对路径提示（若已注入 workspaceDir），
  /// 让 AI 知道文件类工具（尤其 vision OCR/读图）需要绝对路径。
  String _withWorkspaceHint(String base) {
    final ws = _workspaceDir;
    if (ws == null || ws.isEmpty) return base;
    // 归一化为绝对路径：initGreenixPaths 未运行时 _greenixBaseDir 可能仍是
    // 相对 `.greenix`，注入相对路径会导致 vision 等工具无法解析。
    final abs = p.normalize(p.absolute(ws));
    return '$base\n\n## 工作区\n'
        '当前 AI 助手的工作区绝对路径：`$abs`\n'
        '文件类工具说明：\n'
        '- 工作区工具（read_file / write_file 等）：文件参数可传工作区内相对路径或绝对路径。\n'
        '- vision 工具（OCR 提取文字 / 读图描述）：`file_path` **必须传文件的绝对路径**'
        '——工作区文件请用「工作区绝对路径 + 相对子路径」拼接后传入。\n'
        '- 注意：工作区路径由宿主（Dart）注入，Python 环境无法自行推断'
        '（尤其安卓 Chaquopy），请始终使用上方绝对路径拼接文件参数。\n';
  }

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
        systemPrompt: _withWorkspaceHint(systemPrompt ?? defaultSystemPrompt),
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
            break;
          case ProviderEventKind.reasoning:
            final reasoningText = event.text;
            if (reasoningText != null && reasoningText.isNotEmpty) {
              reasoningBuf.write(reasoningText);
              yield AgentEvent.reasoning(reasoningText);
            }
            break;
          case ProviderEventKind.toolCalls:
            pendingCalls = event.toolCalls;
            print('[Agent:D] ✅ received ${pendingCalls!.length} tool calls from LLM');
            break;
          case ProviderEventKind.usage:
            if (event.usage != null) {
              _session.accumulateUsage(event.usage!);
              yield AgentEvent.usage(event.usage!);
            }
            break;
          case ProviderEventKind.error:
            print('[Agent:D] ❌ Provider error: ${event.error}');
            yield AgentEvent.notice(
                'API 错误: ${event.error}', level: NoticeLevel.warn);
            break;
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
      if (pendingCalls != null && pendingCalls.isNotEmpty) {
        _session.add(Message.assistantTool(pendingCalls));
        usedAnyTool = true;
        print('[Agent:D] added ${pendingCalls.length} tool calls to session');
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
      if (pendingCalls != null && pendingCalls.isNotEmpty) {
        print('[Agent:D] === Executing ${pendingCalls.length} tool call(s) ===');
        for (final call in pendingCalls) {
          print('[Agent:D]   tool: ${call.name} id=${call.id} argsLen=${call.arguments.length}');
          if (_cancelled) break;

          // 门控检查
          if (_gate != null) {
            Map<String, dynamic> args;
            try {
              args = jsonDecode(call.arguments) as Map<String, dynamic>;
            } catch (_) {
              args = {};
            }
            final tool = _registry.get(call.name);
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

          // ── 风暴抑制检查（工具执行后） ──
          // 仅对写工具检查：连续失败 ≥3 次触发抑制；成功则重置计数。
          final stormTool = _registry.get(call.name);
          if (stormTool != null && !stormTool.readOnly) {
            final isError = result.startsWith('[error:');
            final stormBlocked = _stormBreaker.record(
              call.name,
              isError ? result : null,
            );
            if (stormBlocked) {
              final blockMsg = '[storm breaker: 工具 "${call.name}" 连续失败 ${_stormBreaker.threshold} 次，已抑制]';
              print('[Agent:D]   ⛈ $blockMsg');
              // 仍然记录本次失败结果到 session
              _session.add(Message.toolResult(call.id, result));
              // 发射抑制事件（带 error，让模型感知到被阻止）
              yield AgentEvent.toolResult(ToolEventPayload(
                id: call.id,
                name: call.name,
                arguments: call.arguments,
                error: blockMsg,
              ));
              // 跳过正常的 output 发射，但继续 Post-hook
              if (_hooks != null) {
                Map<String, dynamic> args;
                try {
                  args = jsonDecode(call.arguments) as Map<String, dynamic>;
                } catch (_) {
                  args = {};
                }
                await _hooks!.postToolUse(call.name, args, blockMsg);
              }
              continue;
            }
          }

          // 记录工具结果
          _session.add(Message.toolResult(call.id, result));

          // 发射 ToolResult 事件
          yield AgentEvent.toolResult(ToolEventPayload(
            id: call.id,
            name: call.name,
            arguments: call.arguments,
            output: result,
          ));

          // Post-hook：失败走 postToolUseFailure，成功走 postToolUse
          if (_hooks != null) {
            Map<String, dynamic> args;
            try {
              args = jsonDecode(call.arguments) as Map<String, dynamic>;
            } catch (_) {
              args = {};
            }
            final isFailure = result.startsWith('[error:') || result.contains('❌');
            if (isFailure) {
              await _hooks!.postToolUseFailure(call.name, args, result);
            } else {
              await _hooks!.postToolUse(call.name, args, result);
            }
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
