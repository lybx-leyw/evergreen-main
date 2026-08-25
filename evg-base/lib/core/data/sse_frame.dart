/// data 层 SSE 帧序列化 —— 最小自实现，复用 agent 侧 `event: <name>\ndata: {...}`
/// 的 SSE 帧格式约定，**零新依赖**。
///
/// 纯 Dart（仅依赖 `dart:convert` + [data_diff.dart]），可在 data 子包独立
/// `dart test`；[DataHttpServer] 的 SSE 端点（`/data/stream/:name`、`/data/events`）
/// 复用本文件的帧构造函数，保证「传输帧格式」与「单测」单一真相源。
library;

import 'dart:convert';

import 'data_diff.dart';

/// 把任意值安全转为可 JSON 编码的等价结构。
///
/// 递归处理 Map/List；对无法 JSON 编码的自定义对象叶子（如 [Uri]、自定义类）
/// 回退为 `toString()`，避免因单个非 JSON 数据中断整条流。
dynamic _jsonSafe(dynamic v) {
  if (v == null || v is num || v is bool || v is String) return v;
  if (v is List) return v.map(_jsonSafe).toList();
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), _jsonSafe(val)));
  }
  return v.toString();
}

/// 把任意值安全编码为 SSE `data:` 行的 JSON 负载。
String _sseJson(dynamic value) {
  try {
    return jsonEncode(_jsonSafe(value));
  } catch (_) {
    return jsonEncode(value.toString());
  }
}

/// 数据流帧：`event: data\ndata: {"name":..., "data":...}\n\n`。
///
/// [data] 为流式数据源的单个数据项（`Stream<T>` 的 `T`）。
String dataStreamSseFrame(String name, dynamic data) =>
    'event: data\ndata: ${_sseJson({'name': name, 'data': data})}\n\n';

/// 数据流错误帧：`event: error\ndata: {"name":..., "error":...}\n\n`。
String dataStreamErrorSseFrame(String name, Object error) =>
    'event: error\ndata: ${_sseJson({'name': name, 'error': '$error'})}\n\n';

/// 数据流结束帧：`event: done\ndata: {"name":...}\n\n`。
String dataStreamDoneSseFrame(String name) =>
    'event: done\ndata: ${_sseJson({'name': name})}\n\n';

/// 变更事件帧：`event: change\ndata: <DataChangeEvent.toJson()>\n\n`。
String changeEventSseFrame(DataChangeEvent e) =>
    'event: change\ndata: ${_sseJson(e.toJson())}\n\n';
