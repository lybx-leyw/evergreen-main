/// Agent Trace 数据层（共享组件 · Phase 3 · C1-C5）。
///
/// 记录 Agent 历史：按 round（turnStarted→turnDone）分组的三类事件：
/// - [TraceToolEvent]：工具名 + 主参数摘要 + 结果摘要（行数/字节数/前 200 字符）+ [error] 标记
/// - [TraceThinkEvent]：reasoning 首 delta → 结束计时 → "思考 4.2s"
/// - [TraceReplyEvent]：正文预览（≤500 字符）+ UTF-8 字节数
///
/// 数据源：
/// - 工具事件走 [TraceBuffer] 接口（Phase 1 `ScraperHooks.postToolUse/`
///   `postToolUseFailure` 已产出结果摘要，Recorder 实现该接口）
/// - 轮次边界 / 思考 / 回复走 Agent 事件流订阅（[attach]），作为兜底
///
/// 内存环形缓冲（默认 500 事件）+ 可选 JSONL 落盘（trajectory 风格，
/// `schema_version/seq/ts`，复用 50KB 单消息 / 1MB 整体保护，
/// 防止复现 scraper_sessions.json 8MB 事故）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:evergreen_base/core/agent/agent.dart' as agent;

// ═══════ 事件模型 ═══════

/// Trace 事件种类。
enum TraceEventKind { tool, think, reply }

/// 单条 Trace 事件（sealed：tool / think / reply 三种）。
sealed class TraceEvent {
  final DateTime at;
  const TraceEvent({required this.at});
}

/// 工具调用事件。
class TraceToolEvent extends TraceEvent {
  final String tool;
  final String argsSummary;
  final String resultSummary;

  /// 执行失败（postToolUseFailure）→ 视图打 `[error]` 红标（C3）。
  final bool isError;

  const TraceToolEvent({
    required super.at,
    required this.tool,
    required this.argsSummary,
    required this.resultSummary,
    this.isError = false,
  });
}

/// 思考事件（时长摘要，C1）。
class TraceThinkEvent extends TraceEvent {
  final Duration elapsed;

  /// 思考内容前 120 字符（可选，事件流兜底时附带）。
  final String preview;

  const TraceThinkEvent({
    required super.at,
    required this.elapsed,
    this.preview = '',
  });
}

/// 回复事件（正文预览 + UTF-8 字节数，C1）。
class TraceReplyEvent extends TraceEvent {
  final String preview; // ≤500 字符
  final int byteCount; // UTF-8 字节数

  const TraceReplyEvent({
    required super.at,
    required this.preview,
    required this.byteCount,
  });
}

// ═══════ 轮次 ═══════

/// 一个 round：从 turnStarted 到 turnDone 之间的全部事件。
class TraceRound {
  /// 1 基轮次号（"Round N"）。
  final int index;
  final DateTime startedAt;
  final Duration duration;
  final List<TraceEvent> events;

  const TraceRound({
    required this.index,
    required this.startedAt,
    required this.duration,
    required this.events,
  });

  /// 事件数（视图标题 "· N events" 用）。
  int get eventCount => events.length;
}

// ═══════ TraceBuffer 接口（共享，C5） ═══════

/// Trace 缓冲接口（原 Phase 1 定义于 scraper_hooks，Phase 3 共享化迁至此处）。
///
/// 由 [AgentTraceRecorder] 实现；`ScraperHooks` 通过构造注入调用
/// `recordTool`（结果摘要来自 L4 postToolUse / postToolUseFailure）。
abstract class TraceBuffer {
  void recordTool(String tool, String argsSummary, String resultSummary,
      {bool isError = false});
  void recordThink(Duration elapsed);
  void recordReply(String preview, int byteCount);

  /// 全部轮次（只读）。
  List<TraceRound> get rounds;
  void clear();
}

// ═══════ Recorder ═══════

/// Trace 记录器（共享组件 · ChangeNotifier 供视图监听）。
class AgentTraceRecorder extends ChangeNotifier implements TraceBuffer {
  /// 内存环形缓冲上限（事件总数，超限丢最旧；当前 open round 恒保留）。
  final int maxEvents;

  /// 可选 JSONL 落盘路径（trajectory 格式）；null = 不落盘。
  final String? jsonlPath;

  /// 整体文件大小保护（默认 1MB，超出停写）。
  final int maxJsonlBytes;

  /// 单行大小保护（默认 50KB，超长截断）。
  final int maxJsonlLineBytes;

  /// 思考预览保留长度。
  static const int thinkPreviewMax = 120;

  /// 回复预览长度。
  static const int replyPreviewMax = 500;

