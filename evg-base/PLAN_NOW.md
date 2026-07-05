# PLAN_NOW — 插件 JSON 声明式架构

> **状态：当前最新计划**
> **生效日期：2026-07-04**
> **除非有其他计划文档显式声明本计划无效，否则本计划为唯一有效方案。**
>
> 本计划**否决并替代**以下方案：
> - `PLAN_ABC.md`（方案一+二+四，HTTP 聚合网关 + gRPC + 代码生成管线）
> - `Evergreen_插件通信协议改进方案.md` 中推荐的所有 5 套方案

---

## 一、否决 PLAN_ABC 的原因

| 否决理由 | 详述 |
|---------|------|
| **引入新进程 = 单点故障** | 聚合网关 + gRPC Server 合一的单进程崩溃后所有插件不可用 |
| **引入新协议 = 维护噩梦** | gRPC + protobuf 增加外部依赖、学习成本、proto 文件持续维护负担 |
| **6-7 人月成本过高** | 相比真正需要的改进，投入产出比不合理 |
| **Windows UDS 兼容性未验证** | 方案依赖 Unix Domain Socket，Windows 适配存疑 |
| **仍未解决推送/订阅** | #8 仅获 ★，无真正 pub/sub |
| **仍未解决成本感知** | #10 仅加了一个字段，无预算控制/成本归因/实时告警 |
| **仍未解决跨轮次上下文** | #9 仅获 ★，会话持久化、多 Agent 上下文传递皆未覆盖 |
| **治标不治本** | 花大力气让"调 API 更容易"，但插件开发者根本不应该关心 API 调用 |

---

## 二、核心范式转变

```
PLAN_ABC 思路：  让插件更容易调 API → 网关、gRPC、SDK 生成
本计划思路：      插件不调 API → 声明 JSON，Dart 把一切组装好
```

**不是通信协议改进，而是插件范式升维。**

### 核心原则

| # | 原则 | 说明 |
|---|------|------|
| 1 | **JSON 通讯** | 插件与平台之间只通过 JSON 声明配置，不写过程式代码 |
| 2 | **保留 59 个原子端点** | 原封不动，简单场景继续用；JSON 声明是增量而非替换 |
| 3 | **零新进程** | 组装模块跑在现有 Dart 进程内，直接调用 Service 对象 |
| 4 | **零新协议** | HTTP + JSON 原样，curl 调试、Python stdlib 调用全部保留 |
| 5 | **零外部依赖** | 不需要 gRPC 库、protoc、NATS、任何第三方服务 |
| 6 | **渐进式** | 先做高频预设，以后按需扩展 |

---

## 三、Manifest 结构：页面 → 栏目 → 内容组件

### 3.1 完整声明示例（背词软件）

```json
{
  "type": "module",
  "id": "vocab-tutor",
  "name": "背词软件",
  "version": "1.0.0",
  "icon": "school",
  "route": "/vocab-tutor",
  "ui": "composite",

  "sidebar": { "section": "学习", "sectionOrder": 30, "order": 10 },

  "process": { "exe": "vocab-global.exe", "protocol": "http" },

  "pages": [
    {
      "id": "learn",
      "label": "背词",
      "layout": {
        "mode": "scroll",
        "grid": { "columns": 2, "gap": 16 },
        "drawers": ["right"]
      },
      "slots": {
        "left": {
          "component": "type-check",
          "config": {
            "caseSensitive": false,
            "feedback": {
              "correct": { "color": "#4caf50", "animation": "bounce" },
              "incorrect": { "color": "#f44336", "animation": "shake" }
            }
          },
          "process": { "exe": "vocab-engine.exe", "protocol": "http" }
        },
        "right": {
          "component": "ai-assistant",
          "config": {
            "global_memory": true,
            "memory_isolation": "plugin",
            "skills": { "mode": "all" },
            "tools": { "mode": "all" },
            "multi_session": false,
            "workspace": { "enabled": true },
            "temperature": 0.7,
            "context_window": 32000,
            "output_style": "encouraging",
            "system_prompt": "你是一个背词导师，擅长用词根词缀法帮助学生记忆单词。使用中文。",
            "bubble_style": "rounded",
            "thinking_visible": true
          }
        }
      },
      "globalProcess": { "exe": "vocab-page.exe", "protocol": "http" }
    },
    {
      "id": "review",
      "label": "复习",
      "layout": { "mode": "scroll", "grid": { "columns": 1 } },
      "slots": {
        "main": { "component": "flashcards", "config": {} }
      }
    }
  ],

  "actions": [
    {
      "trigger": "button:quick-translate",
      "label": "快速翻译",
      "process": { "exe": "translate.exe", "protocol": "http" }
    }
  ],

  "dependencies": ["agent"]
}
```

