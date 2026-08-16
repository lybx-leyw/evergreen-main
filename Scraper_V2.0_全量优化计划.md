# Scraper V2.0 全量优化计划（重写版 · 按拓扑顺序划分 Phase）

> 状态：**v1.0 草案，待用户审核**
> 取代：`scraper_v2.0_改造PLAN.md`（旧 4 Phase 划分）与 `Phase1-PLAN.md`（旧 Phase 1 详设）
> 重写原因：旧划分未按拓扑顺序——Phase 1（守卫）依赖 Phase 2（workflow 事件）、Phase 3（Trace）、Phase 4（探索），无法按序交付。本版按**依赖拓扑**重排，每个 Phase 只依赖前序 Phase 的产出，可独立验收。
>
> **全部已确认决策（来自多轮用户确认）**：
> 1. 假数据检测：warning 放行 + 回灌修正，不阻断执行；但 **workflow 在推进 done/注册时卡住**（G5 门禁）
> 2. import 白名单：严格 stdlib + requests
> 3. 终端命令：黑名单硬拒（不进弹窗）/ 白名单自动 / 其余弹窗确认
> 4. 凭证 key：允许任意 key，校验合法性 + 长度，prompt 引导功能简写
> 5. write_file 缺失：仅修 prompt
> 6. 假数据门禁弹窗：**AI 澄清后即弹**，展示守卫原因 + AI 澄清文本，用户裁决放行/拒绝
> 7. **AskTool 移植**：强化 core/agent 底座（借鉴 `D:\green_ds\DeepSeek-Reasonix\internal\agent\ask.go`）
> 8. **AI Guardian 同时移植**：借鉴 `reasonix/internal/guardian/guardian.go`（AI 子代理审查）
> 9. 阶段级回退：AI 自主回退到已完成阶段，UI 可见回退轨迹；前进必须重过验收
> 10. 门语义：**显式 tool 审核 + 另调 API 对 AI 的 trace 和产物进行审核**
> 11. 日志快照：显式「确认操作完毕」按钮 → 冻结快照 → **锁定 WebView**；重抓需确认框 → WebView 回首页 → 重启抓取
> 12. done 可被反馈重新激活：用户对话反馈 → AI 检测 → 进 refining（debugging 路线），不重新抓包
> 13. 迭代轮次：不设硬上限，仅展示轮次
> 14. 调试轮次：**连续 3 轮失败 → warning** 提示 AI 换策略（探索未暴露接口），非 5 轮预算；warning 后继续、反复提醒
> 15. 打断：**停止按钮 + 阶段保留**（Controller.cancel）
> 16. 探索衔接：Phase 1 只留提示文案，探索工具最后 Phase 落地
> 17. **多画板支持**：每个画板 = 沙盒 = 独立任务，**任务绝不交叉**；同一项目日志单快照 + 产物保留
> 18. 多画板形态：**每画板独立 WebView**
> 19. 画板内选模式（定向/探索）
> 20. 画板持久化：**重启恢复画板**
> 21. Trace：组件共享化，先只接 scraper；三类事件按 round 分组；[error] 标记；笔记本横线风格；随时切换
> 22. 探索守卫：同域 + 20 页 + 50 请求 + 1s 节流
> 23. 批量注册：每源一个插件目录 `data-{name}`
> 24. 探索与定向是**两种并列模式**，手动选择

---

## 一、拓扑依赖图（重划分依据）

```
core/agent 底座（AskTool / Gate·Hooks 接线 / cancel）
        │
        ▼
ScraperWorkflow 工程化（快照/验收门/回退/refining/调试轮次/guardFlags）
        │
        ├──────────────────────┐
        ▼                      ▼
守卫规则（命令白名单/lint/凭证）    （依赖 workflow 状态）
        │                      │
        ▼                      ▼
workflow×harness 集成     多画板 + 可视化（Stepper/AgentStepIndicator）
（G5 门禁/G6 防线/AI 回退）      │
        │                      │
        └──────────┬───────────┘
                   ▼
        Trace（Recorder + View）—— Trace 喂给 Guardian
                   │
                   ▼
        Guardian（AI 审查 trace+产物，门禁自动 + AI 显式调用）
                   │
                   ▼
        AI 探索模式（WebView JS 通道 + ExploreWorkflow + GET 守卫 + 批量注册）
```

**依赖规则**：每个 Phase 只 import 前序 Phase 的产出。跨 Phase 的接口（TraceRecorder 数据模型、Guardian 审查输入）在本计划 §六 提前定义，实现时按序落地。

---

