# Agent 运行时核心

> **示例 & 测试路径**
> - 平台开发者 → `example/example.dart`
> - 插件开发者 → `example/plugins/<name>/`（插件模板，含 manifest.json + plugin.py + README）
> - 源码 → `agent.dart` `tool.dart` `provider.dart` `agent_runtime.dart` `session_manager.dart` `agent/` `controller/` `memory/` `skill/` `compact/` `evidence/` `output_style/` `tools/` `test/` `docs/`
> - 接口契约 → `docs/api-contracts.md`（Sprint 1 冻结：I1–I++ 全部接口签名 + Skill 格式 + Compaction 阈值 + 降级路径）

---

## 平台 API（平台开发者）

### AgentRuntime

```dart
final runtime = ref.watch(agentRuntimeProvider);
runtime.controller.send('你好');
runtime.events.listen((e) { ... });
```

| 成员 | 类型 | 说明 |
|------|------|------|
| `agentRuntimeProvider` | `Provider<AgentRuntime>` | 全局唯一运行时 |
| `controller` | `Controller` | send / cancel / approve / reject |
| `session` | `Session` | 当前会话消息历史 |
| `events` | `Stream<AgentEvent>` | 事件流 |

### ChatMessage

```dart
final notifier = ref.read(chatMessagesProvider.notifier);
notifier.addUser('你好');
notifier.addAssistant('你好！');
notifier.addToolCall('search');
notifier.addToolResult('search', '3 条结果');
notifier.clear();
```

| 方法 | 说明 |
|------|------|
| `addUser(text)` | 入: `String` / 用户消息 |
| `addAssistant(text, {reasoning})` | 入: `String`, `String?` / AI 回复 |
| `updateLastAssistant(text)` | 入: `String` / 流式追加到最新消息 |
| `addToolCall(name)` | 入: `String` / 工具调用卡片 |
| `addToolResult(name, output)` | 入: `String`, `String` / 工具结果卡片 |
| `clear()` | 清空 |

### 开关

| Provider | 类型 | 默认 |
|------|------|------|
| `webSearchEnabledProvider` | `StateProvider<bool>` | `false` |
| `deepThinkingEnabledProvider` | `StateProvider<bool>` | `false` |

### Session

```dart
class MyStore implements SessionStoreInterface {
  Future<void> save(Session s) async { ... }
  Session? load(String id) { ... }
  Future<void> delete(String id) async { ... }
  List<Session> listAll() { ... }
}
sessionStoreProvider.overrideWith((ref) => MyStore());
```

| Provider | 说明 |
|------|------|
| `sessionListProvider` | 出: `AsyncValue<List<Session>>` / 会话列表 |
| `createSessionProvider(title?)` | 入: `String?` / 新建并切换 |
| `switchSessionProvider(id)` | 入: `String` / 切换（自动保存当前） |
| `saveCurrentSessionProvider(id)` | 入: `String` / 保存当前 |
| `deleteSessionProvider(id)` | 入: `String` / 删除 |
| `renameSessionProvider(id, title)` | 入: `String`, `String` / 重命名 |
| `activeSessionTitleProvider` | 出: `String` / 当前标题 |

### 文件 I/O 工具

Agent 内置文件读写与工作区访问能力。

```dart
// 工作区
final ws = WorkspaceTool('/path/to/workspace');
await ws.execute({'action': 'list'});
await ws.execute({'action': 'read', 'path': 'file.txt'});

// 读文件
final reader = ReadFileTool(maxSize: 100 * 1024);
await reader.execute({'path': '/path/to/file', 'offset': 0, 'limit': 50});

// 写文件（六种编辑操作）
final writer = WriteFileTool(workspaceDir: '/path/to/workspace');
await writer.execute({'action': 'write', 'path': 'a.txt', 'content': '...'});
await writer.execute({'action': 'append', 'path': 'a.txt', 'content': '...'});
await writer.execute({'action': 'insert', 'path': 'a.txt', 'start_line': 3, 'content': '...'});
await writer.execute({'action': 'replace_lines', 'path': 'a.txt', 'start_line': 1, 'end_line': 2, 'content': '...'});
await writer.execute({'action': 'delete_lines', 'path': 'a.txt', 'start_line': 5, 'end_line': 7});
await writer.execute({'action': 'replace_text', 'path': 'a.txt', 'old_text': 'foo', 'new_text': 'bar', 'regex': false});
```

