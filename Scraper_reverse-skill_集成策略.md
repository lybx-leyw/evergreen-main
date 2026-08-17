# Scraper × reverse-skill 全量集成策略

> 状态：**P0-1 已落地（2026-08-17，验证全绿）**，P0-2 证据绑定待开工
> 日期：2026-08-17
> 依据：`.reference/reverse-skill/`（v1.0.1，MIT，© 2026 zhaoxuya520）+ 本仓库 scraper Phase 3/4 架构

---

## 一、背景与结论

`reverse-skill` 是一套**安全任务 AI 技能路由器**（路由矩阵 → 授权门 → 方法论 → 工具 → 证据链）。它的核心命题与我们的 scraper 是**同一类问题**：

> AI 对真实目标执行有副作用的操作时，如何同时保证**安全**与**产出可追溯**。

因此**不照搬它的工具链**（burp/IDA/Frida/CTF-Sandbox 与本机环境无关），而是**移植 4 个我们缺失的机制**。双方已有对应物：

| 我们已有（Phase 3/4） | reverse-skill 对应物 |
|---|---|
| `ScraperGate`（L1 权限门） | `case-guard.ps1` 授权门 |
| `ScraperHooks`（L2 lint） | `lint` 规则 |
| `Guardian`（L3 独立 LLM 审查） | `analysis-decision-framework.md` 裁决 |
| `ExploreWorkflow`（阶段机 + 上限守卫） | `scope-contract.md` + 阶段控制 |
| `AgentTraceRecorder`（轮次 trace） | `evidence-finding-path.md` 证据链 |
| `scraper_skill.md`（锁定模板） | `agent-obedience-engineering.md` 服从工程 |

**结论：可集成，价值排序为「持久化授权 Scope > 证据绑定 > 无进展熔断 > 经验 journal > 工具事实源 + 借口反驳」。**

---

## 二、他们考虑而我们没考虑的（缺口清单）

| # | 缺口 | reverse-skill 出处 | 严重度 |
|---|------|-------------------|--------|
| G1 | **无持久化授权边界**（Guardian 每次动态猜"这域名在不在授权内"） | `skills/ops/scope-contract.md` + `case-guard.ps1`（未就绪 exit 2） | 🔴 P0 |
| G2 | **候选数据源无证据绑定**（用户无法验证 url/字段来自真实抓包） | `skills/ops/evidence-finding-path.md`（validated 需 ≥2 条独立证据） | 🔴 P0 |
| G3 | **无进展熔断**（只有硬上限，无空转检测——上轮"卡 exploring"bug 根因层） | `analysis-decision-framework.md` R43（3 次动作无新证据 → replan） | 🟠 P1 |
| G4 | **无运行时经验回写**（`scraper_skill.md` 只有硬编码 ZJU 案例） | `field-journal/` + `_index.md`（新任务先查 index 再复用） | 🟠 P1 |
| G5 | **工具能力非事实源**（prompt 硬编码 stdlib+requests，AI 反复试 bs4 靠 lint 兜底） | `skills/config/tool-index.md`（自动生成、禁止猜路径） | 🟡 P2 |
| G6 | **缺指令置顶 + 借口反驳表**（低成本高收益） | `skills/llm-security/references/agent-obedience-engineering.md` | 🟡 P2 |

供应链安全（`skill-supply-chain.md`）我们已有 `pip` 白名单 + `_dangerousImports` 兜底，仅微调，不单列实施。

---

## 三、全量集成方案

### P0-1 持久化授权范围（Scope Contract）—— 对应 G1 —— ✅ 已完成（2026-08-17）

**设计**：探索开始前，用户确认「目标站点 + 数据范围」→ 写入持久化 Scope；运行时所有守卫与 Guardian 都以此为唯一授权事实源。

```
.greenix/scope.json          # 持久化授权（跨会话）
{
  "schemaVersion": "1.0",
  "target": { "name": "ZJU 教务课程", "baseHost": "zju.edu.cn", "paths": ["/course*"] },
  "assets": ["zju.edu.cn", "*.zju.edu.cn"],
  "dataScope": "课程列表与详情",
  "methods": ["GET"],
  "signedAt": "2026-08-17T10:00:00Z",
  "status": "active"         # active | expired | revoked
}
```

