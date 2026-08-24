---
name: plugin-scraper
role: Evergreen 所见即所得爬虫 OWNER
scope: evg-base/plugins/scraper/ + evg-base/lib/renderer/templates/scraper_modle/
parent: plugins
---

# AGENT.md — plugin-scraper 职责书

> 本文件是「谁负责这里」的职责书。技术原理见根 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：
  - 插件声明：`evg-base/plugins/scraper/`（`module/manifest.json`，`template: "scraper"`）
  - 模板实现：`evg-base/lib/renderer/templates/scraper_modle/`（39 文件：`agent/`、`board/`、`explore/`、`view/`、`web/`、`workflow/` + 导出/校验/bridge/模板入口）
- 一句话定位：WYSIWYG 爬虫脚本生成器——内嵌浏览器抓包 + AI 生成 Python 爬虫 + 导出 .py/.exe。

## 2. 边界与红线

- ✅ 可以：改 `scraper/` 声明与 `scraper_modle/` 实现；新增抓包、AI 生成、导出能力。
- ❌ 禁止：改动 `core/data` 的数据源注册机制（那是 `core-data` 的地盘）；改动其他插件/模板；在渲染层写业务逻辑。
- ⚠️ 需协调：导出的 scraper `.py`/`.exe` 与数据源注册契约（stdout 顶层 Map）变更需与 `core-data` 对齐；`scraper_json_validator` 的校验逻辑与平台侧 `jsonDecode` 行为必须一致（AI loop 才能自修）。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `scraper` 模板 | `template_registry`（manifest `template` 字段） | app-shell + core-module | 模板名/路由变更需广播 |
| 导出 data 源 | `data/manifest.json` + `scraper.exe` | core-data（register_data_source） | stdout 契约变更需通知 core-data |
| 导出 config | `config/config.json` | core-config | 敏感字段声明变更需通知 core-config |
| AI 导出/注册工具 | `export_and_register_scraper` | 自身 AI loop | 结果回灌契约需自洽 |

## 4. 规则（本 OWNER 内必须遵守）

- 渲染层只画 UI，不写业务逻辑。
- AI 调试循环必须执行与平台完全相同的校验（同一校验器），失败日志回灌 AI（含 `❌` 标记）。
- 导出 scraper 的 stdout 顶层必须是 `Map<String, dynamic>`（列表型包 `{"items":[...]}`）。
- 凭据只从设置页/config.json 读，禁止读 `.env` 或硬编码。

## 5. 验收标准

- 改完必须：`test/scraper_json_validator_test.dart` 等纯 Dart 回归通过；导出/注册链路需全量回归。

## 6. 引用索引

- 心智模型：根 `CLAUDE.md`
- 数据源契约（依赖）：`evg-base/lib/core/data/CLAUDE.md`
- 上层职责书：`evg-base/plugins/AGENT.md`
