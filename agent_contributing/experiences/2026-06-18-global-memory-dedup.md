---
task_type: bug-fix
tags: [agent, memory, controller, performance, io]
files_touched:
  - lib/core/agent/controller/controller.dart
  - test/core/agent/tools/global_memory_tools_test.dart
difficulty: medium
outcome: success
date: 2026-06-18
related_pr: 2026-06-18-全局记忆回合内已读标记.md
related_files: [lib/core/agent/controller/controller.dart, lib/core/agent/memory/memory.dart]
---

## 做了什么

修复 BUG-16：Greenix Agent 多轮思考模式下，同一用户回合内全局记忆被重复读取（多次磁盘 I/O）。

## 关键决策

- **回合级布尔标记** 而非缓存内容：`_globalMemoryReadThisTurn` 仅控制是否跳过，不缓存内容。理由是标记简单可靠，不会引入缓存失效问题。
- **不限制 AI 主动调用工具**：标记仅控制 Controller 的自动读取，AI 主动调用 `read_global_memory` 工具搜索特定记忆仍然是合法的。

## 踩过的坑

### 要在正确的时机重置标记
- **问题**：最初把重置放在 `_runAgent()` 末尾，但 `_runAgent()` 内部有循环（多个 Agent 步骤），导致只有第一步读了记忆
- **根因**：标记应该在**用户发新消息**时重置，而不是在 Agent 循环内部重置
- **解决**：`send()`（用户新消息入口）中 `_globalMemoryReadThisTurn = false`，`_autoReadGlobalMemory()` 中检查并设置为 `true`

## 可复用的模式

### 回合级去重标记模式
```dart
class Controller {
  bool _flagThisTurn = false;

  void send(String userMessage) {
    _flagThisTurn = false;  // 新回合 → 重置
    _runAgent(userMessage);
  }

  void _autoDoSomething() {
    if (_flagThisTurn) return;  // 本回合已做过 → 跳过
    // ... 执行实际操作 ...
    _flagThisTurn = true;       // 标记本回合已完成
  }
}
```

### 测试写后读一致性
```dart
test('写入后立即读取到最新内容', () async {
  await tool.execute({'action': 'remember', 'fact': 'test fact'});
  final memories = store.all();
  expect(memories.any((m) => m.body.contains('test fact')), isTrue);
});
```

## 注意事项

- `controller.dart` 的 `_autoReadGlobalMemory()` 不是公共 API，外部不要直接调用
- 记忆系统的磁盘 I/O 是同步的（`readAsStringSync`），不适合在高频路径上调用
- `ChatScreen.setMemoryContext()` 已标记 deprecated，保留仅为向后兼容，不要在新代码中使用
