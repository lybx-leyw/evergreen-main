---
task_type: fix
tags: [reeditor, keyboard, shortcut, page-up, page-down, code-editor, third-party, debugging]
difficulty: hard
outcome: success
date: 2026-07-06
files_touched:
  - evg-base/lib/renderer/widgets/code_editor.dart
---

## 做了什么

在 `CodeEditor` 上层包裹 `Actions` widget，提供自定义 `Action<CodeShortcutCursorMovePageIntent>` 拦截 Page Up / Page Down 按键。re_editor 内部 `_onAction()` 会先通过 `Actions.maybeFind(context)` 向上查找祖先 Actions，找到后跳过静态 handler（空实现）。自定义 action 直接操作 `controller.selection` 翻 `_kPageSize=24` 行。

## 关键决策

<!-- TODO -->

## 踩过的坑

代码编辑器按 Page Up / Page Down 键没有反应。

**根因**：re_editor v0.10.0 的 `CodeLineEditingValue.moveCursorToPageUp()` 和 `moveCursorToPageDown()` 是空 `// TODO` 实现。

**完整链路追踪**（6 层，5 层正确 + 1 层断裂）：

| 层级 | 组件 | 状态 |
|------|------|------|
| 1 | `CodeShortcutsActivatorsBuilder` 返回正确 activators | ✅ |
| 2 | `_CodeShortcuts.buildShortcuts()` 映射 activator→intent | ✅ |
| 3 | `_CodeShortcutActions._onAction()` 分发到静态 handler | ✅ |
| 4 | 静态 handler 调用 `editingController.moveCursorToPageUp()` | ✅ |
| 5 | `_CodeLineEditingControllerDelegate.moveCursorToPageUp()` 委托到 `_delegate` | ✅ |
| 6 | `_CodeLineEditingControllerImpl.moveCursorToPageUp()` → `// TODO` | ❌ |

**原则**：使用三方库时，不能假设所有方法都有完整实现。遇到快捷键不工作时，应追踪完整链路（activator → intent → action → controller → 具体方法），而不是只检查快捷键映射层。

## 可复用的模式

<!-- TODO -->