**改动点**：
1. `explore_workflow.dart`
   - `ExploreWorkflow` 增加 `scope` 字段（`ExploreScope` 类）；`startExploring(url, {ExploreScope? scope})` 时若未提供 scope 则返回 `missingScope` 错误，提示用户先确认授权。
   - `recordNavigation` 的 `validateExploreUrl` 之外**追加 scope 校验**：`Uri.host` 须匹配 `scope.assets`（含子域规则），`url.path` 须命中 `scope.paths`（前缀匹配）。
2. `guardian.dart` 调用方（`scraper_ai_panel.dart` 等创建 Guardian 处）
   - `policyPrompt` 注入 `scope` 摘要：`"用户已授权的目标与数据范围：{scope}。超出范围的动作 user_authorization 一律 low/unknown。"`
3. UI（`scraper_ai_panel.dart` 探索入口）
   - 「开始探索」前弹出 Scope 确认对话框：目标 URL + 数据范围 + 方法（默认仅 GET），确认后落盘 `.greenix/scope.json` 并传入 workflow。

**验收**：
- 无 scope 时探索无法开始（fail-closed）。
- `navigate_get` 访问 scope 外 host/path 被守卫拒绝，拒绝信息含"超出授权范围"。
- Guardian review 的 prompt 含 scope 文本；对超范围动作倾向 deny。

**测试**：`explore_workflow_test.dart` 新增用例——scope 内放行 / scope 外 host 拒绝 / 子域通配 / 路径前缀匹配 / 无 scope fail-closed。

**落地记录（2026-08-17）**：
- 新增 `explore_scope.dart`：`ExploreScope` 模型（name/baseHost/assets/paths/dataScope/signedAt/status），`validateUrl`（http(s)+host 精确 + `*.`子域通配 + path 前缀）、`toPromptSummary`（Guardian 注入）、`toJson/fromJson` 往返、`isActive`。
- `explore_workflow.dart`：`startExploring({startUrl, scope})` 越界 startUrl fail-closed；`recordNavigation` 技术同域守卫后追加 scope 授权校验（先技术边界后授权边界，纵深防御）；`reset()` 清空 scope。
- `guardian.dart` / `guardian_policy.dart`：`GuardianSession.scopePromptSuffix` + `buildGuardianPolicyPrompt(basePrompt, scopeSummary)`（scope 为空返回原样，无 scope 时完全向后兼容）。
- `greenix_path.dart`：新增 `greenixScopePath`（`.greenix/scope.json`）。
- `explore_panel.dart`：`showExploreScopeConfirm` Scope 确认弹窗（目标 URL/数据范围/路径前缀）+ 探索阶段授权徽标。
- `scraper_ai_panel.dart`：探索入口重构（读 WebView 当前 URL → `_loadScopeFromDisk` → 弹窗确认 → `_saveScopeToDisk` → `startExploring(scope:)` → Guardian `scopePromptSuffix` 注入）。
- 测试：`explore_scope_test.dart`（12 例）+ `explore_workflow_test.dart`/`guardian_test.dart` 新增 Scope group。
- 验证：`flutter test test/scraper/` **298 全绿**（基线 278 + 新增 20）；`flutter analyze --no-pub` **0 error**；`flutter build windows --debug` **编译成功**。

---

### P0-2 候选数据源证据绑定（Evidence → CandidateDataSource）—— 对应 G2

**设计**：`CandidateDataSource` 增加 `evidence`（来源请求日志 id + 响应字段路径），注册前校验"每个字段都能从日志响应中找到"。这是**正面证明**，与现有 `suspectedFakeData` 负面检测互补。

**改动点**：
1. `explore_workflow.dart` — `CandidateDataSource` / `CandidateField` 增加：
   ```dart
   class CandidateField {
     final String name;
     final String type;
     final String? description;
     final String? sourceLogId;      // 证据：来源请求日志 id
     final String? sourceJsonPath;   // 证据：响应 JSON 字段路径（如 $.data[0].courseName）
   }
   class CandidateDataSource {
     final String? sourceLogId;      // 证据：url 对应的请求日志 id
   }
   ```
