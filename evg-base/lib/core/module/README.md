# Module 模块

> 声明式模块系统：`manifest.json` → `ModuleDescriptor` → `ModuleRegistry` → 渲染管线。  
> 源码: `module_descriptor.dart` `module_registry.dart` `module_loader.dart` | 示例: `example/` | 教程: `docs/` | 测试: `test/`

---

## 核心 API

### ModuleDescriptor — 模块描述符

```dart
const ModuleDescriptor(id, name, {description, icon, route, ui, ...})
ModuleDescriptor.fromJson(Map<String,dynamic>)   // manifest 解析
ModuleDescriptor.fromJsonString(String)          // JSON 字符串解析
.toJson() → Map<String,dynamic>
```

| 字段 | 必填 | 类型 | 默认 | 说明 |
|------|:--:|------|------|------|
| `id` | ✓ | `String` | — | 全局唯一标识 |
| `name` | ✓ | `String` | — | 展示名称 |
| `description` | | `String` | `""` | 描述 |
| `icon` | | `IconData?` | — | 图标 |
| `route` | | `String?` | — | 主路由；`null` = 纯服务 |
| `ui` | | `String` | `"default"` | `default`/`chat`/`spreadsheet`/`document`/`presentation`/`dashboard`/`editor` |
| `sidebar` | | `SidebarDescriptor?` | — | 侧边栏 |
| `secondaryNavs` | | `List<NavDescriptor>` | `[]` | 子导航 |
| `layout` | | `LayoutDescriptor` | `const` | 布局 |
| `dataBindings` | | `List<DataBindingDescriptor>` | `[]` | 数据绑定 |
| `chat` | | `ChatOptions?` | — | `ui:"chat"` 专用 |
| `spreadsheet` | | `SpreadsheetOptions?` | — | `ui:"spreadsheet"` 专用 |
| `document` | | `DocEditorOptions?` | — | `ui:"document"` 专用 |
| `presentation` | | `PresentationOptions?` | — | `ui:"presentation"` 专用 |
| `input` | | `InputOptions?` | — | 键盘交互 |
| `actions` | | `ActionDescriptor?` | — | 鼠标/触摸交互（旧版） |
| `media` | | `MediaDescriptor?` | — | 内嵌文件 |
| `workspace` | | `WorkspaceDescriptor?` | — | 文件工作区 |
| `timeline` | | `TimelineDescriptor?` | — | 时间线 |
| `map` | | `MapDescriptor?` | — | 地图 |
| `form` | | `FormDescriptor?` | — | 表单 |
| `process` | | `ProcessDescriptor?` | — | 模块级后端进程 |
| `dependencies` | | `List<String>` | `[]` | 依赖模块 id |
| `activateSkills` | | `List<String>` | `[]` | 自动激活的 Skill 名 |
| `version` | | `String` | `"0.0.0"` | 语义版本号 |
| `pages` | | `List<PageDescriptor>` | `[]` | 多页面（composite 模式） |
| `actionButtons` | | `List<ActionButtonDescriptor>` | `[]` | 动作按钮（composite 模式） |

**便捷属性**: `isServiceOnly`（无 UI）、`hasSidebar`（在侧边栏）、`allRoutePaths`（全部路由）

### ModuleRegistry — 注册中心

| 方法 | 说明 |
|------|------|
| `register(d)` | 注册模块；seal 后或重复 id 抛 `StateError` |
| `registerAll(list)` | 批量注册 |
| `registerFromJson(str)` | JSON 字符串注册 |
| `seal()` | 锁定 + 校验依赖 |
| `modules` → `List<ModuleDescriptor>` | 只读列表 |
| `findById(id)` → `ModuleDescriptor?` | 按 id 查找 |
| `findByRoute(path)` → `ModuleDescriptor?` | 按路由路径查找 |
| `search(query, {dims, cat})` → `List<PluginManifest>` | 搜索/筛选 |
| `listByCapability(dim)` → `List<ModuleDescriptor>` | 按能力维度列出 |
| `buildRoutePaths()` → `List<String>` | 所有路由路径 |
| `navGroups` / `navFlat` / `paletteItems` | 导航数据 |

### ModuleLoader — 加载器

| API | 说明 |
|------|------|
| `loadBuiltinModules(dir, registry)` | 加载内置模块 |
| `scanModules(dir)` → `List<ModuleDescriptor>` | 扫描目录，不启动进程 |
| `scanAndLoadModules(dir, registry)` → `Future<List<ModuleLoader>>` | 扫描 + 注册 + 并行启动 exe |

