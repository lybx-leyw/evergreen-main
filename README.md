# Evergreen 2.0-alpha

**Flutter 桌面微工具平台 — 无账号、无服务端、本地优先、AI 原生**

一个以 JSON 声明式模块 + Python 可执行插件为双轨驱动的桌面工作台。核心是自管 6 个本地 HttpServer 的 Dart 服务层，所有模块通过统一声明注册、热插拔。

---

## 特性

- **双轨架构** — `PluginBridge`（Agent Tool 调 Python 插件）+ `ModuleLoader`（Flutter 模块插件），两种扩展方式解耦
- **声明式模块** — `ModuleDescriptor` JSON 注册 → `TemplateRegistry` 分派路由，未知字段静默忽略
- **AI Agent 引擎** — function calling / 多级深度思考 / SSE 流式 / web_search（Bing 抓取，零 API key）/ 多 Agent 协作视图
- **多模板共存** — 同一份 `ModuleDescriptor` 可路由到不同 UI 模板

| 模板 | 适用场景 | 特点 |
|------|---------|------|
| **v4_modle** | 通用模块 | composite 布局、卡片/表格/图表/代码、AI 助手抽屉、插件市场 |
| **paper_reading_modle** | 学术论文研读 | 书架 → 星空 → 三栏终端（原文/译文/草稿 + AI 答疑） |
| **html_modle** | HTML 内嵌渲染 | 内嵌 WebView 或 HTML 解析渲染 |
| **scraper_modle** | 爬虫生成器 | 可视化爬虫配置与数据抓取 |
| **theme_creator_modle** | 主题创建器 | 可视化编辑 + 热预览主题方案 |
| **zdbk_modle** | 知大百科 | 知识库浏览器 |
| **zju_modle** | ZJU 校园 | 浙大校园场景适配 |

- **全流程插件系统** — 插件定义 → PyInstaller 打包 → 插件市场安装/卸载，完整闭环
- **本地优先** — 数据走 `.greenix/` 工作区文件系统 + SharedPreferences，零服务端依赖
- **三层架构** — `core/`（纯 Dart 服务层）→ `plugins/`（JSON 声明 + .exe）→ `renderer/`（纯 UI 渲染层），严格分层禁止跨层耦合
- **CI/CD 就绪** — GitHub Actions 自动执行子包测试、Flutter 测试、Android APK 构建、Windows 桌面构建

---

## 快速开始

```bash
git clone https://github.com/lybx-leyw/evergreen-main.git
cd evg-base
flutter pub get
flutter run -d windows   # 或 -d android
```

首次使用请在 Settings 中填入 `DEEPSEEK_API_KEY`（DeepSeek 开放平台免费注册）。

---

## 项目结构

```
evergreen-main/
├── .github/workflows/ci.yml    GitHub Actions CI（子包测试 + Flutter 测试 + APK + Windows 构建）
├── evg-base/
│   ├── lib/
│   │   ├── main.dart           启动入口
│   │   ├── app.dart            MaterialApp.router
│   │   │
│   │   ├── core/               纯 Dart 服务层（6 个 HttpServer）
│   │   │   ├── agent/          Agent Runtime — function calling / 工具注册 / 会话管理
│   │   │   ├── config/         配置读写封装（SharedPreferences / HttpServer）
│   │   │   ├── data/           数据管道 — orchestrator / manifest / 插件热注册
│   │   │   ├── module/         ModuleDescriptor / ModuleLoader / ProcessManager
│   │   │   ├── theme/          ThemeDescriptor / ThemeLoader / ThemeStore
│   │   │   ├── services/       通用服务（OCR 管线 / PDF 翻译 / 插件安装器 / 更新）
│   │   │   ├── utils/          工具函数（文件 / 路径 / Python 环境 / token 估算）
│   │   │   ├── plugin/         插件运行器
│   │   │   └── feedback/       用户反馈收集
│   │   │
│   │   ├── renderer/           纯 UI 渲染层
│   │   │   ├── app/            应用壳（AppShell / CommandPalette / DebugErrorBar）
│   │   │   ├── atomic/         共享原子取数原语（data_source_resolver / json_path）
│   │   │   ├── components/     共享组件（MarkdownRenderer / ChatView / 图表 / 代码高亮）
│   │   │   ├── module/         模块调度（ModuleDispatch / ModulePage）
│   │   │   ├── multi_agent/    多 Agent 协作视图
│   │   │   ├── page/           页面视图（市场 / 设置 / 数据看板 / 文件查看器 / 全局记忆）
│   │   │   └── templates/      模块模板（v4 / paper_reading / html / scraper / theme_creator / zdbk / zju）
│   │   │
│   │   └── theme/              根级兼容性 stub
│   │
│   ├── plugins/                插件仓库（17 个内置插件）
│   │   ├── ai-assistant/       AI 助手
│   │   ├── data-dashboard/     数据看板
│   │   ├── data-zdbk/          知大百科数据源
│   │   ├── marketplace/        插件市场
│   │   ├── pdf_translate/      PDF 翻译
│   │   ├── python-runner/      Python 运行器
│   │   ├── scraper/            爬虫生成器
│   │   ├── settings/           设置面板
│   │   ├── theme-creator/      主题创建器
│   │   ├── warm_study/         温馨学习主题
│   │   └── liyu_weiyang_hongfen/ 丽语未央红粉主题
│   │
│   ├── scripts/                Python 管线脚本
│   │   ├── paper_reader.py     PDF 提取 + pdf2zh_next 翻译
│   │   ├── paper_vision.py     OCR + 章节拆分 + 段落重排 + 翻译
│   │   ├── pdf_translate.py    PDF 翻译管线
│   │   ├── pdf_to_images.py    PDF 转图片
│   │   ├── ocr_file.py         文件 OCR
│   │   └── ocr_slides.py       幻灯片 OCR
│   │
│   ├── assets/                 资产（plugins_bundle / video）
│   ├── android/                Android 平台（Chaquopy Python 3.11）
│   ├── windows/                Windows 平台（CMake / Win32）
│   └── pubspec.yaml
│
├── PRODUCT_DESIGN_DOCUMENT.md  产品设计文档
├── v5P渲染重构规划.md          v5 渲染重构规划
└── CLAUDE.md                   AI 协作入口
```

