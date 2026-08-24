# CLAUDE.md — Evergreen 项目 AI 协作入口

> 本文档是整个仓库的 AI 协作总入口。子包级约定见各子目录 `CLAUDE.md` / `README.md`。
> 最后更新：2026-08-25

---

## 项目定位

Evergreen 是一个面向 AI4Life 的开源 AI 平台，当前版本为 **v2.0-rc 系列**（版本号以根 `README.md` 为准）。
核心形态是本地优先的 Flutter 桌面/移动应用，提供 AI 助手、数据采集、HTML 插件创作、主题创作、Skill 创作等能力。

**当前最重要的事实：用户侧插件创作已切换为 HTML 为主。**

- 用户自写 **HTML / CSS / JS**，平台提供 **HTML 创作中心**（`html-creator`）作为三栏 IDE。
- 创作中心提供实时预览、AI 辅助生成/改稿、一键导出。
- 导出物是 `plugins/<id>/module/index.html + manifest.json`，`manifest.json` 中 `"template":"html"`。
- 运行时由 `html_modle` 用 WebView 加载，并通过 `platform.*` JS Bridge 调用平台能力。
- Dart/JSON 模块声明、`.exe` 数据源/Agent 工具保留为 **开发者模式 / 高级能力**，不是普通用户创作入口。

---

## 仓库结构

```
evergreen-main/
├── README.md                     # 项目总览 / 快速开始 / 内置插件
├── CLAUDE.md                     # 本文件（AI 协作总入口）
├── AGENT.md                      # OWNER 职责书（仓库总工程师 root）
├── CONTRIBUTING.md               # 贡献协议（OWNER 分工 / 架构红线 / 提交规范）
├── docs/                         # 下载中心（index.html）+ 产品特性截图 + 设计文档（superpowers/specs）
├── evg-base/                     # Flutter 应用主体
│   ├── lib/
│   │   ├── main.dart / app.dart  # 启动入口 + MaterialApp.router
│   │   ├── providers.dart        # 应用级 Riverpod 提供者
│   │   ├── core/                 # 纯 Dart 服务层（禁止引用 Flutter Widget）
│   │   │   ├── agent/            #   Agent 运行时 / 工具 / 记忆 / Skill / 守护
│   │   │   ├── config/           #   设置 / 权限 / 插件源
│   │   │   ├── data/             #   数据谱仪器 / 数据源
│   │   │   ├── module/           #   模块描述符 / 注册表 / 加载器 / 进程
│   │   │   ├── theme/            #   扁平 8 色主题系统
│   │   │   ├── services/         #   OCR / 更新 / 插件安装 / Core HTTP
│   │   │   ├── utils/            #   安全解析 / Token / Python 环境 / 路径
│   │   │   ├── plugin/           #   插件运行器
│   │   │   └── feedback/         #   用户反馈
│   │   ├── renderer/             # Flutter UI 渲染层
│   │   │   ├── app/              #   应用壳 / 主题服务
│   │   │   ├── atomic/           #   原子取数原语
│   │   │   ├── components/       #   共享组件
│   │   │   ├── module/           #   ModuleDispatch / ModulePage
│   │   │   ├── multi_agent/      #   多 Agent 并行视图
│   │   │   ├── page/             #   页面视图
│   │   │   └── templates/        #   模板注册表（v4/html/scraper/theme-creator/skill-creator/dsh/zju/paper_reading）
│   │   ├── theme/                # 兼容性 stub
│   │   └── generated/            # 兼容性 stub
│   ├── plugins/                  # 内置插件仓库（完整清单见 evg-base/plugins/README.md）
│   ├── scripts/                  # Python 管线 / 打包脚本
│   ├── assets/                   # 插件 bundle / 媒体
│   ├── android/                  # Android 平台（Chaquopy Python）
│   └── windows/                  # Windows 平台（CMake / Inno Setup）
└── .reasonix/                    # 参考实现（非当前 Flutter 主应用）
```

---

## 核心架构

> 📐 交互式架构示意图：[`docs/evergreen-architecture.html`](docs/evergreen-architecture.html)（可缩放 / 聚焦 / 明暗主题）

```
core/（纯 Dart 服务层）
  ├── AgentHttpServer / ConfigHttpServer / DataHttpServer / ModuleHttpServer / ThemeHttpServer / CoreHttpServer
  ├── 端口文件：.agent_port / .config_port / .data_port / .module_port / .theme_port / .core_port
  └── 供 renderer 和 HTML 插件 bridge 使用

plugins/（HTML/JSON/.exe）
  ├── module/index.html + manifest.json   ← HTML 插件（用户侧主路径）
  ├── module/manifest.json + pages        ← JSON 模块（开发者模式）
  ├── agent/manifest.json + .exe          ← Agent 工具（开发者模式）
  ├── theme/theme.json                    ← 主题插件
  └── config/config.json                  ← 配置插件

renderer/（Flutter UI 渲染层）
  ├── ModuleDispatch 按 template/pages/workspace 自动选视图（不再使用 descriptor.ui）
  └── html_modle：本地 HTTP + WebView + JS Bridge 渲染 HTML 插件
```