**ModuleLoader 类**: `ModuleLoader(manifest, workingDir, {required projectRoot})` → `start()` / `stop()` / `isRunning` / `port`

---

## 子描述符参考

### SidebarDescriptor

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `section` | `String` | — | 分类标签（必填） |
| `sectionOrder` | `int` | `50` | 分类间排序 |
| `order` | `int` | `50` | 分类内排序 |
| `badge` | `bool` | `false` | 角标 |

### NavDescriptor

| 字段 | 类型 | 说明 |
|------|------|------|
| `icon` | `IconData?` | 图标 |
| `label` | `String` | 展示名 |
| `routePath` | `String` | 路由路径 |
| `section` | `String` | 所属分类 |

### LayoutDescriptor

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `mode` | `String` | `"scroll"` | `scroll` / `fit` |
| `grid` | `GridOptions?` | `null` | `{columns:2, gap:16}` |
| `zoom` | `ZoomDescriptor` | `enabled:false` | `{enabled, min:0.5, max:2.0}` |
| `drawers` | `List<String>` | `[]` | `top`/`left`/`right`/`bottom` |
| `search` | `SearchDescriptor?` | `null` | `{enabled, placeholder:"搜索..."}` |
| `panels` | `List<PanelDescriptor>` | `[]` | `{id, label, path, isDefault}` |

### ChatOptions（`ui:"chat"`）

| 子组 | 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|------|
| `thinking` | `visible` / `transparent` / `mode` / `showDuration` | `bool`/`String`/`bool` | `true`/`false`/`"expand"`/`false` | 思考栏 |
| `toolCalls` | `visible` / `showArgs` / `showResult` / `autoCollapse` | `bool` | `true`/`true`/`true`/`false` | 工具调用 |
| `bubble` | `style` / `avatarPosition` / `showTimestamp` | `String`/`String`/`bool` | `"rounded"`/`"left"`/`true` | 气泡样式 |
| `stream` | `enabled` / `animation` / `cursorStyle` | `bool`/`String`/`String` | `true`/`"typewriter"`/`"blinking"` | 流式输出 |
| — | `placeholder` / `multi_session` | `String`/`bool` | `"输入消息..."`/`false` | 占位/多会话 |

### SpreadsheetOptions（`ui:"spreadsheet"`）

`formulas` `charts` `sheets` `conditionalFormatting`（`bool`, `false`）| `resizableColumns`（`bool`, `true`）| `columns`（`int`, `26`）| `rows`（`int`, `100`）

### DocEditorOptions（`ui:"document"`）

`trackChanges` `comments` `tableOfContents` `footnotes` `headersFooters`（`bool`, `false`）| `pageSetup`（`bool`, `true`）| `exportFormats`（`List<String>`, `["pdf","docx"]`）

### PresentationOptions（`ui:"presentation"`）

`transitions` `animations` `speakerNotes` `presenterView` `slideMaster`（`bool`, `false`）| `layouts`（`List<String>`, `["title","content","blank","two-column"]`）| `exportFormats`（`List<String>`, `["pdf","pptx"]`）

### DataBindingDescriptor

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `dataType` | `String` | — | `DataType.name`（必填） |
| `display` | `String` | `"list"` | `table` / `list` / `card` / `raw` |
| `filter` | `bool` | `false` | 前端筛选 |

### ActionDescriptor（旧版交互）

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `itemTap` | `String?` | `null` | `detail` / `select` / `none` |
| `itemLongPress` | `String?` | `null` | `context_menu` / `none` |
| `itemSwipe` | `String?` | `null` | `delete` / `archive` / `none` |
| `selection` | `String` | `"none"` | `none` / `single` / `multi` |
| `refresh` | `RefreshDescriptor?` | `null` | `{enabled, pullToRefresh, autoInterval}` |
| `sortable` | `List<String>` | `[]` | 可排序字段 |
| `creatable` | `bool` | `false` | 允许新增 |
| `editable` | `bool` | `false` | 允许编辑 |
| `deletable` | `DeletableDescriptor?` | `null` | `{enabled, confirm}` |
| `exportable` | `List<String>` | `[]` | 导出格式 |

### InputOptions

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `mode` | `String` | `"free-text"` | `free-text` / `type-check` / `code` / `select` |
| `autoFocus` | `bool` | `true` | 自动聚焦 |
| `maxLength` | `int` | `0` | 最大长度（0 = 不限） |

