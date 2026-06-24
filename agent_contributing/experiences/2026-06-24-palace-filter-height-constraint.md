---
task_type: bug-fix
tags: [palace, ui, layout, column, constraint, overflow, height, scroll]
files_touched:
  - lib/features/palace/screens/palace_screen.dart
difficulty: easy
outcome: success
date: 2026-06-24
related_pr: 2026-06-24-page-overflow-fixes.md
---

## 做了什么

修复 Palace 页面"标签栏满屏时下面内容点不开"的 bug——根因是 `TypeFilterBar` 和 `TagChipBar` 在 `Column` 中无高度约束，标签过多时无限扩展，把 `Expanded` 内容区挤到 0 高度。

## 关键决策

1. **TypeFilterBar → SizedBox(height: 48)**：固定高度防止意外扩展，内部 `SingleChildScrollView(horizontal)` 不受影响
2. **TagChipBar → ConstrainedBox(maxHeight: 72) + SingleChildScrollView**：标签多时垂直滚动而非无限换行挤压内容
3. **不改 EventTreeView**：它本身布局正确，问题在上游 Column 的约束丢失

## 踩过的坑

### Column 中无约束 Widget + Expanded 的布局陷阱

- **现象**：标签栏 chips 换行后，下面的树形列表完全不可点击（高度为 0）
- **根因**：`Column` 的布局算法是先给非 `Expanded`/`Flexible` 子节点无限高度，等它们确定自身高度后再把剩余空间分给 `Expanded`。当 `TypeFilterBar`（`SingleChildScrollView`）和 `TagChipBar`（`Wrap`）无高度上限时，它们可能请求极高的固有高度，导致 `Expanded` 分到 0
- **解决**：对过滤区的每个组件分别加上高度约束（`SizedBox` / `ConstrainedBox`），确保 `Expanded` 总有正空间

## 可复用的模式

### Column 中混用固定 + Expanded 的安全公式

```dart
Column(
  children: [
    // 固定头部：必须给高度约束
    SizedBox(
      height: 48,  // ← 必须
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [...chips]),
      ),
    ),
    // 可变头部：maxHeight + 内部滚动
    ConstrainedBox(
      constraints: BoxConstraints(maxHeight: 72),  // ← 必须
      child: SingleChildScrollView(
        child: Wrap(children: [...manyWidgets]),
      ),
    ),
    // 主内容
    Expanded(child: ...),  // 安全，总能拿到剩余空间
  ],
),
```

## 注意事项

- `SizedBox(height:)` 只约束高度，不约束宽度——水平 `SingleChildScrollView` 需要父级宽度约束（由 Column 提供），`SizedBox` 不干扰
- `ConstrainedBox(maxHeight:)` 同理，只设上限，不设下限——正常内容不会被拉伸
- 这个 bug 在小屏/多标签场景下触发，大屏或少标签时不体现——属于防御性修复，不影响正常工况
