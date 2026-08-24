---
name: plugin-marketplace
role: Evergreen 插件市场 OWNER
scope: evg-base/plugins/marketplace/
parent: plugins
---

# AGENT.md — plugin-marketplace 职责书

> 本文件是「谁负责这里」的职责书。技术原理见根 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/plugins/marketplace/`（`module/manifest.json`，`component.type: "marketplace"`）
- 一句话定位：插件市场（本地插件管理 + 插件发现）——浏览、搜索、启用/停用、卸载。

> **实现归属说明**：市场 UI 的实现代码**不在本目录**，而分属其他 OWNER（不剥离，通过引用协作）：
> - 本地管理槽位 `marketplace_slot.dart` 等 → `renderer-templates`（`v4_modle/components/marketplace/`）
> - 远程市场页 `market_view.dart`、发现页 `discovered_plugins_view.dart` → `renderer-page`
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
