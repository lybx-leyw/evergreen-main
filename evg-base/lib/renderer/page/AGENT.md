---
name: renderer-page
role: Evergreen 下游 renderer/page 子 OWNER
scope: evg-base/lib/renderer/page/
parent: renderer
---

# AGENT.md — renderer-page 职责书

> 本文件是「谁负责这里」的职责书。技术原理见 `../CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/renderer/page/`
- 一句话定位：独立页面视图——数据中枢、市场、设置、全局记忆、技能管理、插件详情、权限管理、文件查看器、发现插件。

### 主要文件

| 文件 | 职责 |
|------|------|
| `market_view.dart` | 远程市场页（GitHub 源插件，含 MarketView + 安装权限闸） |
| `my_plugins_view.dart` | 我的插件 |
| `settings_view.dart` | 设置页 |
| `data_dashboard_view.dart` | 数据中枢面板 |
| `global_memory_view.dart` | 全局记忆（Allport 分组） |
| `skill_management_view.dart` | 技能管理 |
| `plugin_detail_view.dart` | 插件详情 |
| `permission_management_view.dart` | 权限管理 |
| `discovered_plugins_view.dart` | 发现插件 |
| `file_viewer.dart` | 文件查看器 |
| `layouts/` | 布局 |

## 2. 边界与红线

- ✅ 可以：改 `page/` 内一切实现；新增页面。
- ❌ 禁止：写业务逻辑；直调 HTTP；改动 core/ 或其他 renderer 子 OWNER。
- ⚠️ 需协调：`market_view.dart`（远程市场）与 `marketplace_slot.dart`（本地管理）是两套独立市场视图、数据模型不同（`PluginDescriptor` vs `PluginInfo`），改动需分清；市场审核流对接 `core-module` 的 `ReviewQueue`。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `page.dart` barrel | barrel | app-shell + module | 页面增删需广播 |
| 市场页 | `market_view.dart` | core-module（ReviewQueue） | 审核流对接变更需通知 core-module |
| 设置页 | `settings_view.dart` | core-config | 设置项渲染变更需通知 core-config |

## 4. 规则（本 OWNER 内必须遵守）

- 渲染层只画 UI，不写业务逻辑。
- 页面数据经 Riverpod 从 core 取，禁止直调 HTTP。
- 全局记忆分组用 `groupMemoriesByAllport`（core-agent 提供），勿私自撤销 Allport 分类。

## 5. 验收标准

- 改完必须：相关 `flutter test` 通过；市场/设置改动需全量回归。

## 6. 引用索引

- 心智模型：`../CLAUDE.md`
- 上层职责书：`../AGENT.md`
