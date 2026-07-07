# Evergreen Base — AI 协作规范

> 这份文档教 AI 理解本项目的设计逻辑。它不是 API 参考（API 在 `lib/README.md`），不是实施计划（计划在 `PLAN.md`），而是**架构心智模型**——让 AI 在修改代码之前先理解"为什么长这样"。

---

## 一、项目是什么

**Evergreen** 是一个无账号、无服务端、本地优先、AI 原生的去中心化微工具集成平台。Flutter 桌面应用，目标用户是大学生。

插件开发门槛从"学 Flutter 全栈开发"降到了"写 JSON + 写 .exe"——manifest.json 声明页面形态，可执行脚本跑业务逻辑。任何能编译出可执行文件的语言都能写插件，不绑定特定技术栈。

更关键的是，这个模型对 AI 极度友好：逻辑足够简单、脚本语言 AI 足够擅长，用户用自然语言描述需求，AI 就能直接生成成品插件。这才是"AI 原生"的真正含义——不是 AI 辅助写代码，而是 AI 直接交付成品。

---

## 二、上中下游架构（最核心的心智模型）

```
上游 core/             中游 plugins/               下游 renderer/
═══════════          ════════════════            ══════════════════
纯 Dart 服务层        插件 = JSON + .exe            纯渲染层

提供原子能力：         决定页面形态：                按声明画 UI：
Agent 运行时           manifest.json 声明           ModuleDispatch 派发
Tool 注册               ui 范式/布局/slot            widgets/ 原子组件
Config 引擎             数据绑定/交互规则             shared/ 范式视图
Data 管线              .exe 跑业务逻辑               compositions/ 叠加
Module 注册中心         HTTP 调用上游服务
Theme 引擎
OCR 等通用服务
```

### 数据流向

```
上游 core/  ←──HTTP JSON 调用──  中游 plugins/  ──descriptor/Riverpod→  下游 renderer/
(提供服务)                       (JSON声明+.exe)                        (按声明渲染)
```

### 各层的"不"

| 层 | 不做什么 |
|----|---------|
| 上游 core/ | 不定义页面长什么样，不画像素 |
| 中游 plugins/ | 不写 Dart UI 代码，不直接操作渲染 |
| 下游 renderer/ | 不解析 manifest 管理进程，不写业务逻辑 |

### main.dart 的角色

横跨三层的**组装者**：启动上游 6 个 HTTP Server → 扫描中游插件目录 → 解析 manifest → 注册到 Registry → 启动 .exe 进程 → 注入 Riverpod → runApp。

### 下游的双渲染模式

下游 renderer 有两种渲染模式，由 manifest 的 `renderMode` 字段决定：

| 模式 | 引擎 | 能力 | 定位 |
|------|------|------|------|
| `dart`（默认） | Flutter Widget 树 | 完整功能 | 主渲染路径 |
| `html` | WebView 内嵌 HTML | 预览 | 受限预览 |

Dart 路径有一个 HTML 路径享受不到的优势：直接 `import core/`对一些特定范式进行封装——如Agent 运行时、Config 引擎、Module 描述符全部零序列化调用。这是 Dart 下游永远是最原生、最高效路径的原因。
但需要项目建设者需要注意，除非足够复杂或者足够整体，其他插件大概率不可能用到，否则尽量不设计封装的范式。

- **agent 快速通道**：提供 AI 助手封装组件，连接上下游。
  - `shared/chat_controller_view.dart`：主聊天 UI，直接 `import core/agent/agent.dart`、`agent_factory.dart`、`agent_runtime.dart`、`session_manager.dart`，通过 `AgentAssembly.fromConfig()` 实例化 Agent，消费完整 `AgentEvent` 流
  - `multi_agent/single_agent_column.dart`：多 Agent 并行列，直接 `import core/agent/agent.dart`、`agent_factory.dart`、`file_memory_store.dart`、`skill.dart`，每个列持有独立 `AgentAssembly` + `Controller`
  - `multi_agent/multi_agent_view.dart`：多 Agent 布局外壳
  - `shared/chat_view.dart`：轻量嵌入聊天视图（用于 composite 页面 `ai-assistant` 槽位）
  - `shared/global_memory_view.dart`：直接 `import core/agent/memory/memory.dart`，按特质分类展示记忆
  - `shared/skill_management_view.dart`：直接 `import core/agent/skill/skill.dart`，技能列表与管理
  - `widgets/chat_input_bar.dart`：直接 `import core/agent/agent_runtime.dart`，Web 搜索/推理级别切换
  - `widgets/session_list_bar.dart`：直接 `import core/agent/agent.dart` + `session_manager.dart`，会话选择器