## 二、Phase 划分总览

| Phase | 名称 | 对应需求 | 核心产出 | 依赖 |
|---|---|---|---|---|
| **1** | core 底座 + Workflow×Harness 一体化 | 需求 1（主体） | AskTool / Gate·Hooks 接线 / workflow 工程化 / 守卫规则 / G5·G6 门禁 | 无 |
| **2** | 多画板 + 可视化 | 需求 2 + 画板架构 | 多画板沙盒（独立 WebView/会话/快照/持久化）+ Stepper + 统一进度 | Phase 1 |
| **3** | Trace + Guardian | 需求 3 + 需求 1（AI 审查层） | TraceRecorder/View（共享）+ Guardian AI 审查 | Phase 1·2 |
| **4** | AI 探索模式 | 需求 4 | WebView JS 通道 + ExploreWorkflow + GET 守卫 + 归类多选 + 批量注册 | Phase 1·2·3 |

---

## 三、Phase 1：core 底座 + Workflow×Harness 一体化

### 3.1 目标
core/agent 补上守卫调用链的接线，移植 AskTool；ScraperWorkflow 工程化（快照/验收/回退/refining/调试轮次/guardFlags）；落地确定性守卫规则（命令白名单、lint、凭证校验）；G5 假数据门禁 + G6 注册防线；prompt 修正。

### 3.2 core/agent 底座（3 项）

| 改动 | 文件 | 内容 | 借鉴 |
|---|---|---|---|
| **Gate/Hooks 接线** | `core/agent/agent_factory.dart`、`core/agent/controller/controller.dart` | `AgentAssembly.fromConfig` 与 `Controller` 增加 `gate`/`hooks` 参数，`send()` 创建 Agent 时传入；core 层只加参数不引 Flutter | — |
| **AskTool 移植** | `core/agent/tools/ask_tool.dart`（新）+ `event.dart`（已有 askRequest） | `AskTool`：结构化多选提问（1-4 问，header/question/options/multiSelect），经 `Asker` 接口到达 UI；headless 返回"模型假设回退"不阻塞 | `reasonix/internal/agent/ask.go` |
| **cancel 打通** | `controller.dart`（已有 cancel）+ scraper UI | AI 面板加「停止」按钮调 `Controller.cancel()`，当前阶段保留 | — |

### 3.3 ScraperWorkflow 工程化（`scraper_workflow.dart` 重构）

新增机制（全部纯 Dart，可单测）：

| 机制 | 说明 |
|---|---|
| **阶段时间戳/耗时** | 每次转换记录 `enteredAt/elapsed`，`phaseTimeline` 供可视化（Phase 2）与 Trace（Phase 3）消费 |
| **验收门槛 G1-G4** | `capturing→analyzing` 需快照非空；`analyzing→generating` 需 schema 就绪；`running→done` 需执行通过 + JSON 校验；violation 拒绝转换 + 原因回灌 |
| **日志快照（决策 11）** | `snapshot()` 冻结当前 logs；`confirmCaptureDone()` 由「确认操作完毕」按钮触发 → 冻结 + 锁定 WebView（回调 UI）；`restartCapture()` 需确认框 → 回首页 → 清日志重启 |
| **guardFlags（决策 1/6）** | `suspectedFakeData` 等标记；`markDone()` 检查 → 有则触发 G5 弹窗流程 |
| **G5 假数据门禁** | `onUserConfirmRequest(GuardReason, aiClarification)` 回调 → UI 弹窗（守卫原因 + AI 澄清）→ 用户放行（清标记进 done）/ 拒绝（转 debugging 回灌） |
| **阶段级回退（决策 9）** | `rollbackTo(ScraperPhase)`：AI 可自主回退到已完成阶段，`rollbackHistory` 记录轨迹（UI 可见）；**回退后前进必须重过该阶段验收** |
| **refining 循环（决策 12）** | `done` 非终态：`feedbackTriggered()` 检测用户反馈 → 进入 `debugging`（复用调试路线），快照与产物保留 |
| **调试轮次（决策 14）** | 移除 5 轮预算 → `consecutiveFailures` 计数，**连续 3 轮失败 → warning 事件**（文案提示换策略：探索未暴露接口 / 询问用户），warning 后继续、每轮重申 |
| **awaitingUserConfirm 子状态** | G5 弹窗 / 命令弹窗 / save_credential 弹窗期间 workflow 处于该子状态，事件流不丢 |

### 3.4 守卫规则（`scraper_guard.dart` 新建，纯函数可单测）

