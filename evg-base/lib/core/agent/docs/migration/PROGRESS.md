# 迁移进度日志（硬盘化执行状态）

> 本文档是迁移执行的**磁盘真相源**之一：任何会话恢复上下文时，读取本文档 +
> `MIGRATION_MATRIX.csv` 即可得知"做到哪、下一步做什么"，不依赖会话记忆。
> 规则：每次提交前必须更新本文档与 CSV；提交信息引用 `PROGRESS.md` 的进度计数。

---

## 一、总进度

| 指标 | 值 |
| --- | --- |
| 目标 | `.reasonix-ref/internal` 全部 Go 文件全量移植到 `evg-base/lib/core/agent`（源文件数与包数以 `PLAN.md` / CSV 为准） |
| 当前 CSV 状态 | 以 `MIGRATION_MATRIX.csv` 为准（`grep -c ",done"` 计数；2026-08-25 复查与 2026-08-20 一致） |
| 当前分支 | `feat/reasonix-agent-full-migration-plan` |
| 关联 PR | #51（计划 + CSV 基线） |
| 用户约定 | 移植期间**不运行** `dart analyze` / `dart test`；全部 Phase 完成后统一 debug |

> ⚠️ 2026-08-25 清点：`ref/` 已落 P1 + P2 四包实现镜像，但 `test/ref/`
> 目录不存在，P1/P2 镜像测试未随实现提交。迁移当前暂停，恢复前需先对账 CSV 与磁盘。

## 二、批次状态

| 批次 | 状态 | 说明 |
| --- | --- | --- |
| P0 | ✅ done | PLAN.md + MIGRATION_MATRIX.csv + GENERATE_MATRIX.sh（PR #51） |
| P1 | ✅ done | 叶子基础包全部移植（含 event/eventwire/stats/trajectory 与杂项测试） |
| P2 | 🔄 in_progress | 执行安全/Provider/Tool 批次：sysproxy/secrets/shellparse/netclient 已完成，继续按依赖推进 |
| P3–P12 | ⏳ pending | 见 PLAN.md 第 5 节 |

## 三、已提交批次明细

### P1-a：叶子包第一批（commit `ae62fe1`）
- 包：`nilutil`、`textutil`、`frontmatter`、`diff`、`filelock`、`fileref`、`store`（session/remote）、`outputstyle`、`ablation`、`testenv`
- 镜像：`evg-base/lib/core/agent/ref/{nilutil,textutil,frontmatter,diff,filelock,fileref,store,outputstyle,ablation,testenv}/`
- 测试：`evg-base/lib/core/agent/test/ref/` 同名目录

### P1-b：fileutil（commit `0de00ff`）
- 包：`fileutil`（atomicwrite / globset / replacefallback / encoding）
- 镜像：`ref/fileutil/`；测试：`test/ref/fileutil/`

### P1-c：P1 收尾（本次提交）
- 包：`event`、`eventwire`、`stats`、`trajectory`
- 镜像：`ref/{event,eventwire,stats,trajectory}/`
- 测试：`test/ref/{event,eventwire,stats,trajectory}/`
- 补齐杂项：`frontmatter/list_test`、`fileref/skip_test`、`diff/diff_extra_test`、`diff/largediff_test`

### P2-a：sysproxy（本次提交）
- 包：`sysproxy`（sysproxy.go + system_other.go + system_windows.go + 测试）
- 镜像：`ref/sysproxy/`；测试：`test/ref/sysproxy/`
- Windows WinHTTP 绑定当前为适配器占位，CSV 备注标记 `platform-adapter`

### P2-b：secrets（本次提交）
- 包：`secrets`（redact.go + redact_test.go）
- 镜像：`ref/secrets/`；测试：`test/ref/secrets/`
- 新增 `ref/provider/message.dart` 最小 provider 消息类型 stub 以支撑 RedactMessage/RedactMessages
- ProcessEnv 相关 Go `t.Setenv` 测试在 Dart 中改为 `filterEnv` / `registerCredentialEnvKeys` 单元测试

### P2-c：shellparse（本次提交）
- 包：`shellparse`（bash.go + bash_test.go + mask_test.go）
- 镜像：`ref/shellparse/`；测试：`test/ref/shellparse/`
- Go 使用 `mvdan.cc/sh`，Dart 侧用保守静态扫描器适配，覆盖 StaticFields / ParseStaticCommand / SplitTopLevel / CanMaskEarlierFailure / ContainsUnquotedGlob / AnalyzeApprovalFeatures

### P2-d：netclient（本次提交）
- 包：`netclient`（netclient.go + dialer.go + netclient_test.go）
- 镜像：`ref/netclient/`；测试：`test/ref/netclient/`
- 纯代理解析全量移植：ProxySpec / TransportOptions / NormalizeMode / Validate / proxyFunc（含 custom/env/auto 三模式）/ customProxyUrl / validateProxyUrl / Summary / redactUrl / withDirectHosts / environmentProxyFunc（env 可注入，替代 Go t.Setenv）
- Go 的 `http.Client`/`http.Transport` 在 Dart 侧建模为 `Transport` 配置对象（CSV 备注 `adapter`）；网络集成测试（httptest/CONNECT/SOCKS）适配为 resolver 级断言
- `dialer.dart`：StreamDialer/DialerFunc/newStreamDialer + 直连已实现；SOCKS5 / HTTP-CONNECT 隧道路径为适配器占位（CSV 备注 `adapter`）

## 四、进行中 / 下一步

### 当前批次：P2 已启动
- sysproxy：纯解析 + 非 Windows 适配 + Windows 适配器占位
- secrets：redact/redactCredentials/redactMessages + 测试
- shellparse：静态 Bash 扫描器 + 测试
- netclient：纯代理解析 + 直连 dialer + resolver 级测试适配
- 下一步按依赖/难度继续：`shellsafe` / `proc` / `permission` / `shellrun` 等，再进入 `provider` / `tool` 主包
- P1 已完成明细保留在本文件上方

### 后续批次
P2：provider / tool / shellsafe / shellparse / shellrun / sandbox / proc / secrets / netclient / sysproxy / boundedllm
P3：instruction / memory / skill / command / sessioninbox / sessiontemp / agentpreset
…（完整顺序见 PLAN.md 第 5 节）

## 五、执行细则（对照 PLAN.md 红线）

- 一次一个机制单元：一个源文件 + 其直接测试。
- 实现放 `ref/<pkg>/<file>.dart`，测试放 `test/ref/<pkg>/<file>_test.dart`。
- 每个 Dart 文件头部注释注明源文件（`Port of reasonix/internal/<pkg>/<file>.go`）。
- 依赖的 stub（provider/evidence/billing 等）若字段不足，随用随补，不阻塞当前单元。
- CSV 状态：实现 + 测试都创建后改为 `done`；未建测试保持 `pending`。
- 提交信息格式：`feat(agent): port P1 <pkg> (<n> done)`，`<n>` 为 CSV 中 `done` 累计计数。

## 六、会话恢复指引

1. 读本文档 → 知道总进度与下一步。
2. 读 `MIGRATION_MATRIX.csv` → 逐文件状态（`grep -c done` 得到精确计数）。
3. 读 `PLAN.md` → 批次顺序、红线、SOP、DoD。
4. 若 `ref/` 或 `test/ref/` 有未提交文件，先 `git status` 核对，补齐后提交。
