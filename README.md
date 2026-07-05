# Evergreen Multi-Tools

Flutter 桌面微工具平台——无账号、无服务端、本地优先、AI 原生。

## 架构

```
plugins/                          ← 所有插件（Agent 工具 + 模块）
├── <name>/agent/manifest.json    → Agent Tool：命令行工具，AI 可调用
├── <name>/module/manifest.json   → Module：独立 HTTP 后端，完整 UI
└── <name>/config/config.json     → 设置声明
      /theme/theme.json           → 主题定义

evg-base/lib/
├── main.dart                     ← 启动入口，初始化所有 HttpServer + 模块
├── app.dart                      ← MaterialApp + go_router 路由
├── providers.dart                ← Riverpod 全局提供者
└── core/
    ├── agent/                    ← AI Agent 引擎（控制器/工具/记忆/技能）
    ├── config/                   ← 配置层（ConfigHttpServer + 设置/权限/源）
    ├── module/                   ← 模块系统（注册/加载/发现）
    └── theme/                    ← 主题引擎（ThemeHttpServer）
```

### 6 个内部 HttpServer

| Server | 端口发现文件 | 职责 |
|--------|-------------|------|
| ConfigHttpServer | `.config_port` | 设置/权限/插件源 CRUD |
| AgentHttpServer | `.agent_port` | AI 对话 SSE 代理 |
| ThemeHttpServer | `.theme_port` | 主题管理 |
| DataHttpServer | `.data_port` | 数据管线 |
| ModuleHttpServer | `.module_port` | 模块注册查询 |
| CoreHttpServer | `.core_port` | 核心服务 |

## 插件类型

### Agent Tool（命令行工具）

目录 `plugins/<name>/agent/`，通过 PluginBridge 注册为 AI 可调用工具。

```json
{
  "name": "calculator",
  "description": "四则运算",
  "schema": { "type": "object", "properties": { ... } },
  "argMode": "args",
  "argSpec": { "style": "flag", "prefix": "--" }
}
```

支持三种 argMode：`stdin`（JSON 写入）、`args`（flag/positional/json）。

### Module（独立 HTTP 模块）

目录 `plugins/<name>/module/`，每个模块启动独立 `.exe` HTTP 后端，Flutter 端通过 WebView 或 HTTP API 消费。

```json
{
  "type": "module",
  "id": "my-module",
  "route": "/my-module",
  "ui": "default",
  "process": { "exe": "module/my-module.exe", "protocol": "http" }
}
```

启动后打印 `PORT:<num>` → ModuleLoader 自动检测并注册。

## 已安装插件（21）

### 模块（5）

| 插件 | UI | 说明 |
|------|----|------|
| `ai-assistant` | `chat` | AI 对话（SSE 代理到 AgentHttpServer） |
| `settings` | `settings` | 设置面板（独立 HTML 渲染，动态拉取配置） |
| `pomodoro` | `default` | 番茄钟（HTTP 后端状态机） |
| `multi-agent` | `multichat` | 多智能体协作测试 |
| `python-runner` | — | Python 代码执行沙箱 |

### Agent 工具（15）

| 工具 | 说明 |
|------|------|
| `calculator` | 四则运算 + 幂/取余 |
| `password_gen` | 随机密码生成 |
| `uuid_gen` | UUID v1/v4 |
| `base64` | Base64 编解码 |
| `unit_convert` | 8 类单位换算 |
| `text_utils` | 大小写/反转/统计 |
| `json_format` | JSON 美化/压缩/校验 |
| `word_count` | 文本统计 + 词频 |
| `url_encode` | URL 编解码 |
| `color_convert` | HEX↔RGB↔HSL |
| `qr_text` | ASCII 二维码 |
| `mkdir` | 创建目录 |
| `web_search` | 网络搜索 |
| `write_file` | 写文件（沙箱内） |
| `read_global_memory` | 读全局记忆 |

### 主题（2）

`dark`、`light` — 语义 token 主题定义。

## 构建与运行

```bash
# 安装依赖
cd evg-base && flutter pub get

# 分析
flutter analyze

# 运行
flutter run -d windows

# 构建
flutter build windows
```

### 编译 Python 插件

```bash
pyinstaller --onefile --windowed plugins/<name>/module/settings.py
# 或
pyinstaller --onefile --console plugins/<name>/agent/plugin.py
```

### 环境

| 工具 | 路径 |
|------|------|
| Flutter SDK | `C:\flutter\` |
| PyInstaller | `D:\soft\Conda\Scripts\pyinstaller.exe` |
| Python | Conda / 嵌入式 `.greenix/python/` |

## 技术栈

- **框架**: Flutter 3.x + Dart
- **状态管理**: Riverpod
- **路由**: go_router
- **HTTP 后端**: Python 标准库 `http.server`（插件）+ Dart `dart:io` HttpServer（核心）
- **AI**: DeepSeek API（DeepSeekProvider）
- **沙箱**: 路径限定 `.greenix/workspaces/`，文件 I/O 不可逃逸
