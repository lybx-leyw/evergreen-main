# Shared — 组合视图 + 调度基础设施

> 将 `widgets/` 中的原子组件组合为完整的 UI 范式视图。

## 基础设施

| 组件 | 文件 | 说明 |
|------|------|------|
| RendererProviders | `renderer_providers.dart` | 全局 Riverpod 提供者（主题、模块、断点、数据） |
| ThemeProvider | `theme_provider.dart` | ThemeDescriptor → Material ThemeData + 组件 Token |

## 布局工具

| 组件 | 文件 | 说明 |
|------|------|------|
| AdaptiveLayout | `adaptive_layout.dart` | 桌面/移动端自适应布局 |
| ResponsiveScrollView | `responsive_scroll_view.dart` | 响应式居中滚动视图 |

## 布局引擎

| 组件 | 文件 | 说明 |
|------|------|------|
| LayoutEngine | `layout_engine.dart` | 布局描述符解析引擎（scroll/fit/grid/panels/drawers/search/zoom） |
| GridLayout | `grid_layout.dart` | 网格布局 |
| PanelLayout | `panel_layout.dart` | TabBar + TabBarView 多面板 |
| DrawerHost | `drawer_host.dart` | Drawer/BottomSheet 抽屉宿主 |

## 交互系统

| 组件 | 文件 | 说明 |
|------|------|------|
| InteractionWrapper | `interaction_wrapper.dart` | 交互包装器（刷新/CRUD/导出） |

## 调度 + 页面

| 组件 | 文件 | 说明 |
|------|------|------|
| ModuleDispatch | `module_dispatch.dart` | UI 范式调度器（switch on ui field） |
| EvergreenModulePage | `module_page.dart` | 完整模块页面入口 |

## 7 个范式视图

| 组件 | 文件 | 说明 |
|------|------|------|
| DefaultView | `default_view.dart` | 通用列表/表格/卡片视图 |
| ChatView | `chat_view.dart` | 对话界面 |
| SpreadsheetView | `spreadsheet_view.dart` | 电子表格界面 |
| DocumentView | `document_view.dart` | 文档编辑器 |
| PresentationView | `presentation_view.dart` | 演示文稿 |
| DashboardView | `dashboard_view.dart` | 仪表盘 |
| EditorView | `editor_view.dart` | 代码/文本编辑器 |

## 表单视图

| 组件 | 文件 | 说明 |
|------|------|------|
| FormView | `form_view.dart` | 动态表单（从 FormDescriptor 生成） |

## 架构数据流

```
ModuleDescriptor.ui
  → LayoutEngine (scroll/fit, grid, panels, drawers, search, zoom)
    → InteractionWrapper (gestures, selection, CRUD, refresh, sort, export)
      → ModuleDispatch (switch on ui field)
        → DefaultView | ChatView | SpreadsheetView | DocumentView | ...
          → widgets/ 原子组件
```

## 使用

```dart
import 'package:evergreen_base/renderer/shared/shared.dart';

EvergreenModulePage(descriptor: myModuleDescriptor);
```
