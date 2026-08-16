# Scraper v2.0 工程化改造 PLAN（全量 · 分 Phase 交付）

> 状态：**草案，待用户确认后按 Phase 实施**
> 依据：`v2.0重点优化对象.md` 表二 scraper 行 + 代码实况盘点
> 决策（用户已确认）：
> - 全部需求完成，分 Phase 交付，每 Phase 独立可验证
> - Trace 组件共享化，先只接入 scraper
> - 探索守卫默认：同域 + 20 页 + 50 请求 + 1s 节流（可配置）
> - 批量注册：每源一个插件目录 `data-{name}`
> - **探索模式与定向抓取模式是两种并列模式**：不同工作流状态机、不同工具集、不同 harness 约束，UI 手动选择模式

---

## 〇、总览

| 需求 | 交付物 | Phase |
|---|---|---|
| 1. Harness 工程化（hooks/guards/可靠性） | Agent 层 Gate/Hooks 接线 + 终端命令守卫 + 工作流工程化 | Phase 1 + Phase 2 |
| 2. Workflow 可视化 + 统一进度 | 步骤条 + 事件驱动的统一进度指示器 | Phase 2 |
| 3. AI History + Trace 视图 | 共享 TraceRecorder + 笔记本风格 TraceView + scraper 接入 | Phase 3 |
| 4. AI 探索机制 | 双模式架构 + GET-only 探索工具集 + 归类/多选/批量构建/批量注册 | Phase 4 |

**依赖关系**：Phase 1 的守卫接线是 Phase 4 探索安全的前提；Phase 2 的工作流 Hook/事件是 Phase 3 Trace 与 Phase 4 双模式状态机的数据基础；Phase 3 的 TraceRecorder 复用 Phase 1 的 ScraperHooks 结果摘要。

---

## 一、双模式架构（需求 4 前置设计）

两种模式并列存在，各自独立的状态机与工具集，**UI 手动切换**，切换后各自状态保留、互不干扰。

| 维度 | 模式 A：定向抓取（现有，保留） | 模式 B：AI 探索（新增） |
|---|---|---|
| 用户意图 | "我要这个具体数据" | "这个网站我登录好了，帮我看看有什么数据可抓" |
| 触发 | 手动选日志 → 分析 → 生成（现有流程） | 手动切到探索模式 → 点"开始探索" |
| 工作流 | `ScraperWorkflow`（现有状态机，Phase 2 工程化） | `ExploreWorkflow`（新状态机：idle → exploring → categorizing → confirming → building → registering → done/failed） |
| 工具集 | 现有 scraper 工具 + 新增守卫 | 探索专用工具（`explore_page_links` / `navigate_get` / `list_captured_requests` / `present_data_sources`）+ 复用构建/注册工具 |
| Harness 约束 | Gate：写工具需确认；终端命令白名单 | **更强**：仅 GET、同域、页数/请求数上限、节流；探索阶段禁用 `run_terminal_command`、`save_credential`、`export_and_register_scraper`（构建阶段才启用） |
| UI | 现有 AI 面板对话流 | 探索进度面板 + 归类多选对话框 + 批量构建进度 |

**模式切换器**：`ScraperGeneratorView` 顶部加入模式选择（SegmentedButton / Tab），切换时 `IndexedStack` 保留两侧状态。

---

## 二、Phase 1：Agent 层守卫接线（需求 1 A + B）

### 目标
把 core 已有的 Gate/ToolHooks 能力真正接到 scraper 隔离 Agent 上，补上"零门控"缺口；给终端命令加白名单守卫。

