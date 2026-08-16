# Scraper V2.0 全量重构计划（完整版 · 需求全量归档 + Reasonix 移植清单）

> 状态：**v2.0 草案，待用户审核**
> 定位：**重构整个 scraper 插件底层实现**（非增量优化）。当前 `scraper_modle/` 的 13 个文件是围绕"单画板定向抓取"长出来的草稿箱结构，本次按「workflow×harness 强化 Agent」目标整体重排。
> 取代：`scraper_v2.0_改造PLAN.md`、`Phase1-PLAN.md`、`Scraper_V2.0_全量优化计划.md`（v1.0）
> 参考实现：**`D:\green_ds\DeepSeek-Reasonix`**（Go）——本项目 `core/agent` 本就是其 Dart 移植（代码注释大量标注"对应 reasonix/internal/..."），本次所有可移植机制**优先移植而非重造**，见 §四 移植清单。

---

## 一、需求全量归档（防遗忘 · 全部编号）

> 所有需求来自多轮讨论，均已确认或标注状态。实施时逐条对照，防止遗漏。

### A. 需求 1：Harness 工程化（hook / guard / 可靠性）

| # | 需求 | 状态 |
|---|---|---|
| A1 | 工作流更可靠、更可视化；现有 workflow 是"草稿箱子"，需工程性重构 | ✅ 确认 |
| A2 | 添加 hook 机制、guard 机制等针对 scraper 场景的 harness 工程 | ✅ 确认 |
| A3 | **守卫要审查**：AI 有没有穿透、生成文件格式是否符合基本规范、有无硬编码虚假数据、脚本是否可以真实 work | ✅ 确认 |
| A4 | 深刻探索当前给 AI 的 prompt，理解 scraper 目标产物形态与约束，**硬编码做 hook** | ✅ 确认 |
| A5 | 假数据检测：warning 放行 + 回灌修正，**不阻断执行**；但 workflow 在推进 done/注册时卡住（G5 门禁），AI 无法拿假数据蒙混过关 | ✅ 确认 |
| A6 | import 白名单：**严格 stdlib + requests**；黑名单硬拒 os/subprocess/socket/eval 等 | ✅ 确认 |
| A7 | 终端命令：黑名单硬拒（不进弹窗）/ 白名单自动 / 其余**弹窗确认** | ✅ 确认 |
| A8 | 凭证 key：允许任意 key（**动机：不想要设置里出现一大堆 SCRAPER**），校验合法性+长度，prompt 引导含功能简写 | ✅ 确认 |
| A9 | write_file 缺失：仅修 prompt（改为 run_python_scraper 写盘） | ✅ 确认 |
| A10 | 假数据门禁弹窗：**AI 澄清后即弹**，展示守卫原因 + AI 澄清文本，用户裁决放行/拒绝 | ✅ 确认 |
| A11 | **AskTool 移植**：强化 core/agent 底座，AI 随时可结构化 ask 用户 | ✅ 确认 |
| A12 | **AI Guardian 同时移植**：AI 子代理审查工具调用，审 trace + 产物 | ✅ 确认 |
| A13 | 门语义：**显式 tool 审核**（`guardian_review` 工具，AI 可主动调用）+ **另调 API 对当前 AI 的 trace 和产物进行审核**（G5/G6 门禁自动触发独立 LLM 会话） | ✅ 确认 |
| A14 | 阶段级回退：AI 自主回退到已完成阶段，UI 可见回退轨迹；前进必须重过验收 | ✅ 确认 |
| A15 | 调试轮次：本质是**防 AI 自循环的 guard**；**连续 3 轮失败 → warning**（提示换策略：用网页探索能力探索用户未暴露的接口/问用户），非 5 轮预算；warning 后继续、每轮失败重申 | ✅ 确认 |
| A16 | done 可被反馈重新激活：**当前产物已满足用户需求的 MVP**，用户对话反馈 → refining（debugging 路线，处理反馈的 debug/优化改进），**不重新抓包** | ✅ 确认 |
| A17 | 打断：**停止按钮 + 阶段保留**（Controller.cancel），用户补充要求后从当前阶段继续或自主回退，**整个 workflow 结构不变** | ✅ 确认 |
| A18 | 日志快照：用户操作完一次 → **全量快照保存**；显式「确认操作完毕」按钮 → 冻结快照 → **锁定 WebView**（日志不再更新，即便用户在操作）；**AI 随时可调用工具阅读快照**（A26）；**AI ask 指出需重新走一遍 → 触发确认框** → 同意后 WebView 回首页 → 重启日志抓取和确认流程 | ✅ 确认 |
| A19 | 迭代轮次：不设硬上限，仅展示轮次 | ✅ 确认 |
| A20 | 探索衔接：Phase 1 只留提示文案，探索工具最后 Phase 落地 | ✅ 确认 |
| A21 | **多画板支持**：每画板 = 沙盒 = 独立任务，任务绝不交叉；同一项目日志单快照 + 产物保留 | ✅ 确认 |
| A22 | 多画板形态：**每画板独立 WebView** | ✅ 确认 |
| A23 | 画板内选模式（定向 / 探索） | ✅ 确认 |
| A24 | 画板持久化：**重启恢复画板** | ✅ 确认 |
| A25 | AI 走 workflow 但**不是无人值守**：AI 随时可 ask、用户随时可打断补充要求、AI 可无条件回退到已完成步骤、但不能不经 harness 验收就 step 到下一步；本质是"特定场景 workflow×harness 强化的 Agent" | ✅ 确认 |
| A26 | **AI 随时可调用工具阅读日志快照**：`read_request_snapshot` 工具（AI 读取冻结快照，非仅 UI 可见） | ✅ 确认（第 3 轮 Q2 补充） |
| A27 | 探索与定向是两种模式：**不同工作流 + 不同 harness 约束**，手动选择 | ✅ 确认（并入 D9） |

