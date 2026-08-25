---
name: root
role: Evergreen 仓库总工程师 OWNER
scope: 仓库根目录 + 全仓统筹
parent: "-"
---

# AGENT.md — root（仓库总工程师）职责书

> 本文件是「谁负责这里」的职责书。技术原理见根 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：仓库根目录（`AGENT.md`、`CONTRIBUTING.md`、`README.md`、`CLAUDE.md`、`LICENSE`、`ATTRIBUTION.md` 等根级文档）
- 一句话定位：统筹全局、跨模块仲裁、OWNER 索引维护、贡献协议、发布流程。

## 2. 边界与红线

- ✅ 可以：维护根级文档、OWNER 索引表、贡献协议；协调跨 OWNER 的契约变更；制定发布流程。
- ❌ 禁止：直接改动任何子 OWNER 管辖目录内的业务代码（应派发给对应 OWNER）；绕过 OWNER 边界做跨模块改动；修改正本目录（当前是副本）。
- ⚠️ 需协调：跨 OWNER 契约变更（HTTP 端点、端口文件格式、ModuleDescriptor 字段等）必须召集相关 OWNER 对齐并登记。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| OWNER 索引表 | 本文件 §6 | 全部 OWNER | 新增/删除 OWNER 时必须更新 |
| 贡献协议 | `CONTRIBUTING.md` | 全部贡献者 | 变更需广播 |
| AI 协作总入口 | `CLAUDE.md` | 全部 AI 协作者 | 架构变化时更新 |

## 4. 规则（本 OWNER 内必须遵守）

- 遵循 `CONTRIBUTING.md` §3 的架构红线（renderer 不调 HTTP、不改正本、不绕过 ModuleDescriptor、设置开关必须联动消费方等）。
- 跨 OWNER 契约变更必须登记到对应 OWNER 的「对外契约」表并通知受影响方。

## 5. 验收标准

- 改完必须：根级文档改动无代码回归；若涉及跨 OWNER 契约，确认相关 OWNER 已登记变更。

## 5.1 跨 OWNER 契约变更登记（2026-08-25 通用插件化工程）

> 依据 `docs/2026-08-25-general-pluginization-plan.md`（用户已确认）。所有实现任务完成后须回写本表状态。

| 日期 | 契约变更 | 涉及 OWNER | 状态 |
|------|---------|-----------|------|
| 2026-08-25 | HtmlExportService 单目标化：HTML 插件导出不再双写 `assets/plugins_bundle/`（bundle=plugins/ 纯镜像不变式，仅 `tool/bundle_plugins.dart` 生成）；统一走 `resolvePluginsRoot()`（与主题插件导出路径一致） | renderer（改造）/ platform（bundle/CI）/ plugins（插件清单） | ✅ 已实现（t10/t14） |
| 2026-08-25 | .egsync 同步中心新契约：`.egsync.zip` 包结构 + `config.evgconfig` v2 格式（向后兼容 v1）+ 会话 `parent_id/fork_turn` 元数据 + 插件/数据源/主题导出导入契约（复用 .plugin 信封 + fail-closed） | core-config（牵头）/ core-agent / core-module / core-data / plugins / renderer | ✅ 已实现（t11/t15/t16/t17），规格 `docs/superpowers/specs/egsync-sync-center-spec-v1.md` v1.3 |
| 2026-08-25 | Python 解释器唯一路径：`PythonInterpreter.resolve()` 单例收敛（消除 5+ 处重复探测 + `'chaquopy'` 哨兵 + 双真理源）；agent 工具 `.exe` 优先改为 `.py` 优先（runtime 字段） | core（基础设施）/ core-agent / core-data / plugins | ✅ 已实现（t9/t12/t13/t18），plugins 域 .exe 残留=0 |

## 6. OWNER 索引表

> 本表是 16 个固定 OWNER 的唯一权威索引。新增/删除 OWNER 必须同步更新。

| OWNER | 管辖目录 | AGENT.md 路径 |
|-------|---------|--------------|
| `root` | 仓库根 | 根 `AGENT.md`（本文件） |
| `core` | `evg-base/lib/core/` 顶层 + errors/log/result | `evg-base/lib/core/AGENT.md` |
| `core-agent` | `evg-base/lib/core/agent/` | `evg-base/lib/core/agent/AGENT.md` |
| `core-config` | `evg-base/lib/core/config/` | `evg-base/lib/core/config/AGENT.md` |
| `core-data` | `evg-base/lib/core/data/` | `evg-base/lib/core/data/AGENT.md` |
| `core-module` | `evg-base/lib/core/module/` | `evg-base/lib/core/module/AGENT.md` |
| `core-theme` | `evg-base/lib/core/theme/` | `evg-base/lib/core/theme/AGENT.md` |
| `core-services` | `evg-base/lib/core/services/` | `evg-base/lib/core/services/AGENT.md` |
| `core-infra` | `evg-base/lib/core/utils/` + `plugin/` + `feedback/` | `evg-base/lib/core/utils/AGENT.md` |
| `renderer` | `evg-base/lib/renderer/` 顶层 + atomic + components | `evg-base/lib/renderer/AGENT.md` |
| `renderer-app` | `evg-base/lib/renderer/app/` | `evg-base/lib/renderer/app/AGENT.md` |
| `renderer-page` | `evg-base/lib/renderer/page/` | `evg-base/lib/renderer/page/AGENT.md` |
| `renderer-templates` | `evg-base/lib/renderer/templates/` | `evg-base/lib/renderer/templates/AGENT.md` |
| `app-shell` | `evg-base/lib/` 顶层（main/app/providers） | `evg-base/lib/AGENT.md` |
| `platform` | `evg-base/scripts/` + `tool/` + `windows/` + `android/` | `evg-base/scripts/AGENT.md` |
| `plugins` | `plugins/` | `evg-base/plugins/AGENT.md` |
| `plugin-theme-creator` | `plugins/theme-creator/` + `renderer/templates/theme_creator_modle/` | `evg-base/plugins/theme-creator/AGENT.md` |
| `plugin-html-creator` | `plugins/html-creator/` + `renderer/templates/html_modle/` | `evg-base/plugins/html-creator/AGENT.md` |
| `plugin-scraper` | `plugins/scraper/` + `renderer/templates/scraper_modle/` | `evg-base/plugins/scraper/AGENT.md` |
| `plugin-dsh` | `plugins/dsh/` + `renderer/templates/dsh_modle/` | `evg-base/plugins/dsh/AGENT.md` |
| `plugin-marketplace` | `plugins/marketplace/` | `evg-base/plugins/marketplace/AGENT.md` |
| `plugin-ai-assistant` | `plugins/ai-assistant/` | `evg-base/plugins/ai-assistant/AGENT.md` |
| `plugin-pdf-translate` | `plugins/pdf_translate/` | `evg-base/plugins/pdf_translate/AGENT.md` |
| `plugin-zju` | `renderer/templates/zju_modle/` | `evg-base/lib/renderer/templates/zju_modle/AGENT.md` |
