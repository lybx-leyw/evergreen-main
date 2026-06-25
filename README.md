# Evergreen Multi-Tools v1.4.0

> **v1.4.0**：rvpn 启用 · 全代码初步重构 · 百级专属 AI 集群试探  
> **下一站 v2.0.0**：完整重构 + 多 Agent 联邦稳定后发布

> 这是将奥尔波特人格理论引入 AI 记忆的开源实践。  
> 是集成 Agent 运行时的浙大校园工具。  
> 更是 AI Agent 贡献规约 + 百级多 Agent 联邦协作的实践者。  
> **欢迎广大浙大学子共建共创。**

---

## 快速开始

```bash
# Flutter 桌面应用
flutter pub get && flutter run -d windows

# 百级 AI Agent 联邦（全仓库重构时启用）
cd agent_contributing\evergreen_agents\reasonix
go build -o bin/reasonix_gr.exe ./cmd/reasonix_gr
reasonix_gr ceo
```

---

## 核心特色

- **🧠 奥尔波特特质理论记忆** — MemoryAgent 每轮对话后分析用户特质，五层结构，人类可随时查看编辑
- **📋 热加载 Skill 系统** — 丢 `.md` 到 `.greenix/skills/`，AI 即刻加载
- **🔍 两级 OCR** — DeepSeek-OCR 云端 → Tesseract 本地自动降级
- **🤖 自研 Agent 运行时** — Reasonix 的 Dart 复刻，17 种类型化事件
- **🏰 Palace 认知中间件** — 事件采集·AI 提炼·教训冶炼·认知回响
- **🖥️ RVPN** — 校园 VPN（zju-connect SOCKS5 代理），v1.4.0 启用
- **🤖 百级 AI Agent 联邦** — reasonix_gr：每模块持久 Keeper+Executor，闲置零消耗（探索中，v2.0.0 目标）
- **📊 1000+ 个自动化测试**（1067 passed）

---

## 功能模块（18 个）

| 模块 | 功能 |
|---|---|
| Auth | ZJU SSO 统一认证 |
| Courses | 课程列表 |
| Scores | 成绩 + 四种 GPA 制式 |
| Exams | 考试倒计时 |
| Todo | 待办 + 钉钉推送 |
| ZDBK | 教务通知、开课情况 |
| Classroom | 智云课堂视频 + PPT |
| Teachers | 查老师评分 |
| Schedule | 课表 iCal 导出 |
| Tutor | AI 笔记 + DeepSeek + OCR |
| Agent | AI 教学助手（对话 + 工具） |
| Translate | PDF 翻译（DeepSeek + pdf2zh 引擎） |
| Palace | 认知宫殿（事件采集·AI 提炼·树状浏览） |
| WordPecker | FSRS 间隔重复背词 |
| Downloads | 课件下载管理 |
| Plan | 计划管理（多计划、大纲任务、周时间表涂色） |
| Settings | 配置管理 |
| RVPN | ✅ 校园 VPN（zju-connect SOCKS5 代理）— **v1.4.0 启用** |

> ⚠️ 以下模块因后端 API 不可用等原因暂未启用：图书馆、一卡通、PTA 答题、自动签到、智能调度

---

## AI Agent 双工作模式

| 模式 | 入口 | 适用 | 流程 |
|------|------|------|------|
| **11 步 Skill** | 加载 `agent_contributing/skill/SKILL.md` | 单次聚焦任务、日常开发 | 状态机强制 11 步 |
| **联邦 Fleet** | `reasonix_gr ceo` | 全仓库整改、跨模块重构 | CEO 分派→Keeper→Executor（轻量，探索中） |

> 联邦模式**不走 11 步流程**——跨模块重构足够复杂，叠加完整流程会导致上下文过早枯竭。v2.0.0 将稳定此模式。

---

## 安装与依赖

### Windows（推荐）

Windows 安装包**自带 Python 3.10 运行时**，无需手动安装任何依赖。详见 [BUILD.md](./BUILD.md)。

### 本地 OCR

两级 OCR：云端 DeepSeek-OCR（DashScope API）→ 本地 Tesseract 自动降级。