  final List<TraceRound> _rounds = [];
  int _totalEvents = 0;
  TraceRound? _current;

  // ── 思考计时（事件流）──
  DateTime? _thinkStartedAt;
  final StringBuffer _thinkPreview = StringBuffer();

  // ── JSONL ──
  int _seq = 0;
  final StringBuffer _jsonlBuffer = StringBuffer();
  int _jsonlWrittenBytes = 0;
  bool _jsonlOverflow = false;
  static const int _jsonlFlushThreshold = 32 * 1024;

  StreamSubscription<agent.AgentEvent>? _sub;

  AgentTraceRecorder({
    this.maxEvents = 500,
    this.jsonlPath,
    this.maxJsonlBytes = 1024 * 1024,
    this.maxJsonlLineBytes = 50 * 1024,
  });

  // ── 只读视图 ──

  /// 全部轮次（含当前 open round，视图/证据立即可见；只读）。
  List<TraceRound> get rounds {
    final cur = _current;
    if (cur == null) return List.unmodifiable(_rounds);
    return List.unmodifiable([..._rounds, cur]);
  }

  /// 当前事件总数。
  int get totalEvents => _totalEvents;

  /// 当前是否正在记录（有 open round）。
  bool get hasOpenRound => _current != null;

  // ── 事件流订阅（兜底：轮次边界 / 思考 / 回复）──

  /// 订阅 Agent 事件流（broadcast 流，与 AI 面板监听共存）。
  void attach(Stream<agent.AgentEvent> stream) {
    _sub ??= stream.listen(_onAgentEvent);
  }

  /// 取消事件流订阅。
  void detach() {
    _sub?.cancel();
    _sub = null;
  }

  void _onAgentEvent(agent.AgentEvent e) {
    switch (e.kind) {
      case agent.EventKind.turnStarted:
        _beginRound();
        break;
      case agent.EventKind.reasoning:
        if (e.reasoning != null) {
          _thinkStartedAt ??= DateTime.now();
          if (_thinkPreview.length < thinkPreviewMax) {
            _thinkPreview.write(e.reasoning);
          }
        }
        break;
      case agent.EventKind.message:
        _finishThink();
        final text = e.text ?? '';
        if (text.trim().isNotEmpty) {
          // byteCount 取完整正文 UTF-8 字节数；预览截断由 recordReply 统一处理
          recordReply(text, utf8.encode(text).length);
        }
        break;
      case agent.EventKind.turnDone:
        _finishThink();
        _closeRound();
        break;
      default:
        break;
    }
  }

  // ── TraceBuffer 实现 ──

  @override
  void recordTool(String tool, String argsSummary, String resultSummary,
      {bool isError = false}) {
    _append(TraceToolEvent(
      at: DateTime.now(),
      tool: tool,
      argsSummary: argsSummary,
      resultSummary: resultSummary,
      isError: isError,
    ));
  }

  @override
  void recordThink(Duration elapsed) {
    _append(TraceThinkEvent(at: DateTime.now(), elapsed: elapsed));
  }

  @override
  void recordReply(String preview, int byteCount) {
    // 统一截断：预览 ≤500 字符（C1）；byteCount 仍为完整正文的 UTF-8 字节数
    final p = preview.length > replyPreviewMax
        ? '${preview.substring(0, replyPreviewMax)}…'
        : preview;
    _append(TraceReplyEvent(
      at: DateTime.now(),
      preview: p,
      byteCount: byteCount,
    ));
  }

  @override
  void clear() {
    _rounds.clear();
    _current = null;
    _totalEvents = 0;
    _thinkStartedAt = null;
    _thinkPreview.clear();
    notifyListeners();
  }

  // ── 轮次生命周期 ──

  void _beginRound() {
    _closeRound();
    _current = TraceRound(
      index: _rounds.length + 1,
      startedAt: DateTime.now(),
      duration: Duration.zero,
      events: [],
    );
    notifyListeners();
  }

  /// 关闭当前 round（若无 open round 则忽略）。
  void _closeRound() {
    final cur = _current;
    if (cur == null) return;
    final closed = TraceRound(
      index: cur.index,
      startedAt: cur.startedAt,
      duration: DateTime.now().difference(cur.startedAt),
      events: List.unmodifiable(cur.events),
    );
    _current = null;
    _rounds.add(closed);
    notifyListeners();
  }

  /// 懒开 round：hook 在事件流之外调用 recordTool 时保证有归属轮次。
  void _ensureRound() {
    if (_current == null) {
      _current = TraceRound(
        index: _rounds.length + 1,
        startedAt: DateTime.now(),
        duration: Duration.zero,
        events: [],
      );
    }
  }

  // ── 思考计时 ──

