# Super App — 微服务网格联动示例

> 一个插件同时提供 data source + page module + agent tool。
> 三种能力共享同一个 Python 后端，通过**端口文件**发现平台服务。

## 架构：插件如何与平台交互

```
  插件 data/plugin.py（独立进程）
    │
    ├─ 启动时读取 .core_port → 发现 Core 服务
    │   └─ GET /core/health、POST /core/ocr（转发 OCR 请求）
    │
    ├─ stdout 输出 PORT:xxxx → 平台 DataSourceLoader 发现
    │   └─ 注册到 DataOrchestrator
    │
    └─ 提供 /health、/data、/ocr 端点
         ↑
    agent/agent_bridge.py ── 读取 .data_port 发现数据源
         ↑
    PluginBridge 启动，传参 → agent_bridge 调用数据源 → stdout JSON
```

## 端口文件发现链

| 文件 | 谁写入 | 谁读取 |
|------|--------|--------|
| `.core_port` | CoreHttpServer（启动管线第 4 步） | plugin.py — 转发 OCR 请求 |
| `.data_port` | DataHttpServer（启动管线第 6 步） | agent_bridge.py — 发现数据源 |
| `.agent_port` | AgentHttpServer（启动管线第 8 步） | 任何需要调用 Agent 的插件 |
| `.config_port` | ConfigHttpServer（启动管线第 3 步） | 需要读写设置的插件 |
| `.module_port` | ModuleHttpServer（启动管线第 7 步） | 需要查询路由的插件 |
| `.theme_port` | ThemeHttpServer（启动管线第 10 步） | 需要查询配色的插件 |

## 目录结构

```
plugins/super_app/
  data/
    manifest.json          ← 数据源声明 (type=data-source)
    plugin.py              ← Python HTTP 后端（port=0 自动分配）
  module/
    manifest.json          ← 页面模块声明 (type=module, ui=default)
  agent/
    manifest.json          ← 工具声明 (PluginBridge, argMode=args)
    agent_bridge.py        ← 工具入口——读取 .data_port 发现数据源
```

## 运行

```bash
# 1. 启动 core 示例（自动启动 CoreHttpServer + 写入 .core_port）
cd ../../../
dart run example/example.dart
# → CoreHttpServer 已启动 → .core_port 写入

# 2. 选 4（数据交互）→ 自动启动 plugin.py → 端口发现 → HTTP 交互
# 3. 选 5（AI 工具调用）→ 自动启动 agent_bridge.py → 读取 .data_port
# 4. 选 15（微服务网格）→ 查看完整的 HTTP 调用流程

# 构建 .exe（可选）
cd example/plugins/super_app/data
pyinstaller --onefile plugin.py --distpath .
cd ../agent
pyinstaller --onefile agent_bridge.py --distpath .
```

## 联动关系

```
CoreHttpServer (:XXXX)
  ├── /core/health              → plugin.py 启动时检查
  ├── /core/ocr                 → plugin.py 转发 OCR 请求
  └── /core/plugins             → 查询已安装插件

DataHttpServer → .data_port
  └── agent_bridge.py 读取 → 构造数据源 URL

agent_bridge.py
  ├── 读取 .data_port  → http://127.0.0.1:XXXX/data
  ├── HTTP GET /data?sort=score&order=desc
  └── stdout → PluginBridge → Agent → 渲染层
```
