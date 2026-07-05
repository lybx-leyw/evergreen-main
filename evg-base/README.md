# Evergreen Base

Flutter 桌面应用平台底层——双轨架构（`core/` 声明 + `renderer/` 渲染）。提供模块系统、Agent 运行时、数据谱仪器、主题引擎、OCR 服务。外部插件放入 `plugins/` 目录即热加载，无需修改 base 源码。

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
│   │   ├── widgets/      原子渲染组件（AppShell / CommandPalette / MessageBubble …）
│   │   ├── shared/       组合视图 + 调度 + 主题解析 + 布局引擎
│   │   └── compositions/ 高级多视图叠加工作区
│   │
│   ├── theme/                        兼容性 stub → Breakpoints 常量
│   └── generated/                    兼容性 stub → re-export providers.dart
│
├── windows/                          Flutter Windows runner + CMake
├── scripts/                          Python OCR 脚本 + 嵌入式运行时 + Inno Setup
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

# 打包
flutter build windows --release
ISCC.exe scripts\installer.iss
```

## 插件接入

安装后在应用目录下创建 `plugins/` 空占位文件夹。用户将插件放入此目录，应用启动时自动热加载。

```
plugins/<name>/
  agent/manifest.json + .exe      ← PluginBridge（AI 工具）
  module/manifest.json            ← ModuleLoader（UI 模块）
  theme/theme.json                ← ThemeLoader（配色主题）
  data/manifest.json              ← DataSourceLoader（数据源）
  config/config.json              ← SettingsLoader（设置项）
```

一个插件可同时提供多种类型——各子目录互不冲突。

## 6 模块对外接口

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
