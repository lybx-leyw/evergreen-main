# Agent HTTP API 参考

> 24 端点完整 API 文档，面向插件 .exe 开发者与平台集成工程师。

AgentHttpServer 在 `127.0.0.1` 随机端口启动，端口号写入 `.agent_port` 文件。

---

## 端点一览

### 健康检查

| # | 方法 | 路径 | 说明 |
|---|------|------|------|
| 1 | GET | `/health` | 健康检查 |

**响应 200:**
```json
{
  "status": "ok",
  "tools": 12,
  "sessions": 5,
  "provider": "deepseek-v4-flash"
}
```

---

### 对话

| # | 方法 | 路径 | 说明 |
|---|------|------|------|
| 2 | POST | `/agent/chat/stream` | 流式对话 (SSE) |
| 3 | POST | `/agent/chat` | 非流式对话 |

**`POST /agent/chat/stream`** — SSE 流式响应

请求：
```json
{
  "input": "帮我查北京天气",
  "style": "concise"
}
```

SSE 事件帧格式（`data: <json>\n\n`）：
```
data: {"type":"turn_started"}
data: {"type":"reasoning","text":"用户询问天气..."}
data: {"type":"text","text":"好的，我来帮你查。"}
data: {"type":"tool_dispatch","id":"c1","name":"weather","arguments":"{\"city\":\"北京\"}"}
data: {"type":"tool_result","id":"c1","name":"weather","output":"北京：晴 25°C"}
data: {"type":"turn_done","usage":{"total":350}}
```

**`POST /agent/chat`** — 非流式，返回完整事件数组

请求：
```json
{
  "input": "你好"
}
```

响应 200:
```json
{
  "events": [
    {"kind": "turnStarted", "text": null},
    {"kind": "text", "text": "你好！有什么可以帮你的？"},
    {"kind": "turnDone", "error": null}
  ]
}
```

---

### 会话管理

| # | 方法 | 路径 | 说明 |
|---|------|------|------|
| 4 | GET | `/agent/sessions` | 列出会话 |
| 5 | POST | `/agent/sessions` | 创建会话 |
| 6 | GET | `/agent/sessions/:id` | 获取单个会话 |
| 7 | PUT | `/agent/sessions/:id` | 更新/重命名会话 |
| 8 | POST | `/agent/sessions/:id/messages` | 追加消息 |
| 9 | GET | `/agent/sessions/:id/messages` | 获取消息历史 |
| 10 | POST | `/agent/sessions/switch` | 切换会话 |
| 11 | DELETE | `/agent/sessions/:id` | 删除会话 |

**GET /agent/sessions** — 响应 200:
```json
{
  "sessions": [
    {"id": "session_abc", "title": "北京天气查询", "messageCount": 8, "createdAt": "2026-07-02T10:00:00"}
  ]
}
```

**POST /agent/sessions** — 创建会话：
```json
{ "title": "新对话" }
```
响应 201:
```json
{ "id": "session_xyz", "title": "新对话", "messageCount": 0, "createdAt": "..." }
```

**GET /agent/sessions/:id** — 响应 200:
```json
{
  "id": "session_abc", "title": "北京天气",
  "messageCount": 8, "totalTokens": 1200,
  "createdAt": "...", "updatedAt": "..."
}
```

**PUT /agent/sessions/:id** — 重命名：
```json
{ "title": "新标题" }
```

**POST /agent/sessions/:id/messages** — 追加消息：
```json
{ "role": "user", "content": "追加的消息" }
```

**GET /agent/sessions/:id/messages** — 响应 200:
```json
{
  "messages": [
    {"role": "user", "content": "你好", "toolCalls": null},
    {"role": "assistant", "content": "你好！", "toolCalls": null}
  ],
  "count": 2
}
```

**POST /agent/sessions/switch** — 切换：
```json
{ "id": "session_abc" }
```

**DELETE /agent/sessions/:id** — 响应 200:
```json
{ "deleted": "session_abc" }
```

---

### 工具管理

| # | 方法 | 路径 | 说明 |
|---|------|------|------|
| 12 | GET | `/agent/tools` | 列出工具 |
| 13 | POST | `/agent/tools/toggle` | 启用/禁用工具 |

**GET /agent/tools** — 响应 200:
```json
{
  "tools": [
    {"name": "weather", "description": "查询天气", "readOnly": true},
    {"name": "time", "description": "获取时间", "readOnly": true}
  ]
}
```