| 规则 | 内容 | 决策 |
|---|---|---|
| `isTerminalCommandBlocked/Allowed` | 黑名单（`rm`/`del`/`rmdir`/`format`/`shutdown`/`reboot`/`taskkill`/拼接 `;&&|||><`/读取 `type cat Get-Content`/外联 `curl wget nc`/`python -c`）；白名单（`python scraper.py`/`pip install <pkg>`/`cd <dir>`/`python -m pip ...`） | 决策 3 |
| `lintScraperCode` → `{violations[], warnings[]}` | **violation**：模板缺失（无 `_get_config`/无三级降级）/残留占位符/危险 import（os-system 类、subprocess、socket、ctypes、pickle、base64、pty、importlib、非 stdlib）/危险调用（`os.system`、`eval(`、`exec(`、`__import__`、open 逃逸）/凭证硬编码（`USERNAME='字面量'`）/无 `__main__`/main 不返回 dict-list；**warning**（假数据启发式）：无网络库却输出数据 / `print(json.dumps([{...}]))` 字面量直出 / 代码 URL ∩ 捕获日志 URL 为空 / 占位符数据 | 决策 1·2 |
| `validateCredentialArgs` | key 无路径/换行/控制字符/`=`，≤128；value ≤8KB；不强制前缀 | 决策 4 |
| **G6 注册防线** | `export_and_register_scraper` 前强制 lint：violation → 拒绝注册；`suspectedFakeData` 未清除 → 拒绝注册并回灌 | 决策 1 |

### 3.5 接线与 UI（`scraper_ai_panel.dart` / `scraper_generator_view.dart`）

- 注入 `ScraperGate`（pendingCallback：命令黑名单硬拒 / 白名单自动 / 其余弹窗；save_credential 弹窗 value 打码）+ `ScraperHooks`（pre：lint/命令/凭证校验；post：结果摘要写 TraceRecorder 缓冲接口）
- AI 面板加「停止」按钮（cancel + 阶段保留）
- 「确认操作完毕」按钮（快照冻结 + WebView 锁定）；重抓确认框
- G5 弹窗（守卫原因 + AI 澄清文本 + 放行/拒绝）
- prompt 修正（`scraper_skill_const.dart`）：`write_file` → `run_python_scraper`；守卫说明；假数据红线；凭证 key 功能简写

### 3.6 验收标准
- `dart test`：守卫纯函数（命令 12+ / lint 16+ / 凭证 5+）；workflow（快照/回退/refining/3轮 warning/G5 门禁 15+）；core（Gate·Hooks 透传回归）
- 手工：完整定向抓取跑通；假数据被 G5 卡住（弹窗裁决两分支）；命令黑名单硬拒、白名单自动、其余弹窗；打断保留阶段

---

## 四、Phase 2：多画板 + 可视化

### 4.1 目标
画板化架构（每画板 = 独立 WebView + workflow + 会话 + 快照，任务绝不交叉，重启恢复）；workflow 可视化（Stepper）+ 统一进度指示器（事件驱动）。

### 4.2 多画板（决策 17·18·19·20）

| 文件 | 内容 |
|---|---|
| `scraper_modle/board/scraper_board.dart`（新） | `ScraperBoard` 模型：`{id, name, mode(定向/探索), workflow, sessionId, snapshotRef, createdAt, updatedAt}` |
| `scraper_modle/board/board_container_view.dart`（新） | 顶部画板 Tab 栏（新建/关闭/切换）+ `IndexedStack` 保状态；**每画板独立 WebView** |
| `scraper_modle/board/board_store.dart`（新） | 持久化：`.greenix/workspaces/<moduleId>/boards.json`（元数据 + 快照引用 + 会话引用），重启恢复画板列表与状态 |
| `scraper_generator_view.dart` | 重构为画板容器；画板内模式选择（定向/探索，探索 UI Phase 4 落地，先留模式位） |

**隔离保证**：每画板独立 WebView 实例、独立 `ScraperWorkflow`、独立 Agent 会话（`scraper_sessions.json` 按画板分文件或分 key）；**不同画板日志/快照/产物引用绝不交叉**；同一画板内日志单快照 + 产物保留。

### 4.3 可视化

| 文件 | 内容 |
|---|---|
| `scraper_modle/scraper_workflow_stepper.dart`（新） | 横向步骤条：8 阶段，当前态高亮 + 动画，已完成打勾/失败红叉，悬停显示耗时与关键计数；数据来自 `workflow.phaseTimeline`（Phase 1 产出） |
| `renderer/components/shared/widgets/agent_step_indicator.dart`（新，共享） | 事件驱动统一进度：空闲"就绪"/思考中/「调用工具 `{name}` · 第 n/50 步」/工具失败处理中/turnDone 归零；替换 scraper 内 6+ 处裸进度条（复用 `EvergreenProgress` 主题约定） |