### B. 需求 2：Workflow 可视化 + 统一进度

| # | 需求 | 状态 |
|---|---|---|
| B1 | 添加 workflow 可视化图 | ✅ 确认 |
| B2 | 统一各个位置的进度条，**确保真实反映 AI 每一步**（不是假转圈） | ✅ 确认 |

### C. 需求 3：AI History + Trace 视图

| # | 需求 | 状态 |
|---|---|---|
| C1 | 记录三种事件，按 agent 轮次（round）分组展示：工具调用（工具名+主参数+结果摘要如行数）、思考（时长摘要）、回复正文（预览+字节数） | ✅ 确认 |
| C2 | 可随时切换进/出该视图 | ✅ 确认 |
| C3 | 特殊标记 `[error]`：执行失败的工具调用 | ✅ 确认 |
| C4 | 视觉：平铺 + 笔记本横线风格（粗线分轮次、细线分事件、低对比灰）；每行固定宽度前缀列（`● tool` / `● think` / `● reply`），内容列对齐 | ✅ 确认 |
| C5 | Trace 组件**共享化**，先只接 scraper | ✅ 确认 |

### D. 需求 4：AI 探索机制

| # | 需求 | 状态 |
|---|---|---|
| D1 | 用户进入某网站并走完登录流程后，AI 可探索该 web 所有 GET 按钮 | ✅ 确认 |
| D2 | guard：**只允许 GET**，不允许 POST 等其它行为（避免不可控） | ✅ 确认 |
| D3 | 探索完毕后 AI 自动为数据做**非常细粒度的归类** | ✅ 确认 |
| D4 | 弹出**多选选择框**让用户选择要构建哪些数据源 | ✅ 确认 |
| D5 | 用户确认后 AI 逐一构建指定数据源的抓取包 | ✅ 确认 |
| D6 | 最终**注册一批次的多个同 web 数据源** | ✅ 确认 |
| D7 | 探索守卫默认：同域 + 20 页 + 50 请求 + 1s 节流（可配置） | ✅ 确认 |
| D8 | 批量注册形态：**每源一个插件目录 data-{name}** | ✅ 确认 |
| D9 | 探索模式与定向抓取是**两种并列模式**（**不同工作流状态机 + 不同 harness 约束**），手动选择 | ✅ 确认 |

### E. 工程/过程需求

| # | 需求 | 状态 |
|---|---|---|
| E1 | 全量改造分 Phase 完工，每 Phase 独立可验证 | ✅ 确认 |
| E2 | **按拓扑顺序划分 Phase**（旧划分 Phase 1 依赖 2~4，错误） | ✅ 确认 |
| E3 | 规模不亚于**重构整个 scraper 插件底层** | ✅ 确认 |
| E4 | **DeepSeek-Reasonix 为移植优先参考**，避免重复造轮子 | ✅ 确认 |
| E5 | 所有设计需求**归档防遗忘**（本文档 §一 即为归档） | ✅ 确认 |

---

## 二、当前 scraper 底层结构盘点（重构基线）

