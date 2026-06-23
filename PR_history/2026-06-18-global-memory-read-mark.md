# PR_history/2026-06-18-global-memory-read-mark.md

## 修改目的

修复 BUG-16：全局记忆在 Greenix 多轮思考模式下被重复读取的问题。

**问题现象**：同一用户消息回合内，Greenix Agent 循环运行多步（compose → LLM → tool calls → execute → loop），每步都会触发全局记忆读取（读盘 I/O），导致不必要的性能开销和潜在的读写竞争。

**根因**：Controller._autoReadGlobalMemory() 无回合级去重，且 MemoryAgent 在回合结束时写入新记忆后，下一回合的第一步又重复读取同一份数据。

**修复方案**：在 Controller 中增加 `_globalMemoryReadThisTurn` 布尔标记。
- `send()`（新用户消息）→ 重置为 `false`
- `_autoReadGlobalMemory()` → 检查标记：若 `true` 则跳过；若 `false` 则读取并设为 `true`
- 同一回合内的后续 Agent 步骤复用已读取的上下文，不重复读盘

## 修改文件清单

- `lib/core/agent/controller/controller.dart` — 添加 `_globalMemoryReadThisTurn` 字段，在 `send()` 重置，在 `_autoReadGlobalMemory()` 检查
- `test/core/agent/tools/global_memory_tools_test.dart` — 新增「写后读一致性」测试组（3 个测试），验证写入后立即读取到最新内容

## 核心逻辑说明

```
用户点击发送
  └─ Controller.send()
       ├─ _globalMemoryReadThisTurn = false   ← 新回合重置
       └─ _runAgent()
            ├─ _autoReadGlobalMemory()
            │    ├─ if (_globalMemoryReadThisTurn) → skip ← 第二次调用跳过
            │    ├─ 读取全局记忆（磁盘 I/O）
            │    └─ _globalMemoryReadThisTurn = true
            ├─ _memory.buildContext()
            └─ agent.run() 主循环（多步骤）→ 用已读的 memoryContext，不重复读盘
```

**设计决策**：标记仅控制 Controller 的自动读取逻辑，不限制 AI 主动调用 `read_global_memory` 工具（AI 主动搜索特定记忆仍是合法的应用场景）。

## 潜在影响

- **正面**：大幅减少同一用户回合内的磁盘 I/O（从一个回合 3 次降至 1 次）
- **风险**：极低。回合间（用户发新消息时）标记自动重置，不会导致记忆更新丢失
- **兼容性**：不影响 ChatScreen 的 `setMemoryContext()` 调用（标记为 deprecated，但合并逻辑保持不变）

## 测试结果摘要

- 新增测试：`test/core/agent/tools/global_memory_tools_test.dart` ✅ 3 个新测试全部通过
- 全量测试：`flutter test` ✅ 977 通过，1 跳过，1 失败（预存：DeepSeekClient 429 限流测试，依赖实际 API 网络）
- 截图：待人工补充

## 人工验证清单（由人类执行）

- [x] 编译成功
- [x] 新功能在真机上表现符合预期
- [x] 已有核心流程（登录、课表、AI 对话）未受影响
- [x] 补充测试截图至本文件(不需要，主观上很难看出变更)