### 3.2 结构层级

```
Module（模块）
├── process              ← 插件级后端（整个模块共享，加载→卸载）
│
├── pages[]              ← 多页面
│   ├── layout           ← 复用现有 LayoutDescriptor（mode/grid/zoom/drawers/search/panels）
│   ├── slots            ← 栏目内容
│   │   ├── left
│   │   │   ├── component    ← 内容组件类型
│   │   │   ├── config       ← 组件配置
│   │   │   └── process      ← 栏级后端（栏可见→隐藏）
│   │   └── right
│   │       ├── component
│   │       ├── config
│   │       └── process
│   └── globalProcess    ← 页面级后端（页面激活→切走）
│
└── actions[]            ← 动作按钮
    ├── trigger
    ├── label
    └── process          ← 动作级后端（触发→完成）
```

### 3.3 四种 Process 作用域

| 作用域 | 绑定位置 | 生命周期 |
|--------|---------|---------|
| **插件级** | 模块顶层 `process` | 模块加载时运行，卸载时停止 |
| **页面级** | `page.globalProcess` | 页面激活时运行，切走时停止 |
| **栏级** | `slot.component.process` | 栏可见时运行，隐藏时停止 |
| **动作级** | `action.process` | 触发时启动，完成即退出 |

部分组件不需要 `.exe`：`ai-assistant`（Dart 内建 Agent）、`markdown`、`divider`、`data-table` 等纯展示组件。

### 3.4 与现有 LayoutDescriptor 的关系

`page.layout` 复用现有 `LayoutDescriptor` 全部字段：

```json
"layout": {
  "mode": "scroll",                    // scroll | fit
  "grid": { "columns": 2, "gap": 16 }, // 分栏布局
  "zoom": { "enabled": true, "min": 0.5, "max": 3.0 },
  "drawers": ["left", "right"],
  "search": { "enabled": true, "placeholder": "搜索..." },
  "panels": [
    { "id": "main", "label": "概览", "path": "/vocab-tutor", "default": true }
  ]
}
```

---

## 四、内容组件类型清单（53 个）

### 智能交互（4）
| # | 组件 | 来源 | 说明 |
|---|------|------|------|
| 1 | `ai-assistant` | 新（现有 `ui: "chat"` 升维） | 完整 AI 对话框，记忆/Skill/Tool/Session 全内置 |
| 2 | `form` | 现有 `FormDescriptor` | 结构化表单（文本/选择/日期/文件上传） |
| 3 | `code-editor` | 现有 `InputOptions.code` 升维 | 代码编辑器（语法高亮/自动缩进） |
| 4 | `prompt-builder` | 新 | 提示词组装器 |

### 数据展示（8）
| # | 组件 | 来源 | 说明 |
|---|------|------|------|
| 5 | `data-table` | 现有 `DataBindingDescriptor.display: "table"` | 数据表格（排序/筛选/分页） |
| 6 | `card-list` | 现有 `DataBindingDescriptor.display: "list"` / `"card"` | 卡片列表 |
| 7 | `chart` | 新 | 图表（折线/柱状/饼图/雷达） |
| 8 | `stat-tile` | 新 | 统计指标卡（大数字+趋势箭头） |
| 9 | `kanban` | 新 | 看板（拖拽列） |
| 10 | `tree` | 新 | 树形结构 |
| 11 | `timeline` | 现有 `TimelineDescriptor` | 时间线（垂直/水平） |
| 12 | `map` | 现有 `MapDescriptor` | 地图/位置（标记/搜索/路线） |