`evg-base/lib/renderer/templates/scraper_modle/` 现有 13 文件：

| 文件 | 职责 | 重构去向 |
|---|---|---|
| `scraper_generator_view.dart` | 主视图（dock 布局） | → 拆为 `view/` 容器 + 画板容器 |
| `scraper_webview.dart` | 内嵌浏览器 + CDP/JS 抓包 | → `web/`（加 JS 执行通道，Phase 4） |
| `scraper_workflow.dart` | 状态机（草稿箱） | → `workflow/` 工程化重构（Phase 1） |
| `scraper_ai_panel.dart` | 1400+ 行巨石（会话/事件/导出/注册/推断全在这） | → 拆为 `agent/` 多文件（Phase 1） |
| `scraper_tools.dart` | 7 个自定义工具 | → `agent/tools/` + 守卫注入 |
| `scraper_guard.dart` | （无，新建） | Phase 1 守卫纯函数 |
| `scraper_skill_const.dart` | Skill prompt | → prompt 修正（Phase 1） |
| `scraper_flow_facade.dart` | 门面 | → 保留/重构 |
| `scraper_exporter.dart` | 导出 .py/.exe + manifest | → 保留（产物契约源） |
| `scraper_json_validator.dart` | stdout JSON 校验 | → 保留（契约校验源） |
| `scraper_terminal.dart` | 终端 | → `view/terminal/` |
| `request_log_panel.dart` | 请求日志面板 | → `view/log_panel/` + 快照 UI（Phase 1） |
| `scraper_template.dart` | 模板入口 | → 保留 |

**目标目录结构（重构后）**：
```
scraper_modle/
├── scraper_template.dart          # 入口（不变）
├── board/                         # 多画板（Phase 2）
│   ├── scraper_board.dart         #   画板模型
│   ├── board_container_view.dart  #   画板容器
│   └── board_store.dart           #   持久化
├── workflow/                      # 工作流 × harness（Phase 1）
│   ├── scraper_workflow.dart      #   状态机（工程化重构）
│   ├── scraper_guard.dart         #   守卫纯函数（lint/命令/凭证）
│   ├── workflow_hooks.dart        #   工作流级 hook 接口
│   └── scraper_workflow_stepper.dart # 可视化（Phase 2）
├── agent/                         # 隔离 Agent（Phase 1 拆分）
│   ├── scraper_ai_panel.dart      #   面板（瘦身）
│   ├── scraper_hooks.dart         #   ScraperHooks（L2/L4）
│   ├── scraper_gate.dart          #   ScraperGate（L1）
│   └── tools/                     #   工具（+ ask/guardian_review 等）
├── explore/                       # 探索模式（Phase 4）
│   ├── explore_workflow.dart
│   ├── scraper_explore_tools.dart
│   └── explore_panel.dart
├── web/                           # 浏览器（含 JS 执行通道）
│   ├── scraper_webview.dart
│   └── cdp_network_client.dart
├── view/                          # 视图组件
│   ├── request_log_panel.dart
│   ├── scraper_terminal.dart
│   └── trace_toggle.dart          # 对话/轨迹切换（Phase 3）
├── scraper_flow_facade.dart
├── scraper_exporter.dart
├── scraper_json_validator.dart
└── scraper_skill_const.dart
```

---

## 三、拓扑依赖与 Phase 划分

```
core/agent 底座（AskTool / Gate·Hooks 接线 / cancel / Guardian 框架）
        │
        ▼
ScraperWorkflow 工程化（快照/验收门/回退/refining/调试轮次/guardFlags）
        │
        ├───────────────────────────┐
        ▼                           ▼
守卫规则（命令白名单/lint/凭证）      （依赖 workflow 状态）
        │                           │
        ▼                           ▼
workflow×harness 集成           多画板 + 可视化
（G5 门禁 / G6 防线 / AI 回退）      │
        │                           │
        └────────────┬──────────────┘
                     ▼
          Trace（Recorder + View）—— 喂给 Guardian
                     │
                     ▼
          Guardian（AI 审查 trace+产物）
                     │
                     ▼
          AI 探索模式（JS 通道 + ExploreWorkflow + GET 守卫 + 批量注册）
```