free-text 专用: `multiline` `sendOnEnter` `attachments` `voice` `slashCommands` `quickReplies`  
type-check 专用: `caseSensitive` `feedback.{correct,incorrect}`  
code 专用: `language` `autoIndent` `tabSize`  
select 专用: `options`

### MediaDescriptor

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `accept` | `String` | `"*.*"` | 文件后缀 |
| `mode` | `String` | `"inline"` | `inline`/`fullscreen`/`drawer`/`dropdown`/`fixed` |
| `direction` | `String` | `"top"` | drawer/dropdown 方向 |
| `controls` | `bool` | `true` | 显示控件 |
| `fixedSize` | `{width,height}?` | — | fixed 模式尺寸 |

子媒体选项: `video`（`speeds`/`cache`/`quality`/`captions`）、`audio`（`speeds`/`waveform`）、`document`（`zoomable`/`searchable`/`pageIndicator`/`paginated`）、`image`（`zoomable`/`gallery`）

### 其他描述符

| 描述符 | 关键字段 |
|--------|---------|
| `WorkspaceDescriptor` | `enabled` `accept` `maxFiles` `maxSizeMb` `aiCreatable` `persistAcrossSessions` |
| `TimelineDescriptor` | `mode`(`calendar`/`timeline`/`agenda`) `view` `defaultView` `itemTap` `creatable` |
| `MapDescriptor` | `center`(`{lat,lng}`) `zoom` `markers` `search` `route` |
| `FormDescriptor` | `fields[]`(`{key,label,type,required,options,placeholder}`) `submitLabel` `validateOnBlur` |
| `ProcessDescriptor` | `exe`（必填） `protocol`(`http`/`stdio`) `preferredPort`（0 = 自动） |
| `SidebarSection` | `SidebarSection(label, {order})` |
| `NavEntry` | `{icon, label, routePath, order}` |

---

## v1.1 扩展

### 六维插件模型（`capability.dart`）

| API | 说明 |
|------|------|
| `discoverCapabilities(dir)` → `List<CapabilityDimension>` | 扫描插件目录自动发现能力 |
| `parseCapabilityDimension(name)` → `CapabilityDimension?` | 字符串解析（不区分大小写） |

### ModuleHttpServer（6 端点）

```
GET /module/health    /module/modules    /module/modules/:id
GET /module/search?q=&dim=&cat=    /module/nav    /module/routes
```

`start()` → `Future<int>`（实际端口），`port:0` 自动分配，启动后写入 `.module_port`。

### v1.1 新增字段/方法

| 位置 | 新增 |
|------|------|
| `ModuleDescriptor` | `activateSkills` `version` |
| `ModuleRegistry` | `findByRoute` `search` `listByCapability` `setCapabilities` |
| `ModuleLoader` | 注册后自动 `discoverCapabilities()` → `setCapabilities()` |

### 其他模型

- **`PluginManifest`**（`plugin_manifest.dart`）— `search()` 返回类型
- **`PluginDetail`**（`plugin_detail.dart`）— 详情页完整信息
- **`ModuleLifecycle`**（`module_lifecycle.dart`）— 安装/卸载/禁用/升级
- **`ProcessManager`**（`process_manager.dart`）— 四级进程作用域
- **`PageEventBus`**（`page_event_bus.dart`）— 页级跨栏事件
- **`ExposeStateWriter`**（`expose_state_writer.dart`）— 状态快照

---

## 插件开发者入口

| 需求 | 文档 |
|------|------|
| 快速上手 | [`docs/01-quickstart.md`](docs/01-quickstart.md) |
| manifest.json 完整参考 | [`docs/plugin-authoring-guide-module.md`](docs/plugin-authoring-guide-module.md) |
| 完整示例 | `example/example.dart` + `example/plugins/my_module/` |

### 最简插件

```json
{ "type": "module", "id": "my_plugin", "name": "我的插件" }
```

放入 `plugins/my_plugin/module/manifest.json`，启动自动加载。

---

## 设计原则

- 模块只负责导航 + 路由 + UI 声明，渲染由下游实现
- 所有模块统一走 `ModuleDescriptor.fromJson`，无硬编码内置模块
- `register()` → `seal()` 不可变：seal 后写入抛 `StateError`
- 未知字段静默忽略，保证向下兼容
- 四级 `.exe` 层级各自独立，互不覆盖