  void _finishThink() {
    final started = _thinkStartedAt;
    if (started == null) return;
    final elapsed = DateTime.now().difference(started);
    final preview = _thinkPreview.toString();
    _thinkStartedAt = null;
    _thinkPreview.clear();
    if (elapsed.inMilliseconds <= 0 && preview.isEmpty) return;
    // 事件流兜底路径：附带思考预览；接口 recordThink 仅时长。
    _append(TraceThinkEvent(
      at: DateTime.now(),
      elapsed: elapsed,
      preview: preview.length > thinkPreviewMax
          ? '${preview.substring(0, thinkPreviewMax)}…'
          : preview,
    ));
  }

  // ── 环形缓冲 + 落盘 ──

  void _append(TraceEvent event) {
    _ensureRound();
    final cur = _current!;
    _current = TraceRound(
      index: cur.index,
      startedAt: cur.startedAt,
      duration: cur.duration,
      events: [...cur.events, event],
    );
    _totalEvents++;
    _evictIfNeeded();
    _enqueueJsonl(_jsonlRecord(event));
    notifyListeners();
  }

  /// 环形缓冲：超出上限丢最旧事件（先丢已关闭轮次，再丢 open round 头部）。
  void _evictIfNeeded() {
    while (_totalEvents > maxEvents) {
      if (_rounds.isNotEmpty) {
        final first = _rounds.first;
        if (first.events.isEmpty) {
          _rounds.removeAt(0);
          continue;
        }
        final rest = first.events.sublist(1);
        _rounds[0] = TraceRound(
          index: first.index,
          startedAt: first.startedAt,
          duration: first.duration,
          events: List.unmodifiable(rest),
        );
        _totalEvents--;
        if (rest.isEmpty) {
          _rounds.removeAt(0);
        }
        continue;
      }
      // 全部事件都在 open round：丢其头部
      final cur = _current;
      if (cur == null || cur.events.isEmpty) break;
      _current = TraceRound(
        index: cur.index,
        startedAt: cur.startedAt,
        duration: cur.duration,
        events: List.unmodifiable(cur.events.sublist(1)),
      );
      _totalEvents--;
    }
  }

  // ── JSONL 落盘（trajectory 风格 + 大小保护）──

  Map<String, dynamic> _jsonlRecord(TraceEvent event) {
    final base = <String, dynamic>{
      'schema_version': 1,
      'seq': ++_seq,
      'ts': event.at.millisecondsSinceEpoch,
    };
    switch (event) {
      case TraceToolEvent():
        return {
          ...base,
          'kind': 'tool',
          'tool': event.tool,
          'args': event.argsSummary,
          'result': event.resultSummary,
          'is_error': event.isError,
        };
      case TraceThinkEvent():
        return {
          ...base,
          'kind': 'think',
          'elapsed_ms': event.elapsed.inMilliseconds,
          if (event.preview.isNotEmpty) 'preview': event.preview,
        };
      case TraceReplyEvent():
        return {
          ...base,
          'kind': 'reply',
          'preview': event.preview,
          'bytes': event.byteCount,
        };
    }
  }

  void _enqueueJsonl(Map<String, dynamic> record) {
    if (_jsonlOverflow || jsonlPath == null) return;
    var line = jsonEncode(record);
    if (line.length > maxJsonlLineBytes) {
      // 单行超限：截断到安全上限（防御性，正常摘要远小于此）。
      line = '${line.substring(0, maxJsonlLineBytes)}…}';
    }
    _jsonlBuffer.writeln(line);
    if (_jsonlBuffer.length >= _jsonlFlushThreshold) {
      flushJsonl();
    }
  }

  /// 将缓冲的 JSONL 行追加到文件（带 1MB 整体保护）。
  void flushJsonl() {
    final path = jsonlPath;
    if (path == null || _jsonlBuffer.isEmpty) return;
    final pending = _jsonlBuffer.toString();
    _jsonlBuffer.clear();
    if (_jsonlOverflow) return;
    if (_jsonlWrittenBytes + pending.length > maxJsonlBytes) {
      _jsonlOverflow = true;
      debugPrint('[AgentTraceRecorder] ⚠ trace.jsonl 超过 ${maxJsonlBytes ~/ 1024}KB，'
          '停止落盘（内存视图不受影响）');
      return;
    }
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(pending, mode: FileMode.append);
      _jsonlWrittenBytes += pending.length;
    } catch (e) {
      debugPrint('[AgentTraceRecorder] ⚠ JSONL 落盘失败: $e');
      _jsonlOverflow = true; // 失败降级：不再重试，避免反复 IO
    }
  }

  @override
  void dispose() {
    detach();
    flushJsonl();
    super.dispose();
  }
}