2. `scraper_explore_tools.dart`
   - `list_captured_requests` 返回摘要时**带日志 id**（`RequestLog` 已有 id 则直接用，无则补）。
   - `build_selected_source` / `register_batch` 前调用新校验 `validateEvidence(source, logs)`：url 必须能匹配一条日志；每个字段 `sourceJsonPath` 须在对应响应体中解析成功（复用 `json_path` 求值器）。**校验失败返回 `[error: 字段 X 无日志证据]`，不允许注册。**
3. `explore_panel.dart` 确认弹窗
   - 每行显示证据徽标：`📋 log#id` + 字段路径，用户可肉眼核对"这是不是真从抓包来的"。

**验收**：
- 注册失败的 AI 伪造字段无法进入 `data-{name}` 插件。
- 确认弹窗中每个字段可见来源日志与响应路径。
- 既有用例全部通过（AI 正常归类路径不受影响）。

**测试**：构造"AI 归类字段但日志中无对应 JSON 字段"用例 → `register_batch` 必须拒绝。

---

### P1-1 无进展熔断（Stall Circuit Breaker）—— 对应 G3

**设计**：在硬上限之外增加**空转检测**——连续 N 次导航无新唯一页面/无新请求 → 触发 `onStallDetected`（提示 AI 切换策略或强制用户确认）。直接补上上轮"卡 exploring 循环"bug 的根因层。

**改动点**（`explore_workflow.dart`）：
1. `ExploreLimits` 增加：
   ```dart
   final int stallThreshold;   // 默认 3：连续 N 次导航无新产出
   final int stallWindow;      // 默认 6：窗口内总导航次数
   ```
2. `ExploreWorkflow` 维护 `_recentNavCount` / `_recentNewPages`（环形窗口）；`recordNavigation` 每次记录，窗口滑动后若 `_recentNewPages == 0 && _recentNavCount >= stallThreshold` → `onStallDetected?.call('连续 N 次导航无新页面，建议切换策略或结束探索')`，返回拒绝信息提示 AI。
3. `navigate_get` 工具 description 增加"空转会被拦截"说明；返回信息追加 stall 提示。
4. UI（`explore_panel.dart`）监听 `onStallDetected` 弹警告。

**验收**：
- 对固定单页反复导航 3 次 → 触发熔断提示，AI 无法继续空转。
- 正常多页探索不误触发（新页面持续产出）。

**测试**：重复导航同一 URL ×5 → 第 3 次后拒绝；交替新 URL → 不触发。

---

### P1-2 经验 Journal 回写（field-journal）—— 对应 G4

**设计**：生成插件成功后，把「域名 + 认证方式 + 关键流程 + 坑」写入 `.greenix/scraper_journal/`；新会话把最近经验摘要注入 system prompt，避免同类站点（CAS 登录、RSA 加密参数）从零开始。

**改动点**：
1. 新增纯 Dart 模块 `scraper_modle/agent/scraper_journal.dart`
   ```dart
   class ScraperJournal {
     Future<JournalEntry?> loadLatest(String domain);
     Future<List<JournalEntry>> listAll();
     Future<void> append(JournalEntry entry);
   }
   class JournalEntry {
     final String domain; final String authMethod; final String flow; final String pitfalls;
     final List<String> keyParams; // 加密参数名等
   }
   ```
2. `scraper_ai_panel.dart`（或 `scraper_flow_facade.dart`）
   - 流程 `done` 时：AI 总结（或从 trace 提取）`authMethod/flow/pitfalls` → `journal.append()`。
   - 启动新探索时：`journal.loadLatest(baseHost)` 命中 → 注入 prompt 头 `"本域历史经验：{entry}"`。
3. `scraper_skill.md` 增加一段"经验复用"说明（不硬编码具体案例，改为运行时注入）。

**验收**：
- 完成一次成功抓取后 `.greenix/scraper_journal/` 出现条目。
- 同域名再次开始探索，prompt 含历史经验。