### 改动文件
| 文件 | 改动 |
|---|---|
| `evg-base/lib/core/agent/agent_factory.dart` | `AgentAssembly.fromConfig` 增加可选 `gate` / `hooks` 参数；构造 Controller 时透传；增加 `AgentAssembly.forScraper(...)` 便捷工厂 |
| `evg-base/lib/core/agent/controller/controller.dart` | 构造参数增加 `gate`/`hooks`；`send()` 创建 `Agent` 时传入 |
| `evg-base/lib/core/agent/agent/agent.dart` | （已支持 `setGate/setHooks`，无需改动；确认 Controller 透传即可） |
| `evg-base/lib/renderer/templates/scraper_modle/scraper_guard.dart`（新） | `ScraperGate`（InteractiveGate 规则表）+ `ScraperHooks`（ToolHooks 实现）+ 终端命令白名单守卫 |
| `evg-base/lib/renderer/templates/scraper_modle/scraper_ai_panel.dart` | `_initAgent` 中改走 `AgentAssembly.forScraper`，注入 Gate/Hooks |

### 设计要点
1. **ScraperGate 规则表**（`PermissionRule`）：
   - `run_terminal_command` → `confirm`（用户确认）
   - `run_python_scraper` → `always`（沙箱内执行 + JSON 校验，可放行）
   - `save_credential` → `confirm`
   - `export_and_register_scraper` → `always`
   - 未知写工具 → 默认 confirm；未知只读工具 → 默认放行（沿用现有 Gate 语义）
2. **ScraperHooks（ToolHooks）**：
   - `preToolUse`：
     - `run_terminal_command` → **命令白名单校验**（命中黑名单/未命中白名单 → block + 理由）
     - `run_python_scraper` → code 长度上限（如 ≤200KB）校验
     - `export_and_register_scraper` → data_name 与用户命名一致性校验（现有工具内已做，上移为统一 hook）
   - `postToolUse`：生成**结果摘要**（行数 / 字节数 / 前 200 字符预览）→ 写入 Trace 缓冲（Phase 3 消费）
3. **终端命令白名单守卫**（`isTerminalCommandAllowed(cmd)`）：
   - 白名单模式：`python scraper.py`、`pip install <pkg>`、`cd <dir>`、`python -m pip ...`
   - 黑名单（硬拒绝）：`rm` / `del` / `rmdir` / `format` / `shutdown` / `reboot` / `> /dev/sda` 等破坏性命令、shell 重定向链、`;` / `&&` / `|` 命令拼接（白名单模式外一律拒绝）
   - 拒绝消息回灌 AI：`[error: 命令被守卫拒绝: <原因>]`

### 验收标准
- `dart test`（core/agent）全绿；scraper 相关 widget 测试新增：Gate 拒绝路径、Hooks 校验路径、白名单命中/拒绝
- 手工验证：AI 调用 `run_terminal_command("rm -rf /")` 被守卫拒绝并可见拒绝原因；`pip install requests` 放行
- 现有"定向抓取"全流程（浏览→分析→生成→执行→注册）回归通过

---

## 三、Phase 2：工作流工程化 + 可视化 + 统一进度（需求 1 C + 需求 2）

### 目标
把 `ScraperWorkflow` 从"草稿箱"升级为带时间戳、验收门槛、Hook 事件的工程化状态机；新增步骤条可视化；统一进度指示器，真实反映 AI 步骤。

### 改动文件
| 文件 | 改动 |
|---|---|
| `evg-base/lib/renderer/templates/scraper_modle/scraper_workflow.dart` | 阶段记录 `enteredAt/elapsed`；每阶段转换增加验收门槛（`_guardTransitions`）；新增工作流级 Hook 接口 + 轻量事件流；`phaseTimeline` 供可视化/trace 消费 |
| `evg-base/lib/renderer/templates/scraper_modle/scraper_workflow_stepper.dart`（新） | 横向步骤条组件 |
| `evg-base/lib/renderer/components/shared/widgets/agent_step_indicator.dart`（新） | 事件驱动的统一进度指示器（共享） |
| `evg-base/lib/renderer/templates/scraper_modle/scraper_generator_view.dart` | 顶部/底部接入 Stepper + AgentStepIndicator；替换裸进度条 |
| `evg-base/lib/renderer/templates/scraper_modle/scraper_ai_panel.dart` | 头部小转圈替换为 AgentStepIndicator（显示当前工具名 + 步骤计数） |
| `evg-base/lib/renderer/templates/scraper_modle/scraper_webview.dart` | 页面加载进度条统一为 EvergreenProgress 风格 |

