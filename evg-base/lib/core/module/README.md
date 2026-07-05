# 模块

> 示例 `example/example.dart`、教程 `docs/`、内置模块 `builtins/`、源码 `module_descriptor.dart` `module_registry.dart` `module_loader.dart` `sidebar_section.dart`、测试（待添加）

模块声明与注册——所有模块通过 `manifest.json` 声明。内置模块放 `builtins/`，外部插件放 `plugins/`。

---

## 一、平台开发者 API

### ModuleDescriptor

| 工厂 / 构造 | 输入 | 输出 | 说明 |
|------------|------|------|------|
| `ModuleDescriptor(...)` | 各字段 | `ModuleDescriptor` | const 构造 |
| `ModuleDescriptor.fromJson(json)` | `Map<String,dynamic>` | `ModuleDescriptor` | manifest 解析；校验 `type=="module"` |
| `ModuleDescriptor.fromJsonString(str)` | `String` | `ModuleDescriptor` | JSON 字符串解析 |
| `toJson()` | — | `Map<String,dynamic>` | 序列化 |

| 字段 | 必填 | 类型 | 默认值 | 说明 |
|------|------|------|--------|------|
| `id` | ✓ | `String` | — | 全局唯一标识 |
| `name` | ✓ | `String` | — | 展示名称 |
| `description` | | `String` | `""` | 描述 |
| `icon` | | `IconData?` | — | 图标 |
| `route` | | `String?` | — | 主路由；不填 = 纯服务 |
| `ui` | | `String` | `"default"` | `default` / `chat` / `spreadsheet` / `document` / `presentation` / `dashboard` / `editor` |
| `sidebar` | | `SidebarDescriptor?` | — | 侧边栏配置 |
| `secondaryNavs` | | `List<NavDescriptor>` | `[]` | 子导航 |
| `layout` | | `LayoutDescriptor` | `const` | 布局 |
| `dataBindings` | | `List<DataBindingDescriptor>` | `[]` | 数据绑定 |
| `chat` | | `ChatOptions?` | — | ui=="chat" |
| `spreadsheet` | | `SpreadsheetOptions?` | — | ui=="spreadsheet" |
| `document` | | `DocEditorOptions?` | — | ui=="document" |
| `presentation` | | `PresentationOptions?` | — | ui=="presentation" |
| `input` | | `InputOptions?` | — | 键盘交互 |
| `actions` | | `ActionDescriptor?` | — | 鼠标/触摸交互 |
| `media` | | `MediaDescriptor?` | — | 内嵌文件 |
| `workspace` | | `WorkspaceDescriptor?` | — | 文件工作区 |
| `timeline` | | `TimelineDescriptor?` | — | 时间线 |
| `map` | | `MapDescriptor?` | — | 地图 |
| `form` | | `FormDescriptor?` | — | 表单 |
| `process` | | `ProcessDescriptor?` | — | 后端进程 |
| `dependencies` | | `List<String>` | `[]` | 依赖模块 id |

### 便捷属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `isServiceOnly` | `bool` | 无 UI 页面 |
| `hasSidebar` | `bool` | 出现在侧边栏 |
| `allRoutePaths` | `List<String>` | 全部路由路径 |

### ModuleRegistry

| 方法 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `register(d)` | `ModuleDescriptor` | `void` | 注册；seal 后或 id 重复抛异常 |
| `registerAll(list)` | `List<ModuleDescriptor>` | `void` | 批量注册 |
| `registerFromJson(str)` | `String` | `void` | JSON 字符串注册 |
| `seal()` | — | `void` | 锁定 + 校验依赖 |
| `modules` | — | `List<ModuleDescriptor>` | 只读 |
| `findById(id)` | `String` | `ModuleDescriptor?` | 按 id 查 |
| `buildRoutePaths()` | — | `List<String>` | 所有路由路径 |
| `navGroups` | — | `List<(SidebarSection, List<NavEntry>)>` | 分组导航 |
| `navFlat` | — | `List<NavEntry>` | 扁平导航 |
| `paletteItems` | — | `List<({...})>` | 命令面板条目 |

