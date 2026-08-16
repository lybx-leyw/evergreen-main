# Phase 1 — Scraper Agent 守卫体系 PLAN（v0.3 · harness 嵌入 workflow）

> 状态：**v0.3，待用户最终审核**
> 范围：需求 1（Harness 工程化）—— **harness 与 workflow 一体设计**：守卫不是挂在 workflow 外的附加层，而是**嵌入每个转换点的检查机制**。
>
> **用户已拍板的决策**：
> 1. 假数据检测：warning 放行 + 回灌修正，不阻断执行；**workflow 在推进 done/注册时卡住**，AI 无法拿假数据蒙混过关
> 2. import 白名单：**严格 stdlib + requests**
> 3. 终端命令：白名单内自动执行；**白名单外弹窗确认**；危险命令黑名单硬拒（不进弹窗）
> 4. 凭证 key：允许任意 key，校验合法性 + 长度，prompt 引导功能简写
> 5. write_file 缺失：仅修 prompt
> 6. **AI 澄清"该站是静态 JSON 页"时，弹窗让用户确认是否放行**——人工确认是 workflow 的一等公民
>
> **架构原则（v0.3 新增）**：harness 作用于 workflow。每个 workflow 转换点 = 守卫检查点；每个守卫动作（拦截/放行/弹窗/回退）都是 workflow 状态转换的一部分。

---

## 1. 探索结论（代码实况）

### 1.1 Agent 主循环守卫调用链（已存在但未接线）

`core/agent/agent/agent.dart` 主循环时序：

```
gate.check(工具, 参数, readOnly)      ← L1 权限门控（allow/deny/confirm）
  → preToolUse(工具, 参数)            ← L2 前置钩子（可 block + 消息）
  → toolDispatch 事件
  → registry.call(工具, 参数)         ← 执行
  → StormBreaker（写工具连续失败≥3 抑制）
  → toolResult 事件
  → postToolUse(工具, 参数, 结果)     ← L4 后置钩子（摘要/违规记录）
```

**缺口**：`AgentAssembly.fromConfig`（`agent_factory.dart:327`）与 `Controller.send()`（`controller.dart:197`）创建 Agent 时**不传 gate/hooks** → scraper 隔离 Agent 零门控，时序空转。

### 1.2 scraper 隔离 Agent 工具面（7 个）

| 工具 | 类型 | 穿透风险 |
|---|---|---|
| `run_python_scraper(code)` | 写 | 代码可硬编码假数据 / import 任意库 / Python 内读任意文件 |
| `run_terminal_command(command)` | 写 | **最大穿透面**：任意 shell |
| `save_credential(key, value)` | 写 | key 任意命名、value 无长度限制 |
| `export_and_register_scraper(data_name)` | 写 | 已有 3 层 data_name 防护 |
| `get_request_logs()` | 只读 | 无 |
| `read_workspace_file(path)` | 只读 | 已有路径逃逸防护 |
| `read_existing_credential(plugin_name)` | 只读 | 无 |

**Prompt 穿透诱因**：`scraper_skill_const.dart:298,318`、`scraper_tools.dart:344` 引导 AI 用 `write_file`，但工具面没有它。（决策 5：仅修 prompt。）

### 1.3 产物契约

- **scraper.py**：锁定模板 `_get_config` 三级降级（`scraper_exporter.dart:35`）+ `{CREDENTIAL_PLACEHOLDER}` 只填 `VAR = _get_config('KEY')` + 业务代码 + 注入 JSON validator
- **data/manifest.json**（`scraper_exporter.dart:257`）：`type=data-source` / `runtime=python` / `script=scraper.py` / `dataTypes[]`
- **config/config.json**（`config_register.dart:140`）：`schemaVersion=2.0` / `settings[]`，敏感字段 `type: password`
- **stdout 契约**（`scraper_json_validator.dart`）：整体合法 JSON；已有 `validateScraperStdout` + `truncateToolOutput(8000)`

---

## 2. Workflow × Harness 一体架构（核心）

