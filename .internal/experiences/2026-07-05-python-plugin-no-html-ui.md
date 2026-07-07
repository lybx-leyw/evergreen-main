---
task_type: refactor
tags: [python, plugin, architecture, html, separation-of-concerns, settings]
difficulty: medium
outcome: success
date: 2026-07-05
files_touched:
  - plugins/settings/module/settings.py
---

## 做了什么

从 `plugins/settings/module/settings.py` 中删除所有 HTML 渲染相关代码（约 270 行），包括 `_render_setting_control()`、`_render_page()` 以及完整的 CSS 样式、JavaScript 逻辑和 HTML 模板。文件从 480 行精简到 208 行，只保留 JSON API 代理逻辑。

## 关键决策

<!-- TODO -->

## 踩过的坑

把 Python 插件当成了 Web 服务器来渲染页面——`settings.py` 中混入了完整的 HTML/CSS/JS 渲染代码，违反了项目架构的职责分离原则。

**根因**：没有遵循上中下游三层架构。Python 端应该只做后端服务 + API 代理，UI 渲染应该全部交给 Dart/Flutter 端。

**正确架构**：
- **Python 端**：纯 API 代理服务器，只负责 JSON API 端点的转发。不包含任何 HTML/CSS/JS。
- **Dart/Flutter 端**：负责所有 UI 渲染（`SettingsView` 等 widget），通过 manifest.json 声明插件信息和工具。

**原则**：Python = 后端服务 + API 代理；Dart = UI 渲染。两者职责严格分离。

## 可复用的模式

<!-- TODO -->
