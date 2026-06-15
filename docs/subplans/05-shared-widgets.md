# 05 — 共享 Widget 标准化（细化版）

**层级：** 〇（零依赖） | **估时：** 2 天 | **关联 Bug：** BUG-09, BUG-12

---

## 1. 现状审计

### 1.1 三组件 API 对比

| 参数 | `EmptyState` | `ErrorCard` | `LoadingWidget` |
|------|:---:|:---:|:---:|
| 主文本 | `title` | `message` | `message` |
| 副文本 | `subtitle` | `detail` + `hint` | — |
| 图标 | `icon` | 内置 `error_outline` | 内置 spinner |
| 操作 | — | `onRetry` | — |
| 无障碍 | ❌ 无 | ❌ 无 | ❌ 无 |

**结论：API 命名不一致。** `ErrorCard.message` 和 `EmptyState.title` 做的是同一件事（主标题），但名字不同。

### 1.2 当前使用量

| Widget | 调用次数（约） | 分布 |
|--------|:---:|------|
| `ErrorCard` | ~25 | 所有 Feature Screen |
| `EmptyState` | ~12 | 空列表场景 |
| `LoadingWidget` | ~10 | 加载场景 |

### 1.3 响应式现状

```dart
// sidebar.dart:24 — 唯一响应式断点，硬编码
if (constraints.maxWidth <= 768) {
  return _MobileShell(child: child);
}
```

- 断点 `768` 硬编码在 1 处
- 无 `AdaptiveLayout` 抽象
- 移动端底部导航栏硬编码了 5 个 tab（仪表盘/课程/待办/AI笔记/AI助手）
- 48dp 最小触摸区域未强制

---

## 2. 设计目标

1. **API 统一**：三组件统一 `title`/`subtitle` 命名 + 全部加 `semanticLabel`
2. **品牌化加载**：`LoadingWidget` → `LoadingIndicator`，可配置的 ZJU 蓝脉冲动画
3. **断点体系**：`Breakpoints` 常量类，替代硬编码 768
4. **自适应布局**：`AdaptiveLayout` widget，自动在 desktop/mobile 间切换
5. **无障碍**：所有公开 Widget 加 `semanticLabel`（Screen Reader 可读）

---

## 3. 核心设计

### 3.1 `Breakpoints` — 响应式断点

```dart
// lib/widgets/breakpoints.dart

/// 响应式布局断点（Material 3 风格 + 小桌面适配）。
///
/// 参考 Window Size Class，但增加 768 的过渡断点以兼容
/// 现有 sidebar 行为。
class Breakpoints {
  Breakpoints._();

  /// 移动端 → 桌面端过渡（sidebar 切换点）。
  static const double mobile = 768;

  /// 紧凑布局（小桌面 / 平板横屏）。
  static const double compact = 1024;

  /// 标准桌面布局。
  static const double medium = 1280;

  /// 展开布局（大屏）。
  static const double expanded = 1600;
}
```

### 3.2 `AdaptiveLayout` — 自适应布局

```dart
// lib/widgets/adaptive_layout.dart

/// 自适应布局——根据窗口宽度自动切换 desktop / mobile。
///
/// 使用 [LayoutBuilder] 监听窗口尺寸，≤ [Breakpoints.mobile] 时渲染
/// [mobile]，否则渲染 [desktop]。
class AdaptiveLayout extends StatelessWidget {
  final WidgetBuilder desktop;
  final WidgetBuilder mobile;

  const AdaptiveLayout({
    super.key,
    required this.desktop,
    required this.mobile,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= Breakpoints.mobile) {
          return mobile(context);
        }
        return desktop(context);
      },
    );
  }
}
```

### 3.3 `EmptyState` 增强

**现状 API（保留兼容）：**
```dart
EmptyState(icon: ..., title: ..., subtitle: ...)
```

**新增参数：**
```dart
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? semanticLabel;  // ← 新增

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.subtitle,
    this.semanticLabel,
  });
}
```

### 3.4 `ErrorCard` 增强

**现状 API（已有 message/detail/hint/onRetry）：**
```dart
ErrorCard(message: ..., detail: ..., hint: ..., onRetry: ...)
```

**新增参数：**
```dart
class ErrorCard extends StatelessWidget {
  final String message;
  final String? detail;
  final String? hint;
  final VoidCallback? onRetry;
  final String? semanticLabel;  // ← 新增

  // builder 不变
}
```

### 3.5 `LoadingIndicator` — 品牌化重设计

**现状：** `LoadingWidget`，只有 `message` 参数 + 默认 `CircularProgressIndicator`。

**重设计：**
```dart
// lib/widgets/loading_indicator.dart

/// 品牌化加载指示器——ZJU 蓝脉冲动画 + 可选消息。
///
/// ```dart
/// // 默认（标准尺寸 + 无文字）
/// const LoadingIndicator();
///
/// // 带消息
/// const LoadingIndicator(message: '加载课程列表...');
///
/// // 紧凑模式（嵌入卡片内）
/// const LoadingIndicator.compact(hint: '查询中...');
/// ```
class LoadingIndicator extends StatelessWidget {
  final String? message;
  final String? semanticLabel;
  final bool compact;  // ← 新增：紧凑模式（小尺寸 + 水平布局）