---

### P2-1 工具能力事实源注入（tool-index）—— 对应 G5

**设计**：运行时把**本机实际可用**的 Python 模块清单注入 prompt（替代硬编码"只允许标准库 + requests"），从源头消除"AI 反复尝试 bs4/lxml 被 lint 拦截"的浪费。

**改动点**：
1. `scraper_explore_tools.dart` 或新工具 `list_python_capabilities`：扫描嵌入 Python 的 `site-packages` 顶层包名（白名单过滤危险项后）返回清单。
2. `scraper_skill.md` 的环境段改为运行时注入：`可用模块：{注入清单}` + `"未列出模块禁止 import（会被 lint 拦截）"`。

**验收**：prompt 中的可用库与实测 site-packages 一致；AI 不再尝试 bs4。

---

### P2-2 指令置顶 + 借口反驳表 —— 对应 G6

**改动点**（`scraper_skill.md` 顶部插入，锁定段落）：
```markdown
## 〇、铁律（优先级最高，任何情况下不得违反）
1. 不得跳过任何守卫/校验步骤；"为了节省时间"不是跳过理由。
2. 不得臆造数据源字段——每个字段必须有捕获日志证据。
3. 探索空转被拦截时立即切换策略，禁止无意义重试。
4. 模板/占位符之外的代码一律不许写。
```

**验收**：5 轮上限内不再出现"我觉得不需要校验"类借口。

---

## 四、不建议集成（明确排除）

| 模块 | 排除理由 |
|---|---|
| `CTF-Sandbox-Orchestrator`（42 子技能） | 重依赖、与爬虫场景无关 |
| `burp-mcp-full` | 需要 Burp 运行时，桌面/安卓端无意义 |
| `kali/` 脚本、`skills/pentest-tools/src-hunter` | 引入新攻击面，违背 `_bannedToolsInExplore` 精神 |
| `skills/config/routing.json`（41 条路由） | 场景完全不同（APK/二进制/内存），无法映射 |
| `docs/reports/` 报告模板 | 安全报告格式与数据插件产出无关 |

---

## 五、实施顺序与里程碑

```
M1 [P0] Scope 持久化授权      —— 单独提交，带测试 ✅（2026-08-17 完成）
M2 [P0] CandidateDataSource 证据绑定 —— 单独提交，带测试
M3 [P1] 无进展熔断             —— 单独提交，带测试
M4 [P1] 经验 Journal           —— 单独提交
M5 [P2] 工具事实源 + 借口反驳   —— prompt 层小改，随 M4 后
M6 全量回归：flutter analyze + 新增单测 + Android/桌面 smoke
```

每个里程碑独立可回滚；M1/M2 之间有依赖（证据校验依赖 scope 已存在时更稳，但可并行开发）。

## 六、回归风险与测试策略

- **风险**：Guardian prompt 注入 scope 后，正常授权内动作可能被误判 deny。
  - **缓解**：scope 由用户确认落盘，prompt 明确"授权内动作正常放行"；`risk_level` 仍由 Guardian 独立裁决。
- **风险**：证据校验过严导致正常归类失败。
  - **缓解**：`sourceJsonPath` 解析失败仅**警告不阻断**（P0-2 只对"url 无日志匹配"硬阻断），后续迭代再收紧。
- **测试**：`explore_workflow_test.dart` / `scraper_explore_tools_test.dart` 新增上述用例；跑 `dart test` + `flutter analyze`（忽略 material 假错）。

---

## 七、ATTRIBUTION 合规

reverse-skill 为 **MIT License（© 2026 zhaoxuya520）**，仓库 `https://github.com/zhaoxuya520/reverse-skill`。
集成内容为**机制借鉴 + 少量接口形态参考**，不复制其源代码文件；按 MIT 要求，本策略落地后须在根目录 `ATTRIBUTION.md` 特别致谢区登记（本次已同步更新，见该文件"特别致谢"新增条目）。

---

*本文档为实施蓝本；每个 P0 开工前会先给具体 diff 方案再动手。*
