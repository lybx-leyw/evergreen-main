/// Debug 报错栏 — 参考 cp_evergreen_push FeedbackFab 的 Stack+Positioned 模式。
///
/// 固定在屏幕最上层底部，不依赖 AppShell 布局约束。
/// 仅在 kDebugMode 时显示。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:evergreen_base/core/services/ui_operation_log.dart';

/// Debug 模式下固定在屏幕底部的操作日志栏。
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

class _DebugErrorBarState extends State<DebugErrorBar> {
  final List<UIOperationRecord> _records = [];
  StreamSubscription<UIOperationRecord>? _sub;
  bool _expanded = false;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _records.addAll(UIOperationLog.instance.recentRecords.reversed);
    _sub = UIOperationLog.instance.stream.listen((r) {
      setState(() {
        _records.insert(0, r);
        if (_expanded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollCtrl.hasClients) {
              _scrollCtrl.animateTo(0,
                  duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
            }
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    final errorCount = _records.where((r) => !r.success).length;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        child: Container(
          height: _expanded ? 200 : 28,
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
                  Icon(Icons.bug_report, size: 12,
                      color: errorCount > 0 ? Colors.red.shade400 : Colors.green.shade400),
                  const SizedBox(width: 4),
                  Text('Debug Ops', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                  if (errorCount > 0) ...[
                    const SizedBox(width: 6),
                    Text('$errorCount err', style: TextStyle(fontSize: 10, color: Colors.red.shade300)),
                  ],
                  const Spacer(),
                  Text('${_records.length} 条', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  const SizedBox(width: 4),
                  Icon(_expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                      size: 14, color: Colors.grey.shade500),
                ]),
              ),
            ),
            // ── 展开列表 ──
            if (_expanded)
              Expanded(
                child: ListView.builder(
                  controller: _scrollCtrl,
                  itemCount: _records.length,
                  itemBuilder: (context, i) => _buildRecord(_records[i]),
                ),
              ),
          ]),
        ),
      ),
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
    final durationStr = r.duration != null ? ' (${r.duration!.inMilliseconds}ms)' : '';

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
                TextSpan(text: '$time ', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                TextSpan(text: r.source, style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                TextSpan(text: '.${r.action}', style: TextStyle(fontSize: 10, color: Colors.grey.shade300)),
                if (!r.success && r.error != null)
                  TextSpan(text: '  ${r.error!.split('\n').first}',
                      style: TextStyle(fontSize: 9, color: Colors.red.shade300)),
              ]),
            ),
          ),
          Text(durationStr, style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
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
    if (r.params != null && r.params!.isNotEmpty) buf.writeln('Params:  ${r.params}');
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
}