### 4.4 验收标准
- `flutter test`：board 模型/持久化/隔离（互不交叉 8+）；Stepper 渲染与状态；AgentStepIndicator 事件驱动
- 手工：建 3 画板各跑不同站点互不干扰；重启恢复画板；进度条真实显示当前工具与步骤

---

## 五、Phase 3：Trace + Guardian

### 5.1 目标
共享 Trace 组件（记录 + 笔记本风格视图，先接 scraper）；移植 Guardian（AI 子代理审查 trace+产物，门禁自动 + AI 显式调用）。

### 5.2 Trace（决策 21）

| 文件 | 内容 |
|---|---|
| `renderer/components/shared/trace/agent_trace_recorder.dart`（新） | 订阅 Agent 事件流，`turnStarted→turnDone` 分组；三类事件：`TraceToolEvent`（工具名+主参数摘要+结果摘要[行数/字节数/前200字符]+isError→[error] 标记）、`TraceThinkEvent`（reasoning 首 delta→结束 计时 → "思考 4.2s"）、`TraceReplyEvent`（预览≤500 字符 + UTF-8 字节数）；内存环形缓冲 500 + 可选 JSON 落盘（复用 50KB/1MB 保护） |
| `renderer/components/shared/trace/agent_trace_view.dart`（新） | 笔记本横线风格（粗线分轮次/细线分事件/低对比灰）；固定宽度前缀列（`● tool`/`● think`/`● reply`）+ 内容列对齐；`[error]` 红色标记；空态提示 |
| `scraper_ai_panel.dart` | 头部「对话/轨迹」切换（IndexedStack 保状态）；接入 Recorder（数据源：Phase 1 `ScraperHooks.postToolUse` 摘要 + 事件流） |

### 5.3 Guardian（决策 8·10，借鉴 `reasonix/internal/guardian/guardian.go`）

| 文件 | 内容 |
|---|---|
| `core/agent/guardian/guardian.dart`（新） | `GuardianSession`：独立 LLM 会话 + 安全策略 prompt（`guardian_policy.md` 移植精简版）+ 只读工具集；`Review(toolName, args, parentSession)` → JSON 裁决 `{risk_level, user_authorization, outcome(allow/deny), rationale}`；circuit breaker（连续 3 deny → 中断提示）；transcript 增量维护控制成本 |
| `core/agent/tools/guardian_review_tool.dart`（新） | **显式 tool 审核**：`guardian_review(target)` 供 AI 主动调用（审当前 trace 摘要 + 产物） |
| `scraper_ai_panel.dart` / workflow | **门禁自动触发**：G5（假数据门禁前）/ G6（注册前）自动调 Guardian 审「关键 trace（工具序列摘要 + 违规记录）+ 产物（scraper.py/manifest/config）」→ 裁决 allow 放行 / deny 回退 debugging + 回灌 rationale |
| `scraper_skill_const.dart` | prompt 增加 guardian_review 工具说明与使用时机 |

**成本控制**（决策：审产物+关键 trace，单次 LLM 调用）：Guardian 输入 = trace 摘要（截断）+ 产物（截断），一次调用；transcript 只维护增量；circuit breaker 防死循环。

### 5.4 验收标准
- `dart test`：TraceRecorder（分组/摘要/字节数/[error] 8+）；Guardian（裁决解析/deny 回灌/circuit breaker 5+）
- 手工：跑一轮对话切「轨迹」见笔记本风格三类事件；假数据场景下 G5 前 Guardian 给出 deny + rationale，AI 据此修正

---

## 六、Phase 4：AI 探索模式（需求 4）

### 6.1 目标
模式 B 完整闭环：用户登录后手动切探索模式 → AI 仅 GET 探索当前站 → 细粒度归类 → 多选确认 → 逐一构建 → 批量注册。

### 6.2 改动文件

