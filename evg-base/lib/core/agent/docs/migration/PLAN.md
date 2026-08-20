# Reasonix internal → evergreen lib/core/agent 全量机制迁移计划

> 状态：计划先行，待逐项执行。
> 追踪文件：`MIGRATION_MATRIX.csv`（唯一权威 checklist，每迁移一个源文件必须同步更新）。
> 生成脚本：`GENERATE_MATRIX.sh`。

---

## 1. 为什么是现在这份计划

当前 `evg-base/lib/core/agent` 只有一套演示级 agent 循环：单层 for 循环、字符串化工具结果、三档上下文压缩、没有事实合约、没有 delivery gate、没有真实 planner/subagent/skill runtime。它不是工业级 agent runtime，撑不起开发者模式数据源创作流。

`.reasonix-ref/internal` 是目前仓库里唯一完整、经测试、机制自洽的 agent 内核参考实现。本计划的目标是：**把其中全部机制移植到 `lib/core/agent`，并让现有 scraper/explore 流程运行在新 runtime 上**。

这不是重写，是机制移植。判断标准只有一个：**源机制在 Dart 侧有对应的实现与对应的测试，且语义一致**。

---

## 2. 范围盘点（未经删减的基线）

| 源 | 规模 |
| --- | --- |
| `.reasonix-ref/internal` 顶层包 | **93 个包，全部纳入迁移** |
| Go 源文件（非测试） | 2,086 个文件，276,920 LOC |
| Go 测试文件 | 2,086 个文件中的测试文件共 261,501 LOC |
| `internal/agent` 核心 | 141 个非测试文件（37,029 LOC）+ 206 个测试文件 |
| 当前目标 `evg-base/lib/core/agent` | 75 个 Dart 文件，约 16,071 LOC |

`MIGRATION_MATRIX.csv` 覆盖 `.reasonix-ref/internal` 下**每一个 Go 文件**，不抽样、不挑选。测试文件与实现文件同样列入追踪。

### 2.1 模型能力闭包（62 个包，第一批强制完成）

从 `agent / tool / skill / guardian / memory / instruction / permission / hook / runtimepolicy / event / evidence / checkpoint / plancontract / planmode / taskcontract / goaleval / trajectory / completion / control / provider / jobs / capability / sandbox` 出发的 import 闭包：

```
ablation agent agentpreset autoresearch billing boundedllm capability checkpoint
command completion config control diff event eventwire evidence extension
extensioncontract filelock fileref fileutil frontmatter goaleval guardian hook
i18n instruction jobs mcpdiag mcplaunch memory migration netclient nilutil
permission plancontract planmode plugin pluginpkg proc productdocs provider
recovery retrieval runtimepolicy sandbox secrets sessioninbox sessiontemp
shellparse shellrun shellsafe skill store sysproxy taskcontract taskmonitor
testenv textutil tool trajectory workspacelease
```

### 2.2 宿主/传输/运维闭包（31 个包，全量但排在后面）

这些包不是模型能力核心，但同样在 CSV 中，不因“不属于 agent loop”而省略：

```
acp appidentity boot bot botruntime capdiag cli crashreport desktoplauncher
doctor environment gitcmd history historycatalog installlayout installsource lsp
mcpregistry notify outputstyle projectiondb releaseasset remote repair serve
sessioncatalog stats taskcatalog telemetry usagecatalog worktree
```

> 规则：模型闭包决定“先迁什么”；宿主闭包决定“后迁什么”。先后的差别只是批次，不是取舍。

---

## 3. 红线（不可违反）

1. **全量**：93 个包、2,086 个源文件、2,086 个测试文件全部进入 `MIGRATION_MATRIX.csv`，不允许从矩阵中移除任何一行。
2. **逐个**：一次 PR 只迁移一个“机制单元”。一个机制单元 = 一个源文件 + 其直接测试，或一个强内聚的 Go package。禁止一次性倒一大堆半成品。
3. **已有不等于已迁**：当前 `lib/core/agent` 已存在的 Guardian、Memory、Skill、Compact、Evidence 等只视为兼容实现；迁移标准是源文件逐文件对账，不是功能听起来像。
4. **先实现后删除**：旧 Dart 实现只有在对应 ref 镜像 + 测试全绿、且调用方切到新实现之后，才允许废弃/删除。迁移期间任何一步不删旧机制。
5. **测试必须同行**：每个机制单元的 Dart 实现 PR 必须包含从对应 Go 测试翻译的 Dart 测试。测试文件也要在 CSV 中勾选。
6. **语义优先**：Go 的并发、文件锁、平台分支、错误类型、缓存前缀字节稳定性等机制必须保留。Dart 侧允许用 async/isolate/条件导入做等价适配，但要在测试注释中写明映射理由，不能静默改写语义。
7. **追踪同步**：CSV 状态与 PR 同 commit 更新。`done` 必须是“实现 + 测试 + analyze 通过”。

