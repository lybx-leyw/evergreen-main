/// ⚠ DEPRECATED — 2026-07-05
///
/// `AiAssistantSlotWidget` 已被合并到 `ChatControllerView`（`embedded: true`）。
///
/// 参见 [ChatControllerView]——现在通过 `embedded`/`compact`/`pageEventBus`/`agentConfig`
/// 参数同时支持全页面和嵌入式两种形态。
///
/// **迁移指南：**
/// ```dart
/// // 旧写法
/// AiAssistantSlotWidget(
///   slotKey: slotKey,
///   config: config,
///   moduleId: moduleDescriptor.id,
///   pageEventBus: pageEventBus,
/// )
///
/// // 新写法
/// ChatControllerView(
///   descriptor: moduleDescriptor,
///   embedded: true,
///   compact: true,
///   pageEventBus: pageEventBus,
///   agentConfig: config.config,
///   slotKey: slotKey,
/// )
/// ```
library;

export 'chat_controller_view.dart';