| 工具 | name | 说明 |
|------|------|------|
| `WorkspaceTool(dir)` | `workspace` | 列出/读取工作区文件（对接 module/ WorkspaceDescriptor） |
| `ReadFileTool({maxSize})` | `read_file` | 读取磁盘文件，支持 offset/limit、二进制 hex dump |
| `WriteFileTool({workspaceDir, allowedDirs})` | `write_file` | 精准文件编辑：write / append / insert / replace_lines / delete_lines / replace_text |

### PluginBridge

| 方法 | 说明 |
|------|------|
| `PluginBridge.discover(pluginsDir)` | 入: `Directory` / 出: `List<Tool>` / 同步扫描 `plugins/` |
| `PluginBridge.registerAll(registry, pluginsDir)` | 入: `Registry`, `Directory` / 扫描并注册，跳过已注册 |
| `PluginBridge.refresh(registry, pluginsDir)` | 入: `Registry`, `Directory` / 重新扫描，同步增删 |
| `PluginManifest.fromJson(json)` | 入: `String` / 出: `PluginManifest` / JSON → 清单 |
| `ArgSpec.fromJson(map)` | 入: `Map?` / 出: `ArgSpec` / argSpec JSON → 规范 |
| `Registry.register(tool)` | 入: `Tool` / 注册工具，重复抛异常 |
| `Registry.remove(name)` | 入: `String` / 移除已注册工具 |

### Tool

| 方法 | 说明 |
|------|------|
| `Tool.name` | 出: `String` / 蛇形命名 |
| `Tool.description` | 出: `String` / Agent 据此判断是否调用 |
| `Tool.schema` | 出: `Map<String,dynamic>` / JSON Schema |
| `Tool.execute(args)` | 入: `Map<String,dynamic>` / 出: `Future<String>` / 执行工具 |
| `Tool.readOnly` | 出: `bool` / 默认 `true` |

### AgentEvent

```dart
runtime.events.listen((event) {
  switch (event.kind) {
    case EventKind.text:       /* event.text */    break;
    case EventKind.reasoning:  /* event.reasoning */ break;
    case EventKind.toolDispatch: /* event.tool */   break;
    case EventKind.toolResult:   /* event.tool */   break;
    case EventKind.turnDone:     /* 本轮结束 */      break;
  }
});
```

| 属性 | 类型 | 说明 |
|------|------|------|
| `kind` | `EventKind` | 事件类型 |
| `text` | `String?` | text / reasoning / notice / phase 的文本 |
| `reasoning` | `String?` | 思考过程 delta |
| `tool` | `ToolEventPayload?` | 工具调用/结果负载 |
| `usage` | `TokenUsage?` | token 用量 |
| `error` | `String?` | turnDone 时的错误 |

| EventKind | 说明 |
|------|------|
| `turnStarted` / `turnDone` | 对话开始 / 结束 |
| `reasoning` | 思考过程 delta（流式） |
| `text` | 回答文本 delta（流式） |
| `message` | 完整 assistant 消息 |
| `toolDispatch` | 工具调用即将执行 |
| `toolResult` | 工具调用执行完毕 |
| `usage` | token 用量统计 |
| `notice` | 带外通知（警告/压实通知） |

### ToolEventPayload

| 属性 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 调用 ID |
| `name` | `String` | 工具名 |
| `arguments` | `String` | raw JSON 参数 |
| `readOnly` | `bool` | 是否只读 |
| `output` | `String?` | toolResult 时的执行结果 |
| `error` | `String?` | toolResult 时的错误 |
| `truncated` | `bool` | 结果是否被截断 |

### TokenUsage

| 属性 | 类型 | 说明 |
|------|------|------|
| `promptTokens` | `int` | 输入 token 数 |
| `completionTokens` | `int` | 输出 token 数 |
| `totalTokens` | `int` | 总量 |
| `promptCacheHitTokens` | `int?` | 缓存命中 token 数 |
| `promptCacheMissTokens` | `int?` | 缓存未命中 token 数 |
| `cacheHitRatio` | `double?` | 前缀缓存命中率 |

### Message

