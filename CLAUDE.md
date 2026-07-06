# Evergreen Base — AI 协作规范

> 这份文档教 AI 理解本项目的设计逻辑。它不是 API 参考（API 在 `lib/README.md`），不是实施计划（计划在 `PLAN_NOW.md`），而是**架构心智模型**——让 AI 在修改代码之前先理解"为什么长这样"。

---

## 一、项目是什么

**Evergreen** 是一个无账号、无服务端、本地优先、AI 原生的去中心化微工具集成平台。Flutter 桌面应用，目标用户是大学生。

核心价值主张：**一个 Python 学生，一杯咖啡，一页 JSON，一个完整的 AI 助手。** 把创作门槛从"学 Flutter + 调 59 个 API"降到"填 JSON + 写后端脚本"。

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
| 下游 renderer/ | 不解析 manifest，不管理进程，不写业务逻辑 |

### main.dart 的角色

横跨三层的**组装者**：启动上游 HTTP Server → 扫描中游插件目录 → 解析 manifest → 注册到 Registry → 启动 .exe 进程 → 注入 Riverpod → runApp。

---

## 三、中游插件的四级 .exe 层级

> .exe 与**组件**挂钩，不是与模块挂钩。一个模块的不同组件、不同栏目、不同事件可以各自触发独立的 .exe。

```
plugins/<name>/
  module/manifest.json
  │
  ├── process: "global.exe"                    ← ① 模块级：加载→卸载
  │
  ├── pages[]:
  │   └── globalProcess: "page.exe"           ← ② 页面级：激活→切走
  │       └── slots:
  │           ├── left:
  │           │   └── process: "left.exe"     ← ③ 栏位/组件级：可见→隐藏
  │           └── right:
  │               └── process: "right.exe"    ← ③ 同上
  │
  └── actions[]:
      └── process: "action.exe"               ← ④ 动作级：触发→完成即退出
```

| 层级 | 声明位置 | 生命周期 |
|------|---------|---------|
| ① 模块级 | `ModuleDescriptor.process` | 模块加载 → 卸载 |
| ② 页面级 | `PageDescriptor.globalProcess` | 页面激活 → 切走 |
| ③ 栏位/组件级 | `ComponentConfig.process` | 栏可见 → 隐藏 |
| ④ 动作级 | `ActionButtonDescriptor.process` | 按钮触发 → 完成即退出 |

---

## 四、核心设计决策与理由

### 4.1 为什么是 JSON 声明 + HTTP 通信？

- **JSON 声明**：插件开发者不写 UI 代码，只声明"我要什么范式、什么布局、绑什么数据"。中游决定形态，下游按声明渲染。这是 PLAN_NOW 的核心——让插件**根本不需要调 API**。
- **HTTP 通信**：任何语言都有 HTTP 库，`curl` 可调试，Python `stdlib` 可调用。降低插件开发门槛——会写 Python 就会写插件。
- **端口发现文件** (`.agent_port`、`.config_port` 等)：不需要注册中心，文件系统即服务发现。

### 4.2 为什么 core/ 和 renderer/ 分离？

- **可替换渲染层**：core/ 是平台无关的声明引擎，renderer/ 只是 Flutter Desktop 实现。未来可以有 Web 版 renderer，core/ 保持不变。
- **职责分离 + 安全边界**：渲染层只能读 core/ 的公开 API。防止 UI 代码侵入业务逻辑，防止声明逻辑散落进像素代码。
- **renderer/ 的三层结构**：`widgets/`(原子组件，无业务逻辑) → `shared/`(范式视图+调度) → `compositions/`(多视图叠加)。下层不放上层的事。

### 4.3 为什么是 register → seal 模式？

`ModuleRegistry` 在 `main()` 中收集所有模块 → `seal()` 锁定。之后不可注册、不可修改。确保路由表在应用启动后是**不可变的**——避免运行时动态注册带来的竞态和不确定路由。

### 4.4 UI 范式的终局是什么？

PLAN_NOW 的 **composite 模式**是终局方向——页面 → 栏目 → 内容组件的纯 JSON 声明。现有的 10+ 种预设范式（chat/spreadsheet/document/presentation/dashboard/editor 等）将逐步被 composite 统一。不是替代，而是证明：当 composite 能表达所有预设范式时，预设范式就不再需要了。

### 4.5 Agent 的设计哲学

Agent 主循环（`lib/core/agent/agent/agent.dart`）是平台无关的纯 Dart 引擎：

```
用户输入 → Compose(拼装消息+工具schema) → LLM Call(流式) → Tool Execution(串行)
                                                                    ↓
           Final Readiness(检查是否产出有效答案) ←─────────────────
```