### 设计要点
1. **阶段验收门槛**（违规 → 拒绝转换 + debug 日志 + 可选 UI 提示）：
   - `capturing → analyzing`：`logs.isNotEmpty`
   - `analyzing → generating`：schema 已产出（`hasSchema`）
   - `running → done`：执行成功且 JSON 校验通过（现逻辑已具备，收编为门槛）
   - `debugging` 轮次上限（现 5 轮）保留
2. **工作流 Hook 接口**：
   ```dart
   abstract class WorkflowHooks {
     void onPhaseEnter(ScraperPhase phase, {Duration? elapsed});
     void onPhaseExit(ScraperPhase phase);
     void onProgress(ScraperWorkflowEvent event); // 日志计数/步骤更新
     void onDebugRound(int round, int maxRounds);
   }
   ```
   `ScraperWorkflow` 持有 `List<WorkflowHooks>`，`_notify()` 时派发；TraceRecorder（Phase 3）与 Stepper（Phase 2）都订阅它。
3. **ScraperWorkflowStepper**：8 阶段横向排布，当前阶段高亮 + 呼吸动画，已完成打勾，失败红叉，悬停/点击显示阶段耗时与关键计数（日志数/调试轮数）。
4. **AgentStepIndicator（共享）**：由 Agent 事件驱动，显示状态机：
   - 空闲 → "就绪"
   - turnStarted + 无工具 → "思考中…"
   - toolDispatch → "调用工具 `{name}` · 第 {step}/{maxSteps} 步"
   - toolResult 失败 → "工具 `{name}` 失败，正在处理…"
   - turnDone → 隐藏/归零
   视觉统一：4px 圆角进度条 + 标签（复用 `EvergreenProgress` 主题约定）。

### 验收标准
- `flutter test`：Stepper 渲染/状态切换、验收门槛拒绝路径、AgentStepIndicator 事件驱动用例
- 手工：运行一次完整抓取流程，进度条真实显示"调用工具 run_python_scraper · 第 3/50 步"而非假转圈

---

## 四、Phase 3：AI History + Trace 视图（需求 3）

### 目标
记录 Agent 历史（按 round 分组的工具/思考/回复三类事件），提供笔记本横线风格的 Trace 视图，可随时切换进出。

### 改动文件
| 文件 | 改动 |
|---|---|
| `evg-base/lib/renderer/components/shared/trace/agent_trace_recorder.dart`（新） | 共享 Trace 记录器（纯 Dart，可单测） |
| `evg-base/lib/renderer/components/shared/trace/agent_trace_view.dart`（新） | 笔记本横线风格 Trace 视图 |
| `evg-base/lib/renderer/templates/scraper_modle/scraper_ai_panel.dart` | 头部加"对话 / 轨迹"切换；IndexedStack 保状态；接入 TraceRecorder |

### 数据模型（`AgentTraceRecorder`）
- 订阅 Agent 事件流，`turnStarted → turnDone` 为一个 round：
  ```dart
  class TraceRound {
    int roundNo;
    DateTime startedAt;
    List<TraceEvent> events; // tool / think / reply
    Duration totalElapsed;
    bool hasError;          // 本 round 是否含 [error]
  }
  sealed class TraceEvent {
    TraceKind kind;         // tool | think | reply
    DateTime at;
  }
  class TraceToolEvent extends TraceEvent {
    String toolName;
    String argsSummary;     // 主参数摘要（如 data_name=courses）
    String resultSummary;   // 结果摘要：行数/字节数/前 200 字符预览
    bool isError;           // → 前缀标记 [error]
  }
  class TraceThinkEvent extends TraceEvent {
    Duration elapsed;       // reasoning 首 delta → 结束 计时
    String summary;         // "思考 4.2s"（时长摘要）
  }
  class TraceReplyEvent extends TraceEvent {
    String preview;         // 正文预览（≤500 字符）
    int byteCount;          // UTF-8 字节数
  }
  ```
