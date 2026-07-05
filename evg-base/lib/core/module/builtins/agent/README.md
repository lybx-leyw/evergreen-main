# Agent From — 插件版 AI 助手

> 从原 Agent 助手迁移而来的完整插件实现。Chat UI + 流式对话 + 工具调用 + 会话管理 + 记忆 + 权限门控 + Skill + 输出风格。
> **.exe 是薄代理**，将渲染器请求转发到 core/agent 内置 HTTP Server，不重复实现 LLM 逻辑。

## 架构

```
┌─────────────────────────────────────────────────────────┐
│  Flutter App (主进程)                                    │
│  ┌──────────────────────────────────────────────────┐   │
│  │  core/agent/                                      │   │
│  │  ├── DeepSeekProvider  →  DeepSeek API           │   │
│  │  ├── Controller        →  send/cancel/approve    │   │
│  │  ├── Session           →  消息历史 + token 统计   │   │
│  │  ├── Registry          →  工具注册/启用/禁用      │   │
│  │  ├── PluginBridge      →  自动发现 plugins/ .exe │   │
│  │  ├── InteractiveGate   →  高危工具需批准          │   │
│  │  ├── MemoryFacade      →  user/project/global    │   │
│  │  ├── MemoryAgent       →  特质自动提取           │   │
│  │  ├── SkillIndex        →  Skill 加载/索引        │   │
│  │  ├── StyleManager      →  4 种输出风格           │   │
│  │  └── AgentHttpServer   →  内部 HTTP API (NEW)    │   │
│  └──────────────────┬───────────────────────────────┘   │
│                     │ 127.0.0.1:{port}                    │
│                     │ 端口写入 .agent_port                │
└─────────────────────┼───────────────────────────────────┘
                      │
          ┌───────────▼───────────┐
          │  agent_bridge.exe     │  ← 薄代理 (Python)
          │  - 读取 .agent_port   │
          │  - 转发 HTTP 请求     │
          │  - 透传 SSE 流        │
          │  - /health 健康检查    │
          └───────────┬───────────┘
                      │ PORT:{n}
          ┌───────────▼───────────┐
          │  Renderer (Chat UI)   │
          │  manifest.json        │
          │  ui: "chat"           │
          └───────────────────────┘
```

## 目录结构

```
plugins/agent_from/
  module/
    manifest.json           ← Chat UI 页面声明
    agent_bridge.py         ← 薄代理源码
    agent_bridge.exe        ← 构建产物（pyinstaller）
  config/
    config.json             ← 设置项
  README.md                 ← 本文件
```

## 快速上手

### 1. 构建 .exe

```bash
cd module/
pip install pyinstaller
pyinstaller --onefile agent_bridge.py --distpath . --name agent_bridge
```

### 2. 启动 Flutter App（启动后自动暴露 Agent HTTP API）

```
Flutter App → AgentHttpServer 写入 .agent_port → agent_bridge.exe 读取 → 开始代理
```

### 3. 测试

```bash
# 直接调 Agent API
curl -N -X POST http://127.0.0.1:{agent_port}/agent/chat/stream \
  -H "Content-Type: application/json" \
  -d '{"input":"你好"}'

# 通过 bridge 代理
curl -N -X POST http://127.0.0.1:{bridge_port}/chat/stream \
  -H "Content-Type: application/json" \
  -d '{"input":"你好"}'
```

## API 端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/health` | GET | 健康检查 → agent 状态 + 工具数 |
| `/chat/stream` | POST | SSE 流式对话 `{"input":"..."}` |
| `/chat` | POST | 非流式对话 |
| `/sessions` | GET/POST | 列出/创建会话 |
| `/sessions/switch` | POST | 切换会话 `{"id":"..."}` |
| `/sessions/:id` | DELETE | 删除会话 |
| `/tools` | GET | 列出工具 |
| `/tools/toggle` | POST | 开关工具 `{"name":"web_search"}` |
| `/cancel` | POST | 取消当前对话 |
| `/approve` | POST | 批准高危操作 |
| `/reject` | POST | 拒绝高危操作 |
| `/output_styles` | GET/POST | 查看/设置输出风格 |
| `/config` | GET | 查看配置 |

## SSE 事件类型

| type | 说明 |
|------|------|
| `turn_started` | 轮次开始 |
| `turn_done` | 轮次结束，含 token 用量 |
| `reasoning` | 思考 delta（流式） |
| `text` | 回答 delta（流式） |
| `tool_dispatch` | 工具即将执行 |
| `tool_result` | 工具执行结果 |
| `approval_request` | 请求用户批准 |
| `notice` | 通知/警告 |
| `error` | 错误 |

## 关键文件

| 文件 | 位置 | 职责 |
|------|------|------|
| `agent_http_server.dart` | `lib/core/agent/tools/` | Agent 内部 HTTP API |
| `agent_bridge.py` | `plugins/agent_from/module/` | 薄代理 .exe |
| `manifest.json` | `plugins/agent_from/module/` | Chat UI 声明 |
| `config.json` | `plugins/agent_from/config/` | 设置项 |

## 与原版对比

| 能力 | 原 Agent 助手 | 插件版 agent_from |
|------|-------------|-------------------|
| 流式对话 | ✓ | ✓（透传 core/agent SSE） |
| 工具调用 | ✓ | ✓（透传 Registry） |
| 会话管理 | ✓ | ✓（CRUD + 切换） |
| 记忆系统 | ✓ | ✓（透传 MemoryFacade） |
| 权限门控 | ✓ | ✓（透传 Gate） |
| Skill 系统 | ✓ | ✓（透传 SkillIndex） |
| 输出风格 | ✓ | ✓（4 种 + 运行时切换） |
| 插件热加载 | — | ✓（PluginBridge） |
| 对话导出 | — | ✓（actions.exportable） |
| 工作区文件 | — | ✓（WorkspaceDescriptor） |