- **data 快速通道**：数据源绑定，提供数据中枢封装。
  - `shared/data_dashboard_view.dart`：数据中枢面板，直接 `import core/data/data.dart`，调用 `DataOrchestrator.get()` / `.refresh()`，展示所有数据源状态
  - `widgets/freshness_badge.dart`：数据新鲜度徽章，直接 `import core/data/database.dart`，读取 `WebCacheDatabase` 缓存时间戳
  - `shared/composite_view.dart`：SlotDispatch 中 `'data-dashboard'` → `DataDashboardView`
- **config 快速通道**：提供设置页面封装。
  - `shared/settings_view.dart`：设置表单页，直接 `import core/config/settings.dart`，调用 `initSettings()` / `getAllSettings()` / `setSetting()`，按 `SettingType` 渲染对应控件
  - `shared/chat_controller_view.dart`：直接 `import core/config/config.dart`，调用 `getSetting(prefs, 'DEEPSEEK_API_KEY')` 读取 API Key
  - `shared/composite_view.dart`：SlotDispatch 中 `'settings'` → `SettingsView`

---

## 三、插件进程与数据管线

### 3.1 四级进程层级

.exe 与**组件**挂钩，不是与模块挂钩。一个模块的不同页面、不同栏目、不同事件可以各自触发独立的 .exe。

```
plugins/<name>/
  module/manifest.json
  │
  ├── process: [{exe, protocol}]                 ← ① 模块级：加载→卸载
  │
  ├── pages[]:
  │   └── globalProcess: {exe, protocol}        ← ② 页面级：激活→切走
  │       └── layout.slots:
  │           ├── left:
  │           │   └── process: {exe, protocol}  ← ③ 栏位/组件级：可见→隐藏
  │           └── right:
  │               └── process: {exe, protocol}  ← ③ 同上
  │
  └── actionButtons[]:
      └── process: {exe, protocol}              ← ④ 动作级：触发→完成即退出
```

| 层级 | manifest 路径 | 生命周期 |
|------|-------------|---------|
| ① 模块级 | `process[]` | 模块加载 → 卸载 |
| ② 页面级 | `pages[].globalProcess` | 页面激活 → 切走 |
| ③ 栏位/组件级 | `pages[].layout.slots.<key>.process` | 栏可见 → 隐藏 |
| ④ 动作级 | `actionButtons[].process` | 按钮触发 → 完成即退出 |

每个进程声明 `exe`（可执行文件路径）和 `protocol`（通信协议，目前统一为 `"http"`）。

### 3.2 标准 .exe 模式

所有层级的 .exe 遵循同一套契约——不限于 Python，任何语言遵守即可：

1. **启动**：`HTTPServer("127.0.0.1", 0)`，让 OS 分配随机端口
2. **发现**：`print(f"PORT:{port}", flush=True)` 作为 stdout 首行，core 捕获后得知端口
3. **通信**：后续全部走 HTTP JSON，支持 GET/POST
4. **生命周期**：core 管理进程启停，组件可见时启动、隐藏时终止

```
.exe 启动 → stdout 首行 "PORT:xxxx" → core 读取端口 → HTTP JSON 通信 → 进程终止
```

任何语言只要能起 HTTP Server + 打印端口号，就能写插件。Python `stdlib` 即可胜任，零依赖。

模块级 .exe 通常还承担**聚合代理**的角色——它通过读 `.agent_port`、`.data_port` 等端口文件发现上游 core 服务，转发/聚合数据请求，充当整个模块的 API 中枢。

### 3.3 dataSource 数据绑定

除进程外，页面和组件还可以声明**数据源**——这是与进程生命周期解耦的定时拉取管线：

```json
"dataSource": {
  "endpoint": "/api/lottery/draw",
  "refreshInterval": 15,
  "dataPath": "history",
  "transform": "rarityToPie"
}
```

| 字段 | 作用 |
|------|------|
| `endpoint` | 请求路径（相对于模块进程 HTTP 端口，或 core 服务） |
| `refreshInterval` | 自动刷新间隔（秒），0 表示不自动刷新 |
| `dataPath` | 从响应 JSON 中提取数据的路径 |
| `transform` | 数据变形函数名（前端注册的纯函数） |

dataSource 可在页面级声明（整页共享数据），也可在组件级声明（单组件独立数据源）。renderer 按声明定时拉取，组件只需接收数据——不关心数据从哪来、怎么刷新。

---

## 四、核心设计决策与理由

### 4.1 为什么是 JSON 声明 + HTTP 通信？

