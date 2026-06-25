# Evergreen Agents — 百级多Agent联邦协作框架

效法真实世界大型工程团队的组织方式：**分层自治 + 契约治理 + 经验外化**。

> **定位**：`agent_contributing/evergreen_agents` 在**全仓库范围整改重构**时启用。
> 此模式下**不走** `agent_contributing/skill/` 的完整 11 步流程（太复杂，且目前仍在探索中）。
> 针对单次聚焦任务的常规开发，请使用 `agent_contributing/skill/SKILL.md` 定义的 11 步工作流。
>
> | 模式 | 入口 | 适用场景 | 流程 |
> |------|------|---------|------|
> | **联邦模式** | `reasonix_gr ceo` | 全仓库整改、跨模块重构 | CEO 分派→Keeper 审查→Executor 实现（轻量，无强制步骤） |
> | **Skill 模式** | `reasonix_gr task submit` | 单次聚焦任务、常规开发 | 11 步完整流程（读经验→读规则→分析→确认→写代码→测试→文档→编译→人类反馈→写卡→PR） |

> **Evergreen Agents v2** 是 [DeepSeek-Reasonix](https://github.com/esengine/DeepSeek-Reasonix) (MIT) 的**深度集成多智能体集群衍生物**。参见 [ATTRIBUTION.md](ATTRIBUTION.md)。

## 设计哲学

效法真实大型团队的经典策略：

| 真实团队 | 对应机制 |
|---------|---------|
| 特性团队负责模块，边界清晰 | Fleet: 每模块 Keeper + Executor 对，持久 session，闲置零消耗 |
| Tech Lead 分解任务 | Planner (deep-thinking, RAG 注入经验库) |
| Module Owner 审查代码 | Keeper (注入 REVIEW_CHECKLIST.md, 层级 OWNERS) |
| 接口即契约，修改需联合评审 | Contracts: 提案→双签→API Linter 兼容性检查 |
| CI 失败→经验推送 | Suggest: 错误签名匹配→推荐经验卡 |
| 审查不仅是找 Bug，更是知识传递 | REVIEW_CHECKLIST.md: 从经验库自动生成 |

## Fleet 架构

```
Fleet: 3 特殊 Agent + 2×N_modules 个模块 Agent

  Planner (1)    ─ 全局，deep-thinking
  Inspector (1)  ─ 全局，read-only 扫描
  Librarian (1)  ─ 全局，deep-thinking 策展
  Keeper × 26    ─ 每模块一个，持久 session，闲置零消耗
  Executor × 26  ─ 每模块一个，持久 session，闲置零消耗

  总计: 55 persistent agents
  上下文容量: 55 × 131K ≈ 7.2M tokens
  单次任务: ~4 agents active, ~51 idle
```

## 架构关系

```
reasonix_gr/
├── 继承自 DeepSeek-Reasonix (MIT)
│   ├── 事件驱动 · 自注册工具表 · 权限门禁 · Controller
│   ├── Coordinator (双模型) · TUI · CLI · MCP 插件
│   └── LSP · 沙箱 · Checkpoint · Context 压缩
│
└── Evergreen 延申 (GPL-3.0) — 17 包
    ├── 组织:    owners/ (层级OWNERS) + review/ (审查门)
    ├── 契约:    contracts/ (双签 + API Linter)
    ├── 经验:    experience/ (CRUD + RAG + CI错误推送) + checklist/
    ├── 信用:    credit/ (6维评分) + audit/ (不可篡改日志)
    ├── 舰队:    federation/ (Fleet + Runtime + Workflow)
    ├── Agent:   keeper/ + librarian/ + inspector/
    ├── 协议:    protocols/ + metrics/
    └── 入口:    bootstrap/ + CLI 联邦命令
```

## 实现状态

| 包 | 功能 |
|------|------|
| `types/` | 领域枚举 + struct + markdown 解析 (17 tests) |
| `credit/` | 6 维信用评分 + 5 级分类 (11 tests) |
| `audit/` | JSONL 审计日志 + event.Sink 自动记录 |
| `experience/` | CRUD + 搜索 + RAG + **CI错误→经验推送** |
| `contracts/` | 提案→双签→**API Linter 兼容性检查** |
| `owners/` | 双向映射 + **层级 OWNERS (根→叶责任链)** |
| `review/` | submit → approve/reject → canMerge |
| `checklist/` | **REVIEW_CHECKLIST.md 生成 + Keeper 注入** |
| `federation/` | **Fleet (持久化舰队)** + Runtime + Workflow + ConditionalLogic |
| `protocols/` | CL size 验证 + MergeQueue + 测试门禁 |
| `metrics/` | DORA + SPACE |
| `keeper/` | Module Keeper (持久 session, LLM 审查) |
| `librarian/` | Librarian (持久 session, 经验策展) |
| `inspector/` | Inspector (LLM + 规则回退代码扫描) |
| `bootstrap/` | Fleet.CommissionModules() |

## 快速开始

```powershell
# 1. 构建 + 配置
go build -o bin/reasonix_gr.exe ./cmd/reasonix_gr
$env:DEEPSEEK_API_KEY = "sk-your-key"
.\bin\reasonix_gr.exe setup

# 2. 启动 CEO（推荐日常入口）
.\bin\reasonix_gr.exe ceo
# → 67 agents at your service
# → /agents 查看面板  /watch <id> 看实时输出  /help 帮助

# 3. 或直接跑任务
.\bin\reasonix_gr.exe federation run --task "add login test" --module auth
```

## License

- `reasonix/` — MIT (Copyright (c) 2026 Reasonix Contributors)
- Evergreen 延申层 — GPL-3.0
