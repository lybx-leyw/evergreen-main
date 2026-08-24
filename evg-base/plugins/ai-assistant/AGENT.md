---
name: plugin-ai-assistant
role: Evergreen AI 助手 OWNER
scope: evg-base/plugins/ai-assistant/
parent: plugins
---

# AGENT.md — plugin-ai-assistant 职责书

> 本文件是「谁负责这里」的职责书。技术原理见根 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/plugins/ai-assistant/`（`module/manifest.json`，含 `workspace` 配置）
- 一句话定位：内置 AI 对话模块——全功能聊天、深度思考、联网搜索、工具调用、多会话、工作区。

> **实现归属说明**：聊天 UI 与 AI 能力的实现代码**不在本目录**，而分属其他 OWNER（不剥离，通过引用协作）：
> - 聊天视图 `chat_controller_view.dart`（147KB）等 → `renderer-templates`（`v4_modle/components/interaction/chat/`）
> - 全局记忆页 `global_memory_view.dart`、技能管理页 `skill_management_view.dart` → `renderer-page`
> - Agent 运行时/工具/记忆/Skill → `core-agent`
>
> 本 OWNER 负责插件声明（含 workspace 配置）与跨模块协调。

## 2. 边界与红线

- ✅ 可以：改 `ai-assistant/` 声明（manifest/workspace 配置/路由）。
- ❌ 禁止：直接改 `v4_modle/components/interaction/chat/`（归 renderer-templates）、`page/global_memory_view.dart`（归 renderer-page）、`core/agent/`（归 core-agent）。
- ⚠️ 需协调：workspace 工作区路径（`aiAssistantWorkspaceModuleId`）是跨模块契约，改动需对齐；工具禁用集（`toolDisabledProvider`）联动需与 core-agent/renderer 对齐。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `ai-assistant` workspace 配置 | manifest `workspace` | renderer-templates（chat view） | workspace 配置变更需通知 renderer-templates |
| 工作区路径常量 | `aiAssistantWorkspaceModuleId = 'ai-assistant'` | core-agent（工具写）+ renderer（UI 读） | 路径常量变更需广播 |
| 工具禁用集 | `toolDisabledProvider` | core-agent + renderer-templates | 状态 schema 变更需广播 |

## 4. 规则（本 OWNER 内必须遵守）

- 插件只声明 JSON + workspace 配置，AI 能力实现归 core-agent，UI 归 renderer。
- 工作区路径必须以 `aiAssistantWorkspaceModuleId` 常量（经 `greenix_path`）为准，禁止用宿主 `descriptor.id` 拼路径。

## 5. 验收标准

- 改完必须：相关 `flutter test` 通过；workspace 配置/路径常量变更需全量回归。

## 6. 引用索引

- 心智模型：根 `CLAUDE.md`
- 实现（协作方）：`evg-base/lib/core/agent/AGENT.md`、`evg-base/lib/renderer/templates/AGENT.md`、`evg-base/lib/renderer/page/AGENT.md`
- 上层职责书：`evg-base/plugins/AGENT.md`