### HTML 插件 JS Bridge 能力

| API | 说明 |
|------|------|
| `platform.data.get(name)` / `refresh(name)` / `subscribe(name, fn)` / `testConnectivity()` / `list()` | 数据中枢（`list()` 列出可用数据源） |
| `platform.ai.chat(prompt, style)` | AI 对话 |
| `platform.api.call(service, path, opts)` | 通用 core 服务转发（agent/config/data/module/theme/core） |
| `platform.settings.get(key)` / `set(key, value)` | 设置读写 |
| `platform.theme.getColors()` | 当前主题色板 |
| `platform.process.*`（run/start/write/stop/read/onOutput/onExit） | 常驻进程（manifest `process` 白名单 fail-closed，`scope:"long"` 常驻） |
| `platform.emit(event, payload)` / `platform.on(event, fn)` | 页级事件 |

HTML 页面自动获得 `--evg-*` CSS 变量（主题色），主题切换时实时更新。

---

## 模板（Modle）体系

模板注册表由 `evg-base/lib/renderer/templates/templates_index.json` + `tool/gen_template_registry.dart` 生成，支持按 release profile tree-shake。

| 模板名 | 渲染器 | 用途 |
|--------|--------|------|
| `v4` | `V4ModleTemplate` | 通用组件式模块 |
| `html` | `HtmlModleTemplate` | HTML 插件（用户侧主路径） |
| `scraper` | `ScraperTemplate` | 所见即所得爬虫 |
| `theme-creator` | `ThemeCreatorModleTemplate` | 主题创作中心 |
| `skill-creator` | `SkillCreatorModleTemplate` | Skill 创作中心 |
| `dsh` | `DshModleTemplate` | DeepSeek Harness |
| `paper_reading` | `PaperReadingModleTemplate` | 论文阅读 |
| `zju` / `classroom` / `zdbk` | `ZjuModleTemplate` | 浙大校园 |

---

## 开发约定

- **分层红线**：`core/` 不引用 Flutter Widget；`renderer/` 只消费 core 的 barrel 公共 API；`plugins/` 不反向依赖 renderer 内部实现。
- **HTML-first**：新增用户侧插件优先走 `html-creator` + `template:"html"`；不要要求普通用户写 Dart 或 JSON 组件树。
- **未知静默忽略**：所有解析器/渲染器对未知字段静默回退，不抛异常。
- **纯 Dart 子包可独立测试**：`evg-base/lib/core/*` 使用 stub 隔离外部 Flutter 依赖，`cd <subpackage> && dart test`。
- **模板扩展**：新增模板需在 `templates_index.json` 登记并重新生成 `template_registry.g.dart`，否则 AOT tree-shaker 无法裁剪。

---

## 常用命令

```bash
# 拉取依赖
cd evg-base
flutter pub get

# 运行
flutter run -d windows   # 或 -d android

# 测试
cd evg-base/lib/core/agent && dart test
cd evg-base/lib/core/config && dart test
cd evg-base/lib/core/data && dart test
cd evg-base/lib/core/module && dart test
cd evg-base/lib/core/theme && dart test
cd evg-base && flutter test

# 生成模板注册表
cd evg-base
dart tool/gen_template_registry.dart --profile release_full
```

---

## 文档地图

| 范围 | 文档 |
|------|------|
| OWNER 职责书 | `AGENT.md`（root §6 为全部 OWNER 索引） |
| 贡献协议 | `CONTRIBUTING.md` |
| 项目总览 | `README.md` |
| 下载中心 / 特性截图 | `docs/index.html` + `docs/features/*.png` |
| 设计文档 | `docs/superpowers/specs/*.md` |
| 平台底层 | `evg-base/README.md` |
| Lib 层 API | `evg-base/lib/README.md` |
| Core 总规范 | `evg-base/lib/core/CLAUDE.md` |
| Agent | `evg-base/lib/core/agent/CLAUDE.md` + `README.md` |
| Config | `evg-base/lib/core/config/CLAUDE.md` + `README.md` |
| Data | `evg-base/lib/core/data/CLAUDE.md` + `README.md` |
| Module | `evg-base/lib/core/module/CLAUDE.md` + `README.md` |
| Theme | `evg-base/lib/core/theme/CLAUDE.md` + `README.md` |
| Services / Utils | `evg-base/lib/core/services/README.md` / `evg-base/lib/core/utils/README.md` |
| Renderer | `evg-base/lib/renderer/CLAUDE.md` + `README.md` |
| 内置插件 | `evg-base/plugins/README.md` |
| Python 脚本 | `evg-base/scripts/README.md` |
| 插件上架协议 | `evg-base/docs/plugin-registry/plugin-registry-spec-v1.md` |
