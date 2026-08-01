/// 页级事件总线 —— 单页内跨栏实时通信。v5P Phase 4 升级。
///
/// ## 生命周期
/// - 创建：页面激活时（[CompositeView] 中每个 Tab 页建一个实例）
/// - 销毁：页面切走时 dispose
/// - 不持久化、不跨页面、不跨模块
///
/// ## 标准事件类型（`domain:action` 格式）
/// | 类型 | 语义 |
/// |------|------|
/// | `data:selected` | 数据行被选中 |
/// | `data:changed`  | 数据被编辑 |
/// | `ui:refresh`    | 请求刷新数据 |
/// | `ui:toggle`     | 折叠/展开 slot |
/// | `nav:go`        | 页面跳转 |
/// | `form:submit`   | 表单提交 |
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 页级事件总线 —— 单页内所有 slot 共享。
class PageEventBus {
  final String pageId;
  final StreamController<SlotEvent> _controller;

  PageEventBus({required this.pageId})
      : _controller = StreamController<SlotEvent>.broadcast() {
    debugPrint('[PageEventBus:$pageId] 已创建');
  }

  /// 发出事件（兼容旧 API）。
  void emit(String event, {required String sourceSlot, Map<String, dynamic>? data}) {
    final evt = SlotEvent(
      event: event,
      sourceSlot: sourceSlot,
      data: data ?? const {},
      timestamp: DateTime.now(),
    );
    debugPrint('[PageEventBus:$pageId] $sourceSlot → $event');
    _controller.add(evt);
  }

  /// 按事件类型过滤订阅。
  Stream<SlotEvent> on(String event) =>
      _controller.stream.where((e) => e.event == event);

  /// 所有事件的流。
  Stream<SlotEvent> get all => _controller.stream;

  /// 提取 emit 声明。
  static List<String> extractEmits(Map<String, dynamic>? eventsConfig) {
    final arr = eventsConfig?['emit'] as List?;
    if (arr == null) return [];
    return arr.map((e) => e.toString()).toList();
  }

  /// 提取 subscribe 声明。
  static List<String> extractSubscribes(Map<String, dynamic>? eventsConfig) {
    final arr = eventsConfig?['subscribe'] as List?;
    if (arr == null) return [];
    return arr.map((e) => e.toString()).toList();
  }

  void dispose() {
    debugPrint('[PageEventBus:$pageId] 已释放');
    _controller.close();
  }
}

/// 栏间事件。
class SlotEvent {
  final String event;
  final String sourceSlot;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  const SlotEvent({
    required this.event,
    required this.sourceSlot,
    required this.data,
    required this.timestamp,
  });

  @override String toString() => 'SlotEvent(event: $event, source: $sourceSlot, data: $data)';
}

// ═══════ InheritedWidget 注入 ═══════

/// 将 [PageEventBus] 注入 widget 树，供任意深度的 slot 访问。
class PageEventBusScope extends InheritedWidget {
  final PageEventBus bus;

  const PageEventBusScope({super.key, required this.bus, required super.child});

  static PageEventBus of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PageEventBusScope>();
    assert(scope != null, 'PageEventBusScope 未在 widget 树中找到');
    return scope!.bus;
  }

  @override bool updateShouldNotify(PageEventBusScope old) => bus != old.bus;
}
