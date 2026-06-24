# PR_history/2026-06-24-page-overflow-fixes.md

## 修改目的

修复多处页面文本/控件在窄屏（手机）或内容过长时溢出屏幕边界的问题。涉及 Palace 认知中间件的事件详情、树状视图，以及课表页的学期选择器。

## 修改文件清单

| 文件 | 改动 |
|------|------|
| `lib/features/palace/widgets/event_detail_panel.dart` | Row 中来源 Text → `Expanded` + `TextOverflow.ellipsis` |
| `lib/features/palace/widgets/event_tree_view.dart` | 类型标签 Text + 日期标签 Text → `Expanded` + `ellipsis`（2 处） |
| `lib/features/courses/screens/courses_screen.dart` | 学年/学期 Row → 包裹 `SingleChildScrollView(horizontal)` |
| `lib/features/palace/screens/palace_screen.dart` | TypeFilterBar → `SizedBox(height:48)` + TagChipBar → `ConstrainedBox(maxHeight:72)` 防止挤压内容区 |

## 核心逻辑说明

### 修复原则

Row 内放置多个子组件时，固定宽度组件（Icon、SizedBox）不放 Expanded，可变长度文本必须放 Expanded + `overflow: TextOverflow.ellipsis`：

```dart
Row(
  children: [
    const Icon(Icons.star, size: 20),     // 固定：不放
    const SizedBox(width: 8),              // 固定：不放
    Expanded(                              // 可变文本：必须放
      child: Text(label, overflow: TextOverflow.ellipsis),
    ),
  ],
),
```

多控件 Row（如多个 DropdownButton）在窄屏溢出时，包裹 `SingleChildScrollView(scrollDirection: Axis.horizontal)`。

### 已确认无需改动的组件

- `palace/widgets/tag_chip_bar.dart` — 已使用 `Wrap`，自动换行
- `palace/widgets/type_filter_bar.dart` — 已使用 `SingleChildScrollView(horizontal)`
- `scores/screens/scores_screen.dart` — `_GpaCard` 已带 `Expanded`，搜索栏已带 `Expanded`
- `tutor/screens/notes_screen.dart` — Chip 栏已有 `SingleChildScrollView`，输入框已有 `Expanded`

### Palace 过滤栏高度约束修复

**问题**：标签栏满屏时（TypeFilterBar chips 溢出 + TagChipBar 多行换行），过滤区总高度无上限，Column 布局将 `Expanded` 内容区挤压到 0 高度，导致事件树完全不可点击。

**根因**：`Column` 先给非 `Expanded` 子节点分配无限高度让它自定尺寸，剩余空间才给 `Expanded`。`TypeFilterBar` 和 `TagChipBar` 无高度约束时可能请求超大的固有高度。

**修复**：
- `TypeFilterBar` → `SizedBox(height: 48)` — 固定高度，内部水平 `SingleChildScrollView` 不受影响
- `TagChipBar` → `ConstrainedBox(maxHeight: 72)` + 外层 `SingleChildScrollView` — 标签多时垂直滚动，不挤压内容区

## 潜在影响

- **零影响**：所有改动纯防御性——屏幕足够宽时行为不变。
- 截断文本显示 `...` 符合 Material Design 规范。

## 测试结果摘要

- 全量并行测试：`python scripts/run_tests_parallel.py` → **6/6 ✅**（core 542 + features 262 + widgets 101 + services 6 + root 72）
- `flutter analyze` → 仅 pre-existing info/warning，无新问题
- 截图：待人工补充

## 人工验证清单（由人类执行）

- [x] Palace 事件详情：长来源名+日期不溢出
- [x] Palace 树状视图：类型标签("🏔️ 节点")、日期("2024年12月31日")不溢出
- [x] Palace 过滤栏：标签多时 TypeFilterBar 可水平滚动，TagChipBar 可垂直滚动
- [x] Palace 主内容区：过滤栏满屏/多标签时，下方事件树可正常点击展开
- [x] 课表页：学年+学期选择器在手机上可横向滚动
- [x] 手机端整体浏览，无溢出报错
- [x] 已有核心流程未受影响
- [x] 补充测试截图至本文件(pass)
