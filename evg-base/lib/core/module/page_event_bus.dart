/// 页级事件总线 —— 单页内跨栏实时通信。
///
/// 对应 PLAN_NOW 第九节。零外部依赖，纯 Dart Stream 实现。
///
/// ## 生命周期
///
/// - 创建：页面激活时（[CompositeView] 中每个 Tab 页建一个实例）
/// - 销毁：页面切走时 dispose
/// - 不持久化、不跨页面、不跨模块
///
/// ## 用法
///
/// ```dart
/// final bus = PageEventBus(pageId: 'learn');
///
/// // 订阅事件
/// final sub = bus.on('word_completed').listen((e) {
///   print('收到来自 ${e.sourceSlot} 的 word_completed: ${e.data}');
/// });
///
/// // 发出事件
/// bus.emit('word_completed', sourceSlot: 'left',
///   data: {'word': 'apple', 'correct': true});
///
/// // 释放
/// bus.dispose();
/// ```
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 页级事件总线 —— 单页内所有 slot 共享。
///
/// 每个 slot 声明 `events: {emit: [...], subscribe: [...]}` 来定义
/// 自己产生和关注的事件。总线根据声明自动路由事件到订阅方。
class PageEventBus {
  /// 页面标识（如 `"learn"`）。
  final String pageId;

  final StreamController<SlotEvent> _controller;

  PageEventBus({required this.pageId})
      : _controller = StreamController<SlotEvent>.broadcast() {
    debugPrint('[PageEventBus:$pageId] 已创建');
  }

  // ═══════ 发出事件 ═══════

  /// 从指定 slot 发出事件。
  ///
  /// [event] — 事件名（如 `"word_completed"`），需匹配 manifest 中的 emit 声明。
  /// [sourceSlot] — 发出事件的栏（如 `"left"`、`"right"`）。
  /// [data] — 附带数据。
  void emit(String event, {required String sourceSlot, Map<String, dynamic>? data}) {
    final evt = SlotEvent(
      event: event,
      sourceSlot: sourceSlot,
      data: data ?? const {},
      timestamp: DateTime.now(),
    );
    debugPrint('[PageEventBus:$pageId] $sourceSlot → $event${data != null ? " $data" : ""}');
    _controller.add(evt);
  }

  // ═══════ 订阅 ═══════

  /// 订阅指定事件名的流。
  ///
  /// 返回的 Stream 只发送匹配的事件。调用方应在 dispose 时 cancel 订阅。
  Stream<SlotEvent> on(String event) {
    return _controller.stream.where((e) => e.event == event);
  }

  /// 订阅所有事件（调试用）。
  Stream<SlotEvent> get all => _controller.stream;

  // ═══════ 排泄声明 ═══════

  /// 从 manifest 的 events 声明中提取 emit 列表。
  static List<String> extractEmits(Map<String, dynamic>? eventsConfig) {
    final arr = eventsConfig?['emit'] as List?;
    if (arr == null) return [];
    return arr.map((e) => e.toString()).toList();
  }

  /// 从 manifest 的 events 声明中提取 subscribe 列表。
  static List<String> extractSubscribes(Map<String, dynamic>? eventsConfig) {
    final arr = eventsConfig?['subscribe'] as List?;
    if (arr == null) return [];
    return arr.map((e) => e.toString()).toList();
  }

  // ═══════ 生命周期 ═══════

  /// 释放总线。
  void dispose() {
    debugPrint('[PageEventBus:$pageId] 已释放');
    _controller.close();
  }
}

/// 单个栏间事件。
class SlotEvent {
  /// 事件名。
  final String event;

  /// 发出该事件的栏标识（如 `"left"`、`"right"`）。
  final String sourceSlot;

  /// 附带数据。
  final Map<String, dynamic> data;

  /// 时间戳。
  final DateTime timestamp;

  const SlotEvent({
    required this.event,
    required this.sourceSlot,
    required this.data,
    required this.timestamp,
  });

  @override
  String toString() =>
      'SlotEvent(event: $event, source: $sourceSlot, data: $data)';
}