---

## 4. 目标目录结构

第一阶段建立“镜像区”，保证可追踪、可逐个验收：

```text
evg-base/lib/core/agent/
├── ref/                          # .reasonix-ref/internal 的 Dart 镜像（机制移植区）
│   ├── agent/                    # 对应 internal/agent
│   │   ├── agent.dart            # 对应 agent.go
│   │   ├── context_manager.dart  # 对应 context_manager.go
│   │   └── ...
│   ├── tool/                     # 对应 internal/tool
│   ├── skill/
│   ├── memory/
│   └── ...
├── test/ref/                     # 对应 Go 测试的 Dart 测试镜像
│   ├── agent/agent_test.dart     # 对应 agent_test.go
│   └── ...
├── runtime/                      # 第二阶段集成区：镜像通过测试后接线的工业 runtime
├── docs/migration/               # 本计划 + CSV 追踪表
└── （现有 agent.dart / controller / memory / skill ... 暂不删除）
```

命名规则：

- `foo.go` → `foo.dart`
- `foo_test.go` → `foo_test.dart`
- `foo_windows.go` / `foo_unix.go` → Dart 条件导入拆分（`foo_io.dart` + `foo_io_stub.dart`），对应关系写进 CSV 备注。
- 子包 `internal/foo/bar` → `ref/foo/bar/`。

---

## 5. 迁移批次（执行顺序）

每个批次完成定义：CSV 内该批次全部 `done`、`dart analyze` 0 issues、`dart test test/ref/<pkg>` 全绿。

### P0 — 基线锁定与追踪系统（本计划）
- 创建 `docs/migration/`、`MIGRATION_MATRIX.csv`、`GENERATE_MATRIX.sh`。
- CSV 初始状态全部 `pending`。
- 建立 CI 检查：任何 `ref/` 源文件新增时，CSV 对应行必须存在且状态变更。

### P1 — 叶子基础包（无业务语义的底座）
包：`nilutil textutil fileutil frontmatter diff fileref filelock store event eventwire trajectory stats outputstyle`
- 先迁类型、纯函数、序列化、原子文件读写、跨进程锁、事件类型全集。
- `event` 包必须一次迁完 14 个源文件；它是后续所有 runtime 的公共语言。

### P2 — Provider / Tool / 执行安全
包：`provider tool shellsafe shellparse shellrun sandbox proc secrets netclient sysproxy boundedllm`
- 完整 Tool 抽象：`BlockedError`、`ContextualTool`、`Previewer`、`CompressRequest`、`ConfigWriteRequest`、`CallResolver`、`ShellExecution`、`DetailedResult`、`MCPMetadata`。
- Provider 完整抽象：retry、stream error、schema validate/canonicalize/dialect、reasoning replay、output/context budget。
- 权限前置包：Bash 分解、只读判定、重定向语义。

### P3 — 上下文知识层
包：`instruction memory skill command sessioninbox sessiontemp agentpreset`
- 分层 standing instructions：user / ancestor / project / local，`@path` import，verify block。
- Memory 两层模型：standing instructions + auto-memory fact store（frontmatter + `MEMORY.md` 索引 + recall/freshness/activation）。
- Skill 完整实现：inspect/index/profile/tool bindings/slash resolution/invocation policy。
- 当前 `memory/`、`skill/` 先保持兼容，镜像迁完再接线。

### P4 — 事实合约与证据内核
包：`plancontract planmode taskcontract goaleval evidence checkpoint runtimepolicy completion jobs workspacelease`
- `plancontract`：计划是结构化数据，不是散文；Normalize / Validate / Ordered / Diff。
- `taskcontract`：Contract / Requirement / Check / Obligation / Stop 语义，含 Atomic 与 FromPlan。
- `evidence`：Receipt、Ledger、classify、todo identity、completion report、full verification。
- `checkpoint`：Barrier、BlobStore、CaptureBefore/After、MutationObserver、transaction、rewind。
- `runtimepolicy`：单调前/后置 guard engine，固定 guard 组 + merge 语义。
- `completion`：宿主计算完成报告；模型 claim 只增不减。
- `goaleval`：独立 evaluator；失败/不确定 fail-closed。
- `jobs`：后台任务注册与证据。