### ModuleLoader

| 函数 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `loadBuiltinModules(dir, registry)` | `String`, `ModuleRegistry` | `void` | 加载内置模块 |
| `scanModules(dir)` | `String` | `List<ModuleDescriptor>` | 扫描，不启动进程 |
| `scanAndLoadModules(dir, registry)` | `String`, `ModuleRegistry` | `Future<List<ModuleLoader>>` | 扫描 + 注册 + 并行启动 exe，等全部就绪后返回 |

### ModuleLoader 类

| 方法 / 属性 | 类型 | 说明 |
|------------|------|------|
| `ModuleLoader(manifest, workingDir)` | 构造 | manifest + 工作目录 |
| `start()` | `Future<void>` | 启动 exe → PORT 检测 → /health |
| `stop()` | `void` | 终止进程 |
| `isRunning` | `bool` | 进程健康运行中 |
| `port` | `int?` | 监听端口 |

### NavEntry

| 字段 | 类型 | 说明 |
|------|------|------|
| `icon` | `IconData` | 图标 |
| `label` | `String` | 展示名 |
| `routePath` | `String` | 路由路径 |
| `order` | `int` | 排序权重 |

### SidebarSection

| 构造 | 输入 | 说明 |
|------|------|------|
| `SidebarSection(label, {order})` | `label: String`, `order: int` | 自定义分类 |

---

### SidebarDescriptor — 侧边栏

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `section` | `String` | — | 分类标签 |
| `sectionOrder` | `int` | `50` | 分类间排序 |
| `order` | `int` | `50` | 分类内排序 |
| `badge` | `bool` | `false` | 角标 |

### NavDescriptor — 子导航

| 字段 | 类型 | 说明 |
|------|------|------|
| `icon` | `String?` | 图标 |
| `label` | `String` | 展示名 |
| `routePath` | `String` | 路由路径 |
| `section` | `String` | 所属分类 |

---

### LayoutDescriptor — 布局

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `mode` | `String` | `"scroll"` | `scroll` / `fit` |
| `grid` | `GridOptions?` | `null` | 分框布局 |
| `zoom` | `ZoomDescriptor` | `enabled:false` | 缩放 |
| `drawers` | `List<String>` | `[]` | `top`/`left`/`right`/`bottom` |
| `search` | `SearchDescriptor?` | `null` | 搜索栏 |
| `panels` | `List<PanelDescriptor>` | `[]` | 多 tab |

### GridOptions

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `columns` | `int` | `2` | 列数 |
| `gap` | `int` | `16` | 框间距 |

### PanelDescriptor

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 面板标识 |
| `label` | `String` | tab 标签 |
| `path` | `String` | 路由 |
| `isDefault` | `bool` | 默认面板 |

### ZoomDescriptor

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | `bool` | `false` | 启用缩放 |
| `min` | `double` | `0.5` | 最小比例 |
| `max` | `double` | `2.0` | 最大比例 |

### SearchDescriptor

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | `bool` | `false` | 显示搜索栏 |
| `placeholder` | `String` | `"搜索..."` | 占位文本 |

---

### ChatOptions — Chat 范式（`ui:"chat"`）

#### ThinkingOptions

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `visible` | `bool` | `true` | 展示思考栏 |
| `transparent` | `bool` | `false` | 背景透明 |
| `mode` | `String` | `"expand"` | `expand` / `scroll` |
| `showDuration` | `bool` | `false` | 显示耗时 |

#### ToolCallOptions

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `visible` | `bool` | `true` | 展示工具调用 |
| `showArgs` | `bool` | `true` | 展示参数 |
| `showResult` | `bool` | `true` | 展示结果 |
| `autoCollapse` | `bool` | `false` | 自动折叠 |

#### BubbleOptions

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `style` | `String` | `"rounded"` | `rounded` / `flat` / `minimal` |
| `avatarPosition` | `String` | `"left"` | `left` / `none` |
| `showTimestamp` | `bool` | `true` | 显示时间戳 |