| 属性 / 工厂 | 说明 |
|------|------|
| `Message.user(content)` | 入: `String` / 用户消息 |
| `Message.assistant(content, {reasoning})` | 入: `String`, `String?` / AI 回复 |
| `Message.assistantTool(calls)` | 入: `List<ToolCall>` / 工具调用 |
| `Message.toolResult(callId, content, {name})` | 入: `String`, `String`, `String?` / 工具结果 |
| `Message.system(content)` | 入: `String` / 系统消息 |
| `role` | `Role` (`user` / `assistant` / `tool` / `system`) |
| `content` | `String` |
| `reasoningContent` | `String` |
| `toolCalls` | `List<ToolCall>` |

### Session

| 属性 / 方法 | 说明 |
|------|------|
| `id` | `String` / 会话 ID |
| `title` | `String` / 标题 |
| `messages` | `List<Message>` / 完整消息历史 |
| `add(msg)` | 入: `Message` / 追加消息 |
| `lastUsage` | `TokenUsage?` / 最近一次用量 |
| `toJson()` / `fromJson(json)` | 序列化 / 反序列化 |

### Gate

| 类 | 说明 |
|------|------|
| `InteractiveGate({rules, pendingCallback})` | 交互式门控，高危工具触发批准回调 |
| `NoOpGate()` | 所有工具调用都允许 |
| `PermissionRule(toolName, level, reason)` | 入: `String`, `PermissionLevel`, `String?` / 规则 |

| PermissionLevel | 说明 |
|------|------|
| `always` | 总是允许 |
| `confirm` | 需要确认 |
| `approve` | 需要明确批准 |
| `deny` | 总是拒绝 |

### OutputStyle

| 方法 | 说明 |
|------|------|
| `StyleManager.setStyle(style)` | 入: `OutputStyle?` / 设置当前风格 |
| `StyleManager.setByName(name)` | 入: `String` / 出: `bool` / 按名称设置 |
| `StyleManager.applyTo(prompt)` | 入: `String` / 出: `String` / 注入 system prompt |

| BuiltinStyles | 说明 |
|------|------|
| `explanatory` | 解释型：边工作边解释 |
| `learning` | 学习型：协作模式，留 TODO |
| `concise` | 简洁型：最少的散文 |
| `socratic` | 苏格拉底式追问教学 |

### Controller（扩展 API）

| 方法 | 说明 |
|------|------|
| `controller.send(text, {attachments})` | 入: `String`, `String?` / 发送消息（可选附件 OCR 上下文） |
| `controller.activateSkill(id)` | 入: `String` / 出: `bool` / 激活 Skill |
| `controller.deactivateSkill(id)` | 入: `String` / 出: `bool` / 停用 Skill |
| `controller.activeSkillIds` | 出: `List<String>` / 当前激活的 Skill ID |

### AiUnavailableException

```dart
try {
  await provider.chat(messages: [...]).toList();
} on AiUnavailableException catch (e) {
  if (e.recoverable) {
    await Future.delayed(Duration(seconds: e.retryAfterSeconds ?? 5));
    // 重试...
  } else {
    showError(e.message);
  }
}
```

| 工厂 | 说明 |
|------|------|
| `connectionTimeout({detail})` | 网络超时，可恢复 |
| `invalidApiKey()` | API Key 无效，需人工 |
| `rateLimited({retryAfterSeconds})` | 频率限制，可恢复 |
| `serverError({statusCode})` | 服务器错误，可恢复 |
| `insufficientBalance()` | 余额不足，需人工 |
| `unsupportedModel(model)` | 模型不支持，可恢复 |
| `fromStatusCode(int, {body})` | 从 HTTP 状态码自动选择异常 |

### AgentHttpServer（24 端点）

> 完整 API 文档：`docs/agent-http-api.md`

| 类别 | 端点 |
|------|------|
| 健康 | `GET /health` |
| 对话 | `POST /agent/chat/stream` `POST /agent/chat` |
| 会话 | `GET/POST /agent/sessions` `GET/PUT/DELETE /agent/sessions/:id` `GET/POST /agent/sessions/:id/messages` `POST /agent/sessions/switch` |
| 工具 | `GET /agent/tools` `POST /agent/tools/toggle` |
| 控制 | `POST /agent/cancel` `/agent/approve` `/agent/reject` |
| 风格 | `GET/POST /agent/styles` |
| 记忆 | `GET/POST /agent/memory` `DELETE /agent/memory/:name` |
| 技能 | `GET /agent/skills` `POST /agent/skills/toggle` |
| 配置 | `GET /agent/config` |

