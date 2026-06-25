# CLI Command Reference — `reasonix_gr`

> `reasonix_gr` 是 [DeepSeek-Reasonix](https://github.com/esengine/DeepSeek-Reasonix) (MIT) 的多智能体集群衍生物。

## 两种工作模式

| 模式 | 命令 | 适用 | 流程 |
|------|------|------|------|
| **联邦 CEO** | `reasonix_gr ceo` | 全仓库整改、跨模块重构 | 轻量：CEO 分派→Keeper→Executor，**不走 11 步** |
| **Skill 11步** | `reasonix_gr task submit` | 单次聚焦任务、常规开发 | 完整：状态机约束 11 步强制流程 |

> 联邦模式目前**探索中**——跨模块重构足够复杂，叠加 11 步会导致上下文过早枯竭。

## 构建

```powershell
cd agent_contributing\evergreen_agents\reasonix
make build           # → bin/reasonix_gr(.exe)
```

## 原生 Reasonix 命令 (继承)

```powershell
reasonix_gr run "implement the TODOs in main.go"
reasonix_gr chat                    # 交互式 TUI
reasonix_gr serve                   # HTTP/SSE 服务器
reasonix_gr setup                   # 配置向导
reasonix_gr config show             # 查看配置
reasonix_gr mcp list                # 列出 MCP 插件
reasonix_gr doctor                  # 系统诊断
```

详见 `reasonix_gr help` 和 [Reasonix 官方文档](https://github.com/esengine/DeepSeek-Reasonix)。

## Evergreen 联邦命令 (新增)

### `reasonix_gr ceo` — 交互式 CEO（推荐入口）

```powershell
reasonix_gr ceo
# 用户只跟 CEO 对话。CEO 不懂代码，只做协调：理解意图→分派给 Keeper/Executor→综合回复。
# 内置命令：/agents（查看全体 Agent 仪表盘）、/watch <N>（切到任意 Agent 看实时输出）、Enter（回到 CEO）
# 此模式不走 11 步完整流程——轻量、快速、适合全仓库整改。
```

### `reasonix_gr bootstrap` — 一键初始化联邦

```powershell
reasonix_gr bootstrap
# 读取 config/module_registry.yaml → 创建 Keeper agents → 生成 OWNERS 文件 → 加载经验库
```

### `reasonix_gr experience` — 经验库

```powershell
reasonix_gr experience search "cache pattern"
reasonix_gr experience search "overflow" --type antipattern --module palace
reasonix_gr experience stats
```

### `reasonix_gr module` — 模块管理

```powershell
reasonix_gr module list                          # 列出所有模块
reasonix_gr module deps --module auth            # 查看依赖链
reasonix_gr module contracts --module courses    # 查看接口合约
```

### `reasonix_gr inspect` — 代码健康扫描

```powershell
reasonix_gr inspect scan --module palace         # 单模块扫描
reasonix_gr inspect antipatterns                 # 反模式检测
reasonix_gr inspect contracts --module auth      # 合约验证
```

### `reasonix_gr agent` — Agent 管理

```powershell
reasonix_gr agent list                           # 列出所有 Agent
reasonix_gr agent credit --agent eva-keeper-auth # 信用评分
```

### `reasonix_gr federation` — 联邦运行

```powershell
reasonix_gr federation run --task "修复课表溢出" --module schedule
# Planner → Contract → Keeper → Executor → Review → Merge
```

### `reasonix_gr audit` — 决策审计

```powershell
reasonix_gr audit log --limit 20
reasonix_gr audit log --agent eva-keeper-courses
```

## 配置

```toml
# reasonix_gr.toml — Reasonix 原生配置 (MIT)
default_model = "deepseek-flash"

[[providers]]
name        = "deepseek-flash"
kind        = "openai"
base_url    = "https://api.deepseek.com"
model       = "deepseek-v4-flash"
api_key_env = "DEEPSEEK_API_KEY"

# [federation] — Evergreen 联邦配置 (GPL-3.0)
[federation]
module_registry_path = "agent_contributing/evergreen_agents/config/module_registry.yaml"
experience_dir = "agent_contributing/experiences"

[federation.credit]
initial_score = 100.0
min_execute_score = 50.0

[federation.llm_routing.deep_thinking]
provider = "deepseek"
model = "deepseek-v4-pro"

[federation.llm_routing.quick_thinking]
provider = "deepseek"
model = "deepseek-v4-flash"
```

## 模型

| 模型 | 用途 | Context |
|------|------|---------|
| `deepseek-v4-flash` | 快速响应 (Keeper, Executor, Inspector) | 131,072 |
| `deepseek-v4-pro` | 深度思考 (Planner, Librarian) | 131,072 |
