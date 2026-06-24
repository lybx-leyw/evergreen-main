---
task_type: experiment
tags: [flutter, navigator, dialog, async, debugLocked, addPostFrameCallback, go_router, black-screen, dead-end]
files_touched:
  - lib/features/zdbk/screens/training_plan_screen.dart
difficulty: hard
outcome: failure
date: 2026-06-24
superseded_by: (待定)
---

## 尝试了什么
在 `showDialog` + `await` 异步操作后，用 `WidgetsBinding.instance.addPostFrameCallback` 延迟调用 `Navigator.of(context).pop()`，以避免 `_debugLocked` 断言。

## 为什么失败
`addPostFrameCallback` 虽然绕过了 `_debugLocked`，但引入了更严重的问题：

### 错误链条
```
showDialog → loading dialog 显示
await downloadPlanPdf() → 下载失败 (空响应)
_fail() → addPostFrameCallback(() => Navigator.pop())
↓ 下一帧
Navigator.pop() → 弹出了 go_router 的根页面 (而非 dialog)
→ GoRouterDelegate: 'currentConfiguration.isNotEmpty' 断言失败
→ Navigator: '_debugLocked' 再次断言失败
→ 整个路由栈崩溃 → 黑屏
```

### 根因
`addPostFrameCallback` 延迟到下一帧执行时，Dialog 的路由状态可能与预期不一致。在某些时序下，`Navigator.of(context).pop()` 弹出的是 go_router 的最后一个页面而不是 loading dialog，导致路由栈完全清空。

关键日志：
```
GoRouterDelegate._debugAssertMatchListNotEmpty: Failed assertion: 'currentConfiguration.isNotEmpty'
Navigator.pop: Failed assertion: '!_debugLocked': is not true.
Lost connection to device.
```

## 学到什么
1. **`addPostFrameCallback` + `Navigator.pop()` 不是银弹**——延迟 pop 可能在错误时机操作 go_router 导航栈
2. `showDialog` 创建的路由和 go_router 的路由栈是两个不同的导航上下文，post-frame 回调无法可靠区分
3. 在 go_router 项目中使用 `Navigator.of(context).pop()` 比纯 Navigator 项目风险更高

## 被否决的方案
- ❌ `addPostFrameCallback(() => Navigator.pop())` — 会误弹 go_router 根路由，导致路由栈清空黑屏
- ❌ 直接用 `Navigator.pop()` — 触发 `_debugLocked`
- ❌ 在 Dialog builder 中用 PopScope(canPop: false) + 延迟 pop — 同样有问题

## 可能的替代方向（待探索）
1. 不用 `showDialog`，改用 `setState` + 内联 loading 覆盖层（完全避开 Navigator 操作）
2. 使用 `showDialog` 的 `barrierDismissible: false` + 在 Dialog 内部通过 `Navigator.pop(dialogContext)` 关闭（获取 dialog 自己的 context）
3. 使用 `Overlay` + `OverlayEntry` 手动管理 loading 状态
4. 用 Riverpod 的 `StateProvider<bool>` 控制 loading 显示/隐藏
