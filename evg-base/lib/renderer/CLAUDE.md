# Renderer — AI 协作规范

> 渲染层模块 CLAUDE.md，供 AI 助手理解本模块约定。

---

## 目录结构

```
lib/renderer/
├── widgets/          ← 第 1 层：原子渲染组件（不放业务逻辑）
├── shared/           ← 第 2 层：范式视图 + 页面 + 布局/调度基础设施
├── compositions/     ← 第 3 层：高级组合视图（多个 shared 视图叠加）
├── lib/              ← Stub 包（用于独立分析，不用于编译）
├── docs/             ← 设计规范 + 交互原型
└── pubspec.yaml      ← Stub 环境配置
```

---

## 核心规则

1. **widgets/ 不放业务逻辑** — 所有组件只接收描述符 + 数据，不调用 API、不管理状态
2. **shared/ 不放原子 UI** — shared 层负责布局、调度、数据编排，渲染委托给 widgets/
3. **未知字段静默忽略** — 收到未识别的描述符字段时不做任何事，不抛异常
4. **描述符驱动** — 所有配置通过 `*Options` / `*Descriptor` 不可变类传入
5. **数据注入分离** — 视图接收 `descriptor`（配置）和 `data`（运行时数据）两个独立参数
6. **Stub 隔离** — `lib/` 下 11 个 stub 包使 renderer 可脱离 Flutter SDK 独立 `dart analyze`

---

## 代码模式

### 组件模式
```dart
class MyWidget extends StatelessWidget {
  final MyOptions options;
  final List<DataModel> data;
  const MyWidget({required this.options, required this.data});
  // ...
}
```

### 页面模式
```dart
class MyPage extends StatelessWidget {
  // 接收必要参数，组合 widgets/ 原子组件
  // 通过 ThemeProvider 获取主题 token
  // 通过 ModuleDispatch 范式调度（如适用）
}
```

### Token 访问
```dart
final bg = context.componentColor('bubble', 'user') ?? primaryContainer;
```

### 像素常量
```dart
import 'docs/render_rules.dart';
// SpacingRules.sm, RadiusRules.md, DurationRules.fast, ...
```

---

## 环境

| 工具 | 命令 |
|------|------|
| 静态分析 | `dart analyze lib/` (在 renderer/ 目录) |
| 测试 | `flutter test` (在项目根目录) |
| Stub 依赖 | `dart pub get` (在 renderer/ 目录) |

---

## 测试约定

- 模型测试 → 纯 Dart `test()`
- 组件测试 → `testWidgets` + `MaterialApp` + `Scaffold`
- 验证重点：存在性 (`findsOneWidget`) + 数据正确性（字段断言）
- 测试文件位置：项目根 `test/` 目录

---

## 当前状态 (2026-07-04)

- ✅ Sprint 1 完成：AppShell, ChatView, ModuleDispatch, LayoutEngine, ThemeProvider
- ✅ Sprint 2 完成：市场页、工作台页、详情页、我的插件页、设置页、通知、权限弹窗 (103 tests passing)
- ✅ Sprint 3 完成：性能测量文档、帧率监控工具、主题切换 benchmark
- ✅ docs/ 设计交付物：色板 ✅签字, 视觉 spec ✅签字, 原型 HTML ✅签字, render_rules ✅签字
- ✅ docs/ 设计验收：Sprint 2 验收报告, Sprint 3 全量验收报告, ΔE 色差报告, 低端设备审核
- ✅ 11 个 stub 包

---

## Stub 包列表

| # | 包名 | 用途 |
|---|------|------|
| 1 | flutter_stub | Flutter SDK |
| 2 | flutter_riverpod_stub | 状态管理 |
| 3 | go_router_stub | 路由 |
| 4 | markdown_stub | Markdown 渲染 |
| 5 | flutter_highlight_stub | 代码高亮 |
| 6 | flutter_math_fork_stub | 数学公式 |
| 7 | flutter_mermaid_stub | 图表渲染 |
| 8 | flutter_widget_from_html_core_stub | HTML→Widget |
| 9 | google_fonts_stub | 字体 |
| 10 | html_stub | HTML 解析 |
| 11 | shared_preferences_stub | 本地存储 |
