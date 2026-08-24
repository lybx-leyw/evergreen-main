# Renderer — Evergreen 渲染层

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 见根 `README.md` |
| 日期 | 2026-08-02 |
| 负责人 | renderer |
| 适用 | renderer 渲染层 |

> 纯渲染层：读 `ModuleDescriptor`，按声明/模板画 UI。不解析 manifest、不管理进程、不写业务逻辑。
> **用户侧插件创作主路径为 HTML**：`html-creator` 编写 HTML/CSS/JS → 导出 HTML 插件 → `html_modle` WebView 渲染。
> 最后更新：2026-08-25。

---

## 架构定位

```
core/ (服务层) → plugins/ (声明+HTML/.exe) → renderer/ (渲染层)
```

渲染层是最下游消费者：接收 `core/` 提供的 `ModuleDescriptor` + 运行时数据，通过 `ModuleDispatch` 按 `template` / `pages` / `workspace` 自动选择模板或范式视图。

---

## 实际目录结构

```
lib/renderer/
├── app/               # 应用壳（AppShell / CommandPalette / DebugErrorBar / DevModeHub）
│   └── service/       # 全局 Provider、主题服务（ThemeProvider / RenderTokens）
├── atomic/            # 原子取数原语（DataSourceResolver / JSONPath / TransformRegistry）
├── components/        # 共享组件
│   ├── shared/        # 组合基础设施（TemplateEngine / SlotScale / AgentTrace）
│   └── shared/widgets/ # 原子组件（清单见 widgets/）
├── module/            # 模块调度（EvergreenModulePage / ModuleDispatch）
├── multi_agent/       # 多 Agent 并行视图
├── page/              # 页面视图（市场 / 设置 / 数据看板 / 文件 / 全局记忆 / Skill 管理）
├── templates/         # 模板（modle）渲染器与注册表
│   └── v4_modle/      #   slot 分派 + 组件域（document/data/interaction/creative/learning/controls）收敛于此
├── lib/               # Stub 包（独立 dart analyze）
├── docs/              # 设计规范 + 渲染常量
└── renderer.dart      # barrel 导出
```

---

## 模块调度（V2，不再使用 `ui` 字段）

`ModuleDispatch.build(context)` 按以下规则分发：

| 条件 | 视图 | 说明 |
|------|------|------|
| `descriptor.id == 'ai-assistant'` | `ChatControllerView` | AI 助手专用全屏对话 |
| `descriptor.template` 非空且非 `v4` | `TemplateRegistry.render` | 自定义模板：html / scraper / theme-creator / skill-creator / dsh / zju / classroom / zdbk / paper_reading |
| `descriptor.pages` 非空 | `TemplateRegistry.render` | 有 pages 时按模板路由（默认 v4 composite） |
| `descriptor.workspace.enabled` | `EditorView` | 文件工作区 / 代码编辑 |
| 其他 | `DefaultView` | 通用数据绑定兜底 |

> **lattice 契约现状**：六格契约（`static-web`/`web-bridged`/`data-source`/`sidecar`/`agent-tool`/`external-app`）由 `core/module` 解析与权限层裁决；renderer **不按 lattice 路由**（`ModuleDispatch` 只消费 `template`/`pages`/`workspace`），`external-app` 深链特判未在 renderer 实现。详见 `CLAUDE.md`。

模板注册表（生成物 `templates/generated/template_registry.g.dart`）：

| 模板名 | 渲染器 | 用途 |
|--------|--------|------|
| `v4` | `V4ModleTemplate` | 通用组件式模块 |
| `html` | `HtmlModleTemplate` | HTML 插件（用户侧主路径） |
| `scraper` | `ScraperTemplate` | 所见即所得爬虫 |
| `theme-creator` | `ThemeCreatorModleTemplate` | 主题创作中心 |
| `skill-creator` | `SkillCreatorModleTemplate` | Skill 创作中心 |
| `dsh` | `DshModleTemplate` | DeepSeek Harness |
| `paper_reading` | `PaperReadingModleTemplate` | 论文阅读 |
| `zju` / `classroom` / `zdbk` | `ZjuModleTemplate` | 浙大校园 |

---

## HTML 插件渲染

`html_modle` 是用户侧插件的核心模板：

1. 本地 HTTP 服务加载 `plugins/<id>/module/index.html`（支持 css/js/json/png/svg 等静态资源）
2. Windows WebView / Android WebView 加载页面（bridge 双通道 `chrome.webview` / `evgBridge`）
3. 自动注入 `platform.*` JS Bridge（服务端文档顶部内联 + document-created + onPageStarted 三保险）
4. 当前主题色板注入为 `--evg-*` CSS 变量，主题切换实时推送

插件侧可用 API（Promise 风格）：

