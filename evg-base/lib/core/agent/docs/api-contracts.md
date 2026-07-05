# Agent API 接口契约（Sprint 1 冻结）

> 本文档为 Agent 模块全部对外接口的冻结契约，供渲染工程师和插件开发者引用。
> 接口签名冻结后，变更需通过正式的通讯流程通知消费方。

---

## I1. PluginBridge.discover()

**消费方：** Agent 内部  
**冻结日期：** Sprint 1

```dart
/// 同步扫描 plugins 目录，返回发现的全部 PluginTool。
///
/// 发现规则：
///   1. 遍历 pluginsDir 下每个子目录
///   2. 在子目录的 agent/ 子目录中查找 .exe（优先匹配与目录同名的）
///   3. 读取 agent/manifest.json → 解析为 PluginManifest
///   4. manifest.isValid（name 非空）→ 构造 PluginTool
static List<Tool> PluginBridge.discover(Directory pluginsDir)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `pluginsDir` | `Directory` | 插件根目录（通常为 `plugins/`） |
| 返回值 | `List<Tool>` | 发现的工具列表，空列表表示无有效插件 |

**目录规约：**
```
plugins/<name>/agent/<name>.exe    # 可执行文件
plugins/<name>/agent/manifest.json # 元数据（必写）
```

---

## I2. Tool.execute()

**消费方：** Agent 主循环  
**冻结日期：** Sprint 1

```dart
abstract class Tool {
  String get name;                // 蛇形命名，如 get_courses
  String get description;         // 供模型理解用途
  Map<String, dynamic> get schema;// JSON Schema 参数定义
  bool get readOnly;              // 默认 true（只读可并行）
  Future<String> execute(Map<String, dynamic> args); // 执行工具
}
```

| 方法 | 说明 |
|------|------|
| `execute(args)` | 接收模型生成的 JSON 参数 Map，返回结果文本。异常不应抛出——在内部 catch 并返回错误文本 |

**Schema 约定：**
```json
{
  "type": "object",
  "properties": {
    "param_name": { "type": "string", "description": "参数说明" }
  },
  "required": ["param_name"]
}
```

---

## I3. AgentEvent 流

**消费方：** 渲染工程师  
**冻结日期：** Sprint 1

```dart
Stream<AgentEvent> events  // Controller.events / StreamEventSink.stream
```

### EventKind 全集（17 种）

| # | EventKind | 关键 payload | 渲染行为 |
|---|-----------|-------------|---------|
| 1 | `turnStarted` | — | 重置渲染状态，显示加载指示器 |
| 2 | `reasoning` | `.reasoning` (String) | 思考过程面板，流式追加 |
| 3 | `text` | `.text` (String) | 主回答区域，逐 token 追加 |
| 4 | `message` | `.text`, `.reasoning` | 完整消息——可重渲染为 Markdown |
| 5 | `toolDispatch` | `.tool` (ToolEventPayload) | 显示工具调用卡片 |
| 6 | `toolResult` | `.tool` (含 output/error/truncated) | 更新工具卡片——成功/失败/截断 |
| 7 | `toolProgress` | `.tool` (含 output) | 长运行工具的中间输出 |
| 8 | `usage` | `.usage` (TokenUsage) | 用量/成本统计 |
| 9 | `notice` | `.text`, `.noticeLevel` | 带外通知横幅（info/warn） |
| 10 | `phase` | `.text` (label) | 阶段切换标签 |
| 11 | `approvalRequest` | `.approval` (ApprovalPayload) | 工具批准对话框——Agent 阻塞 |
| 12 | `askRequest` | `.askId`, `.askQuestions` | 多选提问组件 |
| 13 | `turnDone` | `.error` (String?) | 轮次结束——error 非 null = 失败 |
| 14 | `compactionStarted` | `.text` (trigger) | "压缩中..." 占位 |
| 15 | `compactionDone` | `.compaction` (CompactionPayload) | 压缩完成——摘要展示 |
| 16 | `retrying` | `.retry` (RetryPayload) | 重试状态指示 |
| 17 | `mcpSurfaceReady` | `.text` (server name) | 刷新可用工具列表 |

### Mock 流

```dart
// 开发用：无需真实 Agent 即可开发 UI
await for (final event in MockEventStream.generate()) { ... }
// 参考表：MockEventStream.eventKindReference
```

---

## I4. Controller.send()

**消费方：** 渲染 + 全局工程师  
**冻结日期：** Sprint 1

```dart
/// 发送用户消息并启动 Agent 运行。
///
/// [attachments] 可选附件上下文文本（OCR 处理结果），
/// 注入本轮 system prompt（单轮有效，run 结束后自动清空）。
void send(String input, {String? attachments})
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `input` | `String` | 用户输入文本（非空） |
| `attachments` | `String?` | OCR 或文件解析上下文，注入 system prompt |
| 副作用 | — | 启动 Agent 主循环，emit turnStarted 事件 |

**状态机：**
```
idle → send() → running → turnDone → idle
                   ↓ cancel()
                  idle
```

---

## I+. activateSkill / deactivateSkill

**消费方：** 渲染（ModuleDispatch）  
**冻结日期：** Sprint 1

```dart
/// 激活指定 Skill。其 body 注入 system prompt。
/// 返回 true 表示成功（skill 存在且已激活）。
bool activateSkill(String id)

/// 停用指定 Skill。其 body 从 system prompt 移除。
/// 返回 true 表示成功（skill 曾激活且已停用）。
bool deactivateSkill(String id)

/// 当前激活的 Skill ID 列表。
List<String> get activeSkillIds
```

