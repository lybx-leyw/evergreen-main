# Renderer — Evergreen 渲染层

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 1.0 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | renderer 渲染层 |

> 纯渲染层：读 `ModuleDescriptor`，按声明画 UI。不解析 manifest、不管理进程、不写业务逻辑。

---

## 架构定位

```
core/ (服务层)  →  plugins/ (JSON声明+.exe)  →  renderer/ (渲染层) ← 我们在这里
```

渲染层是 Evergreen 的**最下游纯消费者**：接收 `core/` 提供的 `ModuleDescriptor` + 运行时数据，通过 `ModuleDispatch` 按 `ui` 字段调度到范式视图。不调 HTTP、不管 `.exe` 进程、不解析 `manifest.json`。

---

## 三层目录结构

```
lib/renderer/
├── widgets/       ← 第 1 层：61 个原子渲染组件
├── shared/        ← 第 2 层：35 个范式视图 + 布局/调度/Token
├── compositions/  ← 第 3 层：高级组合视图
├── multi_agent/   ← 多智能体并行视图
├── html/          ← HTML5 渲染引擎（Dart→HTML 离线导出）
├── lib/           ← 11 个 Stub 包（独立 dart analyze）
├── docs/          ← 设计规范 + 渲染常量 + 事件契约
├── example/       ← 可运行示例
└── test/          ← 组件级 widgetTest
```

### 第 1 层：widgets/ — 原子组件

按领域分组（完整列表见 `widgets/` 目录）：

| 分组 | 代表性组件 |
|------|-----------|
| 通用 | `toast`, `empty_state`, `error_card`, `evergreen_progress`, `loading_indicator` |
| 应用壳 | `app_shell`, `command_palette`, `markdown_renderer` |
| Chat | `message_bubble`, `thinking_block`, `tool_call_card`, `streaming_cursor`, `chat_input_bar` |
| 数据展示 | `data_table`, `data_list`, `data_card_grid`, `dashboard_card` |
| 交互 | `crud_toolbar`, `confirm_dialog`, `search_bar`, `export_menu`, `refresh_widget` |
| 编辑器 | `code_editor`, `rich_text_editor`, `track_changes_gutter` |
| 表单 | `type_check_input`, `select_input`, `form_field_renderer` |
| 媒体 | `media_host`, `video_player`, `audio_player`, `image_viewer`, `document_viewer` |
| Spreadsheet | `spreadsheet_cell`, `formula_bar`, `chart_renderer`, `sheet_tab_bar` |
| Presentation | `slide_canvas`, `slide_sorter`, `speaker_notes_panel` |
| 市场/权限 | `ability_tag`, `install_progress`, `permission_dialog`, `notification_card` |

共享数据模型见 `widgets/models.dart`。

### 第 2 层：shared/ — 范式调度 + 页面

核心文件：

| 类别 | 关键文件 | 职责 |
|------|---------|------|
| 调度 | `module_dispatch.dart` | 按 `ui` 值分发到 10 种范式 |
| 调度 | `composite_view.dart` | composite 多页 Tab + SlotDispatch |
| 布局 | `layout_engine.dart` | 6 层布局管线 |
| 主题 | `theme_provider.dart` | ComponentTokens + 语义 Token |
| Token | `render_tokens.dart` | 颜色/间距/尺寸常量（Dart + CSS 双格式） |
| 渲染 | `plugin_renderer.dart` | 一键渲染：manifest → Widget 或 HTML |

范式视图：`chat_controller_view`, `default_view`, `dashboard_view`, `editor_view`, `spreadsheet_view`, `document_view`, `presentation_view`, `settings_view`

页面视图：`market_view`, `my_plugins_view`, `plugin_detail_view`, `permission_management_view`, `skill_management_view`, `global_memory_view`, `file_viewer`

HTML 引擎：`html_renderer.dart`, `html_components.dart`, `html_layout.dart`, `html_style.dart`, `html_template.dart`

### 第 3 层：compositions/ + multi_agent/

- `workspace_hub.dart` — 文件树 + 编辑器 + Chat 侧栏三合一
- `workspace_page.dart` — 工作区页面容器
- `multi_agent_view.dart` — 2 页 × 2 列并行 Agent 视图
- `single_agent_column.dart` — 单栏自包含 Agent 对话

