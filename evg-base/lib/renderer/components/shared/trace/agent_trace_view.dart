/// Agent Trace 视图（共享组件 · Phase 3 · C2-C4）。
///
/// 笔记本横线风格：
/// - 近纸色底 + 低对比灰细线分事件（0.5px）
/// - 粗线分轮次（"Round N · 12.3s · 5 events" 标题 + 2px 分隔）
/// - 固定宽度前缀列（`● tool` / `● think` / `● reply`，等宽左对齐）
/// - 内容列对齐；`[error]` 红色高亮（colorScheme.error）
/// - 空态："暂无轨迹，开始一次对话后自动记录"
library;

import 'package:flutter/material.dart';

import 'agent_trace_recorder.dart';

/// 前缀列宽度（固定，等宽）。
const double _prefixWidth = 64;

/// 事件行高（笔记本横线节距）。
const double _lineHeight = 26;

/// 前缀列提示语颜色（低对比灰）。
Color _prefixColor(BuildContext context, TraceEventKind kind) {
  final scheme = Theme.of(context).colorScheme;
  switch (kind) {
    case TraceEventKind.tool:
      return scheme.primary;
    case TraceEventKind.think:
      return scheme.tertiary;
    case TraceEventKind.reply:
      return scheme.onSurfaceVariant;
  }
}

/// 前缀列标签（`● tool` 等）。
String _prefixLabel(TraceEvent event) {
  switch (event) {
    case TraceToolEvent():
      return '● tool';
    case TraceThinkEvent():
      return '● think';
    case TraceReplyEvent():
      return '● reply';
  }
}

/// 时长格式化："12.3s" / "4.2s" / "350ms"。
String _formatDuration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
  final s = d.inMilliseconds / 1000;
  return '${s.toStringAsFixed(1)}s';
}

/// Trace 视图：监听 [recorder]，滚动展示分轮次事件。
class AgentTraceView extends StatefulWidget {
  final AgentTraceRecorder recorder;

  const AgentTraceView({super.key, required this.recorder});

  @override
  State<AgentTraceView> createState() => _AgentTraceViewState();
}

class _AgentTraceViewState extends State<AgentTraceView> {
  final ScrollController _scrollCtrl = ScrollController();
  bool _stickToBottom = true;

  AgentTraceRecorder get _recorder => widget.recorder;

  @override
  void initState() {
    super.initState();
    _recorder.addListener(_onRecorded);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _recorder.removeListener(_onRecorded);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 40;
    if (atBottom != _stickToBottom) {
      setState(() => _stickToBottom = atBottom);
    }
  }

  /// 新事件到达：若用户贴底则跟随滚动到底部。
  void _onRecorded() {
    if (!mounted || !_stickToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients || !_stickToBottom) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface, // 近纸色底
      child: ListenableBuilder(
        listenable: _recorder,
        builder: (context, _) {
          final rounds = _recorder.rounds;
          if (rounds.isEmpty) {
            return _buildEmpty(context);
          }
          final rows = _buildRows(rounds);
          return ListView.separated(
            controller: _scrollCtrl,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: rows.length,
            separatorBuilder: (context, index) {
              // 细线分事件：0.5px 低对比灰
              return Divider(
                height: 0.5,
                thickness: 0.5,
                color: scheme.onSurface.withValues(alpha: 0.08),
              );
            },
            itemBuilder: (context, index) {
              final row = rows[index];
              return switch (row) {
                _RoundHeaderRow(round: final r) => _buildRoundHeader(context, r),
                _EventRow(event: final e) => _buildEventRow(context, e),
              };
            },
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 40, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text(
            '暂无轨迹，开始一次对话后自动记录',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 粗线分轮次：标题 + 2px 分隔。
  Widget _buildRoundHeader(BuildContext context, TraceRound round) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.18),
            width: 2,
          ),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        'Round ${round.index} · ${_formatDuration(round.duration)}'
        ' · ${round.eventCount} events',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  /// 事件行：固定宽前缀列 + 内容列对齐。
  Widget _buildEventRow(BuildContext context, TraceEvent event) {
    final scheme = Theme.of(context).colorScheme;
    final content = _buildEventContent(context, event);
    return Container(
      constraints: const BoxConstraints(minHeight: _lineHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _prefixWidth,
            child: Text(
              _prefixLabel(event),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: _prefixColor(context, _kindOf(event)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: content),
        ],
      ),
    );
  }

  TraceEventKind _kindOf(TraceEvent event) {
    switch (event) {
      case TraceToolEvent():
        return TraceEventKind.tool;
      case TraceThinkEvent():
        return TraceEventKind.think;
      case TraceReplyEvent():
        return TraceEventKind.reply;
    }
  }

  Widget _buildEventContent(BuildContext context, TraceEvent event) {
    final scheme = Theme.of(context).colorScheme;
    switch (event) {
      case TraceToolEvent():
        return _toolRow(context, event);
      case TraceThinkEvent():
        return Text.rich(
          TextSpan(children: [
            TextSpan(
              text: '思考 ${_formatDuration(event.elapsed)}',
              style: TextStyle(
                  fontSize: 12, color: scheme.onSurface, fontFamily: 'monospace'),
            ),
            if (event.preview.isNotEmpty)
              TextSpan(
                text: '  ·  ${event.preview}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
          ]),
        );
      case TraceReplyEvent():
        return Text.rich(
          TextSpan(children: [
            TextSpan(
              text: event.preview,
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
            ),
            TextSpan(
              text: '  (${event.byteCount} bytes · UTF-8)',
              style: TextStyle(fontSize: 10, color: scheme.outline),
            ),
          ]),
        );
    }
  }

  Widget _toolRow(BuildContext context, TraceToolEvent e) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(
              '${e.tool}(${e.argsSummary})',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: e.isError ? scheme.error : scheme.onSurface,
              ),
            ),
            if (e.isError)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '[error]',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: scheme.error,
                  ),
                ),
              ),
          ],
        ),
        Text(
          e.resultSummary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ── 展平行模型 ──

  List<_TraceRow> _buildRows(List<TraceRound> rounds) {
    final rows = <_TraceRow>[];
    for (final r in rounds) {
      rows.add(_RoundHeaderRow(r));
      for (final e in r.events) {
        rows.add(_EventRow(e));
      }
    }
    return rows;
  }
}

sealed class _TraceRow {
  const _TraceRow();
}

class _RoundHeaderRow extends _TraceRow {
  final TraceRound round;
  const _RoundHeaderRow(this.round);
}

class _EventRow extends _TraceRow {
  final TraceEvent event;
  const _EventRow(this.event);
}