### 2.1 完整工作流图（含守卫介入点 / 阻断 / 回退 / 人工确认）

```
┌────────────────────────────────────────────────────────────────────┐
│                     SCRAPER WORKFLOW（模式 A 定向抓取）              │
└────────────────────────────────────────────────────────────────────┘

 [idle] ──打开页面自动──▶ [capturing]
   │                        │  WebView 浏览 + CDP/JS 三层拦截捕获请求
   │                        │
   │                        │  G1 ── 用户点"分析日志"
   │                        │      门槛：hasLogs == true
   │                        │      ✗ 无日志 → 提示用户先操作（不转换）
   │                        ▼
   │                    [analyzing] ◀────┐
   │                        │  AI: get_request_logs → 分析 → 推断 schema
   │                        │            │
   │                        │            │  R5 修正后重试（不耗调试轮次）
   │                        ▼            │
   │                    [generating]     │
   │                        │  AI 生成代码（run_python_scraper）
   │                        │  G2 ── L2 lintScraperCode（preToolUse）
   │                        │      · violation → block + 违规清单回灌 → R5
   │                        │      · warning  → 放行执行 + guardFlags 标记
   │                        │  G3 ── run_terminal_command
   │                        │      · 黑名单 → 硬拒（不进弹窗）→ R5
   │                        │      · 白名单 → 自动放行
   │                        │      · 其余   → 弹窗确认 → 拒绝 → R5
   │                        ▼
   │                    [running]
   │                        │  G4 ── L3 执行验证：
   │                        │      · exitCode==0？
   │                        │      · stdout 整体合法 JSON？
   │                        │      · 真实性交叉验证（弱校验 → warning）
   │                        │      ✗ 任一失败 → R1 → [debugging]
   │                        ▼
   │                    [questioning] ◀──── 信息严重缺失时 AI 追问（任意点）
   │                        │
   │                        ▼
   │                    G5 ── markDone 门禁（关键！）
   │                        │  guardFlags.suspectedFakeData == true ?
   │                        │  ┌─ 无 → 直接 [done]
   │                        │  └─ 有 → 弹窗（决策 6）：
   │                        │      "检测到疑似硬编码假数据（原因：…）
   │                        │       AI 说明：<AI 澄清文本>"
   │                        │      ├─ 用户【放行】→ 清 guardFlags → [done]
   │                        │      └─ 用户【拒绝】→ R2 → [debugging]
   │                        ▼
   │                    [done]
   │                        │  G6 ── export_and_register_scraper（注册前）
   │                        │      · 强制 lint：violation → 拒绝注册 → R5
   │                        │      · manifest/config 结构断言
   │                        │      · orch.get 真实拉取验证
   │                        │      ✗ 注册/拉取失败 → R3 → [debugging]
   │                        ▼
   │                    ✅ 完成：数据源注册成功
   │
   └── [debugging] ◀──── R1/R2/R3
          │  AI 分析失败原因 → 修改代码 → 重新 run（G2~G4 重走）
          │  R4 ── 调试轮次上限（5 轮）→ [failed]
          │        → 提示用户重新演示 → [idle]
```

### 2.2 守卫介入点矩阵（G1~G6）

| 检查点 | 位置 | 守卫内容 | 命中行为 |
|---|---|---|---|
| **G1** | capturing→analyzing | `hasLogs` 门槛 | 无日志不转换，提示用户操作 |
| **G2** | run_python_scraper (preToolUse) | `lintScraperCode`：模板完整性 / import 白名单 / 危险调用 / 凭证硬编码 / 假数据启发式 | violation → block + 回灌；warning → 放行 + guardFlags |
| **G3** | run_terminal_command (Gate+pendingCallback) | 命令黑/白名单 | 黑名单硬拒；白名单自动；其余弹窗确认 |
| **G4** | running 阶段 (工具内 L3) | exitCode / JSON 合法性 / 真实性交叉验证 | 失败 → debugging |
| **G5** | running→done (markDone 门禁) | `guardFlags.suspectedFakeData` | 有 → 弹窗（放行/拒绝）；无 → done |
| **G6** | done→注册 (export_and_register) | 注册前强制 lint + manifest/config 结构断言 + orch.get | violation/结构错/拉取失败 → debugging |

