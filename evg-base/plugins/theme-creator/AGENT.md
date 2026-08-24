---
name: plugin-theme-creator
role: Evergreen 主题创作中心 OWNER
scope: evg-base/plugins/theme-creator/ + evg-base/lib/renderer/templates/theme_creator_modle/
parent: plugins
---

# AGENT.md — plugin-theme-creator 职责书

> 本文件是「谁负责这里」的职责书。技术原理见根 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：
  - 插件声明：`evg-base/plugins/theme-creator/`（`module/manifest.json`，`template: "theme-creator"`）
  - 模板实现：`evg-base/lib/renderer/templates/theme_creator_modle/`（14 文件：`models/`、`services/`、`view/`、`widgets/` + 模板/视图入口）
- 一句话定位：可视化主题创作中心——8 色语义色板编辑 + Dart 实时预览 + AI 生成 + 一键导出主题插件。

## 2. 边界与红线

- ✅ 可以：改 `theme-creator/` 声明与 `theme_creator_modle/` 实现；新增色板编辑、预览、导出能力。
- ❌ 禁止：改动 `core/theme/` 的主题引擎（那是 `core-theme` 的地盘）；改动其他插件/模板；在渲染层写业务逻辑。
- ⚠️ 需协调：导出的主题插件格式（`theme/theme.json` 扁平 8 色）变更需与 `core-theme` 对齐；`theme_creator_modle/` 从 `renderer-templates` 剥离，模板注册表（`templates_index.json`）变更需同步。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `theme-creator` 模板 | `template_registry`（manifest `template` 字段） | app-shell + core-module | 模板名/路由变更需广播 |
| 主题导出格式 | `theme/theme.json`（扁平 8 色） | core-theme（ThemeLoader） | 色板结构变更需通知 core-theme |
| `theme_chat_store` | `services/theme_chat_store.dart` | 自身 AI 生成 | 无外部消费 |

## 4. 规则（本 OWNER 内必须遵守）

- 渲染层只画 UI，不写业务逻辑。
- 主题导出走 `core/theme` 的 ThemeLoader 契约，不绕过。
- 窄屏 <600px 必须 `LayoutBuilder` 检测。

## 5. 验收标准

- 改完必须：相关 `flutter test` 通过；模板/导出格式变更需全量回归。

## 6. 引用索引

- 心智模型：根 `CLAUDE.md`
- 主题引擎（依赖）：`evg-base/lib/core/theme/CLAUDE.md`
- 上层职责书：`evg-base/plugins/AGENT.md`
