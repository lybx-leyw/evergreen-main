/// 栏状态暴露写入器 —— 将栏事件写入 Workspace。
///
/// 对应 PLAN_NOW §9.2-9.3。
///
/// 栏在 manifest 中声明 `expose_state: {events: [...], subdir: "..."}`，
/// 当指定事件在 EventBus 上被触发时，本 Writer 自动将事件数据写成状态快照
/// 到 `.greenix/workspaces/<moduleId>/<subdir>/state.json`。
///
/// ## 用法
///
/// ```dart
/// final writer = ExposeStateWriter(
///   moduleId: 'vocab-tutor',
///   slotKey: 'left',
///   config: ExposeStateConfig(events: ['word_completed'], subdir: 'type-check'),
///   bus: pageBus,
///   workspaceRoot: '.greenix/workspaces/vocab-tutor',
/// );
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'page_event_bus.dart';
import 'module_descriptor.dart' show ExposeStateConfig;

/// 暴露状态写入器 —— 将 EventBus 事件自动写入 Workspace 文件。
class ExposeStateWriter {
  final String moduleId;
  final String slotKey;
  final ExposeStateConfig config;
  final String workspaceRoot; // .greenix/workspaces/<moduleId>/

  final List<StreamSubscription<SlotEvent>> _subs = [];

  /// 最新写入的状态快照。
  Map<String, dynamic> _latestState = {};

  ExposeStateWriter({
    required this.moduleId,
    required this.slotKey,
    required this.config,
    required PageEventBus bus,
    required this.workspaceRoot,
  }) {
    for (final eventName in config.events) {
      final sub = bus.on(eventName).listen((evt) {
        // 只监听自己 slab 发出的事件
        if (evt.sourceSlot != slotKey) return;
        _onEvent(evt);
      });
      _subs.add(sub);
    }

    debugPrint('[ExposeState:$moduleId/$slotKey] 监听事件: ${config.events.join(", ")}'
        ' → $workspaceRoot/${config.subdir}/state.json');
  }

  void _onEvent(SlotEvent evt) {
    _latestState = Map<String, dynamic>.from(evt.data);
    _latestState['_event'] = evt.event;
    _latestState['_timestamp'] = evt.timestamp.toIso8601String();
    _latestState['_sourceSlot'] = evt.sourceSlot;

    _writeState();
  }

  void _writeState() {
    try {
      final dir = Directory('$workspaceRoot/${config.subdir}');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File('${dir.path}/state.json');
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(_latestState),
      );
      debugPrint('[ExposeState:$moduleId/$slotKey] state.json 已更新');
    } catch (e) {
      debugPrint('[ExposeState:$moduleId/$slotKey] 写入失败: $e');
    }
  }

  /// 获取最新状态快照。
  Map<String, dynamic> get latestState => Map.unmodifiable(_latestState);

  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    debugPrint('[ExposeState:$moduleId/$slotKey] 已释放');
  }
}