- 工具事件的数据来源：Phase 1 的 `ScraperHooks.postToolUse` 摘要 + `toolDispatch/toolResult` 事件兜底（隔离 Agent 均可用）
- 存储：内存环形缓冲（默认 500 事件）+ 可选 JSON 落盘（`scraper_trace.json`，复用 50KB 单消息/1MB 整体保护）

### 视图设计（`AgentTraceView`）
- **笔记本横线风格**：底色近白/近纸色，细灰横线按行绘制（低对比灰，`onSurface.withValues(alpha: 0.08)`）
- **粗线分轮次**（`Round N · 12.3s · 5 events` 标题行 + 2px 分隔线），**细线分事件**（0.5px）
- **固定宽度前缀列**（`● tool` / `● think` / `● reply`，等宽、左对齐、列宽固定如 64px）+ 内容列严格对齐
- **`[error]` 标记**：红色高亮（工具失败事件行前缀 `● tool [error]`）
- 空态："暂无轨迹，开始一次对话后自动记录"
- 随时进出：与对话视图 IndexedStack 并存，切换不丢滚动位置/状态

### 验收标准
- `flutter test`：Recorder 分组/摘要/字节数/error 标记用例；View 渲染快照用例
- 手工：跑一轮含工具调用的对话 → 切"轨迹"→ 看到按轮分组的三类事件、[error] 红标、笔记本横线样式

---

## 五、Phase 4：AI 探索机制（需求 4 · 模式 B）

### 目标
用户完成登录后，手动切到探索模式，AI 仅以 GET 探索当前站 → 细粒度归类候选数据源 → 用户多选 → 逐一构建 → 批量注册一批同 web 数据源。

### 改动文件
| 文件 | 改动 |
|---|---|
| `evg-base/lib/renderer/templates/scraper_modle/explore/explore_workflow.dart`（新） | 探索状态机（idle → exploring → categorizing → confirming → building → registering → done/failed，含上限/节流计数） |
| `evg-base/lib/renderer/templates/scraper_modle/explore/scraper_explore_tools.dart`（新） | 探索工具集 + GET 守卫 |
| `evg-base/lib/renderer/templates/scraper_modle/scraper_webview.dart` | 补 JS 执行通道：Windows `executeScript`（webview_windows 提供）+ Android `runJavaScript` 已有；暴露给探索工具 |
| `evg-base/lib/renderer/templates/scraper_modle/scraper_generator_view.dart` | 模式切换器（定向 / 探索），IndexedStack 保状态 |
| `evg-base/lib/renderer/templates/scraper_modle/scraper_ai_panel.dart` | 探索模式复用隔离 Agent（注入探索工具集 + 探索 Skill）；构建/注册阶段复用 `_generatePlugin`/`_hotRegister` |
| `evg-base/lib/renderer/templates/scraper_modle/explore/explore_panel.dart`（新） | 探索进度面板 + 归类多选对话框 + 批量构建进度 |

### 探索工具集（仅模式 B 注册）
| 工具 | 行为 | 守卫 |
|---|---|---|
| `explore_page_links()` | JS 枚举当前页 `a[href]` / `button` / 可点击 GET 元素 → 返回结构化列表（text/href/selector） | 只枚举，不点击 |
| `navigate_get(url)` | 在 WebView 中导航到该 GET 链接 | **仅 http(s) GET**；非 GET / 表单提交 / javascript: 协议 → `[error: 探索仅允许 GET]`；同域校验；页数 ≤20；1s 节流 |
| `list_captured_requests()` | 读探索期间自动捕获的请求日志（复用现有 CDP/JS 捕获） | 只读 |
| `present_data_sources(candidates)` | 把 AI 归类结果提交给 UI → 弹多选对话框 | 仅确认前展示 |
| `build_selected_source(name)` / `register_batch()` | 复用 `_generatePlugin` / `_hotRegister` 逐源构建、批量注册 | 构建阶段才启用（探索阶段禁用） |

