# Evergreen

Evergreen 是一个面向 AI4Life 的开源 AI 平台，v2.0-rc 系列（最新 tag：`v2.0-rc.2`）。

本项目以 GPLv3 许可证发布，详见 [LICENSE](./LICENSE)。

## 核心能力

- **AI 助手**：本地优先的 Agent 运行时（对话 / 工具 / 记忆 / Skill）
- **HTML 插件创作中心**（用户侧主路径）：三栏 IDE + 实时预览 + AI 辅助生成/改稿 + 一键导出
- **主题创作 / Skill 创作**：可视化创作中心
- **数据采集**：所见即所得爬虫（scraper）+ 数据谱仪器
- **插件市场**：内置插件仓库，外部插件放入 `plugins/` 即热加载

## 快速开始

```bash
# 拉取依赖
cd evg-base
flutter pub get

# 运行（Windows / Android）
flutter run -d windows   # 或 -d android

# 测试
cd evg-base && flutter test

# 生成模板注册表（新增模板后）
cd evg-base
dart tool/gen_template_registry.dart --profile release_full
```

## 插件开发

- **上架协议规范**：[`evg-base/docs/plugin-registry/plugin-registry-spec-v1.md`](evg-base/docs/plugin-registry/plugin-registry-spec-v1.md) —— 定义外部插件如何被市场发现、下载、加载。
- **互动开发指南**：[`plugin_guide.html`](plugin_guide.html) —— 分步讲解 HTML / Dart / 数据源 / 主题四类插件的写法。
- **三类示例插件**（`evg-base/docs/plugin-registry/examples/`）：
  - [`example-theme-warm_study/`](evg-base/docs/plugin-registry/examples/example-theme-warm_study/) —— 主题插件（`theme/theme.json`）
  - [`example-html-view/`](evg-base/docs/plugin-registry/examples/example-html-view/) —— HTML 模块插件（`module/index.html` + `manifest.json`）
  - [`example-data-zju_grades/`](evg-base/docs/plugin-registry/examples/example-data-zju_grades/) —— 数据源插件（`data/manifest.json` + `scraper.py` + `config/config.json`）

> 用户侧插件以 **HTML 为主**：`html-creator` 导出 `plugins/<id>/module/index.html + manifest.json`（`"template":"html"`），运行时由 WebView + `platform.*` JS Bridge 加载。

> 📐 交互式架构示意图：[`docs/evergreen-architecture.html`](docs/evergreen-architecture.html)

## 内置插件（`evg-base/plugins/`）

| 插件 | 类型 | 说明 |
|------|------|------|
| `ai-assistant` | 模块（dart 渲染） | AI 助手——聊天/深度思考/搜索/工具调用/多会话 |
| `html-creator` | 模板 `html` | HTML 插件创作中心 |
| `theme-creator` | 模板 `theme-creator` | 主题创作中心 |
| `skill-creator` | 模板 `skill-creator` | Skill 创作中心 |
| `scraper` | 模板 `scraper` | 所见即所得爬虫 |
| `dsh` | 模板 `dsh` | DeepSeek Harness |
| `marketplace` | 模块（dart 渲染） | 插件市场——浏览/启停/卸载 |
| `pdf_translate` | 模块（JSON pages） | PDF 翻译（DeepSeek API，7 语言互译） |
| `data-dashboard` | 模块（dart 渲染） | 数据中枢——数据源状态总览 |
| `python-runner` | Agent 工具 | Python 运行器 |
| `warm_study` | 主题插件 | 温习主题（`theme/theme.json`） |
| `view` | 模板 `html` | 我的成绩单（HTML 插件） |
| `settings` | 模块（dart 渲染） | 设置——API Key/模型/主题 |
| `zju_autosign` | 模板 `html` | 浙大自动签到（HTML 插件） |

> 说明：`html` / `theme-creator` / `skill-creator` / `scraper` / `dsh` 为模板型插件（manifest 含 `"template"`），其余为 JSON 模块（`pages` 声明）或特殊类型。当前完整清单以 `evg-base/plugins/` 目录与 `evg-base/plugins/README.md` 为准。

## 文档地图

| 范围 | 文档 |
|------|------|
| OWNER 职责书 / 贡献协议 | `AGENT.md` / `CONTRIBUTING.md` |
| AI 协作总入口 | `CLAUDE.md` |
| 平台底层 / Lib 层 | `evg-base/README.md` / `evg-base/lib/README.md` |
| 各子域规范 | `evg-base/lib/core/*/CLAUDE.md` + `README.md`（见根 `CLAUDE.md` §文档地图） |
| 下载中心 / 特性截图 | `docs/index.html` + `docs/features/*.png` |
