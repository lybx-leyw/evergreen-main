---
task_type: bug-fix
tags: [flutter, navigator, dialog, async, training-plan, black-screen, debugLocked]
files_touched:
  - lib/features/zdbk/screens/training_plan_screen.dart
  - test/features/zdbk/training_plan_screen_test.dart
difficulty: medium
outcome: failure
date: 2026-06-24
superseded_by: 2026-06-24-addpostframecallback-pop-dead-end.md
---

## 背景

培养方案页面点击下载后，先 `showDialog` 显示加载指示器，`await` 下载 PDF，然后 `Navigator.of(context).pop()` 关闭对话框。预期：下载完成 → 关闭加载对话框 → 显示内容。实际：黑屏。

## 根因

`await service.downloadPlanPdf(...)` 在 Flutter 的 build 帧中间恢复执行。此时 Navigator 处于 `_debugLocked` 状态，调用 `pop()` 触发断言错误：

```
NavigatorState.pop: Failed assertion: '!_debugLocked': is not true.
```

断言失败导致整个 Widget 树卸载异常，页面黑屏。

## 踩过的坑

### `showDialog` + `await` + `pop()` 的异步陷阱

- **现象**：下载完成后页面黑屏，控制台报 `_debugLocked` 断言失败
- **根因**：`await` 后的代码可能在 build 帧中间恢复，此时 Navigator 被锁定，不能 pop/push
- **关键认知**：这是 Flutter 中异步操作后直接操作 Navigator 的经典陷阱

```dart
// ❌ 危险：可能在 build 帧中恢复
Future<void> _downloadAndOpenPlan() async {
  showDialog(...);                           // 显示加载对话框
  final file = await downloadPlanPdf(...);   // 异步暂停
  Navigator.of(context).pop();               // ← 可能在 build 帧中恢复，触发 _debugLocked
  openPdf(file);
}
```

## ⚠️ 注意：此方案已被否决

**`addPostFrameCallback` + `Navigator.pop()` 在 go_router 项目中不可用。**
详见 [2026-06-24-addpostframecallback-pop-dead-end.md](2026-06-24-addpostframecallback-pop-dead-end.md)。

延迟 pop 会误弹 go_router 根路由，导致 `currentConfiguration.isNotEmpty` 断言失败 → 路由栈清空 → 黑屏。**真实修复方案待定。**

## ~~最终采用的方案~~（已否决，仅供记录）

将 `Navigator.of(context).pop()` 包裹在 `addPostFrameCallback` 中延迟执行：

```dart
// ❌ 已被证伪：在 go_router 中会误弹根路由
WidgetsBinding.instance.addPostFrameCallback((_) {
  Navigator.of(context).pop();
});
```

## ~~可复用的模式~~（已否决，仅供记录）

> ⚠️ 以下模式在 go_router 项目中会导致路由栈清空，不可用。真实可复用模式待探索。
>
> 候选方向：`setState` + 内联 overlay、OverlayEntry、Riverpod StateProvider

```dart
// ❌ 已被否决
Future<T?> runWithLoadingDialog<T>(...) async {
  // ...
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Navigator.of(context).pop();  // go_router 下误弹根路由
  });
}
```

## 遗留的认知

- `await` 后的代码可能在 build 帧中恢复，此时 Navigator 被 `_debugLocked` 锁定
- 这个认知是正确的——只是 `addPostFrameCallback` 作为解决方案在 go_router 下不成立