### 文档与媒体（7）
| # | 组件 | 来源 | 说明 |
|---|------|------|------|
| 13 | `doc-viewer` | 现有 `MediaDescriptor` + `DocumentOptions` | 文档查看器（PDF/DOCX/PPTX/XLSX） |
| 14 | `doc-editor` | 现有 `DocEditorOptions` + `ui: "document"` | 文档编辑器（修订/批注/目录） |
| 15 | `video-player` | 现有 `MediaDescriptor` + `VideoOptions` | 视频播放器（倍速/字幕/缓存） |
| 16 | `audio-player` | 现有 `MediaDescriptor` + `AudioOptions` | 音频播放器（倍速/波形） |
| 17 | `image-gallery` | 现有 `MediaDescriptor` + `ImageOptions` | 图片画廊（缩放/翻页） |
| 18 | `presentation` | 现有 `PresentationOptions` + `ui: "presentation"` | 幻灯片（切换动画/演讲者视图） |
| 19 | `markdown` | 新 | Markdown 渲染器（代码高亮/数学公式） |

### 创作与工具（6）
| # | 组件 | 来源 | 说明 |
|---|------|------|------|
| 20 | `spreadsheet` | 现有 `SpreadsheetOptions` + `ui: "spreadsheet"` | 电子表格（公式/图表/多 sheet） |
| 21 | `notepad` | 新 | 富文本记事本 |
| 22 | `whiteboard` | 新 | 白板（手绘/形状/连线） |
| 23 | `mindmap` | 新 | 思维导图 |
| 24 | `diff-viewer` | 新 | 差异对比（左右分栏） |
| 25 | `terminal` | 新 | 终端（命令输入+输出展示） |

### 学习专用（5）
| # | 组件 | 来源 | 说明 |
|---|------|------|------|
| 26 | `type-check` | 现有 `InputOptions.type-check` 升维 | 打字背词模式 |
| 27 | `flashcards` | 新 | 闪卡（翻转/间隔复习） |
| 28 | `quiz` | 新 | 测验（单选/多选/填空/计时） |
| 29 | `crossword` | 新 | 填字/连线题 |
| 30 | `pronunciation` | 新 | 发音评测（录音→波形→评分） |

### 特殊（23）
| # | 组件 | 来源 | 说明 |
|---|------|------|------|
| 31 | `custom` | 现有 `ProcessDescriptor` | 插件自渲染（走 .exe） |
| 32 | `webview` | 新 | 嵌入网页 |
| 33 | `divider` | 新 | 分割线（视觉分隔） |
| 34–53 | `placeholder-01` ~ `placeholder-20` | 新 | 预留扩展占位符 |

---

## 五、`ai-assistant` 组件完整配置（30 参数）

### Agent 能力参数（11）
| # | 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|------|------|------|--------|------|
| 1 | `system_prompt` | string | 否 | `defaultSystemPrompt` | 系统提示词 |
| 2 | `tool_hint` | string | 否 | `defaultToolHint` | 工具使用指引 |
| 3 | `temperature` | float | 否 | 0.0 | 模型温度 |
| 4 | `max_steps` | int | 否 | 50 | 最大推理步数 |
| 5 | `context_window` | int | 否 | 0（不限制） | 上下文窗口大小 |
| 6 | `model` | string | 否 | 继承全局设置 | 模型选择 |
| 7 | `thinking` | "enabled" \| "disabled" | 否 | "enabled" | 思考模式开关 |
| 8 | `reasoning_effort` | "" \| "low" \| "high" \| "max" | 否 | "" | 推理深度 |
| 9 | `UNUSED_agent_01` | any | 否 | null | 占位 |
| 10 | `UNUSED_agent_02` | any | 否 | null | 占位 |
| 11 | `UNUSED_agent_03` | any | 否 | null | 占位 |