**探索阶段禁用的工具**：`run_terminal_command`、`save_credential`、`run_python_scraper`、`export_and_register_scraper`——由 `ExploreWorkflow` 阶段的工具白名单 + `ScraperGate` 双层强制。

### 流程（ExploreWorkflow）
1. `idle`：用户切探索模式，点"开始探索"（提示：请先完成登录）
2. `exploring`：AI 循环 `explore_page_links` → `navigate_get` → `list_captured_requests`，直到无新 GET 链接或触达上限（20 页 / 50 请求），期间 Trace 全程记录
3. `categorizing`：AI 分析捕获的 URL/请求/页面结构，产出**细粒度候选数据源** JSON（`{name, displayName, category, url, method: GET, fields[]}`，如 `courses 列表` / `score 查询` / `announcements`）
4. `confirming`：`present_data_sources` → UI 多选对话框（勾选 + 可改名称），用户确认
5. `building`：逐源执行现有构建路径（`data-{name}` 目录 + scraper.py + manifest + config），每源一个插件目录
6. `registering`：逐源 `_hotRegister`（或批量调用 `registerDataSourcesFromManifest`），汇总 `orch.get` 验证全部源，结果回灌 AI + UI 汇总
7. `done` / `failed`：批量结果展示（每源：目录、类型名、验证状态）

### 验收标准
- `flutter test`：ExploreWorkflow 状态机/上限/节流、GET 守卫拒绝路径（POST/non-http/js:）、工具白名单阶段切换
- 手工（本地起一个测试站）：登录 → 切探索模式 → 开始探索 → 看到归类多选 → 勾 2-3 个源 → 批量构建注册 → 数据看板出现一批新数据源且 `orch.get` 全部通过

---

## 六、风险与注意

1. **webview_windows `executeScript`**：需确认该包版本提供此 API；若缺失，探索工具降级为"仅枚举当前页 + 复用现有捕获日志"，导航由 UI 按钮触发（Phase 4 内先做技术验证 spike）
2. **探索的 LLM 成本**：20 页/50 请求的上限是默认值，配置项暴露在 settings；探索 Skill 提示词要求 AI 批量 `explore_page_links` 而非逐链接跳转，减少轮次
3. **会话持久化**：探索产生的候选/结果建议落盘（`.greenix/workspaces/<moduleId>/scraper_output/explore_*.json`），防刷新丢失
4. **不与现有流程冲突**：模式 A 现有代码路径零改动语义（仅 Phase 1/2 的守卫与进度增强），模式 B 完全新增目录 `explore/`
5. **Trace 内存上限**：500 事件环形缓冲 + 落盘截断，避免复现 scraper_sessions.json 8MB 事故

---

## 七、Phase 交付顺序与工作量预估

| Phase | 内容 | 预估改动文件 | 依赖 |
|---|---|---|---|
| 1 | Agent 守卫接线 + 终端命令白名单 | 5 改 + 1 新 | 无 |
| 2 | 工作流工程化 + Stepper + 统一进度 | 4 改 + 2 新 | Phase 1 |
| 3 | Trace 记录器 + 视图 + scraper 接入 | 1 改 + 2 新（共享） | Phase 1（hooks 摘要）、Phase 2（事件） |
| 4 | 探索模式（双模式 + 工具集 + 批量） | 4 改 + 4 新 | Phase 1（守卫）、Phase 2（状态机）、Phase 3（trace 记录探索过程） |

每 Phase 交付：实现 + 测试 + 手工回归，确认后再进入下一 Phase。