| Phase | 名称 | 对应需求 | 核心产出 | 依赖 | 状态 |
|---|---|---|---|---|---|
| **1** | core 底座 + Workflow×Harness 一体化 | A1-A18, A20, A25, E | AskTool / Gate·Hooks 接线 / workflow 工程化 / 守卫规则 / G5·G6 门禁 / prompt 修正 | 无 | ✅ 完成（用户确认） |
| **2** | 多画板 + 可视化 | A21-A24, B1, B2 | 画板沙盒（独立 WebView/会话/快照/持久化）+ Stepper + 统一进度 | Phase 1 | ✅ 完成（用户确认） |
| **3** | Trace + Guardian | C1-C5, A12, A13 | TraceRecorder/View（共享）+ Guardian AI 审查 | Phase 1·2 | ⏳ 下一步 |
| **4** | AI 探索模式 | D1-D9, A20 | JS 通道 + ExploreWorkflow + GET 守卫 + 归类多选 + 批量注册 | Phase 1·2·3 | 待定 |

---

## 四、DeepSeek-Reasonix 移植清单（优先移植 · 防重复造轮子）

> 来源：`D:\green_ds\DeepSeek-Reasonix\internal\`（Go）。本项目 `core/agent` 已是其 Dart 移植，移植时对照现有命名保持一致性。

| Reasonix 文件 | 机制 | 移植到 | 对应 Phase |
|---|---|---|---|
| `agent/ask.go` | **AskTool**：结构化多选提问（1-4 问，header/question/options/multiSelect），headless 回退不阻塞 | `core/agent/tools/ask_tool.dart`（新） | 1 |
| `event/event.go`（AskOption/AskQuestion/AskAnswer/GuardianResult） | 事件模型 | `core/agent/event.dart`（已有 askRequest，补 AskOption/AskAnswer/GuardianResult） | 1·3 |
| `permission/permission.go` | **纯 Policy**（Allow/Ask/Deny + Rule{Tool,Subject} 参数级规则）+ Gate + Approver | `core/agent/agent/gate.dart` 增强（现为 InteractiveGate 简版） | 1 |
| `permission/bash_approval.go` | **Bash 命令审批分类**：NestedExecution/DynamicCommandName/Expansion/Redirection → RequireHuman/ExactOnly/Reusable；间接执行识别（eval/source/env/python -c 等） | `scraper_guard.dart` 命令守卫（`isTerminalCommandBlocked/Allowed` 的权威逻辑） | 1 |
| `permission/bash_readonly.go` | 只读命令分类 | 同上 | 1 |
| `shellsafe/shellsafe.go` | 只读命令表 + 子命令表 + shell 语法检测（拼接/重定向防走私） | `scraper_guard.dart` 命令表 | 1 |
| `shellparse/bash.go` | Shell 静态解析（SplitTopLevel/StaticFields/ContainsShellSyntax） | Dart 侧移植为轻量 tokenizer（正则近似或完整解析，spike 决定） | 1 |
| `hook/hook.go` | **Hook 事件矩阵**：PreToolUse/PostToolUse/PostToolUseFailure/PermissionRequest/UserPromptSubmit/Stop/SessionStart/… + 阻塞语义（exit 2=block）+ match 正则 | `core/agent/agent/hooks.dart` 增强（现仅 LoggingHooks/NoOpHooks）+ `workflow_hooks.dart` | 1 |
| `guardian/guardian.go` | **GuardianSession**：独立 LLM 会话 + 安全策略 prompt + 只读工具 + `Review()` → JSON 裁决 + circuit breaker（连续 3 deny 中断）+ transcript 增量 | `core/agent/guardian/guardian.dart`（新）+ `guardian_policy.md`（精简移植） | 3 |
| `guardian/guardian_policy.md` | 安全审查策略提示词 | `core/agent/guardian/guardian_policy.md` | 3 |
| `trajectory/recorder.go` | 事件 JSONL 落盘（SchemaVersion/Seq/TS + 各类 audit） | `renderer/components/shared/trace/agent_trace_recorder.dart` 的落盘格式 | 3 |
| `checkpoint/`（atomic_json/transaction/barrier） | 事务式持久化（原子写/回滚） | `board_store.dart`（画板持久化） | 2 |
| `recovery/`（decision/rules/gate/persist） | 恢复决策（失败后如何续跑） | `workflow_hooks.dart` 回退/恢复语义参考 | 1·2 |
| `history/indexed.go` | 会话历史索引（时间/内容检索） | Trace 视图检索（可选增强） | 3 |
| `control/`（controller.go） | Controller 状态机（对应本项目 controller.dart，已移植） | 对照补 gate/hooks 透传 | 1 |

**移植原则**：
1. **先查先例**：core/agent 注释标注"对应 reasonix/internal/..."的即移植先例，新移植保持相同命名风格（蛇形、EventKind 对齐）
2. **核心优先**：Phase 1 移植 ask.go + permission/bash_approval + shellsafe + hook 矩阵；Phase 3 移植 guardian + trajectory
3. **Dart 化适配**：Go 并发模型 → Dart async/stream；shellparse 需 spike 决定完整移植或正则近似
4. **不引 Flutter**：core 层移植保持纯 Dart（stub 隔离模式沿用）

---

## 五、Phase 1 详设：core 底座 + Workflow×Harness 一体化

> **实现状态（2026 首轮交付）**：✅ 全部完成。测试 876 全绿（新增 44），analyze 0 error。
> 实现偏差记录（相对本详设）：
> - **目录暂不重组**：按用户决策"Phase 1 不动 UI 视觉"，文件保留在原 scraper_modle/ 平铺位置，
>   `workflow/`、`agent/`、`board/` 等子目录重组并入 Phase 2 画板容器时一次性做（避免无效 import 大改）
> - `ask_tool.dart` 实现为直接 `Tool` 接口（非 SimpleTool），以保留实例 asker 访问（SimpleTool 的 execute 是静态闭包）
> - `hooks.dart` 的 match 默认实现：`implements` 不继承接口默认实现，LoggingHooks/NoOpHooks/CompositeHooks 均显式实现
> - `scraper_workflow.dart` 用 `WorkflowCallback` typedef 替代 Flutter 的 VoidCallback（保持纯 Dart）
> - **G6 注册防线双保险**：除 `ScraperHooks.preToolUse` 的 guardFlags 兜底外，`_generatePlugin()`
>   在打包前对磁盘/内存代码执行完整 `lintScraperCode`——violation 拒绝注册 + 回灌违规清单，
>   假数据标记未清除拒绝注册（2026 补充强化）
> - **A5 修正语义修复**：`run_python_scraper` lint 无假数据 warning 时自动清除
>   `suspectedFakeData` 标记（此前只写不清，导致用户拒绝后 AI 修正仍被 G5 反复拦截）
> - **A19 refineCount 落地**：workflow 增加 refining 迭代轮次计数（不设硬上限，仅展示），
>   AI 面板反馈提示与底部状态栏展示轮次；restartCapture/reset 重置
> - **A15 状态栏语义修正**：底部状态栏"调试 x/5"改为"连续失败 n/3 + warning 橙标"，
>   对齐连续 3 轮 warning 机制；移除废弃的 _debugPhase getter
> - **完整编译回归通过**：`flutter build windows --debug` 产出 evergreen_base.exe（35s）

### 5.1 core/agent 底座（3 项，纯 Dart）

| 改动 | 文件 | 内容 | 移植源 |
|---|---|---|---|
| Gate/Hooks 接线 | `agent_factory.dart`、`controller/controller.dart` | `AgentAssembly.fromConfig` 与 `Controller` 增加 `gate`/`hooks` 参数，`send()` 创建 Agent 时传入 | permission/hook 对照 |
| AskTool | `core/agent/tools/ask_tool.dart`（新） | 结构化多选 1-4 问 + headless 回退；经 `Asker` 接口到 UI | agent/ask.go |
| Hook 矩阵增强 | `agent/hooks.dart` | 增加 `PostToolUseFailure`/`PermissionRequest` 事件位 + match 正则 | hook/hook.go |

### 5.2 ScraperWorkflow 工程化（`workflow/scraper_workflow.dart`）

| 机制 | 说明 | 需求 |
|---|---|---|
| 阶段时间戳/耗时 | `phaseTimeline` 供可视化（Phase 2）与 Trace（Phase 3） | B1/C1 |
| 验收门槛 G1-G4 | capturing→analyzing 需快照非空；analyzing→generating 需 schema；running→done 需执行+JSON 通过 | A3 |
| 日志快照 | `snapshot()`/`confirmCaptureDone()`（「确认操作完毕」→ 冻结+锁 WebView）/`restartCapture()`（确认框→回首页→重启） | A18 |
| guardFlags + G5 门禁 | `suspectedFakeData` → `markDone()` 检查 → 弹窗（守卫原因+AI 澄清）→ 放行/拒绝 | A5/A10 |
| 阶段级回退 | `rollbackTo()` + `rollbackHistory` 轨迹；回退后前进重过验收 | A14/A25 |
| refining 循环 | done 非终态，`feedbackTriggered()` → debugging | A16 |
| 调试轮次 | 连续 3 轮失败 → warning（提示换策略），warning 后继续反复提醒 | A15 |
| awaitingUserConfirm 子状态 | 弹窗期间事件流不丢 | A7/A10 |

### 5.3 守卫规则（`workflow/scraper_guard.dart`，纯函数）

| 规则 | 内容 | 移植源 |
|---|---|---|
| `isTerminalCommandBlocked/Allowed` | 黑名单（rm/del/format/shutdown/拼接/读取/外联/python -c）+ 白名单（python scraper.py/pip install/cd/python -m pip）+ 间接执行识别 | permission/bash_approval + shellsafe |
| `lintScraperCode` → violations/warnings | 模板完整性/占位符/import 白名单（严格 stdlib+requests）/危险调用（eval/exec/os.system/open 逃逸）/凭证硬编码/假数据启发式（无网络却输出/print 字面量/URL 无交集/占位符数据） | A3/A5/A6 |
| `validateCredentialArgs` | key 合法性（无路径/换行/控制字符/`=`，≤128）+ value ≤8KB | A8 |
| G6 注册防线 | export_and_register 前强制 lint；violation/假数据未清除 → 拒绝注册 | A5 |

### 5.4 接线与 UI（Phase 1 范围内）

- `ScraperGate`（pendingCallback：命令黑/白名单分级 + save_credential 弹窗 value 打码）+ `ScraperHooks`（pre：lint/命令/凭证；post：结果摘要写 TraceBuffer 接口）
- **新增工具 `read_request_snapshot`**（A26）：AI 随时可调用读取冻结日志快照（返回快照摘要，AI 分析用；快照冻结后不再更新）——注册进 scraper 工具集 + 写入 Skill prompt
- 「停止」按钮（cancel + 阶段保留）；「确认操作完毕」按钮 + WebView 锁定；**AI ask 重抓 → 确认框**（A18）；G5 弹窗
- prompt 修正（write_file → run_python_scraper；守卫说明；假数据红线；凭证 key 功能简写）

### 5.5 验收
- 测试：守卫纯函数 30+ / workflow 15+ / core 透传回归
- 手工：定向抓取全流程；假数据被 G5 卡（两分支）；命令守卫三态；打断保留阶段

---

## 六、Phase 2 详设：多画板 + 可视化（v2 · 已吸收用户 UI 决策）

> **用户 UI 决策（2026）**：
> - 视觉方向：**克制精密工具风**（深色主、高对比强调色），但**必须符合全局 theme 规约**——
>   颜色一律 `Theme.of(context).colorScheme.*` 或 `RenderTokens.colors`（随 ThemeDescriptor 更新），
>   不硬编码（Phase 1 遗留的 `Colors.red/orange/grey` 需清理）
> - 多画板布局：**左侧竖排画板列表**（IDE 侧边栏风格，带状态标记）
> - **主视图可切换**：workflow 视图 / 主工作区视图 / trace 视图（Phase 3 预留）——
>   非 workflow 视图时 workflow 压缩为**顶部 Tab 下方一条横向步骤条**；
>   workflow 视图时绘制**完整流程图**（展示阶段、耗时、回溯 rollbackHistory、refining 轮次）
> - 目录重组：**先重组再开发**

### 6.0 目录重组（先行）✅ 已完成（2026）
`scraper_modle/` 平铺 13 文件 → 子目录重组完成：
- `workflow/`：scraper_workflow + scraper_guard
- `agent/`：ai_panel + gate + hooks + `tools/scraper_tools`
- `web/`：webview + cdp_network_client
- `view/`：generator_view + request_log_panel + terminal
- 顶层保留：scraper_template（外部 registry 引用）/ scraper.dart（barrel，document.dart 引用）/
  exporter / flow_facade / json_validator / skill_const（多路径引用的契约文件）
- 内部 27 处相对 import + 外部 4 文件 + 测试 10 文件 import 全部重写
- 验收：analyze 0 error + 全量 891 测试通过

### 6.1 多画板（A21-A24）✅ 数据层 + 容器 UI 完成（2026）
- `ScraperBoard{id, name, mode, workflow, sessionId, snapshotRef, createdAt, updatedAt}` ✅
- **左侧画板列表**（`board_container_view.dart`）：竖排卡片（画板名 + 模式状态点 + 关闭），
  选中高亮（colorScheme.primaryContainer），新建按钮，长按重命名 ✅
- 每画板独立 ScraperGeneratorView 实例（ValueKey=board id → 独立 WebView/会话/快照）✅
- `board_store.dart`（checkpoint 式原子持久化：temp+rename，**启动清理残留 .tmp**，重启恢复）✅
- `board_paths.dart`：projectRoot/workspaceDir 计算提升为共用（模板层与工作区）
- 隔离保证：快照按画板分文件（`boards/<id>/snapshot.json`）；任务绝不交叉 ✅
- 测试：board 模型/store 11 + 容器 widget 4

### 6.2 多视图切换 + Workflow 可视化（B1/B2）✅ 完成（2026）
- **视图切换器**（`view/scraper_view_switch.dart`）：工作区 / workflow 流程图 / trace（禁用占位）✅
  - 非 workflow 视图：顶部 Tab 下方**常驻横向步骤条**（`ScraperWorkflowStepper` compact 模式）✅
  - workflow 视图：**完整流程图**（`workflow/scraper_workflow_graph.dart`）——节点含耗时、
    回退轨迹（rollbackHistory 虚线回退边 + 图例）、refining 轮次角标、当前呼吸高亮 ✅
- `ScraperWorkflowStepper`：8 阶段横向步骤条（当前态高亮+呼吸动画、已完成打勾、失败红叉、
  悬停显示耗时/日志数/调试轮次；compact 模式含调试/优化徽标）✅
- `AgentStepIndicator`（共享组件 `renderer/components/shared/widgets/`）：事件驱动
  （toolDispatch/turnStarted/turnDone），"调用工具 X · 第 n/50 步"，替换 AI 面板头部小转圈 ✅
- 主题规约：全部颜色从 colorScheme 派生（Phase 1 硬编码色已清理）✅
- 测试：可视化组件 11 用例（Stepper 4 / Graph 3 / AgentStepIndicator 4）

### 6.3 主题规约清理（v2 新增）
- 替换 Phase 1 引入的硬编码色：`Colors.red`（停止按钮）→ `colorScheme.error`；
  `Colors.orange`（warning 状态栏）→ `colorScheme.tertiary`（或 errorContainer）；
  `Colors.grey` → `colorScheme.outline` / `onSurfaceVariant`

### 6.4 验收 ✅ 全部通过（2026）
- 测试：board 模型/持久化/隔离 15 + 容器 widget 4 + 可视化组件 11 + 全部 scraper 194 用例通过
- 全量：917 测试全绿 · analyze 0 error · `flutter build windows --debug` 编译通过（30s）
- 手工验证点：3 画板独立工作区（ValueKey 隔离）；重启恢复（BoardStore.load）；
  视图切换（工作区↔流程图）；进度条真实反映 AI 步骤（AgentStepIndicator）

---

## 七、Phase 3 详设：Trace + Guardian

### 7.1 Trace（C1-C5）
- `AgentTraceRecorder`（共享）：订阅事件流，turnStarted→turnDone 分组；`TraceToolEvent`（工具名+主参数摘要+结果摘要[行数/字节数/前200]+isError→[error]）、`TraceThinkEvent`（时长摘要）、`TraceReplyEvent`（预览≤500+UTF-8 字节数）；内存环形 500 + JSONL 落盘（trajectory 格式）
- `AgentTraceView`：笔记本横线（粗线分轮/细线分事件/低对比灰）+ 固定宽前缀列（`● tool/think/reply`）+ [error] 红标 + 空态
- scraper AI 面板「对话/轨迹」切换（IndexedStack）

### 7.2 Guardian（A12/A13）
- `core/agent/guardian/guardian.dart`：GuardianSession（独立 LLM + policy prompt + 只读工具 + Review → JSON 裁决 + circuit breaker + transcript 增量）
- `guardian_review_tool.dart`：显式 tool 审核（AI 主动调用）
- 门禁自动：G5/G6 前自动调 Guardian 审「关键 trace（工具序列+违规）+ 产物（scraper.py/manifest/config）」
- 成本控制：审产物+关键 trace 单次调用；transcript 增量；circuit breaker；失败降级规则守卫 + 用户弹窗

### 7.3 验收
- 测试：TraceRecorder 8+ / Guardian 5+
- 手工：跑对话切轨迹见三类事件；假数据场景 G5 前 Guardian deny + rationale 回灌

---

## 八、Phase 4 详设：AI 探索模式

### 8.1 改动
| 文件 | 内容 |
|---|---|
| `web/scraper_webview.dart` | 补 JS 执行通道（Windows executeScript spike 验证 + Android runJavaScript） |
| `explore/explore_workflow.dart`（新） | idle → exploring → categorizing → confirming → building → registering → done/failed；页数/请求数/节流计数 |
| `explore/scraper_explore_tools.dart`（新） | `explore_page_links()` / `navigate_get()`（仅 GET，守卫拒绝 POST/表单/js:）+ `list_captured_requests()` / `present_data_sources()` / `build_selected_source()` / `register_batch()` |
| `explore/explore_panel.dart`（新） | 探索进度 + 归类多选 + 批量构建进度 |
| 画板容器 | 模式切换落地；探索阶段工具白名单（禁 run_terminal_command/save_credential/run_python_scraper/export_and_register） |
| prompt | 探索 Skill（仅 GET/批量 explore/归类格式/构建注册流程） |

### 8.2 流程（D1-D6）
1. idle：切探索模式 →「开始探索」（提示先登录）
2. exploring：`explore_page_links` → `navigate_get` → `list_captured_requests` 循环，直到无新链接或触达上限（20 页/50 请求/1s 节流/同域），全程 Trace 记录
3. categorizing：AI 聚合成候选数据源 JSON（name/displayName/category/url/method:GET/fields[]）
4. confirming：`present_data_sources` → UI 多选（勾选+可改名）→ 用户确认
5. building：逐源 `data-{name}` + scraper.py + manifest + config（复用 `_generatePlugin`）
6. registering：逐源 `_hotRegister` + orch.get 验证，汇总回灌
7. done/failed：批量结果展示

### 8.3 验收
- 测试：ExploreWorkflow 状态机/上限/节流；GET 守卫拒绝路径；工具白名单阶段切换
- 手工：登录 → 探索 → 归类多选 → 勾 2-3 源 → 批量构建注册 → 数据看板出现新数据源且 orch.get 全通过

---

## 九、跨 Phase 共享接口（提前定义，按序实现）

```dart
// Phase 1 产出，Phase 3 消费
abstract class TraceBuffer {
  void recordTool(String tool, String argsSummary, String resultSummary, {bool isError});
  void recordThink(Duration elapsed);
  void recordReply(String preview, int byteCount);
  List<TraceRound> rounds();
}

