<div align="center">

<img src="evg-base/assets/branding/logo.svg" alt="Evergreen Logo" width="120" height="120"/>

# Evergreen

**面向 AI4Life 的开源 AI 平台** · 本地优先 · 插件化 · 跨平台（Windows / Android）

<br/>

![platform](https://img.shields.io/badge/平台-Windows%20%7C%20Android-17181a?style=flat-square&labelColor=fafafa)
![license](https://img.shields.io/badge/许可证-GPLv3-0f9d58?style=flat-square&labelColor=fafafa)
![version](https://img.shields.io/badge/版本-v2.0--rc.4-17181a?style=flat-square&labelColor=fafafa)
![flutter](https://img.shields.io/badge/Flutter-本地优先-0f9d58?style=flat-square&labelColor=fafafa)
![ai](https://img.shields.io/badge/AI4Life-开源-17181a?style=flat-square&labelColor=fafafa)

> 当前版本 **v2.0-rc 系列**（最新 tag：`v2.0-rc.4`） · 本项目以 **GPLv3** 许可证发布，详见 [LICENSE](./LICENSE)

</div>

---

## ✨ 核心能力

<table align="center">
<tr>
<td width="33%" align="center">

### 🤖 AI 助手

本地优先的 Agent 运行时
对话 / 工具 / 记忆 / Skill / 守护

</td>
<td width="33%" align="center">

### 🎨 HTML 插件创作

三栏 IDE · 实时预览
AI 辅助生成 / 改稿 · 一键导出

</td>
<td width="33%" align="center">

### 🧩 插件市场

内置插件仓库
外部插件放入即热加载

</td>
</tr>
<tr>
<td width="33%" align="center">

### 📊 数据采集

所见即所得爬虫
+ 数据谱仪器

</td>
<td width="33%" align="center">

### 🎭 主题创作

扁平 8 色语义色板
可视化创作中心

</td>
<td width="33%" align="center">

### 🛠️ Skill 创作

Skill 生成 / 改写
多 Agent 流水线

</td>
</tr>
</table>

---

## 🚀 快速开始

```bash
# 1. 拉取依赖
cd evg-base
flutter pub get

# 2. 运行（Windows / Android）
flutter run -d windows   # 或 -d android

# 3. 测试
cd evg-base && flutter test

# 4. 生成模板注册表（新增模板后）
cd evg-base
dart tool/gen_template_registry.dart --profile release_full
```

> 📐 交互式架构示意图：[`docs/evergreen-architecture.html`](docs/evergreen-architecture.html)

---

## 🧩 插件开发

<div align="center">

| 入口 | 说明 |
|------|------|
| 📖 [**上架协议规范**](evg-base/docs/plugin-registry/plugin-registry-spec-v1.md) | 外部插件如何被市场发现、下载、加载 |
| 📚 [**互动开发指南**](plugin_guide.html) | 分步讲解 HTML / Dart / 数据源 / 主题四类插件的写法 |
| 🖼️ [**示例插件**](evg-base/docs/plugin-registry/examples/) | 主题 / HTML 模块 / 数据源 三类开箱示例 |

</div>

> 💡 **用户侧插件以 HTML 为主**：`html-creator` 导出 `plugins/<id>/module/index.html + manifest.json`（`"template":"html"`），运行时由 WebView + `platform.*` JS Bridge 加载。

### 示例插件一览

| 示例 | 类型 | 位置 |
|------|------|------|
| 🎭 温暖学习 | 主题插件（`theme/theme.json`） | [`example-theme-warm_study/`](evg-base/docs/plugin-registry/examples/example-theme-warm_study/) |
| 🌐 成绩单视图 | HTML 模块插件（`module/index.html` + `manifest.json`） | [`example-html-view/`](evg-base/docs/plugin-registry/examples/example-html-view/) |
| 📈 浙大成绩 | 数据源插件（`data/manifest.json` + `scraper.py` + `config/config.json`） | [`example-data-zju_grades/`](evg-base/docs/plugin-registry/examples/example-data-zju_grades/) |

---

## 📦 内置插件（`evg-base/plugins/`）

| 插件 | 类型 | 说明 |
|------|------|------|
| 🗨️ `ai-assistant` | 模块（dart 渲染） | AI 助手——聊天/深度思考/搜索/工具调用/多会话 |
| 🎨 `html-creator` | 模板 `html` | HTML 插件创作中心 |
| 🎭 `theme-creator` | 模板 `theme-creator` | 主题创作中心 |
| 🛠️ `skill-creator` | 模板 `skill-creator` | Skill 创作中心 |
| 🕷️ `scraper` | 模板 `scraper` | 所见即所得爬虫 |
| 🔮 `dsh` | 模板 `dsh` | DeepSeek Harness |
| 🧩 `marketplace` | 模块（dart 渲染） | 插件市场——浏览/启停/卸载 |
| 📊 `data-dashboard` | 模块（dart 渲染） | 数据中枢——数据源状态总览 |
| 🐍 `python-runner` | Agent 工具 | Python 运行器 |
| ⚙️ `settings` | 模块（dart 渲染） | 设置——API Key/模型/主题 |

> 说明：`html` / `theme-creator` / `skill-creator` / `scraper` / `dsh` 为模板型插件（manifest 含 `"template"`），其余为 JSON 模块（`pages` 声明）或特殊类型。当前完整清单以 `evg-base/plugins/` 目录与 [`evg-base/plugins/README.md`](evg-base/plugins/README.md) 为准。
>
> 🔎 **发现插件（registry）**：`view`（我的成绩单）、`warm_study`（温暖学习）、`zju_autosign`（浙大自动签到）等插件通过 [`evg-base/docs/plugin-registry/plugins.json`](evg-base/docs/plugin-registry/plugins.json) 管理，可在「发现插件」页安装，见 [`plugin-registry-spec-v1.md`](evg-base/docs/plugin-registry/plugin-registry-spec-v1.md)。

---

## 🗺️ 文档地图

| 范围 | 文档 |
|------|------|
| 🏛️ OWNER 职责书 / 贡献协议 | [`AGENT.md`](AGENT.md) / [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| 🤖 AI 协作总入口 | [`CLAUDE.md`](CLAUDE.md) |
| 🏗️ 平台底层 / Lib 层 | [`evg-base/README.md`](evg-base/README.md) / [`evg-base/lib/README.md`](evg-base/lib/README.md) |
| 📚 各子域规范 | `evg-base/lib/core/*/CLAUDE.md` + `README.md`（见根 `CLAUDE.md` §文档地图） |
| ⬇️ 下载中心 / 特性截图 | `docs/index.html` + `docs/features/*.png` |

---

<div align="center">

<img src="evg-base/assets/branding/pet.svg" alt="Evergreen Pet" width="64" height="64"/>

<br/>

**Evergreen** — 让 AI 与生活共生长

[GPLv3](./LICENSE) · Made with 🍃 for AI4Life

</div>
