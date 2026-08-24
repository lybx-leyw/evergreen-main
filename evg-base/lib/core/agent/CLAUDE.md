# CLAUDE.md — Agent 运行时模块

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 README.md 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-agent |
| 适用 | AI 协作者（agent 子包） |

> 本文件为 AI 协作入口，提供模块架构、设计决策、开发约定、测试策略和跨模块接口契约。
>
> **HTML-first 事实**：用户侧插件创作主路径是 HTML/JS。Agent 为 `html-creator` 提供 AI 辅助生成/改稿，
> 并为 HTML 插件暴露 `platform.ai.chat` JS Bridge；Agent 工具插件（`.exe`）仍是开发者模式能力。

---

## 模块架构概览

```
                      ┌─────────────────────────────┐
                      │     agent_runtime.dart       │
                      │  AgentRuntime + Providers    │
                      │  (全局组装：Provider/Registry │
                      │   /Controller/Skill/Memory)   │
                      └──────────┬──────────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              ▼                  ▼                   ▼
     ┌────────────┐    ┌─────────────┐    ┌──────────────┐
     │ Controller │◄───│   Agent     │◄───│  EventSink   │
     │ (send/     │    │  (主循环)    │    │  (事件流)     │
     │  cancel/   │    │  compose→   │    │  EventKind  │
     │  approve)  │    │  LLM→tools  │    └──────────────┘
     └────────────┘    │  →readiness │
                       └─────┬───────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                     ▼
  ┌──────────┐      ┌──────────────┐      ┌──────────────┐
  │ Provider │      │   Registry   │      │   Session    │
  │ (DeepSeek│      │  (Tool注册/   │      │  (消息历史/   │
  │  流式API)│      │   启用/调用)   │      │   token统计)  │
  └──────────┘      └──────────────┘      └──────────────┘

子系统（全部可选，按需注入）：

┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│  Memory  │ │  Skill   │ │ Compact  │ │ Evidence │ │  Style   │
│ (Facade  │ │ (Loader  │ │ (AI驱动  │ │ (Ledger  │ │ (Manager │
│  +Router │ │  +Index) │ │  上下文  │ │  审计)   │ │  风格)   │
│  +Agent) │ │          │ │  压实)   │ │          │ │          │
└──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘

┌──────────────────────────────────────────────────────────┐
│                   PluginBridge                            │
│  plugins/<name>/agent/{<name>.exe|<name>.py} + manifest   │
│  → 自动发现 → PluginTool → Registry.register()           │
└──────────────────────────────────────────────────────────┘
```

### 核心链路（一轮对话）

```
Controller.send(input)
  → Agent.run()
    → ⓪ Compactor.check()        [可选：上下文压实]
    → ① compose()                [构造 system prompt + 工具列表 + 记忆 + 会话历史]
    → ② Provider.chat()          [流式 LLM 调用 → reasoning/text/tool_calls 事件]
    → ③ 记录 assistant 消息到 Session
    → ④ 执行 tool_calls          [Gate 门控 → StormBreaker → ToolHooks → Registry.call()]
    → ⑤ FinalReadiness.check()   [工具调用后是否有可见回答？无则重试]
    → AgentEvent 通过 EventSink 发射
  → turnDone
```

---

## 目录结构

```
lib/core/agent/
├── agent.dart / agent_runtime.dart / agent_factory.dart    ← 入口 + 组装
├── tool.dart / event.dart / message.dart / provider.dart    ← 核心抽象
├── session_manager.dart / file_session_store.dart          ← 会话持久化
├── agent/          ← 主循环 (agent/session/compose/gate/hooks)
├── controller/     ← 状态机 (send/cancel/approve/reject)
├── memory/         ← 三 scope 记忆 (facade/router/agent + stores)
├── skill/          ← Skill 加载/索引/生成/改写 (skill_generator/skill_rewriter)
├── compact/        ← AI 上下文压实
├── evidence/       ← 审计收据与账本
├── output_style/   ← 输出风格
├── guardian/       ← Agent 守护策略（GuardianPolicy / GuardianReviewTool）
├── tools/          ← 内置工具（web/文件/记忆/skill/插件桥/ask/guardian/python/data_query/...）
├── docs/           ← api-contracts / agent-http-api / plugin-agent-tool / plugin-authoring-guide / migration
├── example/        ← Demo + 插件模板
├── test/           ← 测试（tool/registry/session/memory/plugin_bridge/provider/compact/integration/...）
└── lib/            ← stub 包 (dio/flutter/riverpod/shared_preferences/uuid) + core 辅助
```

---

## 核心设计决策

### 1. Agent 循环流程

