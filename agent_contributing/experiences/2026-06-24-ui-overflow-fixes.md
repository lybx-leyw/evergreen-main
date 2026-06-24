---
task_type: bug-fix
tags: [ui, overflow, responsive, scroll, row, expanded, wrap, layout]
files_touched:
  - lib/features/palace/widgets/event_detail_panel.dart
  - lib/features/palace/widgets/event_tree_view.dart
  - lib/features/courses/screens/courses_screen.dart
difficulty: easy
outcome: success
date: 2026-06-24
related_pr: 2026-06-24-page-overflow-fixes.md
---

## 做了什么

修复多个页面的文本/控件溢出问题——窄屏（手机）或内容过长时不会超出屏幕边界。

## 关键决策

1. **Row 中动态文本 + Expanded**：所有 Row 内的可变长度 Text 必须用 Expanded 包裹 + overflow: TextOverflow.ellipsis，固定宽度 widget (Icon, Chip) 不动。
2. **学期选择器 → SingleChildScrollView**：课表页的"学年 + 学期"两个 DropdownButton 在 Row 中溢出时，用 SingleChildScrollView(horizontal) 而非强制换行，保持操作一致性。
3. **不盲目扩大改动范围**：已正确使用 Wrap / SingleChildScrollView / Expanded 的组件不动。

## 踩过的坑

### 1. Palace 事件详情—来源文本溢出
- **现象**：来源+"智云课堂"+"· 6月24日" 在中文字符下超屏
- **根因**：`Row([Chip, Text(source+date)])` 中 Text 无约束
- **解决**：Text 加 `Expanded` + `overflow: TextOverflow.ellipsis`

### 2. Palace 树状视图—标签名溢出
- **现象**：类型标签("🏔️ 节点") 或日期("2024年12月31日") 超屏
- **根因**：类型节点 Row 和 日期节点 Row 中的 Text(label) 无 Expanded
- **解决**：两个 Row 中的 Text 各加 Expanded + ellipsis

### 3. 课表选择器—学年/学期 Row 在手机上溢出
- **现象**：`Row([Text('学年'), DropdownButton, Text('学期'), DropdownButton])` 在 ~360dp 手机上溢出
- **根因**：四个子组件总宽度超屏幕
- **解决**：整行包在 `SingleChildScrollView(scrollDirection: Axis.horizontal)` 中，同时去掉 DropdownButton 的 underline 减少视觉高度

## 可复用的模式

### Row 溢出防御公式
```dart
Row(
  children: [
    const Icon(Icons.star, size: 20),     // 固定宽度：不包
    const SizedBox(width: 8),              // 固定宽度：不包
    Expanded(                              // ← 可变文本：必须包
      child: Text(longText, overflow: TextOverflow.ellipsis),
    ),
    const Text('(12)'),                    // 固定后缀：不包（先确认不会超）
  ],
),
```

### 多控件 Row 窄屏兜底
```dart
// 当 Row 包含多个 DropdownButton 或 Chip 时
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(
    children: [...],
  ),
),
```

## 注意事项

- **Expanded 只能有一个**在一个 Row 中，如果有多个可变文本，用 `flex` 分配空间
- Wrap 更适合 Chip 列表（自动换行），SingleChildScrollView 更适合固定控件的防溢出
- `TextOverflow.ellipsis` 是纯视觉处理，不会影响语义/可访问性
- 不要给所有 Row 盲目加 Expanded——固定宽度 Icon 包了反而会变形