### 能力开关参数（10）
| # | 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|------|------|------|--------|------|
| 12 | `global_memory` | bool | 否 | false | 是否启用全局记忆 |
| 13 | `memory_isolation` | "plugin" \| "shared" \| "none" | 否 | "plugin" | 记忆隔离策略 |
| 14 | `skills` | `{mode: "all"\|"specific"\|"none", allowed: [...]}` | 否 | `{mode: "none"}` | 技能白名单 |
| 15 | `tools` | `{mode: "all"\|"specific"\|"none", allowed: [...]}` | 否 | `{mode: "specific", allowed: []}` | 工具白名单 |
| 16 | `multi_session` | bool | 否 | false | 是否多会话 |
| 17 | `max_sessions` | int | 否 | 1 | 最大会话数 |
| 18 | `workspace` | `{enabled, accept, max_files, max_size_mb, ai_creatable}` | 否 | `{enabled: false}` | 文件工作区 |
| 19 | `UNUSED_capability_01` | any | 否 | null | 占位 |
| 20 | `UNUSED_capability_02` | any | 否 | null | 占位 |
| 21 | `UNUSED_capability_03` | any | 否 | null | 占位 |

### 渲染参数（9）
| # | 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|------|------|------|--------|------|
| 22 | `output_style` | string（内置名或自定义 body） | 否 | null | 沟通风格 |
| 23 | `bubble_style` | "rounded" \| "flat" \| "minimal" | 否 | "rounded" | 气泡样式 |
| 24 | `thinking_visible` | bool | 否 | true | 思考过程可见（含工具调用） |
| 25 | `thinking_transparent` | bool | 否 | false | 思考栏透明 |
| 26 | `thinking_mode` | "expand" \| "scroll" | 否 | "expand" | 思考栏展开方式 |
| 27 | `stream_animation` | "typewriter" \| "fade" \| "none" | 否 | "typewriter" | 流式动画 |
| 28 | `placeholder` | string | 否 | "输入消息..." | 输入框占位文字 |
| 29 | `UNUSED_render_01` ~ `UNUSED_render_05` | any | 否 | null | 占位 |

### 字段语义速查

| JSON 字段 | Dart 行为 |
|-----------|----------|
| `global_memory: true` | 挂载 MemoryAgent，分配 `plugin:<name>` 隔离命名空间 |
| `memory_isolation: "plugin"` | 记忆自动前缀 `plugin:<name>/`，跨插件不可见 |
| `skills.mode: "specific"` | 仅 `allowed` 列表中的 skill 可用 |
| `skills.mode: "all"` | 全部已注册 skill 可用 |
| `skills.mode: "none"` | 不注入任何 skill |
| `tools.mode: "specific"` | ToolGate 白名单模式，仅 `allowed` 列表可用 |
| `tools.mode: "all"` | 全部工具可用 |
| `tools.mode: "none"` | 无工具，纯对话 |
| `workspace.enabled: true` | 挂载 WorkspaceTool + WriteFileTool，root = `.greenix/workspaces/<moduleId>/`（路径由平台分配，不可自定义） |
| `output_style: "socratic"` | 注入对应 prompt/style 模板（内置：explanatory / learning / concise / socratic） |
| `thinking_visible: false` | 隐藏思考过程（含工具调用） |

---

## 六、预设组块（Pre-built Presets）

模块基于预设快速启动，可在预设上微调：

```json
// 预设 1：轻量问答助手
{ "preset": "qa-basic" }
// → global_memory: false, skills: none, tools: none, multi_session: false,
//   workspace: disabled, temperature: 0.0

// 预设 2：完整研究助手
{ "preset": "research-full" }
// → global_memory: true, skills: all, tools: all, multi_session: true,
//   workspace: enabled, temperature: 0.3

// 预设 3：代码助手
{ "preset": "code-assistant" }
// → global_memory: true, skills: all, tools: all, multi_session: true,
//   workspace: enabled, context_window: 64000

// 基于预设微调
{
  "preset": "research-full",
  "ai_assistant": {
    "tools": { "mode": "specific", "allowed": ["web_search"] }
    // 其余字段继承预设默认值
  }
}
```

---

## 七、记忆隔离机制

### 三层隔离模型