---

## 范式调度（10 种 UI 范式）

`ModuleDispatch.build(context)` 按 `descriptor.ui` 分发：

| `ui` | 视图 | 场景 |
|------|------|------|
| `chat` | `ChatControllerView` | AI 对话（全屏/嵌入/紧凑） |
| `settings` | `SettingsView` | 插件配置 |
| `spreadsheet` | `SpreadsheetView` | 电子表格 |
| `document` | `DocumentView` | 文档 |
| `presentation` | `PresentationView` | 演示文稿 |
| `dashboard` | `DashboardView` | KPI 仪表盘 |
| `editor` | `EditorView` | 代码编辑 |
| `composite` | `CompositeView` | 多页 Tab 工作区 |
| `multichat` | `MultiAgentView` | 多 Agent 并行 |
| 其他 | `DefaultView` | 通用数据绑定（**兜底，不崩溃**） |

---

## 核心原则

- **描述符驱动**：配置通过 `*Options` / `*Descriptor` 不可变类传入，运行时数据独立注入
- **未知静默忽略**：未识别字段/UI 值不抛异常，回退到 `DefaultView`
- **三层严格隔离**：widgets/ 不写业务逻辑 → shared/ 不定义原子 UI → compositions/ 只做叠加组合

---

## Token 系统

```dart
// 组件 Token — context.componentColor(组件名, 状态)
final bg = context.componentColor('bubble', 'user') ?? primaryContainer;

// 语义 Token — ThemeData 扩展
final warning = Theme.of(context).evergreen.warning;

// 主题构建
final themeData = buildThemeFromDescriptor(descriptor);
```

---

## 渲染常量

`shared/render_tokens.dart` 定义 5 个 Token 类（Dart + CSS 双格式）：

```dart
RenderTokens.colors.surface          // Color(0xFFFFFFFF) + "#FFFFFF"
RenderTokens.spacing.md              // 16.0
RenderTokens.radius.lg               // 12.0
RenderTokens.font.chatBubbleMaxWidth // 0.75

// HTML 引擎可用 CSS 变量:
RenderTokensCss.cssVariables()       // → :root { --evg-surface: #FFFFFF; ... }
```

`docs/render_rules.dart` 定义 13 个规则类（设计工程师签字验收）。

完整参考见 `shared/render_tokens.dart` 和 `docs/render_rules.dart`。

---

## 开发红线

| 禁止 | 原因 |
|------|------|
| widgets/ 调 API / 管状态 | 原子组件只渲染 |
| shared/ 定义原子 UI | 组合层不重造轮子 |
| 解析 manifest.json | 上游已解析为 `ModuleDescriptor` |
| 管理 .exe 进程 | 进程生命周期归 ModuleLoader |
| 直连 AgentHttpServer | ChatView 必须通过 `process.exe` 代理 |
| import core/ 深层内部 | 只消费 barrel 公开 API |
| 未知字段抛异常 | 容错静默忽略 |

---

## 测试

- `renderer/test/`：组件级 widgetTest
- 项目根 `test/`：集成测试（当前因 core/ 层 V1→V2 迁移暂不可运行）
- `dart analyze lib/`：11 stub 包零问题

```dart
// 典型组件测试模式
testWidgets('renders DashboardCard', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: DashboardCard(title: '活跃用户', value: '1,234')),
  ));
  expect(find.text('活跃用户'), findsOneWidget);
  expect(find.text('1,234'), findsOneWidget);
});
```

---

## 环境

| 命令 | 目录 |
|------|------|
| `dart analyze lib/` | `renderer/` |
| `dart pub get` | `renderer/` |
| `flutter test` | 项目根 |
| `flutter run -t example/main.dart` | 项目根 |

---

## 相关文档

- [CLAUDE.md](./CLAUDE.md) — AI 协作规范
- [docs/plugin-authoring-guide-renderer.md](./docs/plugin-authoring-guide-renderer.md) — 插件开发者集成指南
- [docs/event_contract.md](./docs/event_contract.md) — V2 事件系统契约
- [docs/render_rules.dart](./docs/render_rules.dart) — 像素常量系统
- [shared/render_tokens.dart](./shared/render_tokens.dart) — 共享渲染常量（Dart + CSS）
- [example/](./example/) — 可运行示例
