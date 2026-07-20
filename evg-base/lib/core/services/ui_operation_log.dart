/// UI 操作日志服务 — 记录每次 UI 操作的完整上下文。
///
/// 使用方式：
/// ```dart
/// onPressed: () => uiOp('ScraperAIPanel', '生成插件', () => _generatePlugin()),
/// ```
///
/// Debug 模式下，所有操作记录可通过 [UIOperationLog.instance.stream] 订阅，
/// 供 DebugErrorBar 实时显示。
library;

import 'dart:async';

import 'package:evergreen_base/core/log.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

// ═══════ UIOperationRecord ═══════

/// 一次 UI 操作的完整记录。
class UIOperationRecord {
  final String id;
  final String source;
  final String action;
  final Map<String, dynamic>? params;
  final DateTime startedAt;
  DateTime? endedAt;
  bool success;
  String? result;
  String? error;
  String? stackTrace;
  final List<String> logs;

  UIOperationRecord({
    required this.id,
    required this.source,
    required this.action,
    this.params,
    DateTime? startedAt,
    this.success = false,
    this.result,
    this.error,
    this.stackTrace,
    List<String>? logs,
  })  : startedAt = startedAt ?? DateTime.now(),
        logs = logs ?? [];

  Duration? get duration =>
      endedAt != null ? endedAt!.difference(startedAt) : null;

  bool get isRunning => endedAt == null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source,
        'action': action,
        'params': params,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'durationMs': duration?.inMilliseconds,
        'success': success,
        'result': result,
        'error': error,
        'stackTrace': stackTrace,
        'logs': logs,
      };
}

// ═══════ UIOperationLog ═══════

/// UI 操作日志单例。
///
/// 只在 Debug 模式下生效。Release 模式下所有方法都是空操作。
class UIOperationLog {
  static final UIOperationLog instance = UIOperationLog._();
  UIOperationLog._();

  final List<UIOperationRecord> _records = [];
  final StreamController<UIOperationRecord> _controller =
      StreamController<UIOperationRecord>.broadcast();
  StreamSubscription<LogEntry>? _logSub;

  /// 操作记录流。
  Stream<UIOperationRecord> get stream => _controller.stream;

  /// 最近 N 条记录（最新在前）。
  List<UIOperationRecord> get recentRecords =>
      List.unmodifiable(_records.reversed.take(50));

  /// 所有记录。
  List<UIOperationRecord> get allRecords => List.unmodifiable(_records);

  /// 开始一次 UI 操作。
  UIOperationRecord startOperation(
    String source,
    String action, {
    Map<String, dynamic>? params,
  }) {
    final record = UIOperationRecord(
      id: const Uuid().v4(),
      source: source,
      action: action,
      params: params,
    );
    _records.add(record);
    _controller.add(record);

    // 开始捕获 Log 输出
    final logBuf = record.logs;
    _logSub?.cancel();
    _logSub = Log().logStream.listen((entry) {
      logBuf.add('[${entry.level.name.toUpperCase()}] ${entry.msg}');
    });

    return record;
  }

  /// 操作成功结束。
  void completeOperation(UIOperationRecord record, {String? result}) {
    record.endedAt = DateTime.now();
    record.success = true;
    record.result = result;
    _logSub?.cancel();
    _controller.add(record);
  }

  /// 操作失败。
  void failOperation(
      UIOperationRecord record, Object error, StackTrace stack) {
    record.endedAt = DateTime.now();
    record.success = false;
    record.error = error.toString();
    record.stackTrace = stack.toString();
    _logSub?.cancel();
    _controller.add(record);
  }

  /// 清空所有记录。
  void clear() {
    _records.clear();
  }
}

// ═══════ uiOp() 顶层函数 ═══════

/// 包裹一次 UI 操作，自动记录日志。
///
/// 用法：
/// ```dart
/// onPressed: () => uiOp('ScraperAIPanel', '生成插件', () => _generatePlugin()),
/// ```
Future<T?> uiOp<T>(
  String source,
  String action,
  Future<T> Function() fn, {
  Map<String, dynamic>? params,
}) async {
  if (!kDebugMode) return fn();

  final record = UIOperationLog.instance.startOperation(
    source, action, params: params,
  );
  try {
    final result = await fn();
    UIOperationLog.instance.completeOperation(record);
    return result;
  } catch (e, stack) {
    UIOperationLog.instance.failOperation(record, e, stack);
    rethrow;
  }
}

/// 同步版本。
T? uiOpSync<T>(
  String source,
  String action,
  T Function() fn, {
  Map<String, dynamic>? params,
}) {
  if (!kDebugMode) return fn();

  final record = UIOperationLog.instance.startOperation(
    source, action, params: params,
  );
  try {
    final result = fn();
    UIOperationLog.instance.completeOperation(record);
    return result;
  } catch (e, stack) {
    UIOperationLog.instance.failOperation(record, e, stack);
    rethrow;
  }
}
