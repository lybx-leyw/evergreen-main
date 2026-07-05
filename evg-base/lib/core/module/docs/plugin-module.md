# UI 模块 manifest 开发规范

> 面向插件开发者——第三方如何编写 `manifest.json` 来声明一个 UI 模块。

---

## 一、文件位置

```
plugins/<name>/module/manifest.json
```

平台启动时，`ModuleLoader` 自动扫描 `plugins/` 下所有子目录中该路径的文件。

---

## 二、最小 manifest

```json
{
  "type": "module",
  "id": "my_plugin",
  "name": "我的插件"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | `"module"` | ✅ | 固定值，区分模块与其他插件类型 |
| `id` | `string` | ✅ | 全局唯一标识，不可重复 |
| `name` | `string` | ✅ | UI 展示名称 |

---

## 三、完整字段参考

### 3.1 基础信息

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `id` | `string` | — | 全局唯一标识 |
| `name` | `string` | — | 展示名称 |
| `description` | `string` | `""` | 描述文本 |
| `icon` | `string\|int` | — | 图标名（如 `"smart_toy"`）或 Material Icons codePoint |
| `version` | `string` | `"0.0.0"` | 语义版本号 |
| `dependencies` | `string[]` | `[]` | 依赖的其他模块 id |

### 3.2 路由与导航

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `route` | `string` | — | 主路由路径（如 `"/my-plugin"`）；不填 = 纯服务模块 |
| `sidebar` | `object` | — | 侧边栏配置 |
| `sidebar.section` | `string` | — | 分类标签 |
| `sidebar.sectionOrder` | `int` | `50` | 分类间排序（越小越靠前） |
| `sidebar.order` | `int` | `50` | 分类内排序 |
| `sidebar.badge` | `bool` | `false` | 角标 |
| `secondaryNavs` | `array` | `[]` | 子导航条目 |

#### 子导航条目

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `label` | `string` | ✅ | 展示名 |
| `routePath` | `string` | ✅ | 路由路径 |
| `section` | `string` | ✅ | 所属分类 |
| `icon` | `string\|int` | — | 图标 |

### 3.3 UI 范式

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `ui` | `string` | `"default"` | `default` / `chat` / `spreadsheet` / `document` / `presentation` / `dashboard` / `editor` |

#### chat 模式专属

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `chat.thinking.visible` | `bool` | `true` | 展示思考栏 |
| `chat.thinking.transparent` | `bool` | `false` | 背景透明 |
| `chat.thinking.mode` | `string` | `"expand"` | `expand` / `scroll` |
| `chat.thinking.showDuration` | `bool` | `false` | 显示耗时 |
| `chat.toolCalls.visible` | `bool` | `true` | 展示工具调用 |
| `chat.toolCalls.showArgs` | `bool` | `true` | 展示参数 |
| `chat.toolCalls.showResult` | `bool` | `true` | 展示结果 |
| `chat.toolCalls.autoCollapse` | `bool` | `false` | 自动折叠 |
| `chat.bubble.style` | `string` | `"rounded"` | `rounded` / `flat` / `minimal` |
| `chat.bubble.avatarPosition` | `string` | `"left"` | `left` / `none` |
| `chat.bubble.showTimestamp` | `bool` | `true` | 显示时间戳 |
| `chat.stream.enabled` | `bool` | `true` | 流式输出 |
| `chat.stream.animation` | `string` | `"typewriter"` | `typewriter` / `fade` / `none` |
| `chat.stream.cursorStyle` | `string` | `"blinking"` | `blinking` / `static` / `none` |
| `chat.placeholder` | `string` | `"输入消息..."` | 输入框占位文本 |

#### spreadsheet 模式专属

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `spreadsheet.formulas` | `bool` | `false` | 公式引擎 |
| `spreadsheet.charts` | `bool` | `false` | 图表 |
| `spreadsheet.sheets` | `bool` | `false` | 多 sheet |
| `spreadsheet.conditionalFormatting` | `bool` | `false` | 条件格式 |
| `spreadsheet.resizableColumns` | `bool` | `true` | 列拖拽调宽 |
| `spreadsheet.columns` | `int` | `26` | 默认列数 |
| `spreadsheet.rows` | `int` | `100` | 默认行数 |

#### document 模式专属

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `document.trackChanges` | `bool` | `false` | 修订模式 |
| `document.comments` | `bool` | `false` | 批注 |
| `document.tableOfContents` | `bool` | `false` | 目录 |
| `document.footnotes` | `bool` | `false` | 脚注 |
| `document.headersFooters` | `bool` | `false` | 页眉页脚 |
| `document.pageSetup` | `bool` | `true` | 页面设置 |
| `document.exportFormats` | `string[]` | `["pdf","docx"]` | 导出格式 |

#### presentation 模式专属

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `presentation.transitions` | `bool` | `false` | 切换动画 |
| `presentation.animations` | `bool` | `false` | 元素动画 |
| `presentation.speakerNotes` | `bool` | `false` | 演讲者备注 |
| `presentation.presenterView` | `bool` | `false` | 演讲者视图 |
| `presentation.slideMaster` | `bool` | `false` | 母版编辑 |
| `presentation.layouts` | `string[]` | `["title","content","blank","two-column"]` | 版式 |
| `presentation.exportFormats` | `string[]` | `["pdf","pptx"]` | 导出格式 |

### 3.4 布局

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `layout.mode` | `string` | `"scroll"` | `scroll` / `fit` |
| `layout.grid.columns` | `int` | `2` | 分框列数 |
| `layout.grid.gap` | `int` | `16` | 框间距 |
| `layout.zoom.enabled` | `bool` | `false` | 启用缩放 |
| `layout.zoom.min` | `number` | `0.5` | 最小比例 |
| `layout.zoom.max` | `number` | `2.0` | 最大比例 |
| `layout.drawers` | `string[]` | `[]` | 子集: `top`/`left`/`right`/`bottom` |
| `layout.search.enabled` | `bool` | `false` | 显示搜索栏 |
| `layout.search.placeholder` | `string` | `"搜索..."` | 搜索栏占位文本 |
| `layout.panels` | `array` | `[]` | 多 tab 面板 |

#### 面板条目

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | `string` | ✅ | 面板标识 |
| `label` | `string` | ✅ | tab 标签 |
| `path` | `string` | ✅ | 路由 |
| `default` | `bool` | — | 默认面板 |

### 3.5 数据绑定

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `data[].type` | `string` | ✅ | 指向 DataType.name |
| `data[].display` | `string` | `"list"` | `table` / `list` / `card` / `raw` |
| `data[].filter` | `bool` | `false` | 前端筛选 |

### 3.6 交互

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `actions.itemTap` | `string` | — | `detail` / `select` / `none` |
| `actions.itemLongPress` | `string` | — | `context_menu` / `none` |
| `actions.itemSwipe` | `string` | — | `delete` / `archive` / `none` |
| `actions.selection` | `string` | `"none"` | `none` / `single` / `multi` |
| `actions.sortable` | `string[]` | `[]` | 可排序字段 |
| `actions.creatable` | `bool` | `false` | 允许新增 |
| `actions.editable` | `bool` | `false` | 允许编辑 |
| `actions.deletable.enabled` | `bool` | `false` | 允许删除 |
| `actions.deletable.confirm` | `bool` | `true` | 确认弹窗 |
| `actions.exportable` | `string[]` | `[]` | 导出格式 |
| `actions.refresh.enabled` | `bool` | `false` | 启用刷新 |
| `actions.refresh.pullToRefresh` | `bool` | `true` | 下拉刷新 |
| `actions.refresh.autoInterval` | `int` | `0` | 自动刷新间隔（秒） |

### 3.7 键盘输入

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `input.mode` | `string` | `"free-text"` | `free-text` / `type-check` / `code` / `select` |
| `input.autoFocus` | `bool` | `true` | 自动聚焦 |
| `input.maxLength` | `int` | `0` | 最大长度（0=不限） |

#### free-text 专用

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `input.multiline` | `bool` | `true` | 多行 |
| `input.sendOnEnter` | `bool` | `true` | Enter 发送 |
| `input.attachments.enabled` | `bool` | `false` | 附件 |
| `input.attachments.types` | `string[]` | `["image","file"]` | 允许类型 |
| `input.attachments.maxSizeMb` | `int` | `0` | 单文件体积上限 |
| `input.voice` | `bool` | `false` | 语音 |
| `input.slashCommands` | `bool` | `false` | 斜杠命令 |
| `input.quickReplies` | `string[]` | `[]` | 快捷回复 |

#### type-check 专用

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `input.caseSensitive` | `bool` | `false` | 区分大小写 |
| `input.feedback.correct.color` | `string` | `"#4caf50"` | 正确反馈颜色 |
| `input.feedback.correct.animation` | `string` | `"bounce"` | 正确反馈动画 |
| `input.feedback.incorrect.color` | `string` | `"#f44336"` | 错误反馈颜色 |
| `input.feedback.incorrect.animation` | `string` | `"shake"` | 错误反馈动画 |

#### code 专用

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `input.language` | `string` | `""` | 编程语言 |
| `input.autoIndent` | `bool` | `true` | 自动缩进 |
| `input.tabSize` | `int` | `2` | Tab 空格数 |

#### select 专用

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `input.options` | `string[]` | `[]` | 选项列表 |

### 3.8 媒体

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `media.accept` | `string` | — | 文件后缀（如 `"*.mp4"`） |
| `media.mode` | `string` | `"inline"` | `inline` / `fullscreen` / `drawer` / `dropdown` / `fixed` |
| `media.direction` | `string` | `"top"` | drawer/dropdown 方向 |
| `media.controls` | `bool` | `true` | 显示控件 |
| `media.video.speeds` | `number[]` | `[0.5,1,1.5,2]` | 倍速 |
| `media.video.cache` | `bool` | `false` | 缓存 |
| `media.video.quality` | `string` | `"auto"` | `auto`/`360p`/`720p`/`1080p` |
| `media.video.captions` | `bool` | `false` | 字幕 |
| `media.audio.speeds` | `number[]` | `[0.5,1,1.5,2]` | 倍速 |
| `media.audio.waveform` | `bool` | `false` | 波形 |
| `media.document.zoomable` | `bool` | `true` | 捏合缩放 |
| `media.document.searchable` | `bool` | `false` | 文档内搜索 |
| `media.document.pageIndicator` | `bool` | `true` | 页码 |
| `media.document.paginated` | `bool` | `false` | 分页 |
| `media.image.zoomable` | `bool` | `true` | 捏合缩放 |
| `media.image.gallery` | `bool` | `false` | 画廊模式 |

### 3.9 其他组件

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `workspace.enabled` | `bool` | `false` | 启用工作区 |
| `workspace.accept` | `string` | `"*.pdf,*.docx,..."` | 接受文件类型 |
| `workspace.maxFiles` | `int` | `20` | 最大文件数 |
| `workspace.maxSizeMb` | `int` | `50` | 单文件体积上限 |
| `workspace.aiCreatable` | `string[]` | `[]` | AI 可生成格式 |
| `workspace.persistAcrossSessions` | `bool` | `true` | 跨会话持久 |
| `timeline.mode` | `string` | `"timeline"` | `calendar` / `timeline` / `agenda` |
| `timeline.view` | `string[]` | `["day","week","month"]` | 可用视图 |
| `timeline.defaultView` | `string` | `"week"` | 默认视图 |
| `timeline.creatable` | `bool` | `false` | 创建事件 |
| `map.center.lat` | `number` | — | 中心纬度 |
| `map.center.lng` | `number` | — | 中心经度 |
| `map.zoom` | `int` | `15` | 缩放级别 |
| `map.markers` | `bool` | `true` | 标记点 |
| `map.search` | `bool` | `false` | 搜索 |
| `map.route` | `bool` | `false` | 路线规划 |
| `form.fields` | `array` | `[]` | 表单字段 |
| `form.submitLabel` | `string` | `"提交"` | 提交按钮 |
| `form.validateOnBlur` | `bool` | `true` | 失焦校验 |

#### 表单字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `form.fields[].key` | `string` | ✅ | 字段标识 |
| `form.fields[].label` | `string` | ✅ | 标签 |
| `form.fields[].type` | `string` | `"text"` | `text`/`textarea`/`select`/`datetime`/`number`/`file`/`checkbox` |
| `form.fields[].required` | `bool` | — | 必填 |
| `form.fields[].options` | `string[]` | — | select 选项 |
| `form.fields[].placeholder` | `string` | — | 占位文本 |

### 3.10 后端进程

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `process.exe` | `string` | — | 可执行文件名 |
| `process.protocol` | `string` | `"http"` | `http` / `stdio` |
| `process.preferredPort` | `int` | `0` | 首选端口（0=自动） |

### 3.11 AI 助手胶水（新增）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `activateSkills` | `string[]` | `[]` | 打开模块时自动激活的 Skill 名列表 |

---

## 四、示例

### 纯服务模块（无 UI）

```json
{
  "type": "module",
  "id": "background_service",
  "name": "后台服务",
  "process": { "exe": "service.exe", "protocol": "stdio" }
}
```

### 带侧边栏的聊天模块

```json
{
  "type": "module",
  "id": "ai_chat",
  "name": "AI 助手",
  "icon": "smart_toy",
  "route": "/chat",
  "ui": "chat",
  "sidebar": { "section": "AI 工具", "order": 10 },
  "chat": { "stream": { "enabled": true } },
  "input": { "mode": "free-text", "multiline": false, "sendOnEnter": true },
  "activateSkills": ["web_search", "memory"]
}
```

### 数据驱动的列表页

```json
{
  "type": "module",
  "id": "scoreboard",
  "name": "成绩单",
  "route": "/scores",
  "data": [{ "type": "scores", "display": "table", "filter": true }],
  "actions": {
    "selection": "multi",
    "sortable": ["name", "score"],
    "exportable": ["csv"]
  }
}
```

---

## 五、验证规则

| 规则 | 说明 |
|------|------|
| `type` 必须为 `"module"` | 否则 `ModuleDescriptor.fromJson` 抛出 `FormatException` |
| `id` 必填且全局唯一 | 重复 id 在 `ModuleRegistry.register` 时抛出 `ArgumentError` |
| `dependencies` 必须已注册 | `ModuleRegistry.seal()` 时校验，缺失抛出 `StateError` |
| 未知字段静默忽略 | 向前兼容，不抛异常 |
| JSON 语法错误 | `fromJsonString` 抛出 `FormatException` |

---

## 六、版本兼容

| manifest 版本 | 最低平台版本 | 说明 |
|--------------|-------------|------|
| 1.0 | — | 初始版本，所有字段 |
| 1.1+ | — | `activateSkills` 新增 |
