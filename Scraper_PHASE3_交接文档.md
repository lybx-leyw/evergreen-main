# Scraper V2.0 重构 · Phase 3 交接文档

> **给下一个接手 AI 的完整交接**。本文件自包含，无需回看历史对话。
> 交接人：前序 AI（完成 Phase 1 + Phase 2）｜ 日期：2026
> 当前状态：**Phase 1 ✅ + Phase 2 ✅ 均获用户确认，下一步 = Phase 3（Trace + Guardian）**

---

## 一、任务背景与目标

Evergreen 2.0（Flutter 桌面应用）的 **scraper 插件底层重构**，目标是"特定场景 workflow×harness 强化的 Agent"。用户的核心诉求（全部已归档）：

1. **Harness 工程化**：hook/guard 机制、审查 AI 是否穿透、产物契约校验、硬编码假数据检测、脚本可运行性预检
2. **Workflow 可视化**：多画板 + 步骤条 + 事件驱动统一进度 + workflow 流程图视图
3. **Trace 视图**（Phase 3）：按 round 分组的工具/思考/回复三类事件，笔记本横线风格
4. **AI 探索机制**（Phase 4）：GET-only 探索 → 细粒度归类 → 多选构建 → 批量注册

**用户协作铁律**（务必遵守）：
- **时刻与用户交互**：每个里程碑汇报确认后再继续，多 ask 用户，不要自己埋头循环
- **UI 以美观实用为准可重构**，不拘泥旧实现
- **颜色必须符合全局 theme 规约**（`Theme.of(context).colorScheme.*` / `RenderTokens.colors`），不硬编码
- **优先移植 `D:\green_ds\DeepSeek-Reasonix`（Go）**的优良实现，不重复造轮子（本项目 core/agent 本就是其 Dart 移植）

---

## 二、权威文档（必须先读）

