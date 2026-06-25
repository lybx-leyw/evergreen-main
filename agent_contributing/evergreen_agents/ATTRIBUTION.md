# 致谢与开源许可

> Evergreen Agents 的架构设计建立在多个优秀开源项目的基础上。
> 本文件列出了所有参考项目的归属、许可证信息及合规说明。

---

## reasonix_gr：DeepSeek-Reasonix 的多智能体集群衍生物

**reasonix_gr** 是 [DeepSeek-Reasonix](https://github.com/esengine/DeepSeek-Reasonix) (MIT) 的一个**深度集成 fork**。

我们在 Reasonix 的单智能体 Go 引擎骨骼里直接长出了多智能体联邦能力（事件扩展、信用评分、经验库、合约系统、OWNERS 治理、联邦编排），形成 `reasonix_gr`——一个单模块、单二进制的多智能体集群变体。

### 继承自 DeepSeek-Reasonix (MIT)

Reasonix 的事件驱动架构、自注册工具表、权限门禁、传输无关 Controller、Provider 注册表、TUI、CLI、MCP 插件系统——所有这些原生的单智能体基础设施被完整保留并直接复用。

```
reasonix/internal/           ← Reasonix 原生 Go 代码 (MIT)
reasonix/internal/evergreen/ ← Evergreen 多智能体联邦层 (GPL-3.0)
```

### 借鉴的设计模式

| 模式 | 本项目对应 |
|------|-----------|
| 事件驱动架构（`event.Sink` 接口） | 原生复用 + 18 种 Federation 事件 Kind |
| 自注册工具表（`RegisterBuiltin`） | 原生复用 + RoleToolSets 按角色过滤 |
| 权限门禁（PermissionGate） | 原生复用 |
| Boot 组装模式（`boot.Build`） | 原生复用 |
| 双模型 Coordinator | 原生复用（Planner + Executor 模式） |

> Evergreen 延申层（`internal/evergreen/`）是用 Go 从零编写的，未复制 Reasonix 的任何 Go 源代码。
> 架构概念层面的继承标注于此。

---

## TradingAgents — 多 Agent LLM 金融交易框架

- **项目**: TauricResearch/TradingAgents
- **仓库**: `https://github.com/TauricResearch/TradingAgents`
- **论文**: arXiv:2412.20138 — *TradingAgents: Multi-Agents LLM Financial Trading Framework*
- **许可证**: Apache License 2.0

**借鉴的设计模式：**

| 模式 | 本项目对应 |
|------|-----------|
| 角色工厂模式（`create_*_agent`） | `evergreen/{keeper,librarian,inspector}/` — 3 个角色 |
| 双层级 LLM 路由（deep/quick thinking） | 复用 Reasonix Coordinator + LLMRoutingConfig |
| StateGraph 编排 | `evergreen/federation/` — 6 阶段 Workflow DAG |
| 条件路由（ConditionalLogic） | 辩论循环 / 合同审批 / 人工升级 |
| 结构化输出 | `evergreen/types/` — PlannerOutput / ReviewVerdict / InspectorReport |
| 辩论循环模式 | `ShouldContinueDebate()` |

> Evergreen Agents 与 TradingAgents 在问题域上有本质不同（代码工程 vs 金融交易），
> 借鉴的是其 Agent 编排架构模式，非业务逻辑。

---

## 技术栈

本项目的运行依赖以下开源组件：

| 组件 | 用途 | 许可证 |
|------|------|--------|
| [DeepSeek-Reasonix](https://github.com/esengine/DeepSeek-Reasonix) | 单智能体引擎骨架 | MIT |
| [cobra](https://github.com/spf13/cobra) | CLI 框架 | Apache 2.0 |
| [gopkg.in/yaml.v3](https://github.com/go-yaml/yaml) | YAML 配置解析 | MIT |
| [DeepSeek API](https://api.deepseek.com) | LLM 推理服务 | DeepSeek Terms |

---

## 与 Evergreen Multi-Tools 的关系

Evergreen Agents 是 Evergreen Multi-Tools（GPL-3.0）的子项目，位于 `agent_contributing/evergreen_agents/`。与主项目的交互：

- 读取 `agent_contributing/experiences/` 中的经验卡片
- 维护 `agent_contributing/EXPERIENCE.md` 索引文件
- 调用 `agent_contributing/skill/agent_flow.py` 驱动 11 步工作流
- 为 Flutter 侧的 `lib/features/*/` 模块生成 OWNERS 文件
- 遵循 `AGENT_CONTRIBUTING.md` 中的 Agent 规则

---

## 许可

### reasonix_gr 的许可证分层

| 代码层 | 许可 |
|--------|------|
| `reasonix/internal/` (除 evergreen/ 外) | MIT — Copyright (c) 2026 Reasonix Contributors |
| `reasonix/internal/evergreen/` | GPL-3.0 — Evergreen Multi-Tools |
| `reasonix/cmd/`, `reasonix/internal/event/`, `reasonix/internal/tool/`, `reasonix/internal/config/` | MIT 基础上修改 — 修改部分 GPL-3.0 |

```
Evergreen 延申层 — GPL-3.0-only

Copyright (C) 2026 Evergreen Multi-Tools

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
```

Reasonix 原始代码 — MIT

```
Copyright (c) 2026 Reasonix Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction...
```