```
MemoryStore
├── plugin:vocab-tutor/               ← 本模块所有记忆
│   ├── user:lybx/                    ← 与特定用户的对话记忆
│   │   ├── "用户更喜欢词根记忆法"
│   │   └── "上次学习到第 12 课"
│   └── global/                       ← 模块级全局记忆
│       └── "常用词根：spect=看, dict=说..."
│
├── plugin:other-module/              ← 完全隔离
│
└── global/                           ← 跨模块共享（仅显式声明时）
    └── "用户整体偏好：简洁回答"
```

### 多智能体下的记忆（平台不直接提供多智能体，但支持声明多个单智能体后自定义编排）

```
plugin:code-workshop/
├── agent:architect/
│   ├── user:lybx/
│   └── internal/                    ← 内部"思考笔记"（不与其他 agent 共享）
├── agent:coder/
├── agent:reviewer/
└── shared/                          ← 模块内所有 agent 共享
    └── "项目采用 Rust + Actix Web"
```

Dart 层自动插前缀，模块开发者无感知、无泄漏。

---

## 八、前后端通信：三种模式共存

```
模块开发者选择：

1. JSON 声明模式（推荐）
   插件声明 manifest → Dart 组装工厂 → 自动获得完整 AI 助手
   零 API 调用、零 .exe

2. 原子端点模式（保留）
   插件 .exe → HTTP → GET /agent/sessions/current
                      POST /agent/chat/stream
   适合简单查询、单轮交互、一键出结果

3. 混合模式
   栏位内嵌 ai-assistant（JSON 声明）+ 其他栏走自定义 .exe（原子端点）
   不冲突、不互斥、不强制二选一
```

- 59 个 HTTP 端点**原封不动**，长期维护
- `ai-assistant` 是高层封装，底层仍是 Agent 系统
- 旧模块不改 manifest 继续正常工作

---

## 九、栏间通信：Workspace + EventBus

多栏页面中，栏与栏之间需要共享上下文。例如背词软件：用户在左栏打字背词，右栏 AI 需要知道用户在学哪个词、刚才有没有拼错。

### 9.1 两种机制、各自适用

| 机制 | 适用场景 | 实现 | 延迟 | 持久化 |
|------|---------|------|------|--------|
| **Workspace（被动上下文）** | AI 对话时获取栏的状态快照 | 栏声明 `expose_state` → 平台自动写文件 → AI 对话时读取 | 无（读取时瞬间） | ✓ 跨会话持久 |
| **EventBus（主动推送）** | 栏触发事件 → 立即通知同页其他栏 | 页级 Dart Stream | 实时（内存） | ✗ 页关即消 |

两者并存、互补、不互斥。

### 9.2 Workspace 通道（被动上下文）

栏声明自己暴露哪些状态：

```json
"left": {
  "component": "type-check",
  "expose_state": {
    "events": ["word_completed", "answer_submitted", "score_changed"],
    "format": "json",
    "subdir": "type-check"
  }
}
```

Dart 行为：
- 用户打完一个词 → type-check 组件触发 `word_completed` 事件
- Dart 自动将当前状态写入 `.greenix/workspaces/<moduleId>/type-check/state.json`
- 右栏 AI 每轮对话开始时 → AgentAssembly 自动读取 workspace 下所有 `expose_state` 子目录 → 注入到 `memoryContext`

**模块开发者不需要手动写文件。声明事件，平台自动做。**

### 9.3 Workspace 子目录隔离

```
.greenix/workspaces/vocab-tutor/
├── type-check/              ← 左栏 expose_state 写入
│   └── state.json            ← {"current_word": "apple", "score": 85, "last_mistake": "appple"}
├── flashcards/               ← 另一个栏的 expose_state
│   └── progress.json
├── _shared/                  ← 栏间显式共享区（模块开发者声明）
└── _ai/                      ← AI 自身产生的文件（笔记、导出等，AI 写，人可读）
```

约定：
- 每个 `expose_state` 有自己的子目录，不相覆盖
- `_shared/` 是栏间显式共享区
- `_ai/` 是 AI 的工作产物区
- 组件只能写自己的子目录，AI 可读全部

### 9.4 EventBus 通道（主动推送）

栏声明 emit 和 subscribe 的事件名：

