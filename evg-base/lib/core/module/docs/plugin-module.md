# Module 插件撰写指南

> 面向插件开发者——第三方如何编写 `manifest.json` 来声明一个 UI 模块。
> 本文档是 Module 插件开发的**唯一权威参考**，合并了原 `plugin-authoring-guide-module.md` 和 `plugin-module.md`。

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
| `ui` | `string` | `"default"` | `default` / `chat` / `spreadsheet` / `document` / `presentation` / `dashboard` / `editor` / `composite` |

**范式选择建议**：纯展示→`default`+data | 对话AI→`chat` | 表格→`spreadsheet` | 文档→`document` | 复杂布局→`composite`

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

### 3.11 AI 助手胶水

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `activateSkills` | `string[]` | `[]` | 打开模块时自动激活的 Skill 名列表 |

---

## 四、四级 .exe 层级

| 层级 | manifest 位置 | 生命周期 | 适用场景 |
|------|--------------|---------|---------|
| ① 模块级 | `process`（顶层） | 加载 → 卸载 | 数据库连接、认证 |
| ② 页面级 | `pages[].globalProcess` | 激活 → 切走 | 页面级数据拉取 |
| ③ 栏位级 | `pages[].slots.<k>.process` | 可见 → 隐藏 | 栏专属后端 |
| ④ 动作级 | `actions[].process` | 触发 → 完成退出 | 翻译、导出、计算 |

### 进程协议

1. 启动后 stdout 第一行输出 `PORT:<N>`（HTTP）或直接就绪（stdio）
2. 提供 `GET /health` → 200 `{"status":"ok"}`
3. 日志走 stderr，不污染 stdout
4. 所有响应带 `Access-Control-Allow-Origin: *`

### Python 最小后端

```python
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 8080

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps({"status":"ok"}).encode())

if __name__ == "__main__":
    print(f"PORT:{PORT}", flush=True)
    HTTPServer(("127.0.0.1", PORT), H).serve_forever()
```

---

## 五、Composite 模式（PLAN_NOW 终局方向）

页面结构完全由 JSON 声明，无需 Dart 代码。

```
ModuleDescriptor
  └── pages[]                    ← 多页面
        ├── id / label           ← 页面标识和 Tab 标签
        ├── layout               ← 页面级布局
        ├── globalProcess        ← 页面级 .exe
        └── slots                ← 栏目映射 {left, right, center, top, bottom, main}
              └── ComponentConfig {component, config, process, events, expose_state}
```

### Slot 字段

| 字段 | 说明 |
|------|------|
| `component` | 组件类型名（如 `"type-check"`、`"data-table"`） |
| `config` | 组件专属配置（透传给 Widget） |
| `process` | 栏级后端进程（可选） |
| `events` | `{emit: [...], subscribe: [...]}` |
| `expose_state` | `{events: [...], format: "json", subdir: "..."}` → `.greenix/workspaces/<id>/<subdir>/state.json` |

### 栏间事件（PageEventBus）

页面激活创建 → 切走 dispose。不跨页面、不跨模块、不持久化。

### 完整 Composite 示例

```jsonc
{
  "type": "module",
  "id": "vocab-tutor",
  "name": "单词教练",
  "ui": "composite",
  "route": "/vocab-tutor",
  "sidebar": { "section": "教育", "order": 20 },

  "pages": [
    {
      "id": "learn", "label": "学习",
      "slots": {
        "left": {
          "component": "type-check",
          "config": { "wordList": ["apple", "banana", "cherry"] },
          "process": { "exe": "checker.exe" },
          "events": { "emit": ["word_completed"] },
          "expose_state": { "events": ["word_completed"], "subdir": "type-check" }
        },
        "right": {
          "component": "data-table",
          "config": { "dataType": "progress" },
          "events": { "subscribe": ["word_completed"] }
        }
      }
    },
    {
      "id": "review", "label": "复习",
      "slots": {
        "main": { "component": "flashcard", "config": { "mode": "spaced-repetition" } }
      }
    }
  ],

  "actions": [
    { "trigger": "button:export-progress", "label": "导出进度",
      "process": { "exe": "export.exe", "protocol": "stdio" } }
  ]
}
```

---

## 六、多页多栏能力矩阵

以下字段在所有 UI 范式下均可用（`pages[]` + `slots` 仅 composite）：

| 能力 | 字段 | 层级 | 非 composite | composite |
|------|------|------|:-----------:|:---------:|
| 侧边栏子导航 | `secondaryNavs` | 模块级（路由跳转） | ✅ | ✅ |
| 页面内 Tab 面板 | `layout.panels` | 模块级/页面级 | ✅ | ✅ |
| 多列分框布局 | `layout.grid` | 页面级（数据自动分配） | ✅ | ✅ |
| 可滑出抽屉 | `layout.drawers` | 页面级（top/left/right/bottom） | ✅ | ✅ |
| 多页面 | `pages[]` | 模块级（Tab 切换） | ❌ | ✅ |
| 栏目映射 | `pages[].slots` | 页面级（栏间事件总线） | ❌ | ✅ |
| 动作按钮 | `actionButtons[]` | 模块级 | ❌ | ✅ |
| 栏间事件 | `PageEventBus` | 页面级 | ❌ | ✅ |

