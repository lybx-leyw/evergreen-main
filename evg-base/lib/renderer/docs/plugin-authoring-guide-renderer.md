# 渲染层内部开发文档

> **面向**：渲染工程师（Evergreen 内部开发者）
> **非插件开发者文档**：外部插件开发者无需阅读本文档。插件通过 manifest.json 声明 UI，渲染层自动消费描述符。本文档仅供渲染层维护者参考。
>
> 插件开发者请参阅：顶层 `PLUGIN_AUTHORING_GUIDE.md` 及各维度详细指南。

---

## 1. 架构位置与接口

```
core/ (服务层)  →  plugins/ (声明+.exe)  →  renderer/ (渲染层)
```

渲染层是**纯消费者**。从 `core/` 接收 `ModuleDescriptor`（不可变），通过 `ThemeProvider` 获取 Token，按声明画 UI。不调 HTTP、不管进程、不解析 `manifest.json`。

| 接口 | 方向 | 说明 |
|------|------|------|
| `ModuleDescriptor` | core → renderer | 已解析的模块描述符 |
| `ComponentTokens` | core → renderer | 通过 `BuildContext` 扩展访问 |
| `ThemeDescriptor` | core → renderer | 经 `buildThemeFromDescriptor()` 生成 `ThemeData` |
| `PageEventBus` | core → renderer | composite 模式栏间通信 |
| `ProcessManager` | core → renderer | composite 模式进程管理 |

---

## 2. 范式调度

`ModuleDispatch.build(context)` 按 `descriptor.ui` 分发到 10 种范式视图。已知 `ui` → 对应视图，未知 → `DefaultView`（**不崩溃**）。

新增范式只需两步：
1. 在 `shared/` 创建范式视图（只组合 `widgets/` 原子）
2. 在 `module_dispatch.dart` 的 `switch` 添加 case

范式列表见 [README.md](../README.md#范式调度10-种-ui-范式)。

---

## 3. 三层开发规范

```
widgets/   ← 原子 UI，纯展示，不调 API
shared/    ← 组合 widgets/，处理布局和调度
compositions/ ← 叠加 shared/ 视图
```

### widgets/ — 原子组件

```dart
// ✅ 接收 Options + 数据模型
class MyWidget extends StatelessWidget {
  final MyOptions options;
  final ChatMessage message;
  const MyWidget({required this.options, required this.message});
}

// ❌ 调 API、管全局状态（UI 交互状态如展开/折叠除外）
```

### shared/ — 范式视图

```dart
// ✅ 组合 widgets/ 原子
class MyView extends StatelessWidget {
  final ModuleDescriptor descriptor;
  Widget build(_) => Column(children: [
    DashboardCard(...),  // widgets/ 原子
    EmptyState(...),     // widgets/ 原子
  ]);
}

// ❌ 在 shared/ 中重定义按钮/卡片/输入框
```

### compositions/ — 工作区

```dart
// WorkspaceHub: 文件树 + 编辑器 + Chat 侧栏
Row(children: [
  FileTree(...),            // widgets/
  EditorView(...),          // shared/
  ChatControllerView(...),  // shared/
])
```

---

## 4. 描述符系统

所有配置通过 `*Options` / `*Descriptor` 不可变类传入。未知字段静默忽略。

| 描述符 | 用途 | 位置 |
|--------|------|------|
| `ModuleDescriptor` | 模块声明（id, name, ui, pages...） | `core/module/` |
| `PageDescriptor` | composite 页面声明 | `core/module/` |
| `ComponentConfig` | composite 栏位配置 | `core/module/` |
| `LayoutDescriptor` | 布局偏好 | `core/module/` |
| `DataBindingDescriptor` | 数据绑定 | `core/module/` |
| `ChatOptions` / `BubbleOptions` / `StreamOptions` | Chat 配置 | `core/module/` |
| `InputOptions` | 输入模式（free-text/type-check/code/select） | `core/module/` |
| `FormFieldDescriptor` | 表单字段 | `core/module/` |
| `ChartConfig` | 图表配置（bar/line/pie） | `widgets/chart_renderer.dart` |

容错模式：`switch (descriptor.ui) { ... _ => DefaultView(...) }` / `switch (config.component) { ... _ => _UnknownSlot(...) }`

---

## 5. Token 系统

```dart
// 组件 Token
final bg = context.componentColor('bubble', 'user') ?? primaryContainer;

// 语义 Token
final warning = Theme.of(context).evergreen.warning;

// Fallback
final color = context.componentColor('comp', 'bg')
    ?? Theme.of(context).colorScheme.surface;

// 主题构建
final themeData = buildThemeFromDescriptor(descriptor);
wrapWithComponentTokens(componentTokens: tokens, child: app);
```

---

## 6. 像素常量

`docs/render_rules.dart`，13 个规则类。

```dart
SpacingRules.md          // 16.0
RadiusRules.lg           // 12.0
DurationRules.fast       // 200ms
ChatRules.bubbleMaxWidthRatio  // 0.75
GridRules.desktopColumns        // 4
```

---

## 7. 测试

```dart
testWidgets('renders DashboardCard', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: DashboardCard(title: '活跃用户', value: '1,234')),
  ));
  expect(find.text('活跃用户'), findsOneWidget);
  expect(find.text('1,234'), findsOneWidget);
});
```

| 类型 | 位置 | 验证 |
|------|------|------|
| 模型测试 | 项目根 `test/` | 序列化/反序列化 |
| 集成测试 | 项目根 `test/` | 页面级渲染交互 |
| 组件测试 | `renderer/test/` | 原子组件存在性+数据正确性 |

覆盖建议：正常路径 + 边界（空数据/null/最小字段） + 容错（未知 ui → DefaultView）。

---

## 8. 环境

| 命令 | 目录 |
|------|------|
| `dart analyze lib/` | `renderer/` |
| `dart pub get` | `renderer/` |
| `flutter test` | 项目根 |
| `flutter run -t example/main.dart` | 项目根 |

---

## 9. 相关文档

- [README.md](../README.md) — 渲染层总览
- [CLAUDE.md](../CLAUDE.md) — AI 协作规范
- [docs/render_rules.dart](./render_rules.dart) — 像素常量
- [example/](../example/) — 可运行示例
