# Evergreen Agents v2 — 架构设计文档

## 0. 与 Reasonix 的关系

**Evergreen Agents v2** 不是独立项目。它是 [DeepSeek-Reasonix](https://github.com/esengine/DeepSeek-Reasonix) (MIT) 的一个**深度集成的多智能体集群衍生物**。

```
DeepSeek-Reasonix (MIT, Go)
    │
    └── reasonix_gr/  ← 我们 fork 并深度扩展
        ├── internal/       ← Reasonix 原生单智能体引擎 (保留)
        └── internal/evergreen/ ← Evergreen 多智能体联邦层 (新增)
```

**集成方式：** 不是把 Reasonix 当库来调，而是直接在其 `internal/` 骨骼里长出多智能体集群能力。事件系统、工具注册表、权限门、Controller、Agent loop——全部原生复用，零适配损耗。

---

## 1. 设计哲学：效法真实世界的大型团队协作

核心理念来自真实软件工程团队的运作方式：

| 真实团队 | Evergreen 对应 |
|---------|---------------|
| 特性团队（Feature Team）负责模块 | Fleet: 每模块一对 Keeper + Executor 持久 Agent |
| Tech Lead 分解任务 | Planner (deep-thinking) |
| Module Owner 审查代码 | Keeper (persistent session, 累积模块知识) |
| Senior Dev 实现代码 | Executor (persistent session, 累积实现上下文) |
| QA Architect 扫描质量 | Inspector (read-only) |
| Knowledge Manager 维护经验库 | Librarian (XP card curation) |
| OWNERS 文件强制审批 | Hierarchy: 根→叶责任链, 每层至少一人批准 |
| 接口契约治理 | Contracts: 提案→双签→兼容性检查 |
| CI 失败自动提示经验 | Suggest: 错误签名匹配→推荐经验卡 |
| 代码审查清单 | REVIEW_CHECKLIST.md: 从经验库生成 |

**核心架构：持久化 Agent 舰队 (Fleet)**

```
Fleet: 3 + 2×N_modules 个持久 Agent

  Planner (1)    — 全局视角，任务分解
  Inspector (1)  — 全局只读扫描
  Librarian (1)  — 经验策展
  Keeper × 26    — 每模块一个 Owner，持久 session，闲置零消耗
  Executor × 26  — 每模块一个 Developer，持久 session，闲置零消耗

  总计: 55 persistent agents
  总上下文容量: 55 × 131K ≈ 7.2M tokens
  单次任务消耗: ~4 agents (其余 51 闲置，零上下文消耗)
```

---

## 2. 核心架构模式

### 2.1 事件驱动解耦 (继承自 Reasonix)

```go
// Reasonix 原生 event.Sink 接口
type Sink interface { Emit(Event) }

// Evergreen 扩展：18 种 Federation 事件 Kind
FederationStarted, TaskCreated, ContractProposed,
ExperienceApproved, CreditChanged, ReviewSubmitted...
```

### 2.2 自注册工具表 (继承自 Reasonix)

```go
// Reasonix 原生模式
func init() { tool.RegisterBuiltin(bash{}) }

// Evergreen 扩展：按角色过滤的工具白名单
var RoleToolSets = map[string][]string{
    "planner":       {"read_file", "code_search", "dependency_analyze", "experience_query"},
    "module_keeper": {"read_file", "code_search", "experience_query", "dependency_analyze"},
    "task_executor": {"read_file", "write_file", "bash", "grep", "glob", ...},
    "inspector":     {"read_file", "code_search", "lint_check", "experience_query"},
    "librarian":     {"read_file", "experience_query"},
}
```

### 2.3 持久化 Agent 舰队 (Fleet) + CEO 入口

```go
fleet := federation.NewFleet(opts)
fleet.CommissionModules(allModules)  // ALL 模块注册，不管 active/wip/planned

// CEO — 用户唯一入口，不懂代码，只做协调
ceo := federation.NewCEO(fleet, sink)
resp, _ := ceo.Chat(ctx, "帮rvpn实现VPN管理")

// CEO 分类意图 → 分派给 Keeper/Executor → 综合回复
// 用户看不到背后 67 个 Agent，只跟 CEO 对话

// Agent Monitor — 用户可随时切到任意 Agent 看实时输出
monitor := fleet.Monitor()
monitor.RenderDashboard()        // /agents 命令
monitor.RenderAgentOutput(id, 50) // /watch <agent-id> 命令
```

**CEO 约束：**
- 不懂代码 — 只有 `experience_query` + `dependency_analyze` 两个工具
- 不读不写代码 — 那是 Keeper/Executor 的职责
- 只做：理解意图 → 找对人 → 综合回复

### 2.4 层级化 OWNERS (Hierarchy)

```go
hierarchy.AddDirectory("lib/features/auth",         []string{"eva-keeper-auth"})
hierarchy.AddDirectory("lib/features/auth/widgets", []string{"eva-keeper-widgets"})

pending, ok := hierarchy.ValidateChange(changedFiles, approvals)
// → MR 必须获得所有涉及层级至少一人批准，非仅叶子层
```

### 2.5 双层级 LLM 路由 (继承自 Reasonix Coordinator)

- **深度思考** (`deepseek-v4-pro`): Planner, Librarian
- **快速思考** (`deepseek-v4-flash`): Keeper, Executor, Inspector

---

## 3. 数据流

```
Human Input ("add login test", module=auth)
  │
  ├─ Planner (deep-thinking, 1 agent)
  │   └─ 分解任务 + RAG 注入经验库 (patterns/antipatterns/constraints)
  │
  ├─ [层级 OWNERS 检查]
  │   └─ 涉及 lib/features/auth/ → auth Keeper 必须批准
  │
  ├─ Keeper(auth) (persistent session, 只读工具)
  │   └─ 注入 REVIEW_CHECKLIST.md → 逐项审查
  │
  ├─ Executor(auth) (persistent session, 读写工具)
  │   └─ 11-step workflow: 读经验→读规则→分析→确认→写代码→测试→文档→PR
  │
  ├─ API Linter
  │   ├─ LintContract() → 命名规范 + 废弃标注检查
  │   └─ CheckCompatibility() → 兼容性检查 (类型变更/字段删除 = BREAKING)
  │
  ├─ CI 失败?
  │   └─ Suggest() → "📚 Experience Library suggests: 参考 XX 经验卡"
  │
  └─ Librarian (deep-thinking)
      └─ 策展经验卡 → 存入 ExperienceStore → 下次 Planner 自动注入
```

---

## 4. 模块注册

- **Flutter 侧**: `lib/features/<name>/module.dart` (编译时声明)
- **Agent 侧**: `config/module_registry.yaml` (运行时发现)
- **Go 侧**: `evergreen/bootstrap/` 读取 YAML → Fleet.CommissionModules()

---

## 5. 实现路线图

| 阶段 | 内容 | 状态 |
|------|------|:--:|
| Phase 1 | Python 原型：内核 + 5 Agent + 9 工具 + CLI | ✅ (已归档) |
| Phase 2 | Go 移植：`evergreen/types/` 领域类型 | ✅ |
| Phase 3 | Go 移植：event/config/tool 扩展 reasonix 原生包 | ✅ |
| Phase 4 | Go 移植：credit/audit/experience/contracts/governance | ✅ |
| Phase 5 | Go 移植：federation + protocols + metrics | ✅ |
| Phase 6 | Go 移植：keeper/librarian/inspector Agent 角色 | ✅ |
| Phase 7 | Go 移植：bootstrap + builtin tools | ✅ |
| Phase 8 | Fleet: 持久化 Agent 舰队 + 闲置零消耗 | ✅ |
| Phase 9 | 层级化 OWNERS + REVIEW_CHECKLIST + 经验推送 + API Linter | ✅ |
| Phase 10 | ADR 系统 + Bug 知识库 | ⬜ 规划中 |

---

## 6. 当前实现范围 (Go)

### `internal/evergreen/` (17 包)

| 包 | 功能 | 测试 |
|------|------|:--:|
| **types/** | 领域枚举 + struct + markdown 解析 | 17 |
| **credit/** | 6 维信用评分 + 5 级分类 | 11 |
| **audit/** | JSONL 审计日志 + event.Sink 自动记录 | - |
| **experience/** | CRUD + 搜索 + RAG + **Suggest(CI→经验推送)** | - |
| **contracts/** | 提案→双签 + **API Linter(兼容性检查)** | - |
| **owners/** | 双向映射 + **Hierarchy(层级OWNERS 根→叶)** | - |
| **review/** | submit→approve/reject→canMerge | - |
| **checklist/** | **REVIEW_CHECKLIST.md 生成 + Keeper 注入** | - |
| **federation/** | **Fleet(持久化舰队)** + **CEO(用户入口)** + **Monitor(实时面板)** + Workflow + Runtime | - |
| **protocols/** | CL size 验证 + MergeQueue + 测试门禁 | - |
| **metrics/** | DORA + SPACE | - |
| **keeper/** | Module Keeper (持久 session, LLM 审查) | - |
| **librarian/** | Librarian (持久 session, 经验策展) | - |
| **inspector/** | Inspector (LLM + 规则回退) | - |
| **bootstrap/** | 读 YAML → Fleet.CommissionModules() | - |

### 扩展的 reasonix 原生包

| 包 | 扩展内容 |
|------|---------|
| **event/** | 18 Federation Kind + FederationPayload 家族 |
| **tool/** | RoleToolSets + RegistryForRole |
| **config/** | FederationConfig + YAML 支持 |
| **tool/builtin/** | experience_query + dependency_analyze |
| **cli/** | 7 个联邦子命令 (bootstrap/experience/module/inspect/federation/agent/audit) |

---

## 7. 与 11 步 Skill 工作流的关系

**Evergreen Agents（联邦模式）和 `agent_contributing/skill/` 的 11 步工作流是两种互补模式：**

| | 联邦模式 | Skill 模式 |
|------|---------|-----------|
| **入口** | `reasonix_gr ceo` | `直接对话（/skill 加载 SKILL.md）` |
| **适用** | 全仓库整改、跨模块重构 | 单次聚焦任务、常规开发 |
| **流程** | CEO 分派 → Keeper → Executor（轻量，探索中） | 11 步强制流程（状态机约束） |
| **人类参与** | 对话式，随时介入 | 步骤 3 + 步骤 9 硬门禁 |
| **复杂度** | 低（一次对话完成） | 高（每步必须执行） |

> 联邦模式目前仍在**探索阶段**——不强制 11 步是因为跨模块重构本身就足够复杂，
> 叠加完整流程会让 Agent 输出过长、上下文过早枯竭。未来可能在联邦模式中
> 选择性引入 11 步中的关键步骤（如步骤 10 写经验卡）。

## 8. 环境要求

- Go ≥ 1.25
- `DEEPSEEK_API_KEY` 环境变量
- `go build -o bin/reasonix_gr.exe ./cmd/reasonix_gr` → 23MB 静态二进制