**JSON 声明**：插件开发者不写 UI 代码，只声明"我要什么范式、什么布局、绑什么数据"。manifest.json 描述页面形态，renderer 按声明渲染。这让插件根本不需要碰 Dart 代码。

**HTTP 通信**：任何语言都有 HTTP 库。Python `stdlib`、Go `net/http`、Node.js `http` 模块——零依赖即可参与。`.exe` 启动 `HTTPServer("127.0.0.1", 0)`，把端口号通过 stdout 首行 `PORT:xxxx` 上报，core 捕获后走 HTTP JSON 通信。契约只有两条：打印端口 + 提供 `/health`。

**端口发现文件**（`.agent_port`、`.config_port`、`.core_port`、`.data_port`、`.module_port`、`.theme_port`）：core 启动 6 个独立微服务，每个绑定 `127.0.0.1:0`，将实际端口写入对应文件。插件 .exe 读取这些文件即可发现所有上游服务——**文件系统即注册中心**，不需要 consul/etcd/环境变量。

**PluginBridge**：agent 维度的 .exe 还支持三种参数模式——`stdin`（JSON 管道传入）、`flag`（`--key value`）、`positional`（按序传值），适应不同语言的命令行习惯。

### 4.2 为什么 core/ 和 renderer/ 分离？

- **可替换渲染层**：core/ 是平台无关的服务引擎，renderer/ 是 Flutter Desktop 实现。未来可以有 Web 版 renderer，core/ 保持不变。
- **职责分离 + 安全边界**：渲染层只能读 core/ 的公开 API。防止 UI 代码侵入业务逻辑，防止声明逻辑散落进像素代码。
- **renderer/ 的三层结构**：`widgets/`（原子组件，无业务逻辑）→ `shared/`（范式视图 + 调度 + 布局）→ `compositions/`（多视图叠加）。

### 4.3 为什么是 register → seal 模式？

`ModuleRegistry` 的三段生命周期，由 `_sealed` 布尔门在运行时强制执行：

| 阶段 | 操作 | 门控 |
|------|------|------|
| 注册期 | `register()`、`registerAll()`、`setCapabilities()` | 写开放，读禁止 |
| 密封 | `seal()` 设置 `_sealed = true`，校验依赖完整性 | 一次性操作 |
| 查询期 | `findById()`、`findByRoute()`、`navGroups`、`search()` 等 | 读开放，写禁止 |

密封时自动运行 `_validateDependencies()`——任何模块声明了不存在的依赖 ID 都会导致 `StateError`，启动即失败而非运行时静默异常。模块列表通过 `List.unmodifiable()` 返回，外部不可篡改。

完整加载管线：

```
manifest.json → ModuleDescriptor.fromJson() → registry.register()
→ scanAndLoadModules() 启动所有 .exe 进程
→ discoverCapabilities() → registry.setCapabilities()
→ registry.seal()
→ ModuleHttpServer 启动（仅在 seal 后）
→ GoRouter 路由表、侧边栏导航、命令面板条目全自动生成
```

### 4.4 composite 模式：声明式 UI 的现状

V2 composite 模式已是当前工作系统。V1 的 `descriptor.ui` 字段已删除，改为按模块内容自动选择视图：

```dart
if (renderMode == 'html') → HtmlRenderView       // WebView 预览
else if (pages 非空)       → CompositeView        // 多页 Tab + Slot 调度
else if (workspace 启用)   → EditorView           // 代码/文本编辑器
else                       → DefaultView          // 兜底，不崩溃
```

**CompositeView 内部**：`TabBar + TabBarView` → 每页独立 `ProcessManager` + `PageEventBus` → `LayoutEngine` 包装（drawers → search → zoom → grid）→ 5 种布局范式分发：

| 布局类型 | 行为 |
|---------|------|
| `grid` | 多列网格，`preset.columns`（1-12）+ `preset.gap` |
| `flex` | Row/Column/Wrap，`preset.direction` + `preset.justify` |
| `fullscreen` | 单 slot 填满 |
| `absolute` | `Stack` + `Positioned` 绝对定位 |
| `dock` | top/bottom/left/right/center 停靠 |

**SlotDispatch**：35+ 组件类型按 `ComponentDescriptor.type` 分发——chat、code-editor、data-table、chart、document、spreadsheet、presentation、video、map、calendar、lottery-wheel、form、type-check、flashcards、quiz、mindmap 等。已知组件直接渲染，未知类型回退到 `_UnknownSlot`（不崩溃）。

**PageEventBus**：每页独立的事件总线，slot 间通过 `slot:toggle:<key>` 和 `slot:switch_page:<pageId>` 通信，无需 Dart 代码介入。

### 4.5 Agent 的设计哲学