| 文档 | 作用 |
|---|---|
| `D:\evg-workplace\Scraper_V2.0_全量重构计划.md` | **主计划**：需求编号（A/B/C/D/E）、4 Phase 详设、移植清单、验收标准 |
| `D:\evg-workplace\Scraper_决策原文归档.md` | **决策权威来源**：用户 6 轮 ask 的 32 条回答逐字归档 + 需求编号映射。需求清单冲突时**以此为准** |
| `D:\evg-workplace\v2.0重点优化对象.md` | 项目早期盘点（scraper 现状描述） |
| `D:\green_ds\DeepSeek-Reasonix\internal\` | 移植参考源（Go） |

---

## 三、已完成工作（Phase 1 + Phase 2）

### Phase 1：core 底座 + Workflow×Harness 一体化 ✅

| 改动 | 文件 | 说明 |
|---|---|---|
| Gate/Hooks 接线 | `evg-base/lib/core/agent/agent_factory.dart`、`controller/controller.dart` | `AgentAssembly.fromConfig` 与 `Controller` 支持 `gate`/`hooks` 透传，`send()` 创建 Agent 时传入 |
| AskTool 移植 | `evg-base/lib/core/agent/tools/ask_tool.dart` | 直接实现 `Tool` 接口（非 SimpleTool，保留 asker 实例访问）；headless 返回"模型假设回退" |
| event 模型增强 | `evg-base/lib/core/agent/event.dart` | `AskOption`（label/description）/`AskAnswer`/`AskRequest` |
| hooks 增强 | `evg-base/lib/core/agent/agent/hooks.dart` | `match`（锚定正则）+ `postToolUseFailure` + `CompositeHooks` + `hookMatches` |
| workflow 工程化 | `evg-base/lib/renderer/templates/scraper_modle/workflow/scraper_workflow.dart` | 阶段时间戳/timeline、验收门槛 G1-G4、日志快照（confirmCaptureDone/restartCapture）、guardFlags、G5 假数据门禁（requestDone）、阶段回退 rollbackTo、refining（feedbackTriggered + refineCount）、连续 3 轮 warning、awaitingUserConfirm |
| 守卫纯函数 | `evg-base/lib/renderer/templates/scraper_modle/workflow/scraper_guard.dart` | `isTerminalCommandBlocked/Allowed/classifyTerminalCommand`（移植 shellsafe/bash_approval 语义）、`lintScraperCode`（模板完整性/import 白名单/危险调用/凭证硬编码/假数据启发式）、`validateCredentialArgs` |
| ScraperGate | `evg-base/lib/renderer/templates/scraper_modle/agent/scraper_gate.dart` | 规则表 + pendingCallback 分级（命令黑/白/弹窗 + save_credential 弹窗） |
| ScraperHooks | `evg-base/lib/renderer/templates/scraper_modle/agent/scraper_hooks.dart` | L2 preToolUse 审查 + L4 结果摘要 + `TraceBuffer` 接口（Phase 3 消费）；**A5 修正语义：lint 无假数据自动清除标记** |
| 新工具 | `evg-base/lib/renderer/templates/scraper_modle/agent/tools/scraper_tools.dart` | `read_request_snapshot`（A26：AI 读冻结快照） |
| prompt 修正 | `evg-base/lib/renderer/templates/scraper_modle/scraper_skill_const.dart` | write_file→run_python_scraper、守卫红线六条、凭证 key 功能简写 |

### Phase 2：多画板 + 可视化 ✅

| 改动 | 文件 | 说明 |
|---|---|---|
| 目录重组 | `scraper_modle/` 整体 | workflow/ agent/ web/ view/ board/ 五子目录；顶层保留 scraper_template / scraper.dart(barrel) / exporter / flow_facade / json_validator / skill_const |
| 画板模型+存储 | `evg-base/lib/renderer/templates/scraper_modle/board/scraper_board.dart` | `ScraperBoard` + `BoardStore`（checkpoint 原子写：temp+rename，启动清理 .tmp，损坏备份，重启恢复） |
| 画板容器 | `evg-base/lib/renderer/templates/scraper_modle/board/board_container_view.dart` | 左侧画板列表（状态点/新建/长按重命名/关闭）+ IndexedStack；每画板独立 ScraperGeneratorView 实例（ValueKey=board id） |
| 路径工具 | `evg-base/lib/renderer/templates/scraper_modle/board/board_paths.dart` | findProjectRoot / scraperWorkspaceDir 共用 |
| 步骤条 | `evg-base/lib/renderer/templates/scraper_modle/workflow/scraper_workflow_stepper.dart` | 8 阶段横向步骤条（compact/完整两模式） |
| 流程图 | `evg-base/lib/renderer/templates/scraper_modle/workflow/scraper_workflow_graph.dart` | workflow 视图完整流程图（回退虚线边/refining 角标/节点耗时） |
| 视图切换 | `evg-base/lib/renderer/templates/scraper_modle/view/scraper_view_switch.dart` | 工作区/工作流/轨迹（占位禁用）+ 非 workflow 时顶部紧凑 Stepper |
| 统一进度 | `evg-base/lib/renderer/components/shared/widgets/agent_step_indicator.dart` | 共享 AgentStepIndicator（事件驱动，替换 AI 面板假转圈） |
| 模板入口 | `evg-base/lib/renderer/templates/scraper_modle/scraper_template.dart` | 改渲染 BoardContainerView |

---

## 四、当前代码结构（重组后）

```
evg-base/lib/renderer/templates/scraper_modle/
├── scraper_template.dart          # 入口（渲染 BoardContainerView）
├── scraper.dart                   # barrel（document.dart 引用）
├── scraper_exporter.dart          # 导出 + manifest 契约
├── scraper_flow_facade.dart       # 门面
├── scraper_json_validator.dart    # stdout JSON 校验 + 工具截断
├── scraper_skill_const.dart       # Skill prompt
├── renderScraperGenerator.dart    # HTML 预览占位
├── board/
│   ├── scraper_board.dart         # 画板模型 + BoardStore
│   ├── board_container_view.dart  # 左侧列表 + IndexedStack
│   └── board_paths.dart
├── workflow/
│   ├── scraper_workflow.dart      # 状态机（工程化）
│   ├── scraper_guard.dart         # 守卫纯函数
│   ├── scraper_workflow_stepper.dart
│   └── scraper_workflow_graph.dart
├── agent/
│   ├── scraper_ai_panel.dart      # AI 面板（注入 Gate/Hooks/AskTool）
│   ├── scraper_gate.dart
│   ├── scraper_hooks.dart         # 含 TraceBuffer 接口
│   └── tools/scraper_tools.dart   # 8 工具（含 read_request_snapshot）
├── web/
│   ├── scraper_webview.dart       # WebView + 锁定遮罩
│   └── cdp_network_client.dart
└── view/
    ├── scraper_generator_view.dart
    ├── scraper_view_switch.dart
    ├── request_log_panel.dart
    └── scraper_terminal.dart