### MockEventStream（渲染工程师）

```dart
await for (final event in MockEventStream.generate()) {
  switch (event.kind) {
    case EventKind.turnStarted:  /* ... */ break;
    case EventKind.reasoning:    /* ... */ break;
    case EventKind.text:         /* ... */ break;
    // ... 全部 17 种 EventKind
  }
}
```

| 方法 | 说明 |
|------|------|
| `MockEventStream.generate({delay})` | 出: `Stream<AgentEvent>` / 覆盖 17 种 EventKind 的模拟流 |
| `MockEventStream.eventKindReference` | 出: `List<Map>` / 全部 EventKind 的描述和 payload 参考表 |

### OcrAttachmentHandler

```dart
final handler = OcrAttachmentHandler(recognize: pipeline.recognizeFile, sink: eventSink);
final results = await handler.process(['/path/to/image.png']);
final ctx = handler.toContextString(results);
controller.send('分析这张图片', attachments: ctx);
```

| 方法 | 说明 |
|------|------|
| `process(filePaths)` | 入: `List<String>` / 出: `Future<List<OcrResult>>` / 批量 OCR |
| `toContextString(results)` | 入: `List<OcrResult>` / 出: `String` / 格式化为 context 注入文本 |

### ScriptedAgentHttpServer（集成测试）

预编排 HTTP 服务器，无需 AI Provider / API Key，纯 `dart run` 可启动。供 Core 层集成测试使用。

```dart
final server = ScriptedAgentHttpServer(
  scenario: ScriptedAgentHttpServer.scenario3(),
);
final port = await server.start();
// POST /agent/chat/stream → SSE 流输出预编排事件
server.stop();
```

| 成员 | 说明 |
|------|------|
| `ScriptedAgentHttpServer({scenario, registry, portFile})` | 构造——传入预编排事件列表 |
| `start()` | 出: `Future<int>` / 启动 HTTP 服务器，返回端口 |
| `stop()` | 停止服务器 |
| `scenario3()` | 出: `List<AgentEvent>` / 单工具调用预设（Core §六 场景 3） |
| `scenario4()` | 出: `List<AgentEvent>` / 跨模块双工具预设（Core §六 场景 4） |

### event_serializers（共享工具）

`AgentHttpServer` 和 `ScriptedAgentHttpServer` 共享的序列化逻辑。

| 函数 | 说明 |
|------|------|
| `eventToSseFrame(AgentEvent)` | 出: `String` / AgentEvent → SSE 帧 JSON |
| `eventToJsonMap(AgentEvent)` | 出: `Map<String,dynamic>` / AgentEvent → Map |

---

## 插件开发（插件开发者）

> **完整示例模板**：`example/plugins/time/`（Python + args + flag）、`example/plugins/date/`（Python + stdin）、`example/plugins/weather/`（Python + args + flag + 短 flag）、`example/plugins/random/`（C + args + flag），含 manifest.json + 源码 + README，复制改改就能用。

### 第一步：写一个可执行程序

插件是任意可执行文件，Agent 调用时启动进程，通过 stdin 或命令行参数接收 JSON，stdout 返回结果。

以 Python 为例，一个 stdin 模式插件：

```python
import sys, json

# 从 stdin 读取 Agent 传入的 JSON 参数
args = json.loads(sys.stdin.read())
query = args.get("query", "")

# 执行逻辑，结果写入 stdout
result = json.dumps({"results": [f"搜索 '{query}' 的结果..."]})
print(result)
```

### 第二步：写 manifest.json

```json
{
  "name": "search_docs",
  "description": "搜索内部文档库。",
  "schema": {
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "搜索关键词" }
    },
    "required": ["query"]
  },
  "readOnly": true,
  "argMode": "stdin"
}
```