1. 下载安装 [Tesseract OCR](https://github.com/UB-Mannheim/tesseract/wiki)，勾选 "Chinese Simplified" 语言包
2. `pip install -r scripts/requirements.txt`

### 云端 OCR（可选）

在设置页填入 DashScope API Key 并开通 `vanchin/deepseek-ocr` 模型。未配置时自动降级到本地 Tesseract。

### PDF 翻译

PDF 翻译通过 Python 子进程调用内置于 `scripts/pdf2zh_next/` 的 pdf2zh 引擎，输出保留排版、公式、图表的双语对照 PDF。

特性：
- **零配置**：自带 Python + 自动检测降级链（自带 → 用户配置 → 系统 PATH）
- **中文阶段管线**：9 阶段可视化进度指示器
- **应用内阅读**：全屏 PDF 阅读器，支持翻页（pdfrx）
- **批量翻译**：多文件队列，逐文件显示进度，完成即展示阅读按钮

---

## 构建

```bash
# Windows（包含 Python OCR 脚本 + 本地 Tesseract）
flutter build windows --release

# Android（可编译，不承诺功能可用）
flutter build apk --release

# 百级 AI 集群（reasonix_gr）
cd agent_contributing\evergreen_agents\reasonix
go build -o bin/reasonix_gr.exe ./cmd/reasonix_gr
```

> ⚠️ Android 版本可编译构建 APK，但**不承诺任何功能可用**。OCR、AI 助手等高级功能尚未适配移动端，存在已知问题。推荐使用 Windows 桌面版获得完整体验。

---

## 项目谱系

- **v1.4.0**（当前）— Dart/Flutter 桌面应用，18 个功能模块（rvpn 已启用），自研 Agent 运行时，Palace 认知中间件，PDF 翻译
- **v1.3.1** — 17 个功能模块，自研 Agent 运行时，Palace 认知中间件，PDF 翻译
- Agent 运行时参考 [Reasonix](https://github.com/esengine/reasonix) (MIT)，Dart 独立重写
- reasonix_gr 是 [DeepSeek-Reasonix](https://github.com/esengine/DeepSeek-Reasonix) (MIT) 的深度 fork — 多智能体联邦衍生物
- 成绩计算 & 教务交互参考 [Celechron](https://github.com/Celechron/Celechron) (GPL-3.0)
- 教师评分数据来自 [Lazuli](https://github.com/ADSR1042/Lazuli) (GPL-3.0)
- WordPecker 背词引擎参考 [Qwerty Learner](https://github.com/RealKai42/qwerty-learner) (GPL-3.0)
- PDF 翻译引擎内嵌自 [PDFMathTranslate-next](https://github.com/PDFMathTranslate-next/PDFMathTranslate-next) (AGPL-3.0)
- Agent 贡献规范受 [MemGovern](https://github.com/esengine/memgovern) (MIT) 治理框架启发

详细致谢见 **[ATTRIBUTION.md](./ATTRIBUTION.md)**。

---

## 贡献

欢迎任何形式的贡献：

- 🐛 **[报告 Bug](https://github.com/lybx-leyw/evergreen-main/issues)** / 💡 **[提交想法](https://github.com/lybx-leyw/evergreen-main/issues)**
- 📋 **[分享你的 Skill](https://github.com/lybx-leyw/evergreen-main/issues)** — 写个 `.md` 丢到 `.greenix/skills/`，AI 即刻加载
- 🔧 **[提交 PR](https://github.com/lybx-leyw/evergreen-main/pulls)** — 遵循 [CONTRIBUTING.md](./CONTRIBUTING.md)

详见 **[CONTRIBUTING.md](./CONTRIBUTING.md)**。

---

## AI Agent 贡献规约

本项目维护双轨贡献协议：

- **[CONTRIBUTING.md](./CONTRIBUTING.md)** — 架构、代码风格和开发规范。
- **[AGENT_CONTRIBUTING.md](./AGENT_CONTRIBUTING.md)** — AI Agent 专属治理。双模式：11 步 Skill（日常开发）+ 联邦 Fleet（全仓库重构）。违反本指南的 AI 生成 PR 将被拒绝。

我们认为，定义 AI 如何参与开源与用 AI 构建开源同等重要。

---

## 许可证

**GPL-3.0** — 详见 [LICENSE](./LICENSE)