### P5 — Agent Runtime 主循环
源文件组（镜像于 `ref/agent/`）：
- 核心：`agent.go agent_config.go services.go run_loop.go turnruntime.go turn_phase.go sampling_attempt.go sampling_request.go governor.go storm_breaker.go blocked_outcome.go nested_sink.go textsink.go format.go normalize.go width.go output_budget.go usage_context.go run_usage.go host_stream_track.go`
- 上下文维护（单列验收）：`context_manager.go context_capsule.go context_receipt.go context_recovery.go context_report.go context_status.go context_usage.go`
- Cache-aware compaction / projection：`compact.go compact_commit.go compact_fold_input.go compact_projection.go compact_turn_guard.go compact_user_turns.go projection.go cache_shape.go prune.go failure_snip.go preflight.go`
- 推理/语言/流恢复：`reasoning_language.go reasoning_replay.go reasoning_warn_state.go missing_reasoning_watch.go`
- `ask.go` AskTool。

关键验收：
- canonical transcript 永不因 compaction 改写。
- 唯一自动维护触发是 `compact_ratio`。
- provider-visible 前缀在未跨阈值时保持稳定；cache hit/miss 与 schema token 成本可观测。
- tool output first-visible 上限约 32KB，完整原文保留。

### P6 — 工具执行与运行时策略
源文件组：
- `execute_one.go execute_batch.go execution_engine.go tool_call_plan.go tool_receipts.go tool_hooks_mutation.go`
- `write_access.go write_claims.go workspace_mutation.go path_bound_tools.go preview.go`
- `capability_gate.go background_evidence.go run_turn_evidence.go delegation_admission.go arbiter.go errors.go final_readiness.go`

验收：
- 只读并行 / 写串行 / 同一批内 mutation 失败依赖阻断。
- Gate → PlanMode → DeliveryPolicy → Recovery/Permission → execute 的流水线顺序一致。
- 每条工具回执进入 Evidence Ledger；错误回灌格式与 Go 一致。

### P7 — Planner / PlanMode / Delivery 协议
源文件组：
- `coordinator.go coordinator_rollback.go plan_contract.go plan_submission.go plan_transition_diff.go planned_mutation_policy.go`
- `planner_registry.go planner_route.go planner_safety.go planner_text_fallback.go submit_plan.go`
- `delivery_scope.go contract_shadow.go completion_shadow.go final_readiness_recovery.go readiness_partial.go readiness_salvage.go`

验收：
- 双模型 planner→executor 协议完整；无 planner 时 text fallback 完整。
- plan 身份 host-assigned；revision diff 用于审批。
- DeliveryRuntimeMarker 字节精确；readiness 由宿主事实计算。

### P8 — Task / Subagent / Fleet / Goal
源文件组：
- `task.go task_budget.go taskstate.go taskpolicy_external.go profile_spec.go scheduler.go`
- `parallel_tasks.go fleet.go fleet_graph.go complete_subtask.go`
- `todo_state.go todo_dismissal.go`
- `subagent_identity.go subagent_progress.go subagent_report.go subagent_result.go subagent_store.go`
- `goal_display.go goal_run_boundary.go run_budget.go finalization.go`

验收：
- profile / TaskSpec / CapabilityGrant / ContextRequest / SchedulerPolicy 五概念边界与 Go 测试一致。
- subagent 嵌套事件、写路径声明、并发限制、结果分页读取全部保留。
- Goal FSM 的 continue/complete/blocked、budget、progress signature 全部移植。

### P9 — 能力代理 / MCP / Extension
包：`capability extension extensioncontract plugin pluginpkg mcplaunch mcpdiag`
源文件组：`usecapability.go usecapability_registry.go mcp_concurrency.go mcp_dynamic_tools.go mcp_shared_state.go extensions.go server_search.go`

验收：
- `use_capability` 固定 provider-visible schema；MCP inventory 不改变缓存前缀。
- RuntimeSnapshot 不可变、确定性 winner、CacheHash 稳定。
- MCP 授权、readOnlyHint、destructiveHint、lazy start 语义全部保留。

### P10 — 控制面与配置（模型闭包剩余）
包：`control config recovery retrieval autoresearch billing migration taskmonitor i18n productdocs`
- `control.Controller` 作为所有前端的唯一 transport-agnostic 会话驱动器。
- 配置解析、迁移、缓存策略、凭证、sandbox/write-access 策略。
- Recovery 与 Task Monitor 完整迁入。