**POST /agent/tools/toggle** — 启用/禁用：
```json
{ "name": "weather", "enable": false }
```

---

### 运行时控制

| # | 方法 | 路径 | 说明 |
|---|------|------|------|
| 14 | POST | `/agent/cancel` | 取消当前运行 |
| 15 | POST | `/agent/approve` | 批准工具调用 |
| 16 | POST | `/agent/reject` | 拒绝工具调用 |

响应格式: `{"cancelled": true}` / `{"approved": true}` / `{"rejected": true}`

---

### 输出风格

| # | 方法 | 路径 | 说明 |
|---|------|------|------|
| 17 | GET | `/agent/styles` | 列出输出风格 |
| 18 | POST | `/agent/styles` | 设置输出风格 |

**GET /agent/styles** — 响应 200:
```json
{
  "styles": [
    {"name": "explanatory", "label": "解释型"},
    {"name": "learning", "label": "学习型"},
    {"name": "concise", "label": "简洁型"},
    {"name": "socratic", "label": "苏格拉底式"}
  ]
}
```

**POST /agent/styles** — 设置风格：
```json
{ "style": "concise" }
```

---

### 配置

| # | 方法 | 路径 | 说明 |
|---|------|------|------|
| 19 | GET | `/agent/config` | 获取配置 |

响应 200:
```json
{ "provider": "deepseek-v4-flash", "toolsCount": 12 }
```

---

### 记忆管理

| # | 方法 | 路径 | 说明 |
|---|------|------|------|
| 20 | GET | `/agent/memory` | 列出记忆 |
| 21 | POST | `/agent/memory` | 保存记忆 |
| 22 | DELETE | `/agent/memory/:name` | 删除记忆 |

**GET /agent/memory** — 响应 200:
```json
{
  "memories": [
    {"name": "user-pref", "title": "User Pref", "description": "用户偏好简洁回复", "type": "user", "priority": "high"}
  ]
}
```

**POST /agent/memory** — 保存：
```json
{
  "name": "user-fact",
  "description": "用户主修计算机科学",
  "body": "用户是大三学生，主修计算机科学。",
  "type": "user",
  "priority": "medium"
}
```
响应 201: `{"saved": "user-fact"}`

**DELETE /agent/memory/:name** — 响应 200:
```json
{ "deleted": "user-fact" }
```

---

### 技能管理

| # | 方法 | 路径 | 说明 |
|---|------|------|------|
| 23 | GET | `/agent/skills` | 列出技能 |
| 24 | POST | `/agent/skills/toggle` | 激活/停用技能 |

**GET /agent/skills** — 响应 200:
```json
{
  "skills": [
    {"name": "acceptance", "description": "验收测试", "scope": "builtin", "runAs": "inline", "active": false}
  ],
  "activeIds": []
}
```

**POST /agent/skills/toggle** — 激活/停用：
```json
{ "name": "acceptance", "activate": true }
```
响应 200: `{"name": "acceptance", "activated": true, "success": true}`

---

## 通用规范

### CORS

所有端点自动附加 `Access-Control-Allow-Origin: *` 并处理 OPTIONS 预检。

### 错误响应

```json
{ "error": "描述信息" }
```

| 状态码 | 说明 |
|--------|------|
| 200 | 成功 |
| 201 | 创建成功 |
| 400 | 请求参数错误 |
| 404 | 资源不存在 / 路径未匹配 |
| 500 | 服务器内部错误 |

### 端口发现

启动时生成 `.agent_port` 文件：
```
C:\Users\...\.agent_port
```
内容为纯数字端口号（如 `54321`）。插件 .exe 可读取此文件获知端口。

---

## 集成测试模式

`ScriptedAgentHttpServer`（`tools/scripted_agent_http_server.dart`）提供无需 AI Provider 的预编排 HTTP 服务器，用于 Core 层集成测试。

```dart
final server = ScriptedAgentHttpServer(
  scenario: ScriptedAgentHttpServer.scenario3(),
);
final port = await server.start();
```

**与生产模式的区别：**
- 响应中 `mode` 字段为 `"scripted"`（生产为 `"ok"`）
- SSE 事件为预设序列，忽略请求 `input`
- 支持端点：`/health` `/agent/chat/stream` `/agent/chat` `/agent/sessions` `/agent/tools` `/agent/config` `/agent/styles` `/agent/skills`
- 不支持的端点返回 `{"mode":"scripted","available":false}`

**完整契约：** 参见 `docs/api-contracts.md` § ScriptedAgentHttpServer。
