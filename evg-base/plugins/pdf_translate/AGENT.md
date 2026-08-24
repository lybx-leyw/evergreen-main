---
name: plugin-pdf-translate
role: Evergreen PDF 翻译 OWNER
scope: evg-base/plugins/pdf_translate/
parent: plugins
---

# AGENT.md — plugin-pdf-translate 职责书

> 本文件是「谁负责这里」的职责书。技术原理见根 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/plugins/pdf_translate/`（`module/manifest.json`，`component.type: "pdf-translate"`）
- 一句话定位：基于 DeepSeek API 的 PDF 文档翻译——中/英/日/韩/法/德/西 7 语言互译，多文件并行 + 队列排队，输出双语对照 + 单语译文 PDF。

> **实现归属说明**：翻译 UI 与服务实现代码**不在本目录**，而分属其他 OWNER（不剥离，通过引用协作）：
> - 翻译组件 `translate_slot.dart` 等 → `renderer-templates`（`v4_modle/components/translate/`）
> - 翻译服务 `pdf_translate_service.dart`、`translate_queue.dart` → `core-services`
> - 论文阅读模板（`paper_reading_modle/`，`paper_service.dart`）为独立模板，非本插件实现
>
> 本 OWNER 负责插件声明与跨模块协调。

## 2. 边界与红线

- ✅ 可以：改 `pdf_translate/` 声明（manifest/路由/配置）。
- ❌ 禁止：直接改 `v4_modle/components/translate/`（归 renderer-templates）、`core/services/pdf_translate_service.dart`（归 core-services）。
- ⚠️ 需协调：翻译服务（DeepSeek API、队列、双语 PDF 生成）归属 `core-services`，本 OWNER 只声明不改实现；翻译组件与服务的契约（输入 PDF/语言对/输出）需对齐。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `pdf-translate` 组件类型 | manifest `component.type` | renderer-templates（SlotDispatch） | 组件类型变更需通知 renderer-templates |
| 翻译服务 | `core/services/pdf_translate_service.dart` | renderer-templates（translate_slot） | 服务签名变更需通知 core-services |
| 翻译队列 | `core/services/translate_queue.dart` | renderer-templates | 队列契约变更需通知 core-services |

## 4. 规则（本 OWNER 内必须遵守）

- 插件只声明 JSON，翻译服务/UI 归对应 OWNER，本 OWNER 不写实现代码。
- DeepSeek API Key 凭据从 `core-config` 读取，不硬编码。

## 5. 验收标准

- 改完必须：相关 `flutter test` 通过；声明/契约变更需全量回归。

## 6. 引用索引

- 心智模型：根 `CLAUDE.md`
- 实现（协作方）：`evg-base/lib/core/services/AGENT.md`、`evg-base/lib/renderer/templates/AGENT.md`
- 上层职责书：`evg-base/plugins/AGENT.md`
