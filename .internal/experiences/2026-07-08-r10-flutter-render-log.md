---
task_type: process
tags: [workflow, r10, html, renderer, flutter, clone, discipline]
difficulty: medium
outcome: success
date: 2026-07-08
files_touched:
  - .internal/EXPERIENCE.md
  - .codebuddy/FAIL.md
  - .codebuddy/memory/MEMORY.md
  - evg-base/lib/renderer/html/html_components.dart
  - evg-base/test/r10_render_log.dart
---

## 做了什么
在执行「复刻 28 插件」R10（HTML 渲染日志）校验时，我最初用 `tools/render_log.py` 这个独立 Python 脚本直接拼 HTML 并生成 `plugins/<id>/render_log.html`。用户纠正：**R10 必须用真实的 Flutter 参与的测试**，旧有的绕开 Flutter 的纯 Python HTML 脚本全部是「错误测试」。

## 关键决策
- R10 的 HTML 渲染日志生成器必须内嵌于 `evg-base/lib/renderer/html/`，即真正调用 `HtmlRenderer.render(manifest)`（与运行态 AppShell / `HtmlRenderView` 同源）。
- 「Flutter 参与」= 该生成器运行在 Flutter/Dart 上下文中（`package:flutter` 与 `package:evergreen_base` 可解析），而非独立 `python` 进程拼字符串。
- 真实数据必须注入渲染器：原 `data-table` 组件只渲染示例/占位行（`_sampleCell`），需在 `evg-base/lib/renderer/html/html_components.dart` 中为 `data-table` 增加 `config.rows`（真实行）支持——此改动属 R10 明确允许的「HTML 渲染实现升级」，范围受限、不超出原始组件描述。
- `tools/render_log.py`（绕开 Flutter）判为错误测试，应删除，改由 `evg-base/test/r10_render_log.dart`（Dart，调用真实 `HtmlRenderer`）替代。

## 踩过的坑
把「能生成一份看起来正常的 HTML」误当作「R10 通过」。独立 Python 脚本渲染出的 `data-table` 是硬编码示例数据（`项目 1 / 运行中`），违反 R10「数据为真实拉取数据，非虚构占位」的核心检查项。

**根因**：没吃透 R10 原文「HTML 渲染日志生成器内嵌于 evg-base/lib/renderer，并非绕开现在下游实现的独立脚本，需要flutter参与」；把「HTML 输出」与「Flutter 渲染器参与」混为一谈。

**原则**：R10 的 render_log.html 必须由真实 `HtmlRenderer`（在 Flutter 上下文内）生成，且页面内动态文本全部来自真实 JSON；任何脱离 `evg-base/lib/renderer` 的 HTML 拼装脚本都视为错误测试。

## 可复用的模式
- 正确 R10 流程：`dart run evg-base/test/r10_render_log.dart <id>`（在 evg-base 目录内）→ 读 `plugins/<id>/module/manifest.json` → 用 `Process.run` 跑 `data/<x>.exe` 真实拉取 → 把真实行注入 `data-table.config.rows` → `HtmlRenderer.render()` → 写 `render_log.html` → 跑真实数据/非空/无重叠/合规 四项检查。
- 运行环境：必须用 Flutter SDK 的 dart（`C:\flutter\bin\cache\dart-sdk\bin\dart.exe`），且 `evg-base` 已 `flutter pub get`（`.dart_tool/package_config.json` 存在），否则 `package:flutter` / `package:evergreen_base` 无法解析。