> **层级关系**：`pages[]` > `panels`（父子）。`pages[]` 是一级页面 Tab，`panels` 是页面内的二级 Tab。
>
> **`secondaryNavs`** 不是页面内 Tab，而是**侧边栏的二级导航条目**——切换即路由跳转，和点击侧边栏主条目行为一致。
>
> **`layout.drawers`** 是页面级布局面板（常驻区域），与 `media.mode: "drawer"`（媒体文件临时滑入）是不同概念。slot 与 drawer 之间无源码级映射，由渲染层约定。

---

## 七、示例

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

### 带子导航 + 多 Tab + 抽屉的设置页（非 composite）

```jsonc
{
  "type": "module",
  "id": "settings",
  "name": "设置",
  "ui": "default",
  "route": "/settings",
  "sidebar": { "section": "系统", "order": 90 },
  // 侧边栏子导航：切换即路由跳转
  "secondaryNavs": [
    { "label": "通用", "routePath": "/settings/general", "section": "系统", "icon": "tune" },
    { "label": "账户", "routePath": "/settings/account", "section": "系统", "icon": "account_circle" },
    { "label": "关于", "routePath": "/settings/about", "section": "系统", "icon": "info" }
  ],
  "layout": {
    "drawers": ["right"],              // 右侧可滑出抽屉
    "panels": [                        // 页面内 Tab 面板
      { "id": "prefs", "label": "偏好", "path": "/settings/general", "default": true },
      { "id": "advanced", "label": "高级", "path": "/settings/general/advanced" }
    ]
  }
}
```

**说明**：`secondaryNavs` 在侧边栏生成 3 个二级条目（通用/账户/关于），点击触发路由跳转。"通用"页内通过 `panels` 展示 2 个 Tab（偏好/高级），右侧 `drawers` 提供属性面板。

### 分框数据看板（非 composite）

```jsonc
{
  "type": "module",
  "id": "analytics",
  "name": "数据分析",
  "ui": "dashboard",
  "route": "/analytics",
  "layout": {
    "grid": { "columns": 3, "gap": 12 },  // 3 列分框，数据按声明顺序自动分配
    "drawers": ["left"]                    // 左侧筛选面板
  },
  "data": [
    { "type": "revenue", "display": "chart" },
    { "type": "users", "display": "card" },
    { "type": "orders", "display": "table" }
  ]
}
```

**说明**：`grid.columns: 3` 将 3 个数据源自动分 3 列展示（revenue→第1列图表，users→第2列卡片，orders→第3列表格），`drawers: ["left"]` 提供左侧筛选面板。

---

## 八、验证规则

| 规则 | 说明 |
|------|------|
| `type` 必须为 `"module"` | 否则 `ModuleDescriptor.fromJson` 抛出 `FormatException` |
| `id` 必填且全局唯一 | 重复 id 在 `ModuleRegistry.register` 时抛出 `ArgumentError` |
| `dependencies` 必须已注册 | `ModuleRegistry.seal()` 时校验，缺失抛出 `StateError` |
| 未知字段静默忽略 | 向前兼容，不抛异常 |
| JSON 语法错误 | `fromJsonString` 抛出 `FormatException` |

### 常见错误

| 错误 | 原因 | 解决 |
|------|------|------|
| `FormatException: 缺少必填字段 "id"` | 缺 `id`/`name` | 补全必填字段 |
| `StateError: 模块依赖校验失败` | 依赖未注册 | 检查 `dependencies` id 是否正确 |
| `ModuleRegistry 已锁定` | seal() 后 register() | 在 seal() 前注册 |
| exe 不存在 | 进程路径错误 | 检查 `process.exe` 路径 |
| health check 超时 | 未输出 PORT: | 确认 `print(f"PORT:{PORT}", flush=True)` |

---

## 九、版本兼容

| manifest 版本 | 最低平台版本 | 说明 |
|--------------|-------------|------|
| 1.0 | — | 初始版本，所有字段 |
| 1.1+ | — | `activateSkills` 新增 |

---

## 十、测试与验证

将 `manifest.json` 放入 `plugins/<name>/module/` 目录，启动平台后自动加载。验证方法：

1. 侧边栏应出现你的模块
2. 点击模块应正确显示对应 UI 范式
3. 如果有后端进程，检查 `GET /health` 是否正常响应

可通过 HTTP API 验证模块注册状态：

```bash
curl http://127.0.0.1:PORT/module/modules
```