  const LoadingIndicator({
    super.key,
    this.message,
    this.semanticLabel,
    this.compact = false,
  });

  /// 紧凑工厂——卡片内嵌加载。
  const LoadingIndicator.compact({
    super.key,
    String? hint,
    this.semanticLabel,
  })  : message = hint,
        compact = true;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    // 品牌色脉冲动画（ZJU 蓝 #1677FF）
    // ... 实现
  }
}

/// 向后兼容别名。
@Deprecated('Use LoadingIndicator instead')
typedef LoadingWidget = LoadingIndicator;
```

**动画：** 使用 `CircularProgressIndicator` + `color: Theme.of(context).colorScheme.primary`，自动适配暗色模式。

### 3.6 BUG-12 前置：48dp 最小触摸区域

在所有可点击元素上强制 48×48 最小尺寸。作为 `Theme` 级别的默认值：

```dart
// 在 theme.dart 或独立文件中
/// 确保 widget 满足 48×48dp 最小触摸区域（Material 无障碍规范）。
Widget minTouchTarget(Widget child) {
  return SizedBox(
    width: 48,
    height: 48,
    child: Center(child: child),
  );
}
```

应用到 `IconButton`、`NavigationDestination` 等小触碰区域。

---

## 4. 迁移对照

### 4.1 `sidebar.dart` 断点迁移

```dart
// 旧
if (constraints.maxWidth <= 768) {
  return _MobileShell(child: child);
}

// 新
if (constraints.maxWidth <= Breakpoints.mobile) {
  return _MobileShell(child: child);
}
```

### 4.2 三组件 API 统一命名

| 旧 API | 新 API |
|--------|--------|
| `LoadingWidget(message: '...')` | `LoadingIndicator(message: '...')` |
| `ErrorCard(message: '标题', detail: '技术细节', hint: '恢复建议')` | 不变（已是 `message` 主标题，符合模式） |
| `EmptyState(title: '标题', subtitle: '副标题')` | 不变（`title` + `subtitle` 模式，符合模式） |

### 4.3 无障碍迁移

所有 ~47 处调用点加 `semanticLabel`:

```dart
// 旧
ErrorCard(message: '加载失败', onRetry: ...)

// 新
ErrorCard(message: '加载失败', semanticLabel: '课程列表加载失败，点击重试', onRetry: ...)
```

> ⚠️ 47 处全部迁移工作量大。策略：只对 `lib/widgets/` 内的 Widget 定义加参数，调用方可后续渐进添加。

---

## 5. 测试策略

| 测试 | 内容 |
|------|------|
| `empty_state_test.dart` | `semanticLabel` 渲染到 `Semantics` widget |
| `error_card_test.dart` | ➕ `semanticLabel` 测试（扩展现有 6 个测试） |
| `loading_indicator_test.dart` | `compact` 模式 vs 标准模式渲染差异 |
| `breakpoints_test.dart` | 常量值验证（无逻辑，纯配置） |
| `adaptive_layout_test.dart` | 窄屏渲染 `mobile`，宽屏渲染 `desktop` |

---

## 6. 执行计划

| 步骤 | 内容 | 估时 |
|------|------|------|
| **Step 1** | 创建 `Breakpoints` 常量类 | 0.1 天 |
| **Step 2** | 创建 `AdaptiveLayout` widget | 0.2 天 |
| **Step 3** | `sidebar.dart` 使用 `Breakpoints.mobile` + `AdaptiveLayout` | 0.2 天 |
| **Step 4** | `EmptyState` + `ErrorCard` + `LoadingIndicator` 加 `semanticLabel` | 0.2 天 |
| **Step 5** | `LoadingWidget` → `LoadingIndicator` 重命名 + compact 模式 | 0.3 天 |
| **Step 6** | BUG-12 前置：`minTouchTarget` 工具 + `Theme` 集成 | 0.1 天 |
| **Step 7** | 测试编写（~12 个新测试） | 0.3 天 |
| **Step 8** | 全量回归 | 0.1 天 |

---

## 7. 验收标准

- [ ] `Breakpoints.mobile` 替代 `sidebar.dart` 中硬编码 768
- [ ] `AdaptiveLayout` 在窗口 < 768px 时自动切换 mobile 布局
- [ ] `EmptyState`、`ErrorCard`、`LoadingIndicator` 均支持 `semanticLabel`
- [ ] `LoadingIndicator` 使用 brand color 动画（ZJU 蓝 #1677FF），`compact` 模式正常
- [ ] 三组件在亮/暗模式下视觉一致
- [ ] 旧 `LoadingWidget` 保留为 `@Deprecated` 别名，不破坏现有调用
- [ ] `flutter analyze` 零新增警告
- [ ] Widget 测试 100% 通过