- **Skill**：提示词技能包。既可注入 system prompt（compose 阶段），也可被 Agent 通过 `run_skill` Tool 主动调用。Skill 是 Markdown 文件，不会写代码的人也能贡献。
- **Memory**：跨会话记忆。Agent 通过 `read_global_memory` / `write_global_memory` Tool 主动读写。每轮对话后 MemoryAgent 自动提取用户特质写入文件。
- **Tool**：模型可调用的能力。`Registry` 管理注册，`PluginBridge` 扫描插件目录注册外部工具。读写工具串行，只读工具可并行。
- **Gate / StormBreaker / FinalReadiness**：三道安全网——权限门控、风暴抑制（重复调用自动压制）、最终检查（空答案强制重试）。

---

## 五、关键数据结构心智模型

### ModuleDescriptor（中游产物的 Dart 表示）

```
manifest.json  →  ModuleDescriptor.fromJson()  →  ModuleRegistry.register()  →  seal()
                                                          ↓
                                          GoRouter 路由表自动生成
                                          侧边栏导航自动生成
                                          命令面板条目自动生成
                                          ModuleDispatch 按 ui 字段派发视图
```

- `ModuleDescriptor` 是 const + 不可变的。渲染层收到的永远是已经 seal 的描述符。
- `ui` 字段是调度键——ModuleDispatch 的纯 switch 根据它选择视图。
- 未知字段**静默忽略**——不抛异常，不回退到错误页。这是容错设计，不是 bug。

### 六维插件模型

一个插件目录可同时包含多种类型，各子目录互不冲突：

| 子目录 | 包含 | 被谁加载 |
|--------|------|---------|
| `agent/` | manifest.json + .exe | PluginBridge → toolRegistry |
| `module/` | manifest.json | ModuleLoader → ModuleRegistry |
| `theme/` | theme.json | ThemeLoader → ThemeStore |
| `data/` | manifest.json | DataSourceLoader → Orchestrator |
| `config/` | config.json | SettingsLoader → SharedPreferences |
| （Skill） | `.greenix/skills/*.md` | SkillLoader → SkillIndex |

### Riverpod 依赖注入

所有全局实例（ModuleRegistry、AgentController、EventStream、MemoryStore、SkillIndex 等）通过 `providers.dart` 定义的 Provider 暴露，在 `main()` 的 `ProviderScope.overrides` 中注入。Provider 的默认行为是 `throw UnimplementedError`——未注入时崩溃比静默空值更安全。

---

## 六、当前状态与方向

- ✅ Agent 运行时在对话（DeepSeek v4-pro）
- ✅ 六维插件模型全部运行
- ✅ 插件热加载 + 进程生命周期管理
- ✅ 10+ UI 范式可调度
- ✅ 103 个测试通过
- 🔄 **PLAN_NOW 实施中**：composite 模式是将创作门槛从"学 Flutter"降到"填 JSON"的关键工程

---

## 七、AI 协作规则

### 可写范围

| 层级 | 你有权修改 |
|------|-----------|
| 上游 core/ | `core/` 下非 agent/config/data/module/theme 的内容（services/、utils/、errors.dart 等） |
| 上游子模块 | 仅限你被指定的子模块（agent/ config/ data/ module/ theme/ 之一），只读其他子模块 |
| 中游 plugins/ | 示例插件（`lib/core/*/example/plugins/` 和 `plugins/`） |
| 下游 renderer/ | `renderer/` 全部内容；只读 core/ |
| 全局 | `lib/` 根文件、`scripts/`、`windows/`、根级配置 |

### 核心规则

1. **上游不画像素，下游不写逻辑**——这是最根本的分界。新增功能先判断属于哪层。
2. **中游决定形态**——插件 manifest.json 改变页面行为，不需要改 Dart 代码。
3. **声明驱动**——所有配置通过 `*Descriptor` / `*Options` 不可变类传递，不做运行时可变状态。
4. **未知字段静默忽略**——收到未识别的 JSON 字段时不做任何事，不抛异常。
5. **Stub 隔离**——各模块的 `lib/` 子目录是 stub 包，只用于独立 `dart analyze`，不参与编译。
6. **测试覆盖三层**——core 测逻辑（纯 Dart test），renderer 测渲染（widgetTest），集成测联动（integrationTest）。
7. **跨模块通讯**——发现问题用规范的通讯格式反馈给对应工程师，不越权改他人代码。格式见 `.history_docs/CLAUDE.md`。

### 禁止事项

- ❌ 在 renderer/ 中写业务逻辑或直接调用 HTTP API
- ❌ 在 core/ 中引用 Flutter Widget（Material、Widgets 等）
- ❌ 修改其他子模块的代码（即使在"顺手修个小 bug"的诱惑下）
- ❌ 绕过 ModuleDescriptor 直接硬编码路由或导航
- ❌ 在未沟通的情况下重复实现其他模块已有的能力
- ❌ 让 .exe 进程管理逻辑出现在渲染层