```
for step in 0..maxSteps:
  ⓪ Context Compaction (仅首步)  → 压缩过长上下文
  ① Compose                     → system prompt + tools + session + memory
  ② LLM Call (流式)             → reasoning → content → tool_calls
  ③ Record Message              → assistant 消息写入 Session
  ④ Tool Execution              → 有 tool_calls → Gate → StormBreaker → execute → 回到①
  ⑤ Final Readiness             → 无 tool_calls → 检查是否有可见回答
```

**关键设计**：工具调用后继续循环（`continue`），直到 LLM 返回纯文本回答 → FinalReadiness 通过 → `break`。

### 2. 工具执行规则

- **只读工具可并行，写工具串行**：由 `Tool.readOnly` 决定
- **Registry 级别启用/禁用**：`enable(name)` / `disable(name)` 控制工具可用性
- **Gate 四级权限**：`always` > `confirm` > `approve` > `deny`
- **StormBreaker**：同一写工具连续失败 ≥3 次自动压制；成功则重置计数。只抑制失败循环，不抑制成功调用。

### 3. 四道安全网

| 安全网 | 位置 | 机制 |
|--------|------|------|
| **Gate** | Agent.run() ④ | 权限门控——按工具名 + 规则表决定 allow/deny/approve |
| **StormBreaker** | Agent.run() ④ | 风暴抑制——连续失败 ≥3 次自动压制，成功重置计数 |
| **Compactor** | Agent.run() ⓪ | 上下文压实——AI 驱动三级阈值 (soft/compact/force)，保留 head+tail+LLM 摘要 |
| **FinalReadiness** | Agent.run() ⑤ | 最终检查——工具调用后必须产生产生可见回答，否则重试 (max 3次) |

### 4. 组件隔离策略 (AgentFactory)

`AgentAssembly` 为每个 `ai-assistant` 配置的模块创建隔离的 Agent 实例：

| 组件 | 共享/隔离 | 原因 |
|------|---------|------|
| Provider (LLM API) | 共享 | 同一 API Key，复用连接 |
| Registry (工具) | 隔离 | 每模块 tool whitelist 不同 |
| Session | 隔离 | 不同模块对话历史独立 |
| MemoryFacade | 隔离 | 命名空间 `plugin:<name>/` |
| SkillIndex | 隔离 | 每模块激活 skill 不同 |
| Controller | 隔离 | 各自状态机 |
| Gate | 隔离 | 权限规则不同 |

### 5. Memory 三 Scope 架构

```
MemoryFacade (统一入口)
  └── MemoryRouter (scope → backend)
        ├── conversation → InMemoryStore (会话级，不持久)
        ├── feature      → InMemoryStore (模块隔离)
        └── global       → FileMemoryStore (持久化到 .greenix/memories/)
```

- **MemoryAgent**：后台异步运行，按奥尔波特特质理论提取用户特质（首要特质/中心特质/次要特质/关键事实）
- **Memory 不依赖 Skill，Skill 不依赖 Memory**——完全独立的子系统

### 6. PluginBridge 设计

- **扫描路径**：`plugins/<name>/agent/` → 找入口文件（`.exe` 或 `.py`，同名优先）+ `manifest.json`
- **执行抽象**：`PluginRunner`（桌面子进程 / 安卓 Chaquopy 进程内），`manifest.runtime` 决定解释器（`native` 默认直跑 `.exe`；`python` 用 Python 解释器跑 `.py`）
- **不管理进程生命周期**——只负责发现和注册到 Registry
- **三种 arg 风格**：`stdin` (JSON→stdin)、`args+flag` (`--key value`)、`args+positional` (按序传值)
- **manifest.json 必写**：name + description + schema + readOnly + argMode + argSpec + runtime

### 7. Guardian 守护策略

`guardian/guardian.dart` + `guardian/guardian_policy.dart` 提供 Agent 行为的规则守护；
`tools/guardian_review_tool.dart` 将守护审查暴露为 Agent 可调用工具，用于高风险操作前的人工/策略复核。

### 8. Skill 生成与改写

- `skill/skill_generator.dart`：AI 生成新 Skill 的管线
- `skill/skill_rewriter.dart`：按反馈/评审改写已有 Skill
- 供 `skill-creator` 创作中心使用，是 Agent 侧“技能生产”能力

### 9. AskTool 与 Hooks

- `tools/ask_tool.dart`：Agent 在运行中向用户提问/确认
- `agent/hooks.dart`：`ToolHooks` 扩展点（LoggingHooks / NoOpHooks / CompositeHooks），用于在工具执行前后注入横切逻辑

### 10. Stub 隔离

stub 包位于 `lib/` 下，隔离外部 Flutter 依赖：
- `dio_stub` — HTTP 客户端
- `flutter_stub` — Flutter Widget
- `flutter_riverpod_stub` — Riverpod 状态管理
- `shared_preferences_stub` — SharedPreferences
- `uuid_stub` — UUID 生成
- `core/` — 子包测试用辅助（log/python_env/plugin_runner 副本）