| 文件 | 内容 |
|---|---|
| `scraper_webview.dart` | 补 JS 执行通道：Windows `executeScript`（webview_windows 提供，先 spike 验证）+ Android `runJavaScript` 已有；暴露给探索工具 |
| `scraper_modle/explore/explore_workflow.dart`（新） | `ExploreWorkflow`：idle → exploring → categorizing → confirming → building → registering → done/failed；含页数/请求数/节流计数 |
| `scraper_modle/explore/scraper_explore_tools.dart`（新） | `explore_page_links()`（JS 枚举 a[href]/button）/ `navigate_get(url)`（仅 http(s) GET；**守卫拒绝**非 GET/表单提交/js: 协议 → `[error: 探索仅允许 GET]`；同域/≤20 页/1s 节流）/ `list_captured_requests()` / `present_data_sources(candidates)`（归类结果 → UI 多选）/ `build_selected_source(name)`（复用 `_generatePlugin` 路径）/ `register_batch()`（逐源 `_hotRegister` + `orch.get` 汇总验证） |
| `scraper_modle/explore/explore_panel.dart`（新） | 探索进度面板 + 归类多选对话框（复用 showDialog 模式）+ 批量构建进度 |
| `scraper_generator_view.dart` / `board_container_view.dart` | 画板内模式切换（定向/探索）落地；探索阶段工具白名单（禁用 `run_terminal_command`/`save_credential`/`run_python_scraper`/`export_and_register_scraper`） |
| `scraper_skill_const.dart` | 探索 Skill 提示词（仅 GET、批量 explore_page_links 减少轮次、归类格式、构建/注册流程） |

### 6.3 流程
1. `idle`：用户切探索模式，点「开始探索」（提示先完成登录）
2. `exploring`：AI 循环 `explore_page_links` → `navigate_get` → `list_captured_requests`，直到无新链接或触达上限（20 页/50 请求），全程 Trace 记录（Phase 3 能力）
3. `categorizing`：AI 聚合成候选数据源 JSON（name/displayName/category/url/method:GET/fields[]）
4. `confirming`：`present_data_sources` → UI 多选（勾选 + 可改名）→ 用户确认
5. `building`：逐源 `data-{name}` 目录 + scraper.py + manifest + config（复用 `_generatePlugin`，每源一个插件目录——决策 23）
6. `registering`：逐源 `_hotRegister` + `orch.get` 验证，汇总回灌 AI + UI
7. `done`/`failed`：批量结果展示

### 6.4 验收标准
- `flutter test`：ExploreWorkflow 状态机/上限/节流；GET 守卫拒绝路径（POST/non-http/js:）；工具白名单阶段切换
- 手工（本地测试站）：登录 → 探索 → 归类多选 → 勾 2-3 源 → 批量构建注册 → 数据看板出现新数据源且 orch.get 全通过

---

## 七、跨 Phase 共享接口（提前定义，按序实现）

```dart
// Phase 1 产出，Phase 3 消费
abstract class TraceBuffer {
  void recordTool(String tool, String argsSummary, String resultSummary, {bool isError});
  void recordThink(Duration elapsed);
  void recordReply(String preview, int byteCount);
  List<TraceRound> rounds(); // turnStarted→turnDone 分组
}

// Phase 1 产出，Phase 3 消费
class GuardResult { final List<String> violations; final List<String> warnings; }
// Phase 3 产出，Phase 4 消费
class CandidateDataSource { final String name, displayName, category, url; final List<String> fields; }
```

## 八、风险与注意

1. **webview_windows `executeScript`**：Phase 4 前做 spike 验证；缺失则探索降级"仅枚举当前页 + 复用捕获日志"，导航由 UI 按钮触发
2. **Guardian 成本**：transcript 增量 + 截断 + circuit breaker 控制；失败时降级为规则守卫裁决（fail-closed 到用户弹窗）
3. **多画板内存**：每画板独立 WebView 实例开销大 → 后台画板懒加载/回收策略（如非活跃画板 WebView 挂起）
4. **静态启发式误报**（纯静态 JSON 页）→ G5 弹窗用户裁决兜底 + Guardian 二次审查
5. **core 层隔离**：`scraper_guard.dart` 在 renderer 层；core 只加透传参数与 AskTool/Guardian（不引 Flutter）
6. **会话大小保护**：沿用 50KB 单消息 / 1MB agentSessionJson 保护，Trace 落盘同样截断

## 九、交付顺序

| Phase | 预估改动 | 交付物 |
|---|---|---|
| 1 | core 3 改 + workflow 重构 + guard 新建 + UI 接线 | 守卫体系 + 工程化 workflow |
| 2 | board 3 新 + 可视化 2 新 + 重构 | 多画板 + 统一进度 |
| 3 | trace 2 新 + guardian 2 新 + 接入 | Trace 视图 + AI 审查 |
| 4 | explore 4 新 + webview 扩展 + 接入 | 探索模式闭环 |

每 Phase：实现 + 测试 + 手工回归，确认后再进下一 Phase。
