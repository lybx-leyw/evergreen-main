/// Debug 报错栏 / 错误中心 — 参考 cp_evergreen_push FeedbackFab 的 Stack+Positioned 模式。
///
/// 固定在屏幕最上层底部，不依赖 AppShell 布局约束。
/// 仅在 kDebugMode 时显示。
///
/// 功能：
/// - Ops 视图：UI 操作记录（原有）
/// - Errors 视图：ERROR 级日志（errorId + 模块 + 消息），点击条目复制 errorId
/// - 一键导出最近 200 条日志到剪贴板（供 GitHub Issue 上报，见 Log.exportRecent）
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/services/ui_operation_log.dart';

/// Debug 模式下固定在屏幕底部的错误中心。
///
/// 使用方式：在 MaterialApp 的 builder 中包裹：
/// ```dart
/// builder: (context, child) => Stack(
///   children: [child!, const DebugErrorBar()],
/// ),
/// ```
class DebugErrorBar extends StatefulWidget {
  const DebugErrorBar({super.key});

  @override
  State<DebugErrorBar> createState() => _DebugErrorBarState();
}

enum _BarView { ops, errors }

class _DebugErrorBarState extends State<DebugErrorBar> {
  final List<UIOperationRecord> _records = [];
  final List<LogEntry> _errors = [];
  StreamSubscription<UIOperationRecord>? _sub;
  StreamSubscription<LogEntry>? _logSub;
  bool _expanded = false;
  _BarView _view = _BarView.ops;
  bool _exported = false;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _records.addAll(UIOperationLog.instance.recentRecords.reversed);
    _sub = UIOperationLog.instance.stream.listen((r) {
      if (!mounted) return;
      setState(() {
        _records.insert(0, r);
        _scrollToTopIfExpanded();
      });
    });

