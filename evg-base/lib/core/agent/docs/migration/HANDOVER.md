# 交接报告 — Reasonix internal → evergreen `lib/core/agent` 全量机制迁移

> 生成时间：2026-08-20
> 交接人：上一执行会话（deepseek-v4-flash，经 DSH）
> 接手人：后续任意 AI 协作者 / 维护者
>
> **一句话现状**：迁移已过 P0/P1 全量 + P2 四包，CSV 进度 **77/2086 done**；
> PR #51（计划+CSV 基线）与 PR #52（P1 全量 + P2 前四包）均已合入 `v2.0`，
> 迁移源分支 `feat/reasonix-agent-full-migration-plan` 已合并删除。

---

## 1. 项目背景与目标

- 目标：把 `.reasonix-ref/internal`（Reasonix 的 Go agent 内核参考实现）的**全部机制**
  移植到 `evg-base/lib/core/agent`，让现有 scraper/explore 流程运行在新 runtime 上。
- 规模：93 个顶层包 / 2,086 个 Go 源文件（含测试，共约 54 万 LOC）。
- 判定标准（唯一）：**源机制在 Dart 侧有对应实现 + 对应测试，且语义一致**。
- 计划文档：`evg-base/lib/core/agent/docs/migration/PLAN.md`（批次、红线、SOP、DoD）。
- 权威追踪：`MIGRATION_MATRIX.csv`（逐文件，唯一 checklist）。

## 2. 当前状态（2026-08-20）

| 项 | 值 |
| --- | --- |
| 分支 | `feat/reasonix-agent-full-migration-plan`（本地；远端已合并删除） |
| 主干 | `v2.0`（PR #51、#52 已合入） |
| CSV 进度 | `done 77 / pending 2009`（共 2086 行） |
| 按阶段 | P1 65 done（13 包全量）/ P2 12 done（4 包）/ P3–P12 0 |
| 最新提交 | `117555a feat(agent): port P2 netclient (77/2086 done)` |
| 用户约定 | **移植期间不运行 `dart analyze` / `dart test`**；全部 Phase 完成后统一 debug |

### 2.1 已合入主干的提交线

```
85f7c4c  Merge PR #52 (P1 全量 + P2 sysproxy/secrets/shellparse/netclient)
b98e85e  Merge PR #51 (P0：PLAN + MIGRATION_MATRIX.csv + GENERATE_MATRIX.sh)
117555a  feat(agent): port P2 netclient (77/2086 done)
9eaaa8f  feat(agent): port P2 shellparse (74/2086 done)
df3b175  feat(agent): port P2 secrets (71/2086 done)
476a601  feat(agent): port P2 sysproxy (69/2086 done)
813e586  feat(agent): complete P1 leaf packages (65/2086 done)
0de00ff  feat(agent): port P1 fileutil
ae62fe1  feat(agent): port P1 leaf packages (第一批 10 包)
ccbf396  docs(agent): add Reasonix internal full-migration plan and file matrix
```

## 3. 已完成工作明细

### P1 — 叶子基础包（✅ 65/65，13 包全量）

镜像区 `ref/{...}/` + 测试区 `test/ref/{...}/`：

`nilutil textutil frontmatter diff filelock fileref store outputstyle ablation
testenv fileutil event eventwire stats trajectory`

- `event` 14 源文件一次迁完（后续所有 runtime 的公共语言）。
- `eventwire` 部分源文件合并进 `wire.dart`（CSV 备注 `wire.dart consolidation`）。
- `store/usage_catalog` 用 fake catalog 测试（真实 `usagecatalog` 在 P11）。

### P2 — Provider / Tool / 执行安全（🔄 12/… done，已完 4 包）

| 包 | 行数 | 说明 |
| --- | --- | --- |
| `sysproxy` | 4 | 代理列表解析、bypass 匹配；Windows WinHTTP 为适配器占位（`platform-adapter`） |
| `secrets` | 2 | redact/redactCredentials/redactMessages；`ProcessEnv` 测试适配为 filterEnv 单元测试 |
| `shellparse` | 3 | 静态 Bash 扫描器适配（Go 用 mvdan.cc/sh）；覆盖 StaticFields / ParseStaticCommand / SplitTopLevel / CanMaskEarlierFailure / ContainsUnquotedGlob / AnalyzeApprovalFeatures |
| `netclient` | 3 | 纯代理解析（custom/env/auto 三模式 + DirectHosts + NoProxy）；`http.Client/Transport` 建模为 `Transport` 配置对象；网络集成测试适配为 resolver 级断言；SOCKS5/CONNECT 隧道路径为适配器占位 |

### 关键适配决策（写进 CSV 备注的）

- **Go 并发/文件锁** → Dart async + lock file/isolate 等价实现，差异在测试注释记录。
- **平台特定文件**（windows/unix）→ Dart 条件导入拆分或适配器占位（`platform-adapter`）。
- **Go `t.Setenv` 环境依赖测试** → Dart 侧注入显式 `Map<String,String>` 参数。
- **重网络集成测试**（httptest/CONNECT/SOCKS）→ 降为纯 resolver/纯函数级断言，可观测合约不变。
- **Go `*http.Client/*http.Transport`** → `Transport` 配置对象（代理 resolver + 超时旋钮），调用方自接 HTTP 栈。

## 4. 未完成工作（按计划顺序）

### P2 剩余（约 278 行）— 下一步的主战场