| 字段 | 必填 | 默认 | 说明 |
|------|------|------|------|
| `name` | ✓ | — | 蛇形命名，全局唯一 |
| `description` | ✓ | — | Agent 据此判断何时调用 |
| `schema` | ✓ | — | JSON Schema，每个属性要有 `description` |
| `readOnly` | | `false` | 只读工具可并行 |
| `argMode` | | `"stdin"` | `"stdin"`（JSON → stdin）或 `"args"`（JSON → 命令行） |
| `argSpec` | | `{"style":"json"}` | args 模式命令行构造规范 |

### 第三步：配置 argSpec（argMode="args" 时）

| 字段 | 默认 | 说明 |
|------|------|------|
| `style` | `"json"` | `"flag"` → `--key value`；`"positional"` → 纯 value；`"json"` → `--args=<json>` |
| `prefix` | `"--"` | flag 前缀，可设 `"-"` 或 `"/"` |
| `flags` | `{}` | 按 key 覆盖 flag 名，如 `{"query":"-q"}` |
| `order` | schema 属性顺序 | positional 模式参数顺序 |

args + flag 示例：

```json
{
  "argMode": "args",
  "argSpec": { "style": "flag", "prefix": "--", "flags": { "query": "-q" } }
}
```

### 第四步：构建 .exe

| 语言 | 构建命令 |
|------|----------|
| Python | `pyinstaller --onefile plugin.py` |
| C | `gcc -o plugin.exe plugin.c` |
| Go | `go build -o plugin.exe .` |
| Rust | `cargo build --release`（产物在 `target/release/`） |
| C# | `dotnet publish -c Release -r win-x64` |

### 第五步：部署

```
plugins/
└── search_docs/
    └── agent/                     ← 按类型分目录
        ├── search_docs.exe         可执行文件
        └── manifest.json           元数据（必写）
```

### 通信协议

Agent 调用 `{"query":"hi","limit":5}` 时，各模式实际命令行：

| 模式 | 命令行 |
|------|------|
| stdin | `./search_docs.exe`（JSON 写入 stdin） |
| args + flag | `./search_docs.exe --query hi --limit 5` |
| args + positional | `./search_docs.exe hi 5` |
| args + json | `./search_docs.exe --args={"query":"hi","limit":5}` |

stdout 作为结果返回 Agent。stderr 附加尾部。非零退出码返回 `[plugin "<name>" exited with code N]`。

### 启动流程

平台启动时自动执行，插件开发者无需干预：

1. 扫描 `plugins/` 下所有子目录
2. 发现 `.exe` + `manifest.json` → 解析并构造 `PluginTool`
3. 注册到 `Registry`
4. Agent 调用时启动进程 → 传入参数 → 收集结果

## 规则

- `name` 全局唯一，重复抛异常。
- `schema` 每个属性要有 `description`。
- 只读工具可并行，写工具串行。
- 插件 = `plugins/<name>/agent/<name>.exe` + 必写 `manifest.json`。
- 使用 `agentRuntimeProvider`，不手动构造 Controller / Registry。

---

## 模块负责人代码质量自评

### 核心

| 文件 | 职责 | 行数 | 质量 | 说明 |
|------|------|------|------|------|
| `tool.dart` | Tool 接口 + Registry + BuiltinRegistry | ~170 | ★★★★ | 职责清晰，Registry 支持注册/启用/禁用/移除/调用 |
| `event.dart` | 类型化事件流 + EventSink | ~370 | ★★★★ | 17 种事件类型，载荷类型齐全 |
| `message.dart` | Message / ToolCall / ToolSchema | ~240 | ★★★★ | 完整 API 格式兼容，含 tool 配对修复 |
| `provider.dart` | Provider 接口 + DeepSeek 实现 | ~360 | ★★★ | 流式 + function calling + 自动重试。调试日志较多 |
| `agent/agent.dart` | Agent 主循环 | ~450 | ★★★★ | compose → LLM → tools → loop → readiness 完整流程 |
| `agent/session.dart` | Session 会话状态 | ~170 | ★★★★ | 消息历史 / token 统计 / JSON 序列化 |
| `agent/compose.dart` | 消息组合 + 系统提示词 | ~110 | ★★★ | 组合 session + system prompt + tools + memory |
| `agent/gate.dart` | 权限门控 | ~140 | ★★★★ | 四级权限 + 交互式批准回调 |
| `controller/controller.dart` | 会话驱动器 | ~300 | ★★★★ | 传输无关，支持 send / cancel / approve |

### 记忆

