# Evergreen 2.0-alpha

**Flutter 桌面微工具平台 — 无账号、无服务端、本地优先、AI 原生**

一个以 JSON 声明式模块 + Python 可执行插件为双轨驱动的桌面工作台。核心是自管 6 个本地 HttpServer 的 Dart 服务层，所有模块通过统一声明注册、热插拔。

---

## 内置插件资产

> 2.0-alpha 预览版已集成 **12 个模块插件** + **15 个内置 Agent 工具**，覆盖 AI 对话、数据采集、学术研读、效率工具、创作定制全场景。

### AI 工具

| 插件 | 能力 |
|------|------|
| **AI 助手** `ai-assistant` | 全功能聊天界面：多级深度思考、联网搜索（Bing）、工具调用、多会话管理 |
| **Python 运行器** `python-runner` | Agent 可调用的本地 Python 3.10 环境：执行任意代码、pip 包管理、系统诊断 |
| **HTML 创作中心** `html-creator` | 三栏 IDE：数据中枢浏览 → HTML/CSS/JS 编辑 → 实时预览 → AI 辅助生成 → 一键导出 |

### 数据与采集

| 插件 | 能力 |
|------|------|
| **所见即所得爬虫** `scraper` | 内嵌浏览器抓包 → AI 自动生成 Python 爬虫 → 导出 `.py` / `.exe` |
| **数据中枢** `data-dashboard` | 数据源状态总览：连通性检测、新鲜度检查、一键拉取 |
| **浙大教务网数据源** `data-zdbk` | 浙大教务网对接，提供 9 种数据类型：课表、成绩、考试、培养方案…… |

### 效率工具

| 插件 | 能力 |
|------|------|
| **PDF 翻译** `pdf_translate` | DeepSeek API 驱动，中/英/日/韩/法/德/西 7 语言互译，双语对照 PDF 输出，多文件并行翻译 |
| **插件市场** `marketplace` | 插件全生命周期管理：浏览、搜索、安装、启用/停用、卸载 |
| **设置面板** `settings` | API Key、模型、主题等全局配置，附带 HTTP 设置页面 |
| **成绩 View** `view` | HTML 模板渲染的成绩查看器 |

### 创作定制

| 插件 | 能力 |
|------|------|
| **主题创作中心** `theme-creator` | 8 色语义色板可视化编辑 + Dart 实时预览 + AI 生成 + 一键导出主题插件 |
| **温馨学习** `warm_study` | 暖色调主题（#FAF3E7 背景 + 8 色语义色板） |

### Agent 工具体系

AI Agent 可调用 **15 个内置工具**，均通过 `function calling` 自动调度：

| 类别 | 工具 | 权限 |
|------|------|------|
| 文件操作 | `read_file` `write_file` `read_head` `read_tail` `file_info` `grep` | 写操作需确认 |
| 记忆管理 | `read_global_memory` `write_global_memory` | 写操作需确认 |
| 网络 | `web_search`（Bing 零 API Key） `web_fetch` | 只读 |
| 数据 | `data_query` `get_user_info` | 只读 |
| 技能 | `list_skills` `run_skill` | 只读 |
| 执行 | `python_runner`（本地 Python 解释器） | 需确认 |

### 截图一览

<table>
<tr>
<td align="center" width="50%"><b>AI 助手</b><br><img src="docs/features/ai-assistant.png" alt="AI 助手" width="100%"></td>
<td align="center" width="50%"><b>HTML 创作中心</b><br><img src="docs/features/html-creator.png" alt="HTML 创作中心" width="100%"></td>
</tr>
<tr>
<td align="center" width="50%"><b>爬虫生成器</b><br><img src="docs/features/scraper.png" alt="爬虫生成器" width="100%"></td>
<td align="center" width="50%"><b>数据中枢</b><br><img src="docs/features/data-dashboard.png" alt="数据中枢" width="100%"></td>
</tr>
<tr>
<td align="center" width="50%"><b>PDF 翻译</b><br><img src="docs/features/pdf-translate.png" alt="PDF 翻译" width="100%"></td>
<td align="center" width="50%"><b>插件市场</b><br><img src="docs/features/marketplace.png" alt="插件市场" width="100%"></td>
</tr>
<tr>
<td align="center" width="50%"><b>设置面板</b><br><img src="docs/features/settings.png" alt="设置面板" width="100%"></td>
<td align="center" width="50%"><b>主题创作中心</b><br><img src="docs/features/theme-creator.png" alt="主题创作中心" width="100%"></td>
</tr>
</table>

