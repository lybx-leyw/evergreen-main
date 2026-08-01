/// 组件自注册表 — v4_modle 模板的核心分派机制。
///
/// 每个组件（`*_slot.dart`）在文件底部调用 [SlotRegistry.register] 自注册。
/// [SlotDispatch] 仅需一次 `lookup(config.type)` 即可获取构建器。
///
/// # 设计原则（对齐 HTML Custom Elements）
///
/// - 新增组件类型 = 新增一个 `*_slot.dart` + 一行 `register()` 调用
/// - 模板的树渲染器不持有任何组件的显式 import
/// - 同功能多别名（如 `video-player` / `video`）通过 `aliases` 参数声明
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';

/// 组件构建器签名。
///
/// 接收 [SlotContext]（含 config / moduleDescriptor / pageEventBus / pluginsDir），
/// 返回对应的 Flutter Widget。
typedef SlotBuilder = Widget Function(SlotContext ctx);

/// 构建上下文 — 包含组件渲染所需的全部环境信息。
class SlotContext {
  /// slot 标识（manifest 中的 key）。
  final String slotKey;

  /// 组件描述符（type + config + dataSource 等）。
  final ComponentDescriptor config;

  /// 所属模块的完整描述符。
  final ModuleDescriptor moduleDescriptor;

  /// 页面级事件总线（可选，仅页面上下文中有）。
  final PageEventBus? pageEventBus;

  /// 插件根目录绝对路径（用于资源路径解析）。
  final String? pluginsDir;

  const SlotContext({
    required this.slotKey,
    required this.config,
    required this.moduleDescriptor,
    this.pageEventBus,
    this.pluginsDir,
  });
}

/// 全局组件注册表（单例）。
///
/// 用法：
/// ```dart
/// // 组件自注册（*_slot.dart 底部）
/// SlotRegistry.register('chart', (ctx) => ChartSlot(config: ctx.config),
///     aliases: const []);
///
/// // 模板分派（SlotDispatch）
/// final builder = SlotRegistry.lookup(config.type);
/// ```
class SlotRegistry {
  static final SlotRegistry _instance = SlotRegistry._();
  factory SlotRegistry() => _instance;
  SlotRegistry._();

  final Map<String, SlotBuilder> _builders = {};

  /// 组件自注册入口。
  ///
  /// [type] 为 manifest 中 `component.type` 的值（如 `'chart'`）。
  /// [aliases] 为同功能别名列表（如 `['video-player', 'video']`）。
  /// 别名仅在目标 key 未被注册时才生效，避免覆盖已有的独立类型。
  static void register(String type, SlotBuilder builder, {List<String> aliases = const []}) {
    _instance._builders[type] = builder;
    for (final alias in aliases) {
      if (!_instance._builders.containsKey(alias)) {
        _instance._builders[alias] = builder;
      }
    }
  }

  /// 按组件类型名查找构建器。未注册返回 null。
  static SlotBuilder? lookup(String type) => _instance._builders[type];

  /// 获取所有已注册的组件类型名（供 ComponentPicker 等使用）。
  static Set<String> get registeredTypes => _instance._builders.keys.toSet();

  /// 检查某类型是否已注册。
  static bool isRegistered(String type) => _instance._builders.containsKey(type);

  /// 获取已注册组件数量（含别名）。
  static int get count => _instance._builders.length;
}
