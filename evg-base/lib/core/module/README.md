# Module 模块

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-module |
| 适用 | module 子包 |

> 声明式模块系统：`manifest.json` → `ModuleDescriptor` → `ModuleRegistry` → 渲染管线。  
> 源码: `module_descriptor.dart` `module_registry.dart` `module_loader.dart` | 示例: `example/` | 教程: `docs/` | 测试: `test/`
>
> **用户侧事实**：普通用户不直接编写复杂 `ModuleDescriptor`。用户通过 `html-creator` 编写 HTML/CSS/JS，
> 导出的 manifest 仅需 `"template":"html"` + 基本元数据；模块系统保留给内置功能、开发者模式和高级 JSON 模板。

---

## 核心 API

### ModuleDescriptor — 模块描述符

```dart
const ModuleDescriptor(id, name, {description, icon, route, template, nav, pages, workspace, ...})
ModuleDescriptor.fromJson(Map<String,dynamic>)   // manifest 解析
ModuleDescriptor.fromJsonString(String)          // JSON 字符串解析
.toJson() → Map<String,dynamic>
```

| 字段 | 必填 | 类型 | 默认 | 说明 |
|------|:--:|------|------|------|
| `id` | ✓ | `String` | — | 全局唯一标识 |
| `name` | ✓ | `String` | — | 展示名称 |
| `description` | | `String` | `""` | 描述 |
| `icon` | | `int?` | — | Material Icon codePoint |
| `route` | | `String?` | — | 路由；`null` = 纯服务 |
| `version` | | `String` | `"0.0.0"` | 语义版本号 |
| `dependencies` | | `List<String>` | `[]` | 依赖模块 id |
| `activateSkills` | | `List<String>` | `[]` | 自动激活的 Skill 名 |
| `style` | | `StyleDescriptor` | `const` | 模块级默认样式 |
| `nav` | | `NavObjectDescriptor` | `const` | 导航配置（sidebar + secondary） |
| `process` | | `List<ProcessDescriptor>` | `[]` | 模块级后端进程 |
| `events` | | `EventDescriptor` | `const` | 模块级事件 |
| `actions` | | `ActionDescriptor?` | — | 交互动作（旧版） |
| `dataBindings` | | `List<DataBindingDescriptor>` | `[]` | 数据绑定 |
| `workspace` | | `WorkspaceDescriptor?` | — | 文件工作区 |
| `pages` | | `List<PageDescriptor>` | `[]` | 多页面 |
| `theme` | | `Map<String, Map<String, String>>?` | — | 模块级 theme 覆盖 |
| `template` | | `String` | `"v4"` | 渲染模板：`v4` / `html` / `scraper` / `theme-creator` / `skill-creator` / `dsh` / `zju` / `paper_reading` |
| `dataSource` | | `DataSourceDescriptor?` | — | 模块级数据源（`orch://<type>`） |
| `modleRoute` | | `String?` | — | 模板内子路由（如 zdbk 的 score/notifications） |
| `dataSources` | | `Map<String, DataSourceDescriptor>?` | — | 命名多数据源 |
| `lattice` | | `Lattice?` | 推断 | 六格契约等级（M0）：`static-web`/`web-bridged`/`data-source`/`sidecar`/`agent-tool`/`external-app`。缺省按 §2.4 信号推断；显式声明才写回（`_latticeExplicit` 保证旧 manifest 字节兼容） |
| `runtime` | | `RuntimeDescriptor?` | — | sidecar 运行时描述符（仅 `lattice:sidecar` 非空）：`kind`(node/python/deno)/`entry`/`protocol`(http/stdio)/`port`/`gracefulTimeoutMs`/`capabilities`(fs.scope/net.allow/spawn 白名单，deny-all 默认） |

**便捷属性**: `isServiceOnly`（无 UI）、`hasSidebar`（在侧边栏）、`allRoutePaths`（全部路由）

### ModuleRegistry — 注册中心

| 方法 | 说明 |
|------|------|
| `register(d)` | 注册模块；seal 后或重复 id 抛 `StateError` |
| `registerAll(list)` | 批量注册 |
| `registerFromJson(str)` | JSON 字符串注册 |
| `registerResolved(rp)` | 注册已解析的 `ResolvedPlugin`（M0 单一事实源入口，避免重复解析） |
| `seal()` | 锁定 + 校验依赖 |
| `modules` → `List<ModuleDescriptor>` | 只读列表 |
| `resolved` → `List<ResolvedPlugin>` | 已解析插件只读列表 |
| `findById(id)` → `ModuleDescriptor?` | 按 id 查找 |
| `findByRoute(path)` → `ModuleDescriptor?` | 按路由路径查找 |
| `findByLattice(lattice)` → `List<ResolvedPlugin>` | 按六格契约等级列出 |
| `search(query, {dims, cat})` → `List<PluginManifest>` | 搜索/筛选 |
| `listByCapability(dim)` → `List<ModuleDescriptor>` | 按能力维度列出 |
| `buildRoutePaths()` → `List<String>` | 所有路由路径 |
| `navGroups` / `navFlat` / `paletteItems` | 导航数据 |
| `reloadModule(d)` / `unregister(id)` | seal 后热重载 / 反注册（插件设计器用） |

### ModuleLoader — 加载器

| API | 说明 |
|------|------|
| `ModuleLoader(manifest, workingDir, {required projectRoot})` | 构造（V1 兼容，内部包 ResolvedPlugin） |
| `ModuleLoader.fromResolved(resolved, workingDir, {projectRoot, sidecarRuntime})` | 从单一事实源构造（M0 推荐入口） |
| `loadBuiltinModules(dir, registry)` | 加载内置模块 |
| `scanModules(dir)` → `List<ModuleDescriptor>` | 扫描目录，不启动进程 |
| `scanAndLoadModules(dir, registry)` → `Future<List<ModuleLoader>>` | 扫描 + 注册 + 并行加载（HTML 模块仅注册/加载静态资源，有后端进程的模块才启动 exe；sidecar 格走 `SidecarController`） |

**ModuleLoader 实例**: `start()` / `stop()` / `isRunning` / `port` / `sidecarMeta`（仅 sidecar 格）

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

### LayoutDescriptor（V2）

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `type` | `String` | `"grid"` | `grid` / `flex` / `fullscreen` / `absolute` / `dock` |
| `preset` | `LayoutPreset` | `const` | 布局超参数：`columns`/`rows`/`direction`/`wrap`/`gap`/`justify`/`align`/`regions`（Map 非 String） |
| `features` | `LayoutFeatures` | `const` | `zoom`（enabled/min/max）/ `search`（enabled/placeholder）/ `drawers`（top/left/right/bottom） |
| `style` | `StyleDescriptor` | `const` | 布局级样式 |
| `events` | `EventDescriptor` | `const` | 布局级事件 |
| `slots` | `Map<String, SlotDescriptor>` | `{}` | 插槽映射：slotName → 组件/子容器 |

> V1 的 `layout.mode/grid/panels` 顶层键已不再解析；`panels` 多 tab 改由 `pages[]` 表达。

### ChatOptions（对话组件配置）

| 子组 | 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|------|
| `thinking` | `visible` / `transparent` / `mode` / `showDuration` | `bool`/`String`/`bool` | `true`/`false`/`"expand"`/`false` | 思考栏 |
| `toolCalls` | `visible` / `showArgs` / `showResult` / `autoCollapse` | `bool` | `true`/`true`/`true`/`false` | 工具调用 |
| `bubble` | `style` / `avatarPosition` / `showTimestamp` | `String`/`String`/`bool` | `"rounded"`/`"left"`/`true` | 气泡样式 |
| `stream` | `enabled` / `animation` / `cursorStyle` | `bool`/`String`/`String` | `true`/`"typewriter"`/`"blinking"` | 流式输出 |
| — | `placeholder` / `multi_session` | `String`/`bool` | `"输入消息..."`/`false` | 占位/多会话 |

### SpreadsheetOptions（电子表格组件配置）

`formulas` `charts` `sheets` `conditionalFormatting`（`bool`, `false`）| `resizableColumns`（`bool`, `true`）| `columns`（`int`, `26`）| `rows`（`int`, `100`）

### DocEditorOptions（文档编辑器配置）

`trackChanges` `comments` `tableOfContents` `footnotes` `headersFooters`（`bool`, `false`）| `pageSetup`（`bool`, `true`）| `exportFormats`（`List<String>`, `["pdf","docx"]`）

### PresentationOptions（演示文稿配置）

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
| `ProcessDescriptor` | `id`（V2） `exe`（必填） `runtime`(`native`/`python`) `protocol`(`http`/`stdio`) `scope`(`long`/`short`) `autoStart` `autoRestart` `preferredPort`（0 = 自动）；manifest 中 `process` 为**数组**（V1 单对象自动兼容） |
| `SidebarSection` | `SidebarSection(label, {order})` |
| `NavEntry` | `{icon, label, routePath, order}` |

---

## 早期扩展

### 六维插件模型（`capability.dart`）

| API | 说明 |
|------|------|
| `discoverCapabilities(dir)` → `List<CapabilityDimension>` | 扫描插件目录自动发现能力 |
| `parseCapabilityDimension(name)` → `CapabilityDimension?` | 字符串解析（不区分大小写） |

### ModuleHttpServer（仅 GET，端点见下）

```
GET /module/health    /module/modules    /module/modules/:id
GET /module/search?q=&dim=&cat=    /module/nav    /module/routes
GET /module/sidecars   ← sidecar 运行时状态（M1-10，宿主经 setSidecarSnapshots 刷新）
```

`start()` → `Future<int>`（实际端口），`port:0` 自动分配，启动后写入 `.module_port`。

### 早期新增字段/方法

| 位置 | 新增 |
|------|------|
| `ModuleDescriptor` | `activateSkills` `version` |
| `ModuleRegistry` | `findByRoute` `search` `listByCapability` `setCapabilities` |
| `ModuleLoader` | 注册后自动 `discoverCapabilities()` → `setCapabilities()` |

### 新增：六格契约 / 权限 / 市场（M0–M6）

| 模型 | 文件 | 说明 |
|------|------|------|
| `Lattice` + `inferLattice` | `lattice.dart` | 六格契约枚举（static-web/web-bridged/data-source/sidecar/agent-tool/external-app）+ 缺省推断 |
| `RuntimeDescriptor` / `RuntimeCapabilities` | `runtime.dart` | sidecar 运行时描述符（kind/entry/protocol/port + fs.scope/net.allow/spawn，deny-all 默认） |
| `ResolvedPlugin` | `resolved_plugin.dart` | manifest 解析后的不可变运行时单一事实源 |
| `PermissionResolver` / `PermissionTicket` / `PermissionAudit` / `BridgeInterceptor` | `permission.dart` | 权限裁决 + 审计 + 桥调用拦截（M2） |
| `BridgeHandshake` / `BridgeShimRouter` | `permission.dart` / `bridge_shim.dart` | bridge 版本协商与多版本 shim 路由（M2-5/6） |
| `riskOf` / `maxRisk` | `capability_bridge.dart` | 能力维度风险定级 safe/warning/danger（M5-3/4） |
| `ContentAddress` | `content_address.dart` | manifest+资源 SHA-256 稳定 ID（安装缓存去重/篡改检测，M3-1） |
| `GithubSource` / `RepoClassification` | `github_source.dart` | GitHub 源解析 + 仓库按格分类（M4-1/2） |
| `ScaffoldInput` / `generateManifest` | `scaffold_plugin.dart` | 上架脚手架 manifest 生成（M4-3） |
| `MarketplaceSource` / `parseMarketplaceSources` | `marketplace_source.dart` | 市场源（github/localDir）解析（M5-1） |
| `MarketplaceEntry` / `scanPluginDir` / `scanSources` | `marketplace_scanner.dart` | 市场扫描 → 插件发现列表（M5-5） |
| `RegistryPlugin` / `PluginManifest` / `parsePluginRegistry` | `plugin_registry.dart` | 远程 registry `plugins.json` 解析 + 安装策略（M6-0） |
| `ReviewQueue` / `ReviewStore` / `aggregateReviews` | `plugin_review.dart` | 审核队列（fail-closed 默认拒绝曝光）+ 评分聚合（M5-2） |
| `SidecarController` / `SidecarRuntime` / `sidecarMetaOf` | `sidecar/sidecar_controller.dart` | sidecar 一等公民生命周期抽象（M1） |
| `NodeSidecarController` / `PythonSidecarController` / `DenoSidecarController` | `sidecar/*_sidecar.dart` | 三种语言运行时实现（M1-3/4/5） |
| `SidecarStatus` / `SidecarStatusClient` | `sidecar_status_client.dart` | `/module/sidecars` 查询客户端 |

### 其他模型

- **`PluginManifest`**（`plugin_manifest.dart`）— `search()` 返回类型
- **`PluginDetail`**（`plugin_detail.dart`）— 详情页完整信息
- **`ModuleLifecycle`**（`module_lifecycle.dart`）— 安装/卸载/禁用/升级
- **`ProcessManager`**（`process_manager.dart`）— 四级进程作用域
- **`PageEventBus`**（`page_event_bus.dart`）— 页级跨栏事件
- **`ExposeStateWriter`**（`expose_state_writer.dart`）— 状态快照
- **`CapabilityDimension` / `discoverCapabilities`**（`capability.dart`）— 六维能力枚举 + 目录自动发现 + `latticeToCapability` 桥（M0-15）

---

## 插件开发者入口

| 需求 | 文档 |
|------|------|
| 快速上手 | [`docs/01-quickstart.md`](docs/01-quickstart.md) |
| manifest.json 完整参考（唯一权威） | [`docs/plugin-module.md`](docs/plugin-module.md) |
| 完整示例 | `example/example.dart` + `example/plugins/my_module/` |

### 用户侧最简 HTML 插件（推荐）

```
plugins/my-html-plugin/
└── module/
    ├── manifest.json
    └── index.html
```

`manifest.json`：

```json
{
  "schemaVersion": "2.0",
  "type": "module",
  "id": "my-html-plugin",
  "name": "我的 HTML 插件",
  "template": "html",
  "route": "/my-html-plugin"
}
```

`index.html` 即用户自写 HTML/JS 的入口，运行时可通过 `platform.data.*` / `platform.ai.*` /
`platform.settings.*` / `platform.theme.getColors()` 等 JS Bridge 调用平台能力。
完整创作流程优先使用 `html-creator`，无需手工维护 manifest。

---

## 设计原则

- 模块只负责导航 + 路由 + UI 声明，渲染由下游实现
- 所有模块统一走 `ModuleDescriptor.fromJson`，无硬编码内置模块
- `register()` → `seal()` 不可变：seal 后写入抛 `StateError`
- 未知字段静默忽略，保证向下兼容
- 四级 `.exe` 层级各自独立，互不覆盖