```json
{
  "pages": [{
    "id": "learn",
    "layout": { "grid": { "columns": 2 } },
    "slots": {
      "left": {
        "component": "type-check",
        "events": {
          "emit": ["word_completed", "answer_submitted"],
          "subscribe": ["ai_feedback"]
        }
      },
      "right": {
        "component": "ai-assistant",
        "config": { ... },
        "events": {
          "subscribe": ["word_completed", "answer_submitted"],
          "emit": ["ai_feedback"]
        }
      }
    }
  }]
}
```

Dart PageRuntime 启动时，读到所有 slot 的 events 声明，建一个**页级轻量 EventBus**（纯 Dart Stream，零外部依赖）：

```
type-check 组件触发 "word_completed"
    → EventBus 收到事件 {event: "word_completed", data: {word: "apple", correct: true}}
    → 查找所有 subscribe 了该事件的 slot
    → 注入到 ai-assistant 的下一轮上下文中
    → AI 感知到，可以主动回应
    → AI 也可以 emit "ai_feedback" → EventBus → 路由到 type-check
```

### 9.5 典型时序：背词纠错

```
1. 用户在 type-check 输入 "appple" → 提交
2. type-check 判断拼写错误 → emit "word_completed":
     {word: "apple", user_input: "appple", correct: false}
3. EventBus 路由到 ai-assistant
4. AI 在上下文中看到: "[事件 word_completed] 用户把 apple 拼成了 appple"
5. AI: "你刚才拼的 appple 少了一个 p，正确拼写是 apple。"
6. AI emit "ai_feedback": {correction: "apple", tip: "双写 p"}
   → EventBus → type-check 收到（可选：更新 UI 提示）
```

### 9.6 与 PLAN_ABC #8 推送/订阅的区别

| | PLAN_ABC #8 | 本方案 EventBus |
|------|------------|----------------|
| 范围 | 全局跨进程 | 单页内跨栏 |
| 外部依赖 | NATS / gRPC | 0（Dart Stream） |
| 持久化 | 可选 | 不持久（页关即消） |
| 复杂度 | 中高 | 低 |
| 学习成本 | NATS 概念（主题/订阅/请求-应答） | 声明 emit/subscribe 即可 |

页内 EventBus 不解决"Agent 状态变了通知全局所有插件"这种跨模块推送，但它解决了多栏页面中最常见的栏间实时协作需求。

---

## 十、组装架构：AgentAssembly 工厂

### 新建文件

`lib/core/agent/agent_factory.dart` —— AgentAssembly 工厂类。

### 组件隔离策略

| 组件 | 共享 or 隔离 | 原因 |
|------|-------------|------|
| Provider (LLM API) | **共享** | 同一个 API Key，复用连接 |
| Registry (工具) | **隔离** | 每个模块 tool whitelist 不同 |
| SessionManager | **隔离** | 不同模块对话历史独立 |
| MemoryFacade | **隔离** | 记忆命名空间 `plugin:<name>/` |
| SkillIndex | **隔离** | 每个模块激活的 skill 不同 |
| Controller | **隔离** | 各自的状态机 |
| AgentOptions | **隔离** | temperature / contextWindow 等独立 |
| Gate | **隔离** | 权限规则不同 |

### 工厂方法

```dart
class AgentAssembly {
  final Controller controller;
  final SessionManager sessions;
  final MemoryFacade memory;
  final Registry registry;

  AgentAssembly.fromJson({
    required String moduleId,
    required Map<String, dynamic> config,
    required Provider sharedProvider,
  });
}
```

`fromJson` 内部编排：

```
config.tools        → Registry（注册 + 按 mode 过滤）
config.skills       → SkillIndex（筛选）
config.memory       → MemoryFacade（scope = plugin:<moduleId>）
config.multi_session → SessionManager
config.temperature  → AgentOptions
config.system_prompt → Controller.setSystemPrompt
config.output_style → StyleManager.applyTo
config.workspace    → WorkspaceTool（root = .greenix/workspaces/<moduleId>）
config.thinking_visible → ChatOptions（传给 renderer）
config.bubble_style → ChatOptions（传给 renderer）
```

### 与现有 AgentRuntime 的关系

不冲突。全局单例 `AgentRuntime` 继续给没有声明 `ai-assistant` 的模块用（fallback）。有 `ai-assistant` 配置的模块走 `AgentAssembly`。