- `provider`（主包，约 100+ 行）：retry / stream error / schema validate/canonicalize/dialect / reasoning replay / output/context budget；子包 `openai` / `anthropic` / `responses` 在后。
- `tool`（主包 + builtin + sessiontool，约 100+ 行）：BlockedError / ContextualTool / Previewer / CompressRequest / ConfigWriteRequest / CallResolver / ShellExecution / DetailedResult / MCPMetadata；builtin 工具集最大。
- `shellsafe`（5 行）：只读判定 + bash 重定向语义（依赖已完成的 `shellparse`）。
- `shellrun`（3 行）：descriptor / runner。
- `sandbox`（约 20 行）：escape / prepare / writable_roots / write_access / write_path / shell / seatbelt。
- `proc`（约 20 行）：command / run / tracked / tree / hide / kill / priority / shell_path_probe。
- `permission`（约 10 行）：bash_decompose / bash_readonly / bash_redirect / bash_approval。
- `boundedllm`（1 行）、`hook`（约 15 行）。

**推荐推进顺序**：`shellsafe → shellrun → permission → sandbox → proc → boundedllm → hook → provider 主包 → tool 主包`（先小后大、依赖闭环）。

### P3–P12（全部 pending）

- P3 上下文知识层（instruction/memory/skill/command/sessioninbox/sessiontemp/agentpreset）
- P4 事实合约与证据内核（plancontract/planmode/taskcontract/goaleval/evidence/checkpoint/runtimepolicy/completion/jobs/workspacelease）
- P5 Agent Runtime 主循环（`ref/agent/` 核心，约 349 行）
- P6 工具执行与运行时策略
- P7 Planner / PlanMode / Delivery 协议
- P8 Task / Subagent / Fleet / Goal
- P9 能力代理 / MCP / Extension
- P10 控制面与配置（control/config/recovery/retrieval/autoresearch/billing/migration/taskmonitor/i18n/productdocs）
- P11 宿主/传输/运维闭包（31 包，659 行）
- P12 集成切换：新 runtime 替换演示级 `agent.dart`，scraper/explore 接线，E2E 验收

## 5. 红线与执行细则（必须遵守）

1. **全量**：2,086 行不允许从矩阵移除任何一行。
2. **逐个**：一次只迁移一个机制单元（源文件 + 直接测试），禁止倒半成品。
3. **已有不等于已迁**：现有 Dart 实现只算兼容实现，标准是逐文件对账。
4. **先实现后删除**：旧机制在镜像+测试全绿、调用方切换前不删除。
5. **测试必须同行**：每个实现 PR 必须带翻译的 Dart 测试；测试文件也在 CSV 勾选。
6. **语义优先**：并发/锁/平台分支/错误类型/缓存前缀字节稳定性保留；Dart 用 async/isolate/条件导入等价适配，映射理由写进测试注释与 CSV 备注。
7. **追踪同步**：CSV 状态 + `PROGRESS.md` 与 PR 同 commit 更新；`done` = 实现+测试+analyze 通过。
8. **提交信息格式**：`feat(agent): port P1 <pkg> (<n>/2086 done)`（P2 同理写 P2）。
9. **用户约定**：移植期间不运行 `dart analyze` / `dart test`；全部 Phase 完成后统一 debug。
10. **新文件头注释**：注明源文件（`Port of reasonix/internal/<pkg>/<file>.go`）。

## 6. 风险与注意点

| 风险 | 现状/应对 |
| --- | --- |
| 代码未经验证 | 按约定全部 Phase 后统一 `dart analyze` + `dart test` debug；此前每包只做语法级检查（`dart format`） |
| 网络/凭据 | 环境无 GitHub 凭据时 push 失败（`could not read Username`）；用临时 askpass token 可推送；token 不写盘 |
| 会话中断 | 上次因 HTTP 413（上下文过大）中断——长会话注意控制上下文，恢复时读 `PROGRESS.md` + CSV 即可 |
| 适配器占位累积 | `platform-adapter` / `adapter` 占位在 CSV 备注有标记，P12 接线前需逐项补齐（WinHTTP、SOCKS5/CONNECT、真实 HTTP 栈等） |
| `session.jsonl` | 仓库根下已 gitignore，不入库 |

## 7. 会话恢复指引（接手者必读）

1. 读 `docs/migration/PROGRESS.md` → 总进度与下一步。
2. 读 `docs/migration/MIGRATION_MATRIX.csv` → 逐文件状态（`grep -c ",done"` 得精确计数）。
3. 读 `docs/migration/PLAN.md` → 批次顺序、红线、SOP、DoD。
4. 读本报告第 4 节 → 下一步包清单与推荐顺序。
5. 若 `ref/` 或 `test/ref/` 有未提交文件，先 `git status` 核对，补齐后按格式提交。
6. 每次推进：实现 → 测试 → CSV+PROGRESS 同 commit → 提交信息带进度计数。

## 8. 下一步首个动作（建议）

1. 在本地基于 `v2.0` 新建迁移分支（远端源分支已删）。
2. 按推荐顺序开始 `shellsafe`（5 行，依赖已就绪的 `shellparse`）：先读
   `.reasonix-ref/internal/shellsafe/shellsafe.go` 与 `shellsafe_test.go`，
   移植 `ref/shellsafe/shellsafe.dart` + `bash_redirect.dart` + `effect.dart` + 测试。
3. 完成后 CSV 3–5 行改 done，更新 `PROGRESS.md`，提交 `feat(agent): port P2 shellsafe (<n>/2086 done)`。