#### StreamOptions

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | `bool` | `true` | 流式输出 |
| `animation` | `String` | `"typewriter"` | `typewriter` / `fade` / `none` |
| `cursorStyle` | `String` | `"blinking"` | `blinking` / `static` / `none` |

---

### SpreadsheetOptions — 电子表格范式（`ui:"spreadsheet"`）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `formulas` | `bool` | `false` | 公式引擎 |
| `charts` | `bool` | `false` | 图表 |
| `sheets` | `bool` | `false` | 多 sheet |
| `conditionalFormatting` | `bool` | `false` | 条件格式 |
| `resizableColumns` | `bool` | `true` | 列拖拽调宽 |
| `columns` | `int` | `26` | 默认列数 |
| `rows` | `int` | `100` | 默认行数 |

### DocEditorOptions — 文档范式（`ui:"document"`）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `trackChanges` | `bool` | `false` | 修订模式 |
| `comments` | `bool` | `false` | 批注 |
| `tableOfContents` | `bool` | `false` | 目录 |
| `footnotes` | `bool` | `false` | 脚注 |
| `headersFooters` | `bool` | `false` | 页眉页脚 |
| `pageSetup` | `bool` | `true` | 页面设置 |
| `exportFormats` | `List<String>` | `["pdf","docx"]` | 导出格式 |

### PresentationOptions — 幻灯片范式（`ui:"presentation"`）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `transitions` | `bool` | `false` | 切换动画 |
| `animations` | `bool` | `false` | 元素动画 |
| `speakerNotes` | `bool` | `false` | 演讲者备注 |
| `presenterView` | `bool` | `false` | 演讲者视图 |
| `slideMaster` | `bool` | `false` | 母版编辑 |
| `layouts` | `List<String>` | `["title","content","blank","two-column"]` | 版式 |
| `exportFormats` | `List<String>` | `["pdf","pptx"]` | 导出格式 |

---

### DataBindingDescriptor — 数据绑定

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `dataType` | `String` | — | 指向 `DataType.name` |
| `display` | `String` | `"list"` | `table` / `list` / `card` / `raw` |
| `filter` | `bool` | `false` | 前端筛选 |

---

### ActionDescriptor — 鼠标/触摸交互

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `itemTap` | `String?` | `null` | `detail` / `select` / `none` |
| `itemLongPress` | `String?` | `null` | `context_menu` / `none` |
| `itemSwipe` | `String?` | `null` | `delete` / `archive` / `none` |
| `selection` | `String` | `"none"` | `none` / `single` / `multi` |
| `refresh` | `RefreshDescriptor?` | `null` | 刷新配置 |
| `sortable` | `List<String>` | `[]` | 可排序字段 |
| `creatable` | `bool` | `false` | 允许新增 |
| `editable` | `bool` | `false` | 允许编辑 |
| `deletable` | `DeletableDescriptor?` | `null` | 删除配置 |
| `exportable` | `List<String>` | `[]` | 导出格式 |

### RefreshDescriptor

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | `bool` | `false` | 启用刷新 |
| `pullToRefresh` | `bool` | `true` | 下拉刷新 |
| `autoInterval` | `int` | `0` | 自动刷新间隔（秒） |

### DeletableDescriptor

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | `bool` | `false` | 允许删除 |
| `confirm` | `bool` | `true` | 确认弹窗 |

---

### InputOptions — 键盘交互

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `mode` | `String` | `"free-text"` | `free-text` / `type-check` / `code` / `select` |
| `autoFocus` | `bool` | `true` | 自动聚焦 |
| `maxLength` | `int` | `0` | 最大长度 |

#### free-text 专用

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `multiline` | `bool` | `true` | 多行 |
| `sendOnEnter` | `bool` | `true` | Enter 发送 |
| `attachments` | `AttachmentOptions` | disabled | 附件 |
| `voice` | `bool` | `false` | 语音 |
| `slashCommands` | `bool` | `false` | 斜杠命令 |
| `quickReplies` | `List<String>` | `[]` | 快捷回复 |