```js
const data = await platform.data.get('zju_scores');
const all = await platform.data.list();
await platform.data.refresh('zju_scores');
await platform.data.testConnectivity();
platform.data.subscribe('zju_scores', (payload) => console.log(payload));

const reply = await platform.ai.chat('总结这段数据', 'concise');
await platform.api.call('module', '/module/modules', { method: 'GET' });
await platform.settings.set('THEME_MODE', 'dark');
const colors = await platform.theme.getColors();
platform.emit('my-event', { hello: 'world' });
platform.on('theme:changed', (colors) => { ... });

// 进程白名单（manifest `process` 声明，fail-closed）：
const r = await platform.process.run('zjuical', { args: ['-u', user] });
await platform.process.start('worker.py', { args: [] });   // scope:"long" 常驻
await platform.process.write('worker.py', 'go\n');
const out = await platform.process.read('worker.py');
await platform.process.stop('worker.py');
```

> 特例：`descriptor.id == 'html-creator'` 时短路到 Dart 原生 `HtmlCreatorView`（创作中心三栏 IDE），不启动本地 HTTP / WebView。

---

## 共享组件

### 原子组件（components/shared/widgets/）

按领域分组，代表性组件（`app_shell` / `command_palette` 等壳组件在 `app/`，不属于 widgets）：

| 分组 | 代表组件 |
|------|----------|
| 通用 | `toast`, `empty_state`, `error_card`, `loading_indicator`, `confirm_dialog` |
| Chat | `message_bubble`, `thinking_block`, `tool_call_card`, `chat_input_bar` |
| 数据展示 | `data_table`, `data_list`, `data_card_grid`, `dashboard_card`, `freshness_badge` |
| 交互 | `crud_toolbar`, `confirm_dialog`, `search_bar`, `export_menu`, `refresh_widget` |
| 编辑器 | `code_editor`, `rich_text_editor`, `track_changes_gutter` |
| 表单 | `type_check_input`, `select_input`, `form_field_renderer` |
| 媒体 | `media_host`, `video_player`, `audio_player`, `image_viewer`, `document_viewer`, `pdf_viewer` |
| 办公 | `spreadsheet_cell`, `formula_bar`, `chart_renderer`, `slide_canvas`, `slide_sorter`, `speaker_notes_panel` |
| 市场/权限 | `ability_tag`, `install_progress`, `permission_dialog`, `notification_card` |

### 组合基础设施（components/shared/）

- `template_engine.dart` — 模板引擎
- `slot_scale.dart` — 槽位缩放
- `trace/` — Agent 轨迹记录与视图

---

## 核心原则

- **描述符/模板驱动**：配置通过 `*Options` / `*Descriptor` 不可变类传入，运行时数据独立注入
- **未知静默忽略**：未识别字段/UI 值不抛异常，回退到 `DefaultView`
- **渲染层不越界**：不解析 manifest、不管理 `.exe` 进程、不直连 core HTTP（HTML 插件除外——由 JS Bridge 转发）

---

## 主题系统

扁平 8 色语义色板（见 `core/theme`），渲染层负责：

```dart
final themeData = buildThemeFromDescriptor(descriptor);
final bg = Theme.of(context).evergreen.warning;          // 语义色扩展
final color = context.componentColor('bubble', 'user'); // 组件色（如有）
```

HTML 插件使用 CSS 变量：

```css
:root {
  --evg-background: #0D1117;
  --evg-surface: #161B22;
  --evg-accent: #58A6FF;
}
```

---

## 开发红线

| 禁止 | 原因 |
|------|------|
| widgets/ 调 API / 管状态 | 原子组件只渲染 |
| 解析 manifest.json | 上游已解析为 `ModuleDescriptor` |
| 管理 .exe 进程 | 进程生命周期归 core |
| 使用 `descriptor.ui` 字段 | V2 已删除，按 template/pages/workspace 分发 |
| 未知字段抛异常 | 容错静默忽略 |

---

## 测试

- `renderer/test/`：组件级 widgetTest
- 项目根 `test/`：集成测试
- `dart analyze lib/`：stub 包零问题

```dart
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

---

## 相关文档

- [CLAUDE.md](./CLAUDE.md) — AI 协作规范
- [AGENT.md](./AGENT.md) — OWNER 职责书
- [templates/template_registry.dart](./templates/template_registry.dart) — 模板注册表
- [templates/templates_index.json](./templates/templates_index.json) — 模板清单（生成器输入）
- [templates/html_modle/html_modle_view.dart](./templates/html_modle/html_modle_view.dart) — HTML 插件视图
- [templates/html_modle/bridge_script.dart](./templates/html_modle/bridge_script.dart) — JS Bridge 生成 + core 转发 + 数据订阅轮询
