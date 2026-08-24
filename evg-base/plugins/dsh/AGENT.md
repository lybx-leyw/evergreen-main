---
name: plugin-dsh
role: Evergreen DSH（DeepSeek Harness）OWNER
scope: evg-base/plugins/dsh/ + evg-base/lib/renderer/templates/dsh_modle/
parent: plugins
---

# AGENT.md — plugin-dsh 职责书

> 本文件是「谁负责这里」的职责书。技术原理见根 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：
  - 插件声明：`evg-base/plugins/dsh/`（`module/manifest.json`，`template: "dsh"`）
  - 模板实现：`evg-base/lib/renderer/templates/dsh_modle/`（3 文件：`dsh_modle_template.dart`、`dsh_modle_view.dart`、`dsh_injector.dart`）
- 一句话定位：DSH 平台级常驻 Agent——承载本地 DSH Web UI，赋能数据源创作。

## 2. 边界与红线

- ✅ 可以：改 `dsh/` 声明与 `dsh_modle/` 实现；新增 DSH 能力。
- ❌ 禁止：改动 `core/agent` 的 Agent 运行时（那是 `core-agent` 的地盘）；改动其他插件/模板；在渲染层写业务逻辑。
- ⚠️ 需协调：`dsh_injector` 注入的 Agent 能力依赖 `core-agent` 的 `AgentAssembly`，契约变更需对齐。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `dsh` 模板 | `template_registry`（manifest `template` 字段） | app-shell + core-module | 模板名/路由变更需广播 |
| Agent 注入 | `dsh_injector.dart` → `core-agent` | core-agent（AgentAssembly） | 构造契约变更需通知 core-agent |

## 4. 规则（本 OWNER 内必须遵守）

- 渲染层只画 UI，不写业务逻辑。
- Agent 能力通过 `core-agent` 的公开 API 注入，不绕过。

## 5. 验收标准

- 改完必须：相关 `flutter test` 通过；Agent 注入契约变更需全量回归。

## 6. 引用索引

- 心智模型：根 `CLAUDE.md`
- Agent 运行时（依赖）：`evg-base/lib/core/agent/CLAUDE.md`
- 上层职责书：`evg-base/plugins/AGENT.md`
