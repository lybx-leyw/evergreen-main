# Evergreen Base

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 见根 README.md |
| 日期 | 2026-08-25 |
| 负责人 | platform-owner |
| 适用 | 平台底层全仓 |

Flutter 桌面应用平台底层——双轨架构（`core/` 服务 + `renderer/` 渲染）。提供模块系统、Agent 运行时、数据谱仪器、主题引擎、OCR 服务。**用户侧插件创作以 HTML 为主**：用户通过 `html-creator` 自写 HTML/CSS/JS，平台提供实时预览、AI 辅助生成与一键导出；外部插件放入 `plugins/` 目录即热加载，无需修改 base 源码。

## 架构

```
evergreen-base/
├── lib/
│   ├── main.dart + app.dart          入口 + MaterialApp.router
│   ├── providers.dart                应用级 Riverpod 提供者（moduleRegistryProvider）
│   ├── evergreen_base.dart           对外 barrel
│   ├── README.md                     平台 API 参考
│   │
│   ├── core/                         上游——声明与引擎
│   │   ├── agent/        Agent 运行时 + Tool + Memory + Skill + Session
│   │   ├── config/       设置声明（SettingDecl / init / get / set）
│   │   ├── data/         数据谱仪器（DataOrchestrator / DataType / Cache）
│   │   ├── module/       模块声明（ModuleDescriptor / ModuleRegistry / ModuleLoader）
│   │   ├── theme/        主题声明（ThemeDescriptor / ThemeStore / ThemeLoader）
│   │   ├── services/     OCR 管线 + 更新服务
│   │   └── utils/        safe_parse / token_estimator / greenix_path / python_env
│   │
│   ├── renderer/                    下游——Flutter UI 渲染（只读 core/）
│   │   ├── app/          应用壳、主题服务、全局 Provider
│   │   ├── atomic/       原子取数原语
│   │   ├── components/   共享组件（widgets + shared）
│   │   ├── module/       模块调度（ModuleDispatch / ModulePage）
│   │   ├── multi_agent/  多 Agent 并行视图
│   │   ├── page/         页面视图（市场/设置/数据看板/文件/全局记忆）
│   │   └── templates/    模板路由（v4 / html / scraper / theme-creator / skill-creator / dsh / zju / paper_reading）
│   │
│   ├── theme/                        兼容性 stub → Breakpoints 常量
│   └── generated/                    兼容性 stub → re-export providers.dart
│
├── windows/                          Flutter Windows runner + CMake（含 media_kit 防复发保护）
├── scripts/                          Python 管线（OCR / PDF 翻译）+ 嵌入式运行时 + Inno Setup
├── android/                          Android 平台壳（Chaquopy Python 3.11，Gradle）
├── plugins/                          外部插件（安装后空占位，用户放入即热加载）
└── pubspec.yaml
```

## 快速开始

```bash
# 安装依赖
flutter pub get

# 准备 Python OCR 环境（仅首次）
scripts\setup_python.cmd

# 运行
flutter run -d windows

# 打包（完整流程见 scripts/README.md「构建 / 打包」）
flutter build windows --release --dart-define=EVERGREEN_ZJU=true --no-tree-shake-icons
ISCC.exe scripts\installer.iss "/DMyAppSuffix=-Zju" "/DMyBuildMode=Release"
# 双版：-Zju（浙大专用版）/ -Std（通用版）；输出 build\installer\EvergreenSetup{Zju|Std}-{Release|Debug}-<ver>.exe
```

## 插件接入

安装后在应用目录下创建 `plugins/` 空占位文件夹。用户将插件放入此目录，应用启动时自动热加载。

```
plugins/<name>/
  module/index.html               ← HTML 插件主文件（用户侧主路径）
  module/manifest.json            ← 模块声明（HTML 插件模板为 "template":"html"）
  agent/manifest.json + .exe      ← PluginBridge（AI 工具，开发者模式）
  theme/theme.json                ← ThemeLoader（配色主题）
  data/manifest.json              ← DataSourceLoader（数据源，开发者模式）
  config/config.json              ← SettingsLoader（设置项）
```

一个插件可同时提供多种类型——各子目录互不冲突。

## 模块对外接口

| 模块 | Barrel | 核心类 | 用途 |
|------|--------|--------|------|
| `core/agent/` | `agent.dart` | `AgentRuntime`, `ChatMessage`, `Tool`, `PluginBridge` | AI Agent 运行时 |
| `core/config/` | `config.dart` | `SettingDecl`, `initSettings`, `getSetting`, `setSetting` | 设置读写 |
| `core/data/` | `data.dart` | `DataOrchestrator`, `DataType<T>`, `DataSourceStatus` | 数据获取与缓存 |
| `core/module/` | `modules.dart` | `ModuleDescriptor`, `ModuleRegistry`, `ModuleLoader` | 模块声明与导航 |
| `core/theme/` | `theme.dart` | `ThemeDescriptor`, `ThemeStore` | 主题声明 |
| `core/services/` | `services.dart` | OCR 管线、更新服务 | 平台服务 |

## 文档

| 范围 | 文档 |
|------|------|
| 平台总览 + API 速查 | [lib/README.md](lib/README.md) |
| Core 全局规范 | [lib/core/CLAUDE.md](lib/core/CLAUDE.md) |
| Agent + 工具 | [lib/core/agent/README.md](lib/core/agent/README.md) |
| 设置与配置 | [lib/core/config/README.md](lib/core/config/README.md) |
| 数据谱仪器 | [lib/core/data/README.md](lib/core/data/README.md) |
| 模块系统 | [lib/core/module/README.md](lib/core/module/README.md) |
| 主题系统 | [lib/core/theme/README.md](lib/core/theme/README.md) |
| OCR 服务 | [lib/core/services/README.md](lib/core/services/README.md) |
| 渲染层 | [lib/renderer/CLAUDE.md](lib/renderer/CLAUDE.md) |
| Python 脚本 | [scripts/README.md](scripts/README.md) |

## 许可

GPL-3.0。详见 [LICENSE](LICENSE) 和 [ATTRIBUTION.md](ATTRIBUTION.md)。