| 文件 | 职责 | 行数 | 质量 | 说明 |
|------|------|------|------|------|
| `memory/memory.dart` | Memory 系统 + MemoryStore | ~300 | ★★★★ | 文件系统记忆 + MEMORY.md 索引 |
| `memory/memory_agent.dart` | LLM 自动提取记忆 | ~310 | ★★★ | 奥尔波特特质理论，异步后台运行 |
| `memory/facade.dart` | 三 scope 统一入口 | ~65 | ★★★★ | Facade 模式，消费者无需感知后端 |
| `memory/router.dart` | scope → 后端路由 | ~30 | ★★★★ | 查表路由，无状态 |

### 插件系统

| 文件 | 职责 | 行数 | 质量 | 说明 |
|------|------|------|------|------|
| `tools/plugin_bridge.dart` | .exe 自动发现 + Tool 包装 | ~260 | ★★★★ | 三种 arg 风格，manifest 驱动 |
| `tools/workspace_tool.dart` | 工作区文件列出与读取 | ~110 | ★★★★ | 对接 module/ WorkspaceDescriptor |
| `tools/read_file.dart` | 磁盘文件读取 | ~100 | ★★★★ | offset/limit 分段、二进制 hex dump |
| `tools/write_file.dart` | 精准文件编辑 | ~200 | ★★★★ | 6 种操作、路径越界保护、白名单 |
| `skill/skill.dart` | Skill 加载/索引/内置 | ~250 | ★★★★ | inline + subagent 双模式 |

### 示例

| 文件 | 职责 | 质量 | 说明 |
|------|------|------|------|
| `example/example.dart` | 全部对外接口示例 | ★★★★ | 18 个 Demo（独立 `dart run` 可执行）：Tool / Schema 函数 / Registry / BuiltinRegistry / Previewer / PluginManifest / 插件发现与执行 / Message / Session / AgentEvent / OutputStyle / Gate / Flutter-Only API / 模拟对话 / 在线 DeepSeek API / 文件 I/O 与工作区 / AiUnavailableException / MockEventStream |
| `example/plugins/time/` | args + flag 示例（时间） | ★★★★ | 可选参数、默认值 |
| `example/plugins/date/` | stdin 示例（日期） | ★★★★ | 空输入容错、三种格式 |
| `example/plugins/weather/` | args + flag + 短 flag 示例 | ★★★★ | `flags` 映射、必填+可选参数 |
| `example/plugins/random/` | C 语言 + args + flag 示例 | ★★★★ | 纯 C99、手动 argv 解析、跨平台 |

### 测试

| 文件 | 用例 | 说明 |
|------|------|------|
| `test/tool_test.dart` | 25 | Tool 接口、Registry、BuiltinRegistry、Previewer |
| `test/registry_test.dart` | 14 | 跨插件调度、并行工具、边界条件 |
| `test/session_test.dart` | 19 | CRUD、token 统计、序列化往返（含 tool_calls + reasoning） |
| `test/memory_test.dart` | 24 | Memory 模型、InMemoryStore、FileMemoryStore、Router、MemoryFact |
| `test/plugin_bridge_test.dart` | 18 | PluginManifest 解析、ArgSpec、discover/registerAll/refresh |
| `test/provider_test.dart` | 26 | AiUnavailableException + MockEventStream + OcrAttachmentHandler |
| `test/compact_test.dart` | 13 | 20 轮长对话、Context Compaction、sanitizeToolPairing |
| `test/integration_test.dart` | 18 | 跨插件调度联调 (A-S3-3) + OCR E2E (A-S3-4) + StormBreaker + FinalReadiness |
| `test/scripted_server_test.dart` | 16 | ScriptedAgentHttpServer HTTP SSE 端点 + 场景 [3][4] |
| **合计** | **173** | `dart test` → All passed |

## 已知问题

| 问题 | 严重 | 状态 |
|------|------|------|
| `example/example.dart` 支持 `--api-key` 参数和环境变量 `DEEPSEEK_API_KEY` 进行在线 API 测试 | 低 | 在线 demo 需要网络 + 有效 key |
| `plugin_bridge.dart` 的 `refresh()` 移除已删除插件需依赖 `PluginTool` 类型判断 | 低 | 不影响功能，仅刷新场景涉及 |