### 2.3 阻断与回退机制矩阵（R1~R5）

| 回退 | 触发 | 去向 | 消耗调试轮次？ |
|---|---|---|---|
| **R1** | 执行失败（exitCode≠0 / JSON 非法） | → debugging | ✅ 消耗 |
| **R2** | 假数据门禁用户【拒绝】 | → debugging（回灌"用户确认数据可疑"） | ✅ 消耗 |
| **R3** | 注册/拉取失败（orch.get 异常/lastError） | → debugging（回灌完整日志） | ✅ 消耗 |
| **R4** | 调试达 5 轮上限 | → failed → 用户重新演示 → idle | — |
| **R5** | lint violation / 命令黑名单硬拒 / 弹窗拒绝 | **原地重试**（不转换阶段） | ❌ 不消耗（静态可判定问题，AI 改参数/代码后重试） |

**设计要点**：
- **R5 不消耗调试轮次**：lint violation、黑名单命令是**静态可判定**的格式/安全硬伤，AI 修正参数即可，不该占用"运行失败调试"的 5 轮预算；R1/R2/R3 是**运行时行为问题**，消耗预算
- **弹窗是 workflow 状态**：pendingCallback 弹窗期间 workflow 处于"awaitingUserConfirm"子状态，`_isRunning` 保持，事件流不丢
- **G5 门禁与 R2**：弹窗展示「守卫原因 + AI 澄清文本」；用户放行 → 清 guardFlags（一次放行仅对本轮有效，下次 lint 再命中再问）；用户拒绝 → debugging 且 AI 必须改真实抓取

---

## 3. 守卫规则明细

### 3.1 L1 Gate（`ScraperGate`，`InteractiveGate` 子类）

| 工具 | 等级 | pendingCallback 内分级 |
|---|---|---|
| `run_terminal_command` | confirm | 黑名单→false（硬拒）；白名单→true（自动）；其余→弹窗 |
| `run_python_scraper` | always | —（L2 lint 管内容） |
| `save_credential` | confirm | 弹窗显示 key（value 打码） |
| `export_and_register_scraper` | always | —（L3 管产物） |
| 只读工具 | always | — |
| 未知工具 | deny | — |

### 3.2 L2 preToolUse 静态审查（`scraper_guard.dart`，纯函数可单测）

**A. 终端命令**：黑名单（`rm`/`del`/`rmdir`/`format`/`shutdown`/`reboot`/`taskkill`/拼接 `;&&|||><`/读取 `type cat Get-Content`/外联 `curl wget nc`/`python -c`）硬拒；白名单（`python scraper.py`/`pip install <pkg>`/`cd <dir>`/`python -m pip ...`）自动放行；其余弹窗。

**B. `lintScraperCode` → `{violations[], warnings[]}`**
- **violation（block→R5）**：模板缺失（无 `_get_config` / 无三级降级标志）/ 残留占位符 / 危险 import（os-system 类、subprocess、socket、ctypes、pickle、base64、pty、importlib、非 stdlib 第三方）/ 危险调用（`os.system`、`eval(`、`exec(`、`__import__`、open 逃逸）/ 凭证硬编码（`USERNAME='字面量'`）/ 无 `__main__` / main 不返回 dict/list
- **warning（放行 + guardFlags 标记，决策 1）**：无网络库却输出数据 / `print(json.dumps([{...}]))` 字面量直出 / 代码 URL ∩ 捕获日志 URL 为空 / 占位符数据（example.com、lorem、张三、test、fake）

**C. `validateCredentialArgs`（决策 4）**：key 无路径/换行/控制字符/`=`，≤128 字符；value ≤8KB；不强制前缀，prompt 引导功能简写。