```

测试：`evg-base/test/scraper/`（14 个文件：guard/workflow/hooks/board/container/visualization/json_validator/p5_* 等）

---

## 五、验证状态（交接时）

- 全量测试：**917 通过**（3 skip）
- analyze：**0 error**
- 编译：`flutter build windows --debug` ✅（30s）
- 注意：`flutter analyze <子目录>` 会有 package 解析假阳性（core/agent 子包与根包同名 evergreen_base）——**必须用全项目 `flutter analyze` 验证**

---

## 六、Phase 3 待办：Trace + Guardian（下一步）

### 6.1 Trace（需求 C1-C5，共享组件）

**目标**：记录 Agent 历史（按 round 分组的工具/思考/回复三类事件），笔记本横线风格视图，随时切换进出。

**数据层**（新建 `evg-base/lib/renderer/components/shared/trace/agent_trace_recorder.dart`）：
- 订阅 Agent 事件流（`_assembly.eventSink.stream`），`turnStarted→turnDone` 为一个 round
- 三类事件：
  - `TraceToolEvent`：工具名 + 主参数摘要 + 结果摘要（行数/字节数/前 200 字符）+ `isError` → `[error]` 标记
  - `TraceThinkEvent`：reasoning 首 delta → 结束 计时 → "思考 4.2s"
  - `TraceReplyEvent`：正文预览（≤500 字符）+ UTF-8 字节数
- **数据源**：Phase 1 `ScraperHooks.postToolUse/postToolUseFailure` 已产出结果摘要 → 已定义 `TraceBuffer` 接口（`scraper_hooks.dart`），Recorder 实现它；另订阅事件流兜底
- 内存环形缓冲（默认 500 事件）+ 可选 JSON 落盘（**复用 50KB 单消息/1MB 整体保护**，参考 `scraper_ai_panel.dart` 的 `_saveSessions` 大小保护逻辑，防止复现 8MB 事故）

**视图层**（新建 `evg-base/lib/renderer/components/shared/trace/agent_trace_view.dart`）：
- **笔记本横线风格**：近纸色底 + 细灰横线（`onSurface.withValues(alpha: 0.08)`）
- **粗线分轮次**（`Round N · 12.3s · 5 events` 标题 + 2px 分隔）、**细线分事件**（0.5px）
- **固定宽度前缀列**（`● tool` / `● think` / `● reply`，等宽左对齐，列宽固定如 64px）+ 内容列对齐
- `[error]` 红色高亮（`colorScheme.error`）
- 空态："暂无轨迹，开始一次对话后自动记录"

**接入**（`scraper_modle/agent/scraper_ai_panel.dart`）：
- `ScraperHooks` 构造传入 TraceBuffer 实现（Recorder）
- AI 面板头部或视图切换器加"轨迹"视图（`ScraperViewSwitch.traceEnabled = true`，IndexedStack 保状态，随时切换）

### 6.2 Guardian（需求 A12/A13，核心层）

**目标**：AI 子代理审查 trace+产物，门禁自动 + AI 显式调用。

**移植源**：`D:\green_ds\DeepSeek-Reasonix\internal\guardian\guardian.go` + `guardian_policy.md`

**core 层**（新建 `evg-base/lib/core/agent/guardian/guardian.dart`）：
- `GuardianSession`：独立 LLM 会话 + 安全策略 prompt（`guardian_policy.md` 精简移植）+ 只读工具集
- `Review(toolName, args, parentSession)` → JSON 裁决 `{risk_level, user_authorization, outcome(allow/deny), rationale}`
- circuit breaker（连续 3 deny → 中断提示）；transcript 增量维护控制成本
- **注意 core 层纯 Dart**：stub 隔离模式（参考 `core/agent/lib/` 下的 stub）

**工具层**（新建 `evg-base/lib/core/agent/tools/guardian_review_tool.dart`）：
- `guardian_review(target)`：显式 tool 审核（AI 主动调用，审当前 trace 摘要 + 产物）

**接线**（`scraper_modle/agent/scraper_ai_panel.dart` + workflow）：
- **门禁自动触发**：G5（假数据门禁前）/ G6（注册前）自动调 Guardian 审「关键 trace（工具序列摘要 + 违规记录）+ 产物（scraper.py/manifest/config）」
- 裁决 allow 放行 / deny 回退 debugging + 回灌 rationale
- **成本控制**：审产物+关键 trace，单次 LLM 调用；transcript 增量；circuit breaker；失败降级规则守卫 + 用户弹窗（fail-closed）

**Skill prompt**（`scraper_skill_const.dart`）：增加 guardian_review 工具说明与使用时机

### 6.3 Phase 3 验收标准（来自主计划）

- `dart test`：TraceRecorder（分组/摘要/字节数/[error] 8+）；Guardian（裁决解析/deny 回灌/circuit breaker 5+）
- 手工：跑一轮对话切「轨迹」见笔记本风格三类事件；假数据场景下 G5 前 Guardian 给出 deny + rationale

---

## 七、踩坑记录（务必先读，避免重蹈覆辙）

1. **目录重组脚本事故**：PowerShell 5 无 `[System.IO.Path]::GetRelativePath`，脚本把 import 替换成空串破坏了 11 文件。教训：**批量改文件前先备份或确认改动可 git 恢复**；本项目 Phase 1/2 改动**均未提交 git**（工作区 HEAD 仍是 6adfb06），接手后**建议先 commit 一次**保住成果！
2. **id 唯一性**：`ScraperBoard.create` 的 id 用"时间戳+进程内递增序号"（`_nextSeq`）——早期用"时间戳+随机后缀"同微秒内大量撞车导致快照串扰，已被测试捕获。
3. **原子写 .tmp 残留**：`BoardStore._atomicWrite` 启动/保存时清理同路径 .tmp（崩溃残留），否则测试会留下 `boards.json.tmp`。
4. **analyze 假阳性**：`dart analyze lib/core/agent/...` 或 `flutter analyze <子目录>` 会因嵌套同名包报 `uri_does_not_exist`——**必须全项目 `flutter analyze`**。
5. **hooks 的 match**：Dart `implements` 不继承接口默认实现，`LoggingHooks/NoOpHooks/CompositeHooks` 需显式实现 `match`。
6. **AskTool 用 SimpleTool 的坑**：SimpleTool 的 execute 是静态闭包无法访问实例字段（asker）→ AskTool 直接实现 `Tool` 接口。
7. **workflow 纯 Dart**：`scraper_workflow.dart` 用 `WorkflowCallback` typedef，不能 import Flutter 的 VoidCallback。
8. **widget 测试窗口**：BoardContainerView 测试需 `tester.binding.setSurfaceSize(Size(1200, 800))`，否则 `scraper_terminal.dart:415` 的 Row 在默认窗口溢出（既有组件问题）。
9. **BoardContainerView 测试**：需要 `ProviderScope` 包裹（ScraperAIPanel 依赖 riverpod）；workspaceDir 用系统临时目录避免污染项目根。

---

## 八、协作约定（传给下一个 AI）

1. **每个里程碑先汇报再继续**，用户确认后进下一步；多 ask 用户（可用 ask_user_question）
2. **需求冲突以 `Scraper_决策原文归档.md` 为准**
3. **先查 Reasonix 再动手**（`D:\green_ds\DeepSeek-Reasonix\internal\`），移植保持命名风格一致（蛇形、EventKind 对齐）
4. **颜色从 colorScheme 派生**，不硬编码
5. 每 Phase 交付：实现 + 测试 + analyze 0 error + 编译回归 + 手工验证点说明
6. **建议接手后第一步**：`git add -A && git commit` 保存 Phase 1+2 成果（当前全在工作区未提交）