---

## 架构特性

- **双轨架构** — `PluginBridge`（Agent Tool 调 Python 插件）+ `ModuleLoader`（Flutter 模块插件），两种扩展方式解耦
- **声明式模块** — `ModuleDescriptor` JSON 注册 → `TemplateRegistry` 分派路由，未知字段静默忽略
- **多模板共存** — v4（通用 composite）、paper_reading（论文三栏）、html（内嵌渲染）、scraper（爬虫生成）、theme_creator（主题编辑）、zju（浙大校园）等 7 套模板
- **全流程插件系统** — 插件定义 → 打包 → 插件市场安装/卸载，完整闭环
- **本地优先** — 数据走 `.greenix/` 工作区文件系统 + SharedPreferences，零服务端依赖
- **三层架构** — `core/`（纯 Dart 服务层）→ `plugins/`（JSON 声明 + .exe）→ `renderer/`（纯 UI 渲染层），严格分层禁止跨层耦合
- **CI/CD 就绪** — `Test` 工作流（push/PR 快速验证）+ `Release` 工作流（tag v* 触发或手动构建发布）

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
├── .github/workflows/          GitHub Actions（test.yml + release.yml）
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
│   ├── plugins/                插件仓库（12 个内置插件）
│   │   ├── ai-assistant/       AI 助手
│   │   ├── data-dashboard/     数据看板
│   │   ├── data-zdbk/          浙大教务网数据源
│   │   ├── html-creator/       HTML 创作中心
│   │   ├── marketplace/        插件市场
│   │   ├── pdf_translate/      PDF 翻译
│   │   ├── python-runner/      Python 运行器
│   │   ├── scraper/            爬虫生成器
│   │   ├── settings/           设置面板
│   │   ├── theme-creator/      主题创建器
│   │   ├── view/               成绩 View
│   │   └── warm_study/         温馨学习主题
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

**Python 管线**: pdf2zh_next · pymupdf · Chaquopy（Android 端内嵌 Python 3.11）

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

## 创建新插件

只需一个 JSON 声明文件即可注册模块：

```jsonc
// plugins/<id>/module/manifest.json
{
  "id": "my-tool",
  "name": "My Tool",
  "version": "1.0.0",
  "template": "v4",
  "description": "...",
  "pages": [
    {
      "id": "main",
      "title": "主页",
      "layout": { "type": "composite", "slots": [...] }
    }
  ]
}
```

Python 脚本通过 `PluginBridge` 注册为 Agent 工具（本地子进程，JSON Lines 协议），或用 PyInstaller 打包为 `.exe` 供插件市场分发。

---

## CI / CD

### Test 工作流（`test.yml`）

`push` 到 `main` 或发起 `pull_request` 时自动触发，5-10 分钟出结果：

| Job | 说明 | 环境 |
|-----|------|------|
| 子包测试 | core 子模块 dart test | ubuntu-latest |
| Flutter 测试 | 根级 flutter test（含 widget 测试） | ubuntu-latest |

### Release 工作流（`release.yml`）

打 `v*` tag 或手动触发（`workflow_dispatch`），构建产物并创建 GitHub Release：

| Job | 说明 | 环境 |
|-----|------|------|
| 构建 Android APK | debug APK（Chaquopy Python 3.11） | ubuntu-latest |
| 构建 Windows | 桌面 debug 构建 → zip | windows-latest |
| 创建 Release | 自动生成 Release Notes + 附件上传 | ubuntu-latest |

> Alpha/Beta/RC 版本自动标记为 pre-release。
