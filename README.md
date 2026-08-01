# Evergreen

**Flutter 桌面微工具平台 — 无账号、无服务端、本地优先、AI 原生**

一个以 JSON 声明式模块 + Python 可执行插件为双轨驱动的桌面工作台。核心是一个自管 6 个本地 HttpServer 的 Dart 服务层，所有模块（Agent、Config、Data、Module、Theme、Core）通过统一声明注册、热插拔。

---

## 特性

- **双轨架构** — `PluginBridge`（Agent Tool 调 Python 插件）+ `ModuleLoader`（Flutter 模块插件），两种扩展方式解耦
- **声明式模块** — `ModuleDescriptor` JSON 注册 → `TemplateRegistry` 分派路由，模板策略（v4 / classroom / paper_reading / zdbk）全部私有
- **AI Agent 引擎** — function calling / tool use / 多级深度思考 / SSE 流式 / web_search 内置（Bing 抓取，零 API key）
- **全流程插件创作** — 从插件定义 → PyInstaller 打包 → 插件市场安装/卸载，完整闭环
- **六层渲染管线** — V3 渲染器：取数原语 → 变换 → 布局 → 组件 → 页面 → 主题，严格分层，禁止跨层耦合
- **多模板共存** — 同一份 `ModuleDescriptor` 可路由到不同 UI 模板（v4 通用 / 课堂 / 论文阅读 / 知大百科）
- **本地优先** — 数据走 `.greenix/` 工作区文件系统 + SharedPreferences，无服务端依赖

## 快速开始

```bash
git clone <repo>
cd evg-base
flutter run -d windows   # 或 -d android / -d linux
```

首次使用请在 Settings 中填入 `DEEPSEEK_API_KEY`（DeepSeek 开放平台免费注册）。

## 项目结构

```
evg-base/
├── lib/core/                 纯 Dart 服务层（6 HttpServer）
│   ├── agent/                Agent Runtime — function calling / 工具注册 / 会话管理
│   ├── config/               配置读写封装（SharedPreferences）
│   ├── data/                 数据管道 — orchestrator / manifest / 插件热注册
│   ├── module/               ModuleDescriptor / ModuleLoader / ProcessManager
│   ├── theme/                ThemeDescriptor / ThemeLoader（5 层主题架构）
│   └── example/              示例模块（courses / data-dashboard / showcase-dart-chrome）
│
├── lib/renderer/             渲染层
│   ├── components/shared/    共享组件 — MarkdownRenderer / ChatView / 图表 / 代码高亮
│   └── templates/            模块模板
│       ├── v4_modle/         v4 通用模板（composite 布局 + AI 助手 + 卡片/表格/图表）
│       ├── classroom_modle/  课堂模板
│       ├── paper_reading_modle/  论文阅读模板（书架/星空/三栏终端）
│       └── zdbk_modle/       知大百科模板
│
├── scripts/                  Python 管线脚本
│   ├── paper_reader.py       PDF 提取 + pdf2zh_next 翻译（自定义 system prompt）
│   ├── paper_vision.py       OCR + 章节拆分 + 段落重排 + 翻译
│   └── verify_pipeline.py    管线验证
│
└── pubspec.yaml
```

## 模板对比

| 模板 | 适用场景 | 特点 |
|------|---------|------|
| **v4_modle** | 通用模块（数据看板/工具集） | composite 布局、卡片/表格/图表/代码、AI 助手抽屉、插件市场 |
| **classroom_modle** | 课堂教学 | 简化交互流 |
| **paper_reading_modle** | 学术论文研读 | 书架→星空→探索标签→三栏终端（原文/译文/草稿+AI答疑） |
| **zdbk_modle** | 知识库/百科 | 轻量自管 |

## 技术栈

Flutter 3.x · Dart 3.9 · Riverpod · go_router · Dio · flutter_markdown · flutter_math_fork · flutter_highlight · HtmlWidget · PyInstaller · pdf2zh_next · pymupdf · DeepSeek API

## 插件系统

```jsonc
// plugins/<id>/config/config.json — JSON 声明即可注册
{
  "id": "my-tool",
  "name": "My Tool",
  "version": "1.0.0",
  "template": "v4",        // 路由到 v4 通用模板
  "pages": [...],
  "actions": [...]
}
```

Python 可执行体通过 `PluginBridge` 被 Agent Tool 调用（本地子进程通信，JSON Lines 协议），或打包为 `.exe` 供插件市场安装。