#### type-check 专用

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `caseSensitive` | `bool` | `false` | 区分大小写 |
| `feedback.correct` | `FeedbackState` | `#4caf50 / bounce` | 正确反馈 |
| `feedback.incorrect` | `FeedbackState` | `#f44336 / shake` | 错误反馈 |

#### code 专用

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `language` | `String` | `""` | 编程语言 |
| `autoIndent` | `bool` | `true` | 自动缩进 |
| `tabSize` | `int` | `2` | Tab 空格数 |

#### select 专用

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `options` | `List<String>` | `[]` | 选项列表 |

### AttachmentOptions

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | `bool` | `false` | 启用附件 |
| `types` | `List<String>` | `["image","file"]` | 允许类型 |
| `maxSizeMb` | `int` | `0` | 单文件最大体积 |

### FeedbackOptions

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `correct` | `FeedbackStateOptions` | `#4caf50 / bounce` | 正确反馈 |
| `incorrect` | `FeedbackStateOptions` | `#f44336 / shake` | 错误反馈 |

### FeedbackStateOptions

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `color` | `String` | `"#4caf50"` | 反馈颜色 |
| `animation` | `String` | `"bounce"` | `bounce` / `shake` / `pulse` / `none` |

---

### MediaDescriptor — 内嵌文件

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `accept` | `String` | `"*.*"` | 文件后缀 |
| `mode` | `String` | `"inline"` | `inline` / `fullscreen` / `drawer` / `dropdown` / `fixed` |
| `direction` | `String` | `"top"` | drawer/dropdown 方向 |
| `fixedSize` | `{width,height}?` | — | fixed 模式尺寸 |
| `controls` | `bool` | `true` | 显示控件 |

#### FixedSizeOptions

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `width` | `dynamic?` | — | null=自适应 / `"auto"`=内容撑开 / 数字=像素 |
| `height` | `dynamic?` | — | null=自适应 / `"auto"`=内容撑开 / 数字=像素 |

#### VideoOptions（`accept` 含 `*.mp4` 等）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `speeds` | `List<double>` | `[0.5,1,1.5,2]` | 倍速选项 |
| `cache` | `bool` | `false` | 缓存 |
| `quality` | `String` | `"auto"` | 画质：`auto` / `360p` / `720p` / `1080p` |
| `captions` | `bool` | `false` | 字幕 |

#### AudioOptions（`accept` 含 `*.mp3` 等）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `speeds` | `List<double>` | `[0.5,1,1.5,2]` | 倍速选项 |
| `waveform` | `bool` | `false` | 波形 |

#### DocumentOptions（`accept` 含 `*.pdf,*.docx` 等）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `zoomable` | `bool` | `true` | 捏合缩放 |
| `searchable` | `bool` | `false` | 文档内搜索 |
| `pageIndicator` | `bool` | `true` | 页码 |
| `paginated` | `bool` | `false` | 分页展示 |

#### ImageOptions（`accept` 含 `*.jpg,*.png` 等）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `zoomable` | `bool` | `true` | 捏合缩放 |
| `gallery` | `bool` | `false` | 画廊模式 |

---

### WorkspaceDescriptor — 文件工作区

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | `bool` | `false` | 启用工作区 |
| `accept` | `String` | `"*.pdf,*.docx,..."` | 文件后缀 |
| `maxFiles` | `int` | `20` | 最大文件数 |
| `maxSizeMb` | `int` | `50` | 单文件最大体积 |
| `aiCreatable` | `List<String>` | `[]` | AI 可生成格式 |
| `persistAcrossSessions` | `bool` | `true` | 跨会话持久 |

### TimelineDescriptor — 时间线

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `mode` | `String` | `"timeline"` | `calendar` / `timeline` / `agenda` |
| `view` | `List<String>` | `["day","week","month"]` | 可用视图 |
| `defaultView` | `String` | `"week"` | 默认视图 |
| `itemTap` | `String?` | `null` | `detail` / `edit` |
| `creatable` | `bool` | `false` | 创建事件 |