### P11 — 宿主/传输/运维闭包（31 包）
包：`acp appidentity boot bot botruntime capdiag cli crashreport desktoplauncher doctor environment gitcmd history historycatalog installlayout installsource lsp mcpregistry notify projectiondb releaseasset remote repair serve sessioncatalog stats taskcatalog telemetry usagecatalog worktree`
- 机制层迁入 `lib/core/agent` 的镜像区；纯平台窗口代码用条件导入适配。
- 每个包同样要求测试同行，不做“薄壳跳过”。

### P12 — 集成切换与 scraper/explore 接线
- 用新 runtime 替换 `agent.dart` 的演示级循环，旧实现转为 deprecated shim。
- 把 `scraper_flow_facade` / `ExploreWorkflow` / `ScraperWorkflow` 从硬编码状态机改为调用新 agent runtime + 声明式 workflow 约束。
- E2E：`evg-base/test/scraper/explore_optimization_test.dart`、`scraper_toolchain_e2e_test.dart` 必须在新 runtime 上通过。
- 上线新 runtime 后，再按 CSV 逐行关闭“已迁但未接线”的 pending 状态。

---

## 6. 单个机制单元的迁移 SOP

以 `internal/agent/context_manager.go` 为例：

1. 在 CSV 定位 `agent/context_manager.go` 与 `agent/context_manager_test.go`，状态改 `in_progress`。
2. 通读 Go 实现和全部测试；从 `.reasonix-ref/docs/` 中找对应设计文档。
3. 在 `lib/core/agent/ref/agent/context_manager.dart` 写实现，文件头注明源文件与源 commit。
4. 在 `lib/core/agent/test/ref/agent/context_manager_test.dart` 翻译测试；只允许因 Dart 语言差异调整调用形式，不允许削减断言。
5. 运行 `cd evg-base/lib/core/agent && dart analyze && dart test test/ref/agent/context_manager_test.dart`。
6. 通过后把 CSV 两行（实现 + 测试）改为 `done`，同一 commit 提交。

## 7. 完成定义（DoD）

- CSV 中 `.reasonix-ref/internal` 下 2,086 个源文件、全部测试文件均为 `done`。
- `dart analyze` 0 issues；`dart test` 全绿。
- Provider-visible 合约测试（对应 `internal/tool.TestBuiltinToolContractDocumentation`、`internal/boot.TestBootToolContractMatchesProviderVisibleSurface`）在 Dart 侧复现并通过。
- 关键行为 e2e（对应 `benchmarks/context-maintenance-e2e`、`benchmarks/compaction`、`benchmarks/e2e`）有 Dart 等价用例。
- scraper/explore 开发者模式在新 runtime 上跑通；旧 workflow 代码完成删除/废弃审批。

## 8. 风险与应对

| 风险 | 应对 |
| --- | --- |
| Go 并发/文件锁在 Dart 不可直接等价 | 用 async + lock file/isolate 等价实现；差异在测试注释中记录，CSV 备注列标记 `adapter` |
| 平台特定文件（windows/unix） | Dart 条件导入拆分；映射关系写入 CSV |
| Prompt 字节稳定性 | 用 golden test 锁定；任何改动需同步更新 golden 并走 PR 说明 |
| 迁移期新旧两套实现并存 | 镜像区 `ref/` 不破坏现有 API；接线只在 P12 做，单次可回滚 |
| 体量巨大导致烂尾 | 批次不可并行半成品；每批次一个 PR，一个包一个包合入，CSV 为强制门禁 |

## 9. 当前状态

> 进度追踪以磁盘为准：`PROGRESS.md`（进度日志）+ `MIGRATION_MATRIX.csv`（逐文件状态）。
> 每次推进必须同步更新两处，并在提交信息中引用进度计数。

- [x] P0：基线盘点 + 本计划 + CSV 追踪表（PR #51）
- [x] P1：叶子基础包 — 已完成（13 个包 65 行 done；含 event/eventwire/stats/trajectory 与杂项测试）
- [~] P2：Provider / Tool / 执行安全 — 进行中（sysproxy/secrets 已完成，71/2086 done）
- [ ] P3：上下文知识层
- [ ] P4：事实合约与证据内核
- [ ] P5：Agent Runtime 主循环
- [ ] P6：工具执行与运行时策略
- [ ] P7：Planner / PlanMode / Delivery
- [ ] P8：Task / Subagent / Fleet / Goal
- [ ] P9：能力代理 / MCP / Extension
- [ ] P10：控制面与配置
- [ ] P11：宿主/传输/运维闭包
- [ ] P12：集成切换与 scraper/explore 接线