这使得 Agent 核心逻辑可在纯 Dart 环境测试，不依赖 Flutter Widget。

---

## 开发约定

### 新增 Tool

1. 创建类实现 `Tool` 接口：`name`（蛇形）、`description`、`schema`（JSON Schema）、`execute(args)`、`readOnly`
2. 在 `agent_runtime.dart` 的 `agentRuntimeProvider` 中 `registry.register(tool)`
3. 在 `tools/` 目录放置源码文件
4. 在 `agent.dart` barrel 中 `export`
5. 在 `test/tool_test.dart` 中添加测试

### 新增 Skill

1. 创建 Markdown 文件，带 YAML frontmatter：
   ```markdown
   ---
   name: my-skill
   description: 一行描述
   mode: inline
   allowed_tools: ["search", "read_file"]
   ---
   # Skill Body
   ```
2. 放置在 `plugins/<name>/skill/` 或 `.greenix/skills/`
3. 内置 skill 通过 `BuiltinSkills.register()` 注册

### 新增 Memory 策略

1. 实现 `IMemoryStore` 接口
2. 在 `MemoryRouter` 中注册新的 scope → backend 映射
3. 在 `MemoryFacade` 中暴露相应方法

### 新增 EventKind

1. 在 `event.dart` 的 `EventKind` 枚举中添加新值
2. 在 `AgentEvent` 中添加对应的工厂构造器和 payload 字段
3. 更新 `mock_event_stream.dart` 覆盖新事件
4. 更新 `docs/api-contracts.md` 中的 EventKind 表

---

## 测试策略

| 文件 | 覆盖 |
|------|------|
| `tool_test.dart` | Tool 接口、Registry、BuiltinRegistry、Previewer |
| `registry_test.dart` | 跨插件调度、并行工具、边界条件 |
| `session_test.dart` | Session CRUD、token 统计、序列化 |
| `memory_test.dart` | Memory 模型、InMemoryStore、FileMemoryStore、Router |
| `plugin_bridge_test.dart` | PluginManifest 解析、ArgSpec、discover/registerAll/refresh |
| `provider_test.dart` | AiUnavailableException、MockEventStream、OCR |
| `compact_test.dart` | Context Compaction、sanitizeToolPairing |
| `integration_test.dart` | 跨插件联调、OCR E2E、StormBreaker、FinalReadiness |
| `scripted_server_test.dart` | ScriptedAgentHttpServer HTTP SSE + 场景[3][4] |
| `hooks_test.dart` | ToolHooks / LoggingHooks / CompositeHooks |
| `ask_tool_test.dart` | AskTool 提问/确认 |
| `large_file_tools_test.dart` | 大文件读写/边界 |
| `skill_rewriter_test.dart` | Skill 改写管线 |
| `skill_loader_test.dart` | Skill 加载/索引/插件禁用状态 |

运行：
```bash
cd lib/core/agent && dart pub get && dart test
```

---

## 跨模块接口契约

### 与 Module 的 Skill name 约定

- Module 通过 `ModuleDescriptor.activateSkills` 声明要激活的 Skill 名称列表
- Agent 的 `Controller.activateSkill(id)` 按名称激活，将 body 注入 system prompt
- Skill name 是蛇形标识符（如 `acceptance`、`code-review`）
- Agent 不修改 Module 的 `activateSkills` 字段（角色边界）

### 与 Data/Config 的 HTTP 调用约定

- `AgentHttpServer` 在启动时写入 `.agent_port` 文件
- 插件 .exe 通过读取 `.agent_port` 发现端口号
- 通信协议：HTTP + JSON，支持 SSE 流式输出
- REST 端点覆盖：健康检查、对话、会话、工具、控制、风格、记忆、技能、配置（完整清单见 `docs/agent-http-api.md`）

### 与渲染层的接口

- **事件流**：`Stream<AgentEvent>` — EventKind 全集（见 `event.dart` 枚举），覆盖全生命周期
- **Mock 流**：`MockEventStream.generate()` — 渲染工程师不依赖真实 LLM 即可开发 UI
- **ChatMessage**：渲染层专用的消息模型，支持 `addUser/addAssistant/addToolCall/addToolResult/clear`
- **Controller**：`send(input, {attachments})` / `cancel()` / `approve()` / `reject()`
- **HTML 插件 JS Bridge**：`html_modle` 的 `platform.ai.chat(prompt, style)` 经 `AgentHttpServer`
  转发到 Agent 会话，是 HTML 插件获得 AI 能力的主通道。

---

_更新：2026-08-25（资产清点对齐：EventKind 全集、内置工具清单、测试文件清单、PluginBridge .py/runtime 支持、docs/ 新增插件指南与 migration；版本号以根 README.md 为准）_