### MapDescriptor — 地图

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `center` | `{lat,lng}?` | `null` | 中心坐标 |
| `zoom` | `int` | `15` | 缩放级别 |
| `markers` | `bool` | `true` | 标记点 |
| `search` | `bool` | `false` | 搜索 |
| `route` | `bool` | `false` | 路线规划 |

### FormDescriptor — 表单

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `fields` | `List<FormField>` | `[]` | 字段列表 |
| `submitLabel` | `String` | `"提交"` | 提交按钮文字 |
| `validateOnBlur` | `bool` | `true` | 失焦校验 |

#### FormField

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `key` | `String` | ✓ | 字段标识 |
| `label` | `String` | ✓ | 标签 |
| `type` | `String` | | `text` / `textarea` / `select` / `datetime` / `number` / `file` / `checkbox` |
| `required` | `bool` | | 必填 |
| `options` | `List<String>` | | select 选项 |
| `placeholder` | `String` | | 占位文本 |

### ProcessDescriptor — 后端进程

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `exe` | `String` | — | 可执行文件名 |
| `protocol` | `String` | `"http"` | `http` / `stdio` |
| `preferredPort` | `int` | `0` | 首选端口 |

---

## 二、插件开发者指南

### 1. 最小 manifest

```json
{ "type": "module", "id": "my_plugin", "name": "我的插件" }
```

放进 `plugins/my_plugin/module/manifest.json`，启动时自动加载。

### 2. 带页面和侧边栏

```jsonc
{
  "type": "module",
  "id": "my_plugin",
  "name": "我的插件",
  "icon": "extension",
  "route": "/my-plugin",
  "sidebar": { "section": "AI 工具", "order": 50 }
}
```

### 3. 带数据绑定

```jsonc
{
  "data": [
    { "type": "scores", "display": "table", "filter": true }
  ]
}
```

### 4. 带交互

```jsonc
{
  "actions": {
    "itemTap": "detail",
    "selection": "multi",
    "sortable": ["name"],
    "creatable": true,
    "deletable": { "enabled": true, "confirm": true },
    "exportable": ["csv"]
  }
}
```

### 5. 选择 UI 范式

```jsonc
// 对话
{ "ui": "chat", "chat": { "stream": { "enabled": true } } }

// 电子表格
{ "ui": "spreadsheet", "spreadsheet": { "formulas": true, "charts": true } }

// 文档
{ "ui": "document", "document": { "trackChanges": true, "comments": true } }

// 幻灯片
{ "ui": "presentation", "presentation": { "transitions": true, "animations": true } }
```

### 6. 键盘输入

```jsonc
// 聊天
{ "input": { "mode": "free-text", "multiline": true, "sendOnEnter": true } }

// 打字练习
{ "input": { "mode": "type-check", "caseSensitive": true,
    "feedback": { "correct": { "color": "#4caf50", "animation": "bounce" },
                  "incorrect": { "color": "#f44336", "animation": "shake" } } } }

// 代码
{ "input": { "mode": "code", "language": "c", "tabSize": 4 } }
```

### 7. 内嵌文件

```jsonc
{ "media": { "accept": "*.mp4", "mode": "fullscreen", "video": { "speeds": [0.5,1,1.5,2] } } }
{ "media": { "accept": "*.pdf", "mode": "dropdown", "document": { "paginated": true } } }
```

### 8. 文件工作区

```jsonc
{ "workspace": { "enabled": true, "aiCreatable": ["docx","pdf","pptx"] } }
```

### 9. 后端进程

```jsonc
{ "process": { "exe": "plugin.exe", "protocol": "http", "preferredPort": 0 } }
```

启动后 stdout 输出 `PORT:<N>`，提供 `GET /health` → 200。

### 10. 完整示例

见 `example/plugins/my_module/manifest.json`。

## 插件开发者指南

完整的 step-by-step 教程见 `docs/` 目录：

