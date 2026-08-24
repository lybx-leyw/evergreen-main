---
name: plugin-html-creator
role: Evergreen HTML 插件创作中心 OWNER
scope: evg-base/plugins/html-creator/ + evg-base/lib/renderer/templates/html_modle/
parent: plugins
---

# AGENT.md — plugin-html-creator 职责书

> 本文件是「谁负责这里」的职责书。技术原理见根 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：
  - 插件声明：`evg-base/plugins/html-creator/`（`module/manifest.json`，`template: "html"`）
  - 模板实现：`evg-base/lib/renderer/templates/html_modle/`（4 文件：`html_modle_template.dart`、`html_modle_view.dart`、`bridge_script.dart`、`core_api_discovery.dart`）
- 一句话定位：HTML 插件创作中心——三栏 IDE（数据中枢浏览 → HTML/CSS/JS 编辑 → 实时预览 → AI 辅助生成 → 一键导出）。

## 2. 边界与红线

- ✅ 可以：改 `html-creator/` 声明与 `html_modle/` 实现；新增编辑、预览、导出能力。
- ❌ 禁止：改动 `core/` 的 JS Bridge 能力实现（`platform.*` 由 core 提供）；改动其他插件/模板；在渲染层写业务逻辑。
- ⚠️ 需协调：`platform.*` JS Bridge 能力契约变更需与 core 相关 OWNER 对齐；HTML 插件导出格式（`plugins/<id>/module/index.html + manifest.json`）变更需通知 `plugins` 层。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `html` 模板 | `template_registry`（manifest `template` 字段） | app-shell + core-module | 模板名/路由变更需广播 |
| HTML 插件导出格式 | `plugins/<id>/module/index.html + manifest.json` | plugins（ModuleLoader） | 导出格式变更需通知 plugins |
| `platform.*` JS Bridge | `bridge_script.dart` + core 能力 | 用户 HTML 插件 | Bridge API 变更需通知 core |

## 4. 规则（本 OWNER 内必须遵守）

- 渲染层只画 UI，不写业务逻辑。
- 用户侧插件创作以 HTML-first 为主，不要求用户写 Dart/JSON 组件树。
- WebView 加载 HTML 插件走 `html_modle` 的 JS Bridge，不绕过。

## 5. 验收标准

- 改完必须：相关 `flutter test` 通过；导出格式/Bridge 变更需全量回归。

## 6. 引用索引

- 心智模型：根 `CLAUDE.md`
- 上层职责书：`evg-base/plugins/AGENT.md`