---

## 技术栈

**前端**: Flutter 3.x · Dart 3.9 · Riverpod · go_router · Dio · flutter_markdown · flutter_math_fork · flutter_highlight · flutter_mermaid · HtmlWidget · media_kit · xterm · re_editor · pdfx

**后端（本地）**: 6 个自管 HttpServer · JSON Lines 子进程协议

**AI**: DeepSeek API（Chat + FIM）· Bing 搜索引擎

**Python 管线**: PyInstaller · pdf2zh_next · pymupdf · Chaquopy（Android 端内嵌 Python 3.11）

---

## 架构

```
┌──────────────────────────────────────────────┐
│  renderer/    纯 UI 渲染层                    │
│  ├─ 模板系统（v4 / paper_reading / ...）       │
│  ├─ 共享组件（Markdown / Chat / 图表）         │
│  └─ 原子取数原语                              │
├──────────────────────────────────────────────┤
│  plugins/     JSON 声明式插件                  │
│  ├─ config.json 定义模块                      │
│  └─ .exe / .dart 可执行体                     │
├──────────────────────────────────────────────┤
│  core/        纯 Dart 服务层（禁止引用 Flutter）│
│  ├─ 6 HttpServer（Agent/Config/Data/...）     │
│  ├─ PluginBridge（Agent Tool ↔ 子进程）       │
│  └─ ModuleLoader（模块热插拔）                │
└──────────────────────────────────────────────┘
```

renderer 通过 Riverpod 从 core 取数据，不直调 HTTP；core 不引用任何 Flutter Widget。

---

## 插件系统

```jsonc
// plugins/<id>/config/config.json — JSON 声明即可注册
{
  "id": "my-tool",
  "name": "My Tool",
  "version": "1.0.0",
  "template": "v4",
  "pages": [
    {
      "id": "main",
      "title": "主页",
      "layout": { "type": "composite", "slots": [...] }
    }
  ],
  "actions": [
    { "id": "do-sth", "label": "执行", "exec": "tool.exe --input {data}" }
  ]
}
```

Python 可执行体通过 `PluginBridge` 被 Agent Tool 调用（本地子进程，JSON Lines 协议），或打包为 `.exe` 供插件市场安装。Agent 工具体系内置 12+ 工具（calculator、password-gen、uuid-gen、base64、unit-convert、json-format、qr-text 等）。

---

## CI

推送到 `main` 分支或发起 PR 时，GitHub Actions 自动运行：

| Job | 说明 | 环境 |
|-----|------|------|
| 子包测试 | core 6 个子模块 dart test | ubuntu-latest |
| Flutter 测试 | 根级 testWidgets + 集成测试 | ubuntu-latest |
| 构建 APK | Android debug APK（Chaquopy Python 3.11） | ubuntu-latest |
| 构建 Windows | Windows 桌面 debug 构建 | windows-latest |

APK 和 Windows 构建产物自动上传为 artifact。
