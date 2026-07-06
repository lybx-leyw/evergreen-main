# Renderer — AI 协作规范

> 供 AI 助手理解本模块约定。最后更新：2026-07-06。

---

## 目录结构

```
lib/renderer/
├── widgets/       ← 61 个原子组件（纯渲染，不放业务逻辑）
├── shared/        ← 35 个范式视图 + 布局/调度/Token
├── compositions/  ← 高级组合视图
├── multi_agent/   ← 多 Agent 并行视图
├── html/          ← HTML5 渲染引擎（Dart→HTML 离线导出）
├── lib/           ← 11 个 Stub 包（独立 dart analyze）
├── docs/          ← 设计规范 + 渲染常量 + 事件契约
├── example/       ← 可运行示例
├── test/          ← 组件级 widgetTest
└── pubspec.yaml
```

---

## 核心规则

1. **widgets/ 不放业务逻辑** — 只接收描述符 + 数据，不调 API、不管理状态
2. **shared/ 不放原子 UI** — 负责布局/调度/编排，渲染委托给 widgets/
3. **未知静默忽略** — 未识别字段/UI 值不抛异常（容错）
4. **描述符驱动** — 配置通过 `*Options` / `*Descriptor` 不可变类传入
5. **数据注入分离** — 视图接收 `descriptor`（配置）和 `data`（运行时数据）两个独立参数
6. **Stub 隔离** — `lib/` 下 11 个 stub 包使 renderer 可脱离 Flutter SDK 独立分析

### 范式调度（V2：按 pages/workspace 自动选择）

| 条件 | → 视图 | 说明 |
|------|--------|------|
| `descriptor.pages` 非空 | `CompositeView` | 多页 Tab + SlotDispatch（53 种组件） |
| `descriptor.workspace.enabled` | `EditorView` | 代码/文本编辑器 |
| 其他 | `DefaultView` | 数据绑定兜底（不崩溃） |

> V1 的 `descriptor.ui` 字段已删除。V2 按模块内容自动选择视图。

---

## 代码模式

### 原子组件（widgets/）
```dart
// 纯展示：Options + 数据模型
class MyWidget extends StatelessWidget {
  final MyOptions options;
  final ChatMessage message;
  const MyWidget({required this.options, required this.message});
}
```

### 交互组件（widgets/ — UI 交互状态 OK，不调 API）
```dart
class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final BubbleOptions bubble;
  final StreamOptions stream;
}
```

### 范式视图（shared/）
```dart
// 组合 widgets/ 原子，处理布局和调度
class DashboardView extends StatelessWidget {
  final ModuleDescriptor descriptor;
  const DashboardView({super.key, required this.descriptor});
  // 内部：GridView + DashboardCard（widgets/ 原子）
}
```

### Slot 调度（shared/）
```dart
// 已知组件 → 对应视图，未知 → _UnknownSlot（不崩溃）
class SlotDispatch extends StatelessWidget {
  final String slotKey;
  final ComponentConfig config;
  final ModuleDescriptor moduleDescriptor;
}
```

### Token / 常量
```dart
final bg = context.componentColor('bubble', 'user') ?? primaryContainer;
import 'shared/render_tokens.dart'; // RenderTokens.colors / spacing / radius / size / font
// 或使用 CSS 变量（HTML 引擎）: RenderTokensCss.cssVariables()
```

---

## 环境 & 测试

| 命令 | 目录 |
|------|------|
| `dart analyze lib/` | `renderer/` |
| `dart pub get` | `renderer/` |
| `flutter test` | 项目根 |

测试模式：`testWidgets` + `MaterialApp` + `Scaffold`，验证 `findsOneWidget` + 数据正确性。

---

## 当前状态 (2026-07-06)

- ✅ Sprint 1-3 完成（AppShell, ChatView, ModuleDispatch, LayoutEngine, ThemeProvider + 市场/工作台/设置/通知/权限 + 性能）
- ✅ 11 stub / 61 widgets + 35 shared + 2 compositions + 2 multi_agent
- ✅ 设计交付物全部签字验收
- ✅ Phase 5 集成前置交付：README.md / example/ / test/ / 集成指南
- ✅ 基础设施补全：RenderTokens 常量层 / PluginRenderer 一键渲染 / HTML P2 组件 / 事件系统契约
- ✅ **V2 对齐完成 (2026-07-06)**：
  - LayoutEngine: grid/zoom/panels/search/mode → type/preset/features
  - GridLayout: GridOptions → LayoutPreset
  - SlotDispatch: ComponentConfig → ComponentDescriptor；config.component → config.type
  - ModuleDispatch: 删除 switch(descriptor.ui)，改为按 pages/workspace 自动选择
  - 范式视图：Spreadsheet/Document/Presentation/Editor 从 ComponentDescriptor.config 解析选项
  - **主题色统一**：RenderTokens 从 ThemeDescriptor 动态派生，HTML 引擎 30+ 处硬编码 → CSS 变量
  - `flutter test` 102 pass ✅ / `dart test` core/theme 99 pass ✅