---

## 十一、生命周期

| 事件 | 行为 |
|------|------|
| **安装** | 自动创建 `.greenix/workspaces/<moduleId>/` 目录，初始化 memory 存储 |
| **卸载** | 删除 workspace 目录；**保留 memory**（用户可手动清） |
| **禁用** | 冻结所有状态，不删除数据 |
| **升级** | 不做数据迁移，新字段给默认值；旧字段保持不变 |

---

## 十二、关于多智能体

平台**不直接提供多智能体服务**，只提供单智能体封装。多智能体是单智能体封装足够好之后的自然产物——模块声明多个 `ai-assistant` 组件，然后自己定义交互规则。

这同时也是对上游客单智能体封装能力的检验：如果单智能体封得干净、可组合、可隔离，多智能体只是多声明几个的事。

---

## 十三、与 PLAN_ABC 的最终对比

| 维度 | PLAN_ABC（一+二+四） | PLAN_NOW（JSON 声明式） |
|------|---------------------|------------------------|
| **范式** | 调 API 更容易 | 不需要调 API |
| **新增进程** | 1 个（网关+gRPC） | 0 |
| **新增协议** | gRPC + protobuf | 0（HTTP + JSON 原样） |
| **外部依赖** | gRPC 库 + protoc | 0 |
| **实现成本** | 6-7 人月 | 集中在 Dart 内部，远低于 6 人月 |
| **单点故障** | 有（网关崩溃全挂） | 无 |
| **调试工具** | curl + grpcurl | curl（不变） |
| **59 个端点** | 保留 | 保留 |
| **模块开发者写代码** | 需要（Python SDK） | 不需要（JSON 声明） |
| **记忆隔离** | 应用层各自处理 | 平台层统一隔离 |
| **权限边界** | 靠协议 | 声明即信任（AI 能力本身沙箱化，不设审批流） |
| **多智能体** | 未涉及 | 不直接提供，但单智能体封装支持上层自行组合 |
| **流式双向** | ★★★ gRPC 双向流 | 未解决（SSE 单向，已知限制） |
| **类型安全** | ★★★ protobuf | 未解决（JSON，已知限制） |
| **推送/订阅** | ★ gRPC server streaming | 未解决（已知限制） |

---

## 十四、已知限制

以下问题在本方案中未彻底解决，需关注但不阻塞当前阶段：

| 问题 | 说明 |
|------|------|
| **流式双向** | SSE 仍为单向——用户无法在 AI 输出过程中注入中断指令 |
| **类型安全** | JSON 字段名拼错在运行时才暴露（可通过 JSON Schema 校验缓解） |
| **推送/订阅** | 无事件总线，状态变化需轮询 |
| **成本感知** | 可在响应中附带 token 消耗信息，但无协议级预算控制 |

---

## 十五、实施建议

### 首批交付（MVP）

| 项目 | 内容 |
|------|------|
| AgentAssembly 工厂 | `lib/core/agent/agent_factory.dart`，按 JSON config 组装 Agent |
| ModuleDescriptor 扩展 | 新增 `pages` / `slots` / 组件解析（Module 工程师） |
| 预设 | `qa-basic`、`research-full`、`code-assistant` |
| 记忆隔离 | `plugin:<name>/` 前缀自动注入 |
| 工具白名单 | Registry 按 `tools.mode` + `allowed` 过滤 |
| 渲染层通讯 | 向渲染工程师提 `ai-assistant` 组件 + bubble_style / thinking 渲染需求 |

### 后续迭代

| 项目 | 内容 |
|------|------|
| 更多预设 | 按模块开发者反馈拓展 |
| JSON Schema 校验 | 编译期捕获配置错误 |
| 更多内容组件 | 逐步实现 placeholder 中的组件 |
| 成本感知字段 | 响应中附带 token 消耗 |

---

> **一句话：不是让插件更容易调 API，而是让插件根本不用调 API——声明你要什么能力，平台给你一个配好的 AI 助手。**
>
> **JSON 通讯。保留 59 个端点。零新进程。零新协议。零外部依赖。**
