---
name: plugin-marketplace
role: Evergreen 插件市场 OWNER
scope: evg-base/plugins/marketplace/
parent: plugins
---

# AGENT.md — plugin-marketplace 职责书

> 本文件是「谁负责这里」的职责书。技术原理见根 `CLAUDE.md`。
> 最后更新：2026-08-26

## 1. 职责范围

- 管辖目录：`evg-base/plugins/marketplace/`（`module/manifest.json`，`component.type: "marketplace"`）
- 一句话定位：插件市场（本地插件管理）——浏览、搜索、启用/停用、卸载、排序。
- **「发现插件」由「插件中心」内部按钮跳转，不单列导航入口**：2026-08-26 二次修订，
  `MarketplaceSlot` 头部提供「发现插件」按钮（`context.push('/discover')`），mode_rail
  不再单独列出「发现插件」入口。`MarketplaceSlot` 自身仍为纯本地插件管理（不含内嵌发现 UI）。
  外部可发现插件的浏览与安装由独立视图 `DiscoveredPluginsView`（路由 `/discover`）负责。
  两者管理**层次不同**：插件中心管已装插件，发现插件管外部可装插件的浏览与安装，
  故发现插件作为插件中心内的一个动作而非并列的导航入口。

> **实现归属说明**：市场 UI 的实现代码**不在本目录**，而分属其他 OWNER（不剥离，通过引用协作）：
> - 本地管理槽位 `marketplace_slot.dart`（纯本地插件管理，无内嵌发现 UI）→ `renderer-templates`（`v4_modle/components/marketplace/`）
> - 发现插件独立视图 `discovered_plugins_view.dart` 与其列表卡 `discover_section.dart`
>   （`DiscoverPluginCard` 视觉风格与 `LocalPluginCard` 对齐）→ `renderer-page`
> - 市场领域模型 `plugin_review.dart`（ReviewQueue）→ `core-module`
>
> 本 OWNER 负责插件声明与跨模块协调，实现改动需与上述 OWNER 对齐。

## 2. 边界与红线

- ✅ 可以：改 `marketplace/` 声明（manifest/路由/配置）；协调市场功能跨模块变更。
- ❌ 禁止：直接改 `v4_modle/components/marketplace/`（归 renderer-templates）、`page/market_view.dart`（归 renderer-page）、`core/module/plugin_review.dart`（归 core-module）。
- ⚠️ 需协调：市场审核流（`ReviewQueue`）对接、插件状态联动侧边栏（`pluginStateProvider`）、卸载路径（id vs 文件夹名）均跨 OWNER，改动必须对齐。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `marketplace` 组件类型 | manifest `component.type` | renderer-templates（SlotDispatch） | 组件类型变更需通知 renderer-templates |
| 插件状态 | `.plugin_states.json`（`pluginStateProvider`） | renderer-app（侧边栏） | 状态 schema 变更需通知 renderer-app |
| 审核队列 | `core/module/plugin_review.dart` | renderer-page（market_view） | 审核流变更需通知 core-module |

## 4. 规则（本 OWNER 内必须遵守）

- 插件只声明 JSON，实现归对应 OWNER，本 OWNER 不写 UI 实现代码。
- 市场是「本地 MarketplaceSlot + 远程 MarketView」两套视图，改动需分清数据模型（`PluginInfo` vs `PluginDescriptor`）。

## 5. 验收标准

- 改完必须：相关 `flutter test` 通过；声明/状态 schema 变更需全量回归。

## 6. 引用索引

- 心智模型：根 `CLAUDE.md`
- 市场实现（协作方）：`evg-base/lib/renderer/templates/AGENT.md`、`evg-base/lib/renderer/page/AGENT.md`、`evg-base/lib/core/module/AGENT.md`
- 上层职责书：`evg-base/plugins/AGENT.md`
