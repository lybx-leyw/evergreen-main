---
name: plugins
role: Evergreen 中游插件层总 OWNER
scope: evg-base/plugins/
parent: root
---

# AGENT.md — plugins（插件层总）职责书

> 本文件是「谁负责这里」的职责书。技术原理见同目录 `README.md` 与根 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/plugins/`（内置插件目录 + `README.md`，完整清单见 `plugins/README.md`）
- 一句话定位：中游插件层的总协调者，维护六维插件模型约定，统一托管简单插件。

### 六维插件模型（一个插件目录可含多类型子目录）

| 子目录 | 包含 | 被谁加载 |
|--------|------|---------|
| `agent/` | manifest.json + .exe | PluginBridge → toolRegistry |
| `module/` | manifest.json | ModuleLoader → ModuleRegistry |
| `theme/` | theme.json | ThemeLoader → ThemeStore |
| `data/` | manifest.json + .exe | DataSourceLoader → DataOrchestrator |
| `config/` | config.json | SettingsLoader → SharedPreferences |
| `skill/` | `*.md` | SkillLoader → SkillIndex |

### 内置插件清单

`ai-assistant`、`data-dashboard`、`dsh`、`html-creator`、`marketplace`、`python-runner`、`scraper`、`settings`、`skill-creator`、`theme-creator`

> 2026-08-25（t19）：`pdf_translate` 内置插件已移除（PDF 翻译功能撤销）。

### 已有独立 OWNER 的插件

| 插件 | 独立 OWNER | AGENT.md |
|------|-----------|---------|
| `theme-creator` | `plugin-theme-creator` | `plugins/theme-creator/AGENT.md` |
| `html-creator` | `plugin-html-creator` | `plugins/html-creator/AGENT.md` |
| `scraper` | `plugin-scraper` | `plugins/scraper/AGENT.md` |
| `dsh` | `plugin-dsh` | `plugins/dsh/AGENT.md` |
| `marketplace` | `plugin-marketplace` | `plugins/marketplace/AGENT.md` |
| `ai-assistant` | `plugin-ai-assistant` | `plugins/ai-assistant/AGENT.md` |
| `zju_modle`（纯模板） | `plugin-zju` | `lib/renderer/templates/zju_modle/AGENT.md` |

> 其余插件（`data-dashboard`、`python-runner`、`settings`、`skill-creator`）由本 OWNER 统一托管。
> `view` / `warm_study` / `zju_autosign` 已移交「发现插件」registry（`docs/plugin-registry/plugins.json`）管理
> （该 registry 现由独立视图「发现插件」`/discover` 消费，入口收敛于「插件中心」内部按钮）。

## 2. 边界与红线

- ✅ 可以：改 `plugins/` 内一切内容；新增简单插件；维护插件目录规范。
- ❌ 禁止：写 Dart UI 代码（插件只 JSON + .exe）；直接操作渲染；反向依赖 renderer；修改 core 内部实现。
- ⚠️ 需协调：插件 manifest 的 `template` 字段路由变更需与 `renderer-templates` 对齐；数据源 stdout 契约（顶层 Map）变更需与 `core-data` 对齐；新增配置 key 需在 `config/config.json` 声明（否则 Android 凭证降级失败）。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| manifest.json 规范 | JSON 声明 | core-module / core-data / core-config / core-theme | 字段增删需广播 |
| `.exe` 标准契约（stdout 首行 PORT:xxxx） | 进程协议 | core-module（ProcessManager） | 协议变更需通知 core-module |
| 数据源 stdout（顶层 Map） | 进程 stdout | core-data（register_data_source） | 契约变更需通知 core-data |
| 配置 config.json | JSON | core-config | key 增删需通知 core-config |

## 4. 规则（本 OWNER 内必须遵守）

- HTML-first：用户侧插件优先 `html-creator` + `template:"html"`，不要求用户写 Dart/JSON 组件树。
- 插件只 JSON + .exe，不写 Dart UI。
- 修改 `plugins/` 下运行时脚本（.py 等）后，必须同步运行 `tool/bundle_plugins.dart` 更新 `assets/plugins_bundle/`（否则 APK 打包旧文件）。
- 凭据只从设置页/config.json 读，禁止读 `.env` 或硬编码。

## 5. 验收标准

- 改完必须：修改 plugin 资产 → 重跑 `bundle_plugins.dart` → 相关 `flutter test` 无回归。

## 6. 独立 OWNER 判定标准

满足**任一**条件的插件，应建立独立 `plugins/<id>/AGENT.md`（OWNER 名 `plugin-<id>`）：
- 含多类型子目录（module + data + config + agent 等）
- 含 `.exe`/`.py` 业务逻辑
- 文件数 > 30

## 7. 引用索引

- 模块说明：`README.md`
- 心智模型：根 `CLAUDE.md`
- 上层职责书：根 `AGENT.md`
