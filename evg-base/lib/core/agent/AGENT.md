---
name: core-agent
role: Evergreen 上游 core/agent 子包 OWNER
scope: evg-base/lib/core/agent/
parent: core
---

# AGENT.md — core-agent 职责书

> 本文件是「谁负责这里」的职责书。技术原理见同目录 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/core/agent/`（独立纯 Dart 子包）
- 一句话定位：AI Agent 运行时 + 工具 + 记忆 + Skill + 守护的完整实现。

### 内部子域分区（本 OWNER 内，非独立 OWNER）

| 子域 | 目录 | 职责 |
|------|------|------|
| 主循环 | `agent/` | Agent.run() 主循环（Compactor→compose→chat→Tool→FinalReadiness） |
| 运行时/工厂 | `agent_runtime.dart` / `agent_factory.dart` | 全局组装 + 隔离 AgentAssembly + 工具白名单 |
| 控制器/会话 | `controller/` / `session_manager.dart` / `file_session_store.dart` | 会话管理 + 持久化 |
| 工具 | `tools/` | 读写文件/记忆/搜索/HTTP/PluginBridge/OCR 等 |
| 守护 | `guardian/` | Guardian 审查 + 策略 |
| 记忆 | `memory/` | 三作用域 + MemoryAgent + Allport 分组 |
| Skill | `skill/` | Skill 生成/重写 + inline/subagent 双模式 |
| 压实 | `compact/` | 上下文压实 |
| 输出风格 | `output_style/` | 输出格式 |
| 证据 | `evidence/` | 证据记录 |
| 参考 | `ref/` | 参考实现 |

## 2. 边界与红线

- ✅ 可以：改 `agent/` 内一切实现；新增工具、记忆作用域、Skill 能力。
- ❌ 禁止：引用 Flutter Widget（纯 Dart 子包）；改动其他子包（config/data/module/theme）；绕过 `AgentFactory` 的工具白名单机制。
- ⚠️ 需协调：`buildStandardTools` 是标准工具集唯一权威来源，改动影响所有隔离 Agent；嵌入 Agent 能力 = seedTools 经 preset 过滤，空候选集 + all 策略 = 零能力。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `AgentAssembly.fromConfig` | barrel | renderer（chat/multi_agent） | 构造参数变更需通知 renderer |
| `buildStandardTools` | `agent_factory.dart` | renderer | 标准工具集变更需广播 |
| `Controller.registry` | `controller.dart` | renderer | 工具禁用集合同步 |
| `AgentHttpServer` | HTTP（`.agent_port`） | plugins .exe | 端点变更需通知 plugins |
| `groupMemoriesByAllport` | `memory/memory.dart` | renderer | 分组逻辑变更需通知 renderer |

## 4. 规则（本 OWNER 内必须遵守）

- 纯 Dart，禁止 Flutter 依赖（隔离子包可 `cd lib/core/agent && dart test`）。
- 精确 import，禁止把重依赖 barrel 拉进纯 Dart 编译（skill_rewriter 踩坑）。
- 工具调用遵循 Gate → StormBreaker → pre-hook → call → post-hook。
- 隔离 Agent 能力状态必须从唯一真相源同步进隔离 Registry。

## 5. 验收标准

- 改完必须：`cd lib/core/agent && dart test`（全部测试通过）+ 相关 `flutter test` 无回归。

## 6. 引用索引

- 心智模型：`CLAUDE.md`
- 模块说明：`README.md`
- 上层职责书：`../AGENT.md`