// Phase 1 产出，Phase 3 消费
class GuardResult { final List<String> violations; final List<String> warnings; }

// Phase 3 产出，Phase 4 消费
class CandidateDataSource { final String name, displayName, category, url; final List<String> fields; }
```

## 十、风险与注意

1. **webview_windows executeScript**：Phase 4 前 spike；缺失则探索降级"仅枚举当前页 + 复用捕获日志"
2. **Guardian 成本**：transcript 增量 + 截断 + circuit breaker；失败降级规则守卫 + 用户弹窗（fail-closed）
3. **多画板内存**：每画板独立 WebView 开销大 → 非活跃画板挂起/回收策略
4. **静态启发式误报**（纯静态 JSON 页）→ G5 弹窗 + Guardian 二次审查兜底
5. **core 层隔离**：`scraper_guard.dart` 在 renderer 层；core 只加透传参数 + AskTool/Guardian（不引 Flutter）
6. **shellparse 移植**：spike 决定完整移植 vs 正则近似（影响命令守卫精度）
7. **会话大小保护**：沿用 50KB/1MB 保护，Trace 落盘同规则
8. **旧文件处理**：`scraper_v2.0_改造PLAN.md`、`Phase1-PLAN.md`、`Scraper_V2.0_全量优化计划.md`（v1.0）被本文档取代

## 十一、交付顺序与工作量预估

| Phase | 内容 | 预估改动 | 移植源 |
|---|---|---|---|
| 1 | core 底座 + workflow×harness + 守卫 + 门禁 | core 3 改 + workflow 2 新 1 重构 + guard 1 新 + UI 接线 | ask.go / bash_approval / shellsafe / hook |
| 2 | 多画板 + 可视化 | board 3 新 + 可视化 2 新 + 重构 | checkpoint / recovery |
| 3 | Trace + Guardian | trace 2 新（共享）+ guardian 2 新 + 接入 | trajectory / guardian |
| 4 | 探索模式 | explore 4 新 + webview 扩展 + 接入 | — |

每 Phase：实现 + 测试 + 手工回归，确认后再进下一 Phase。
