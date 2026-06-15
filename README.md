# Evergreen Multi-Tools（内测版，暂时不做宣传推广）

> 这是将奥尔波特人格理论引入 AI 记忆的开源实践。  
> 是自研 Agent 运行时的浙大校园工具。  
> 更是 AI Agent 贡献规约的先行者。  
> **欢迎广大浙大学子共建共创。**

作者：绿意不息

作者：绿意不息

## Getting Started

```bash
cd evergreen-multi-tools
flutter pub get
flutter run -d windows
```

## 核心特色

- **🧠 奥尔波特特质理论记忆** — 独立的 MemoryAgent 每轮对话后分析用户特质，五层结构（首要特质 / 中心特质 / 次要特质 / 用户需求 / 关键事实），人类可随时查看编辑
- **📋 热加载 Skill 系统** — 丢 `.md` 到 `.greenix/skills/`，AI 即刻加载。支持 inline / subagent 双模式
- **🔍 两级 OCR** — DeepSeek-OCR 云端高精度 → Tesseract 本地自动降级。PDF 自动拆页逐页识别
- **🤖 自研 Agent 运行时** — Reasonix 的 Dart 复刻：compose → LLM → tool → loop → readiness，17 种类型化事件
- **📊 900+ 个自动化测试**

## 功能模块（15 个）

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
| WordPecker | FSRS 间隔重复背词 |
| Downloads | 课件下载管理 |
| Plan | 计划管理（多计划、大纲任务、周时间表涂色） |
| Settings | 配置管理 |

> ⚠️ 以下模块因后端 API 不可用等原因暂未启用：图书馆、一卡通、PTA 答题、自动签到、RVPN、智能调度

## OCR 依赖

两级 OCR：云端 DeepSeek-OCR（DashScope API）→ 本地 Tesseract 自动降级。

### 本地 OCR（必须）

1. 下载安装 [Tesseract OCR](https://github.com/UB-Mannheim/tesseract/wiki)，勾选 "Chinese Simplified" 语言包
2. `pip install -r scripts/requirements.txt`

### 云端 OCR（可选）

在设置页填入 DashScope API Key 并开通 `vanchin/deepseek-ocr` 模型。未配置时自动降级到本地 Tesseract。

## 构建

```bash
# Windows (包含 Python OCR 脚本 + 本地 Tesseract)
flutter build windows --release

# Android (可构建但未经测试，不支持 OCR)
flutter build apk --release
```

> ⚠️ Android 版本**未经测试**，且不支持 Python OCR 脚本。OCR 功能仅桌面端可用。

## 项目谱系

- **v1.0**（当前）— Dart/Flutter 桌面应用，15 个功能模块，自研 Agent 运行时
- Agent 运行时参考 [Reasonix](https://github.com/esengine/reasonix) (MIT)，Dart 独立重写
- 成绩计算 & 教务交互参考 [Celechron](https://github.com/Celechron/Celechron) (GPL-3.0)
- 教师评分数据来自 [Lazuli](https://github.com/ADSR1042/Lazuli) (GPL-3.0)
- WordPecker 背词引擎参考 [Qwerty Learner](https://github.com/RealKai42/qwerty-learner) (GPL-3.0)

详细致谢见 **[ATTRIBUTION.md](./ATTRIBUTION.md)**。

## 许可证

**GPL-3.0** — 详见 [LICENSE](./LICENSE)