### 3.3 L3 工具内 + workflow 门禁（决策 1+6 核心）

1. `run_python_scraper` 执行后交叉验证（JSON 合法性已有 → 增加真实性弱校验 warning）
2. warnings → `ScraperWorkflow.guardFlags.suspectedFakeData = true`
3. **G5 门禁**：`markDone()` 检查 guardFlags → 有 → 弹窗（守卫原因 + AI 澄清文本）→ 用户放行/拒绝（决策 6）
4. **G6**：`export_and_register_scraper` 前强制 lint：violation → 拒绝注册；suspectedFakeData 未清除 → 拒绝注册并回灌

### 3.4 L4 postToolUse 摘要

`{tool, argsSummary, resultSummary(行数/字节数/前200字符), violations[]}` → TraceRecorder 缓冲（Phase 3 消费；Phase 1 只建接口 + 内存缓冲）。

### 3.5 Prompt 修正（决策 5）

- `write_file` → `run_python_scraper(code)`（内部写盘）；新增守卫说明（禁终端读文件 / 禁 `python -c` / 禁硬编码凭证 / 凭证 key 功能简写）；新增假数据红线（必须真实抓取）。

---

## 4. 接线改动清单

| 文件 | 改动 |
|---|---|
| `core/agent/agent_factory.dart` | `AgentAssembly.fromConfig` 增加 `gate`/`hooks` 可选参数，透传 Controller |
| `core/agent/controller/controller.dart` | 构造接收 `gate`/`hooks`；`send()` 创建 Agent 时传入 |
| `renderer/templates/scraper_modle/scraper_guard.dart`（新） | `ScraperGate`（pendingCallback 分级）+ `ScraperHooks` + 纯函数守卫库（命令黑白名单 / `lintScraperCode` / `validateCredentialArgs`） |
| `renderer/templates/scraper_modle/scraper_workflow.dart` | 新增 `guardFlags`、`awaitingUserConfirm` 子状态、**G5 markDone 门禁**、`onUserConfirmRequest` 回调 |
| `renderer/templates/scraper_modle/scraper_tools.dart` | 修正 write_file 描述；`run_python_scraper` 内联 L3 交叉验证 |
| `renderer/templates/scraper_modle/scraper_skill_const.dart` | prompt 修正 + 守卫/假数据红线说明 |
| `renderer/templates/scraper_modle/scraper_ai_panel.dart` | 注入 Gate/Hooks；pendingCallback 弹窗 UI（含 G5 假数据放行弹窗）；guardFlags 回灌；R5 重试不耗轮次 |

## 5. 测试计划

| 文件 | 用例 |
|---|---|
| `scraper_guard_test.dart`（新） | 命令黑/白名单 12+；lint violations/warnings 各 8+（模板/占位符/import/危险调用/凭证/假数据/无 main/路径逃逸）；credential 5+ |
| `scraper_workflow_test.dart`（新/扩） | G1 无日志不转换；G5 门禁：假数据→弹窗→放行/拒绝两分支；R5 不耗轮次；R4 上限→failed |
| `agent/agent_test.dart`（core） | gate/hooks 透传回归；block 路径 |
| widget 测试 | save_credential / 白名单外命令 / G5 弹窗；回灌可见 |

## 6. 风险与注意

1. **静态启发式误报**（纯静态 JSON 页无 API 日志）→ G5 弹窗让用户裁决（决策 6），AI 澄清 + 用户放行通道天然兜底
2. **confirm 弹窗频率**：白名单外的命令才弹窗；skill 引导走 `run_python_scraper` 减少终端使用；save_credential 弹窗 value 打码
3. **core 层隔离**：`scraper_guard.dart` 在 renderer 层（依赖 scraper 契约），core 只加透传参数
4. **兼容**：模式 A 现有语义不变，仅多守卫层；规则默认开启、可配置开关
5. **弹窗不丢事件**：awaitingUserConfirm 期间事件流照常缓冲（Controller 已有 approvalRequest 暂停机制可复用）