Agent 主循环（`lib/core/agent/agent/agent.dart`）是平台无关的纯 Dart 引擎。每轮对话：

```
Controller.send(input)
  ├── 自动读取全局记忆 → Session
  └── Agent.run()
        ├── ⓪ Compactor.check()          ← 上下文压实
        ├── ① compose()                  ← 拼装 system prompt + 工具 schema + 记忆 + Skill
        ├── ② Provider.chat() 流式       ← DeepSeek API (SSE)
        ├── ③ 记录 assistant 消息 → Session
        ├── ④ Tool Execution             ← Gate → StormBreaker → pre-hook → call → post-hook
        │     └── 有工具调用 → continue 循环
        └── ⑤ FinalReadiness.check()     ← 有工具但无文本回答 → 重试 (最多 3 次)
              └── 通过 → 产出最终回答
事后：MemoryAgent 自动提取用户特质 → 写入文件
```

**Skill**：Markdown 文件即技能包。两种运行模式——`inline`（注入 system prompt，AI 当场阅读）和 `subagent`（生成隔离的 Agent 实例，继承工具注册表独立执行）。`SkillGenerator` 支持自然语言生成 Skill。不会写代码的人也能贡献。

**Memory**：三作用域架构——`conversation`（单次对话，内存）→ `feature`（模块隔离，内存）→ `global`（跨会话持久化，文件系统）。`MemoryAgent` 基于奥尔波特特质理论，每轮对话后自动提取用户特质。Agent 通过 `read_global_memory` / `write_global_memory` Tool 主动读写记忆。

**Tool**：模型可调用的能力。内置 8 个工具（读写文件、读写记忆、运行 Skill、搜索等）。`PluginBridge` 扫描 `plugins/<name>/agent/` 目录注册外部 .exe 工具。读写工具串行，只读工具可并行。`AgentFactory` 支持工具白名单（`all`/`specific`/`none`），每个 Agent 实例可有独立的工具集。

**四道安全网**：

| 安全网 | 机制 | 行为 |
|--------|------|------|
| **Gate** | 权限分层（`always > confirm > approve > deny`） | 每次工具调用前检查，可通配符匹配 |
| **StormBreaker** | 写工具连续重复调用计数 | 同一错误签名 ≥3 次自动压制 |
| **FinalReadiness** | 有工具调用但无可见回答 | 强制重试，最多 3 次 |
| **Compactor** | 三级阈值（soft/compact/force） | AI 驱动的上下文压实，保留 head + tail + LLM 摘要 |

---

## 五、关键数据结构心智模型

### ModuleDescriptor 链路

```
manifest.json → ModuleDescriptor.fromJson() → ModuleRegistry.register()
                                                   ↓
                              GoRouter 路由表自动生成
                              侧边栏导航自动生成
                              命令面板条目自动生成
                              ModuleDispatch 按 pages/workspace 自动选择视图
```

- `ModuleDescriptor` 是 const + 不可变的。渲染层收到的永远是已经 seal 的描述符。
- V1 的 `descriptor.ui` 字段已删除。V2 改为按模块内容（pages/workspace/renderMode）自动调度视图。
- 未知字段**静默忽略**——不抛异常，不回退到错误页。这是容错设计，不是 bug。

### 六维插件模型

一个插件目录可同时包含多种类型，各子目录互不冲突：

| 子目录 | 包含 | 被谁加载 |
|--------|------|---------|
| `agent/` | manifest.json + .exe | PluginBridge → toolRegistry |
| `module/` | manifest.json | ModuleLoader → ModuleRegistry |
| `theme/` | theme.json | ThemeLoader → ThemeStore |
| `data/` | manifest.json + .exe | DataSourceLoader → DataOrchestrator |
| `config/` | config.json | SettingsLoader → SharedPreferences |
| `skill/` | `*.md` | SkillLoader → SkillIndex |

### Riverpod 依赖注入

所有全局实例（ModuleRegistry、AgentController、EventStream、MemoryStore、SkillIndex 等）通过 `providers.dart` 定义的 Provider 暴露，在 `main()` 的 `ProviderScope.overrides` 中注入。Provider 的默认行为是 `throw UnimplementedError`——未注入时崩溃比静默空值更安全。

---

## 六、当前状态与方向

- ✅ Agent 运行时（DeepSeek），支持多级深度思考
- ✅ 六维插件模型全部运行
- ✅ 插件热加载 + 四级进程生命周期管理
- ✅ V2 composite 模式：5 种布局范式 + 35+ 组件类型，纯 JSON 声明
- ✅ dart + html 双渲染模式
- ✅ Agent：Skill 生成、Memory 三作用域、四道安全网、多 Agent 隔离