| # | 文档 | 内容 |
|---|------|------|
| 1 | [快速开始](docs/01-quickstart.md) | 5 分钟创建第一个插件 |
| 2 | [侧边栏与路由](docs/02-sidebar-route.md) | 导航入口、多页面、自定义分类 |
| 3 | [页面布局](docs/03-layout.md) | 分框、分 tab、抽屉、搜索栏、缩放 |
| 4 | [UI 范式](docs/04-ui-paradigms.md) | 7 种范式详解（chat/spreadsheet/document/presentation） |
| 5 | [数据绑定](docs/05-data.md) | 展示数据、table/list/card |
| 6 | [鼠标/触摸交互](docs/06-actions.md) | 点击、长按、侧滑、选择、增删改、导出 |
| 7 | [键盘交互](docs/07-input.md) | free-text / type-check / code / select |
| 8 | [文件与媒体](docs/08-media.md) | 视频、PDF、图片、文档展示 |
| 9 | [文件工作区](docs/09-workspace.md) | 知识库、AI 文件生成 |
| 10 | [高级组件](docs/10-advanced.md) | 时间线、地图、表单 |
| 11 | [后端进程](docs/11-backend.md) | .exe 协议、HTTP 端点 |
| 12 | [完整示例](docs/12-examples.md) | AI 助手、课程表、Overleaf、打字背词… |

---

## 规则

- 模块只负责导航 + 路由 + UI 声明。渲染由下游实现。
- 无内置模块——全部通过 manifest.json 注入。
- 所有模块（内置 + 外部）统一走 `ModuleDescriptor.fromJson`。
- 工具/设置/数据通过各自专用 API 注册。

---

## v1.1 新增

### CapabilityDimension（`capability.dart`）

六种插件能力维度——`agent` / `module` / `theme` / `data` / `config` / `process`。

| 函数 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `discoverCapabilities(dir, {descriptor})` | `String` + 可选 `ModuleDescriptor` | `List<CapabilityDimension>` | 扫描插件目录自动发现能力 |
| `parseCapabilityDimension(name)` | `String` | `CapabilityDimension?` | 从字符串解析（不区分大小写） |

### PluginManifest（`plugin_manifest.dart`）

轻量搜索结果模型——`ModuleRegistry.search()` 的返回类型（I10 接口）。

### PluginDetail（`plugin_detail.dart`）

详情页完整信息模型——名称/描述/版本/截图/权限/维度/开发者（M-S2-3）。

### ModuleHttpServer（`module_http_server.dart`）

将 ModuleRegistry 暴露为 REST API，6 个端点：

```
GET  /module/health              → 200 {"status":"ok"}
GET  /module/modules
GET  /module/modules/:id
GET  /module/search?q=&dim=&cat=
GET  /module/nav
GET  /module/routes
```

`start()` 返回 `Future<int>`（实际端口），支持 `port: 0` 自动分配，启动后写入 `.module_port`。

### ModuleDescriptor 新增字段

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `activateSkills` | `List<String>` | `[]` | 打开模块时自动激活的 Skill 名列表 |
| `version` | `String` | `"0.0.0"` | 语义版本号 |

### ModuleRegistry 新增方法

| 方法 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `findByRoute(path)` | `String` | `ModuleDescriptor?` | 按路由路径查找（I9） |
| `search(query, {dims, cat})` | `String` + 可选筛选 | `List<PluginManifest>` | 搜索/筛选（I10） |
| `listByCapability(dim)` | `CapabilityDimension` | `List<ModuleDescriptor>` | 按能力维度列出 |
| `setCapabilities(id, dims)` | `String`, `List<CapabilityDimension>` | `void` | 设置模块能力维度（seal 前） |

### ModuleLoader 新增行为

`loadBuiltinModules()` 和 `scanAndLoadModules()` 在注册模块后自动调用 `discoverCapabilities()` → `setCapabilities()`，填充能力维度数据。

### 插件开发规范

详见 [`docs/plugin-module.md`](docs/plugin-module.md)——manifest.json 全部字段参考、示例、验证规则。