    // 错误中心：订阅 ERROR 级日志（错误列表上限 100 条）
    _errors.addAll(Log().entries(minLevel: LogLevel.error).reversed);
    _logSub = Log().logStream.listen((entry) {
      if (entry.level != LogLevel.error || !mounted) return;
      setState(() {
        _errors.insert(0, entry);
        if (_errors.length > 100) {
          _errors.removeRange(100, _errors.length);
        }
        _scrollToTopIfExpanded();
      });
    });
  }

  void _scrollToTopIfExpanded() {
    if (!_expanded || !_scrollCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _logSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    final errorCount = _errors.length;
    final listCount =
        _view == _BarView.ops ? _records.length : _errors.length;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        child: Container(
          height: _expanded ? 220 : 28,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            border: Border(top: BorderSide(color: Colors.grey.shade800)),
          ),
          child: Column(children: [
            // ── 标题栏 ──
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: Colors.black26,
                child: Row(children: [
                  Icon(Icons.bug_report,
                      size: 12,
                      color: errorCount > 0
                          ? Colors.red.shade400
                          : Colors.green.shade400),
                  const SizedBox(width: 4),
                  Text('Debug',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400)),
                  if (errorCount > 0) ...[
                    const SizedBox(width: 6),
                    Text('$errorCount err',
                        style: TextStyle(
                            fontSize: 10, color: Colors.red.shade300)),
                  ],
                  const Spacer(),
                  // 视图切换：Ops / Errors
                  GestureDetector(
                    onTap: () => setState(() => _view = _BarView.ops),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.playlist_play,
                          size: 13,
                          color: _view == _BarView.ops
                              ? Colors.blue.shade300
                              : Colors.grey.shade600),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _view = _BarView.errors),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.error_outline,
                          size: 13,
                          color: _view == _BarView.errors
                              ? Colors.red.shade300
                              : Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text('$listCount 条',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade500)),
                  const SizedBox(width: 4),
                  Icon(
                      _expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      size: 14,
                      color: Colors.grey.shade500),
                ]),
              ),
            ),
            // ── 展开列表 ──
            if (_expanded)
              Expanded(
                child: _view == _BarView.ops
                    ? _buildOpsList()
                    : _buildErrorsList(),
              ),
          ]),
        ),
      ),
    );
  }

  // ═══════ Ops 视图（原有行为） ═══════

  Widget _buildOpsList() {
    return ListView.builder(
      controller: _scrollCtrl,
      itemCount: _records.length,
      itemBuilder: (context, i) => _buildRecord(_records[i]),
    );
  }

  Widget _buildRecord(UIOperationRecord r) {
    final icon = r.isRunning
        ? Icons.hourglass_top
        : r.success
            ? Icons.check_circle
            : Icons.error;
    final color = r.isRunning
        ? Colors.blue.shade300
        : r.success
            ? Colors.green.shade400
            : Colors.red.shade400;
    final time = '${r.startedAt.hour.toString().padLeft(2, '0')}:'
        '${r.startedAt.minute.toString().padLeft(2, '0')}:'
        '${r.startedAt.second.toString().padLeft(2, '0')}';
    final durationStr =
        r.duration != null ? ' (${r.duration!.inMilliseconds}ms)' : '';

    return InkWell(
      onTap: () => _showDetail(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade900)),
        ),
        child: Row(children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(children: [
                TextSpan(
                    text: '$time ',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                TextSpan(
                    text: r.source,
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade400)),
                TextSpan(
                    text: '.${r.action}',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade300)),
                if (!r.success && r.error != null)
                  TextSpan(
                      text: '  ${r.error!.split('\n').first}',
                      style: TextStyle(
                          fontSize: 9, color: Colors.red.shade300)),
              ]),
            ),
          ),
          Text(durationStr,
              style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
        ]),
      ),
    );
  }

  void _showDetail(UIOperationRecord r) {
    final buf = StringBuffer();
    buf.writeln('═══ UI Operation Detail ═══');
    buf.writeln('Source:  ${r.source}');
    buf.writeln('Action:  ${r.action}');
    buf.writeln('Time:    ${r.startedAt.toIso8601String()}');
    buf.writeln('Success: ${r.success}');
    buf.writeln('Duration: ${r.duration?.inMilliseconds ?? "running"}ms');
    if (r.params != null && r.params!.isNotEmpty) {
      buf.writeln('Params:  ${r.params}');
    }
    if (r.result != null) buf.writeln('Result:  ${r.result}');
    if (r.error != null) buf.writeln('Error:   ${r.error}');
    if (r.stackTrace != null) buf.writeln('Stack:\n${r.stackTrace}');
    if (r.logs.isNotEmpty) {
      buf.writeln('Logs (${r.logs.length} entries):');
      for (final log in r.logs.take(50)) {
        buf.writeln('  $log');
      }
      if (r.logs.length > 50) buf.writeln('  ... (${r.logs.length - 50} more)');
    }
    debugPrint(buf.toString());
  }

  // ═══════ Errors 视图（错误中心） ═══════

  Widget _buildErrorsList() {
    return Column(children: [
      // 工具栏：导出日志
      Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: Colors.black38,
        child: Row(children: [
          Text('ERROR 日志（点击条目复制 errorId）',
              style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
          const Spacer(),
          GestureDetector(
            onTap: _exportLogs,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(_exported ? '已复制 ✓' : '导出日志',
                  style: TextStyle(
                      fontSize: 10, color: Colors.blue.shade300)),
            ),
          ),
        ]),
      ),
      Expanded(
        child: _errors.isEmpty
            ? Center(
                child: Text('暂无错误',
                    style:
                        TextStyle(fontSize: 10, color: Colors.grey.shade600)))
            : ListView.builder(
                controller: _scrollCtrl,
                itemCount: _errors.length,
                itemBuilder: (context, i) => _buildErrorItem(_errors[i]),
              ),
      ),
    ]);
  }

  Widget _buildErrorItem(LogEntry e) {
    return InkWell(
      onTap: () => _copyText(e.errorId ?? e.msg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade900)),
        ),
        child: Row(children: [
          Icon(Icons.error, size: 12, color: Colors.red.shade400),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(children: [
                if (e.errorId != null)
                  TextSpan(
                      text: '[${e.errorId}] ',
                      style:
                          TextStyle(fontSize: 10, color: Colors.amber.shade300)),
                TextSpan(
                    text: '${e.module ?? '?'}  ',
                    style:
                        TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                TextSpan(
                    text: e.msg,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade200)),
              ]),
            ),
          ),
          Icon(Icons.copy, size: 10, color: Colors.grey.shade600),
        ]),
      ),
    );
  }

  /// 复制文本（errorId 或日志）到剪贴板。
  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// 一键导出最近 200 条日志到剪贴板（附错误中心入口提示）。
  Future<void> _exportLogs() async {
    final text = await Log().exportRecent(lines: 200);
    await _copyText(text);
    if (!mounted) return;
    setState(() => _exported = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已复制最近 200 条日志到剪贴板（${text.length} 字符）',
          style: const TextStyle(fontSize: 11)),
      duration: const Duration(seconds: 2),
    ));
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _exported = false);
    });
  }
}