---

## I++. AgentHttpServer

**消费方：** 插件 .exe  
**冻结日期：** Sprint 1  
**完整文档：** `docs/agent-http-api.md`

### 端口发现

启动时写入 `.agent_port` 文件（纯数字端口号）：

```dart
final port = int.parse(File('.agent_port').readAsStringSync());
final url = 'http://127.0.0.1:$port';
```

### 端点速查（24 端点）

| 类别 | 方法 + 路径 |
|------|------------|
| 健康 | `GET /health` |
| 对话 | `POST /agent/chat/stream` `POST /agent/chat` |
| 会话 | `GET/POST /agent/sessions` `GET/PUT/DELETE /agent/sessions/:id` `GET/POST /agent/sessions/:id/messages` `POST /agent/sessions/switch` |
| 工具 | `GET /agent/tools` `POST /agent/tools/toggle` |
| 控制 | `POST /agent/cancel` `/agent/approve` `/agent/reject` |
| 风格 | `GET/POST /agent/styles` |
| 记忆 | `GET/POST /agent/memory` `DELETE /agent/memory/:name` |
| 技能 | `GET /agent/skills` `POST /agent/skills/toggle` |
| 配置 | `GET /agent/config` |

---

## Skill 格式规范（Sprint 1 冻结）

**消费方：** 插件开发者  
**格式：** Markdown + YAML frontmatter

```markdown
---
name: my-skill
description: 一行描述，显示在索引中
mode: inline
allowed_tools: ["search", "read_file"]
---

# Skill Body（Markdown）

完整 skill 内容...
```

| Frontmatter 字段 | 必填 | 默认值 | 说明 |
|-----------------|------|--------|------|
| `name` | ✓ | — | 蛇形标识符 |
| `description` | ✓ | — | 一行摘要 |
| `mode` | | `inline` | `inline` 或 `subagent` |
| `allowed_tools` | | `[]` | subagent 模式下的工具白名单（空=继承全部） |

**扫描路径（S1 迁移后）：**
1. `plugins/<name>/skill/*.md`（新版——优先）
2. `.greenix/skills/`（旧版——兼容）
3. 内置 Skills（`BuiltinSkills`）

---

## Context Compaction 阈值（Sprint 1 冻结）

| 阈值 | 触发条件 | 行为 |
|------|---------|------|
| `softRatio` (0.5) | 上下文 > 窗口 50% | 首次触发 soft 压缩通知，后续静默 |
| `compactRatio` (0.8) | 上下文 > 窗口 80% | normal 压缩——AI 总结中间消息 |
| `forceRatio` (0.95) | 上下文 > 窗口 95% | emergency 压缩——紧急释放空间 |
| `recentKeep` (10) | — | 压缩后保留最近 N 条消息 |

**默认窗口：** 由 `AgentOptions.contextWindow` 指定（0 = 禁用压缩）。

---

## 降级路径（Sprint 2 冻结）

### AI 不可用

| HTTP 状态码 | 异常 | recoverable |
|------------|------|:--:|
| 401 | `AiUnavailableException.invalidApiKey()` | false |
| 402 | `AiUnavailableException.insufficientBalance()` | false |
| 429 | `AiUnavailableException.rateLimited()` | true |
| 500/502/503 | `AiUnavailableException.serverError()` | true |
| 其他 | `AiUnavailableException.fromStatusCode(code)` | code >= 500 |

### OCR 附件管线

```
用户选文件 → OcrAttachmentHandler.process(paths) → toContextString(results)
→ controller.send(text, attachments: context)
→ _buildSystemPrompt 注入 → Agent 基于 OCR 内容回答
```

---

## ScriptedAgentHttpServer（集成测试）

**消费方：** Core 工程师（集成测试场景 [3][4]）  
**冻结日期：** Sprint 2  
**源码：** `tools/scripted_agent_http_server.dart`

无需 AI Provider / API Key 的预编排 HTTP 服务器，纯 `dart run` 可启动。

```dart
final server = ScriptedAgentHttpServer(
  scenario: ScriptedAgentHttpServer.scenario3(), // 或 scenario4()
);
final port = await server.start();
// POST /agent/chat/stream → SSE 流输出预编排事件
server.stop();
```

| 预设 | SSE 事件 | 用途 |
|------|---------|------|
| `scenario3()` | turnStarted → toolDispatch(check_schedule) → toolResult → text → turnDone | Core §六 场景 3：单工具调用 |
| `scenario4()` | turnStarted → toolDispatch×2 → toolResult×2 → text → turnDone | Core §六 场景 4：跨模块调度 |

**可用端点：** `/health` `/agent/chat/stream` `/agent/chat` `/agent/sessions` `/agent/tools` `/agent/config` `/agent/styles` `/agent/skills` — 全部返回 `{"mode":"scripted"}`。

**共享序列化：** SSE 帧与 JSON Map 序列化逻辑提取至 `tools/event_serializers.dart`（`eventToSseFrame` / `eventToJsonMap`），`AgentHttpServer` 与 `ScriptedAgentHttpServer` 共享。

---

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.0 | 2026-07-03 | Sprint 1 接口冻结：I1–I++ 全部契约 |
| 1.1 | 2026-07-03 | Sprint 2 补充：AiUnavailable + OCR 管线 |
| 1.2 | 2026-07-03 | Sprint 2 补充：ScriptedAgentHttpServer + event_serializers 共享提取 |
