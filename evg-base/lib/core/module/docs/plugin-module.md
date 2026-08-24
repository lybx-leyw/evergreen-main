# Module 插件撰写指南

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | Module 插件作者 |

> 面向插件开发者——第三方如何编写 `manifest.json` 来声明一个 UI 模块。
> 本文档是 Module 插件开发的**唯一权威参考**，合并了原 `plugin-authoring-guide-module.md` 和 `plugin-module.md`。

> ## ⚠️ V2 迁移说明（2026-08）
>
> 当前解析器为 **V2（schemaVersion "2.0"）**，以下 V1 顶层键**已不再解析**（静默忽略，插件会静默失效）：
>
> | V1 写法 | V2 写法 |
> |---------|---------|
> | 顶层 `"sidebar": {...}` | `"nav": { "sidebar": {...} }` |
> | 顶层 `"secondaryNavs": [...]` | `"nav": { "secondary": [...] }` |
> | 顶层 `"ui": "chat"` | `template` 路由 + `pages[].layout.slots.<k>.component.type` |
> | `layout.mode/grid/panels` | `layout.type/preset/features/slots`（多 tab 用 `pages[]`） |
> | `process: { "exe": ... }` 单对象 | `process: [ { "exe": ... } ]`（单对象仍兼容） |
> | `pages[].globalProcess` | `pages[].process`（`globalProcess` 仍兼容） |
>
> 新增顶层字段：`template`（渲染模板）、`lattice`（六格契约）、`runtime`（sidecar 描述符）、
> `modle_route`（模板内子路由）、`pages[]`（V2 页面树）。详见下文 3.1 / 3.2 / 3.3 与「四、」。

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
| `schemaVersion` | `string` | `"2.0"` | 声明式 schema 版本 |
| `type` | `"module"` | — | 固定值，区分模块与其他插件类型 |
| `id` | `string` | — | 全局唯一标识 |
| `name` | `string` | — | 展示名称 |
| `description` | `string` | `""` | 描述文本 |
| `icon` | `string\|int` | — | 图标名（如 `"smart_toy"`）或 Material Icons codePoint |
| `version` | `string` | `"0.0.0"` | 语义版本号 |
| `dependencies` | `string[]` | `[]` | 依赖的其他模块 id |
| `template` | `string` | `"v4"` | 渲染模板：`v4` / `html` / `scraper` / `theme-creator` / `skill-creator` / `dsh` / `zju` / `paper_reading` |
| `lattice` | `string` | 推断 | 六格契约：`static-web` / `web-bridged` / `data-source` / `sidecar` / `agent-tool` / `external-app`（缺省按信号推断；非法值抛错） |
| `runtime` | `object` | — | sidecar 运行时描述符（仅 `lattice:"sidecar"` 非空，见「四、」） |
| `modle_route` | `string` | — | 模板内子路由（如 zdbk 的 score/notifications） |

### 3.2 路由与导航

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `route` | `string` | — | 主路由路径（如 `"/my-plugin"`）；不填 = 纯服务模块 |
| `nav` | `object` | — | V2 导航聚合（sidebar + secondary） |
| `nav.sidebar` | `object` | — | 侧边栏配置 |
| `nav.sidebar.section` | `string` | — | 分类标签 |
| `nav.sidebar.sectionOrder` | `int` | `50` | 分类间排序（越小越靠前） |
| `nav.sidebar.order` | `int` | `50` | 分类内排序 |
| `nav.sidebar.badge` | `bool` | `false` | 角标 |
| `nav.secondary` | `array` | `[]` | 子导航条目 |

> V1 顶层 `sidebar` / `secondaryNavs` 键已不解析，请写入 `nav` 下。

#### 子导航条目（`nav.secondary[]`）

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `label` | `string` | ✅ | 展示名 |
| `routePath` | `string` | ✅ | 路由路径 |
| `section` | `string` | ✅ | 所属分类 |
| `icon` | `string\|int` | — | 图标 |

### 3.3 UI 范式

> **V2 变更**：顶层 `ui` 字段已不解析。范式由 `template`（渲染模板）+ `pages[].layout.slots.<k>.component.type`（v4 组件类型）声明。
> 下面的范式专属配置键（`chat.thinking` / `spreadsheet.formulas` 等）在 V2 中放进 `component.config` 下（前缀去掉 `chat.`/`spreadsheet.` 等，直接平铺）：

```json
{
  "pages": [
    {
      "id": "chat_page",
      "label": "Chat",
      "layout": {
        "slots": {
          "main": {
            "component": {
              "type": "chat",
              "config": {
                "thinking": { "visible": true },
                "toolCalls": { "visible": true },
                "placeholder": "问点什么..."
              }
            }
          }
        }
      }
    }
  ]
}
```

| 组件类型 | 范式 | 说明 |
|------|------|--------|
| `data-table` | default 列表/表格 | 纯展示 + data 绑定 |
| `chat` | 对话 | 对话AI |
| `spreadsheet` | 电子表格 | 表格 |
| `document` | Word 级文档 | 文档 |
| `presentation` | PPT 级幻灯片 | 幻灯片 |
| `chart` / `dashboard` | 仪表盘 | 数据看板 |
| `code-editor` | 代码/文本编辑器 | 编辑器 |
| `flashcard` / `type-check` | 学习组件 | 单词卡 / 打字练习 |

**范式选择建议**：纯展示→`data-table`+data | 对话AI→`chat` | 表格→`spreadsheet` | 文档→`document` | 复杂布局→多 slot 组合

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

### 3.4 布局（V2）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `layout.type` | `string` | `"grid"` | `grid` / `flex` / `fullscreen` / `absolute` / `dock` |
| `layout.preset.columns` | `int` | — | grid 列数 |
| `layout.preset.rows` | `string` | — | grid 行数 |
| `layout.preset.direction` | `string` | — | flex 方向（`row`/`column`） |
| `layout.preset.wrap` | `bool` | — | flex 是否换行 |
| `layout.preset.gap` | `number` | — | 间距 |
| `layout.preset.justify` / `align` | `string` | — | flex 主轴/交叉轴对齐 |
| `layout.preset.regions` | `object` | — | dock 布局各区域配置 |
| `layout.features.zoom.enabled` | `bool` | `false` | 启用缩放 |
| `layout.features.zoom.min` | `number` | `0.5` | 最小比例 |
| `layout.features.zoom.max` | `number` | `2.0` | 最大比例 |
| `layout.features.drawers` | `string[]` | `[]` | 子集: `top`/`left`/`right`/`bottom` |
| `layout.features.search.enabled` | `bool` | `false` | 显示搜索栏 |
| `layout.features.search.placeholder` | `string` | `"搜索..."` | 搜索栏占位文本 |
| `layout.slots` | `object` | `{}` | 插槽映射：slotName → `{component, process, events, ...}` |

> V1 的 `layout.mode/grid/panels` 顶层键已不解析；多 tab 由模块级 `pages[]` 表达（见 3.3 与「五、」）。

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

### 3.10 后端进程（V2：`process` 为数组）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `process[].id` | `string` | — | 进程唯一标识（V2） |
| `process[].exe` | `string` | — | 可执行文件名（`runtime:"python"` 时可写 `.py` 入口） |
| `process[].runtime` | `string` | `"native"` | `native` / `python` |
| `process[].protocol` | `string` | `"http"` | `http` / `stdio` |
| `process[].scope` | `string` | `"long"` | `long` / `short` |
| `process[].autoStart` | `bool` | `true` | 是否自动启动 |
| `process[].autoRestart` | `bool` | `false` | 崩溃自动重启（仅 long） |
| `process[].preferredPort` | `int` | `0` | 首选端口（0=自动） |

### 3.11 AI 助手胶水

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `activateSkills` | `string[]` | `[]` | 打开模块时自动激活的 Skill 名列表 |

---

## 四、四级 .exe 层级

> V2：`process` 为**数组**（`ProcessDescriptor[]`，单对象仍兼容自动包装）；
> 栏位级进程在 `pages[].layout.slots.<k>.process`。

| 层级 | manifest 位置 | 生命周期 | 适用场景 |
|------|--------------|---------|---------|
| ① 模块级 | `process`（顶层） | 加载 → 卸载 | 数据库连接、认证 |
| ② 页面级 | `pages[].process`（V1 别名 `globalProcess`） | 激活 → 切走 | 页面级数据拉取 |
| ③ 栏位级 | `pages[].layout.slots.<k>.process` | 可见 → 隐藏 | 栏专属后端 |
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

### 备选：sidecar 语言运行时（`lattice: "sidecar"`）

不编 exe 时可用 `lattice: "sidecar"` + `runtime` 直接跑 Node/Python/Deno 脚本，自带能力沙箱
（deny-all 默认：`fs.scope` 限目录、`net.allow` 白名单、`spawn` 白名单；能力只窄不宽）：

```json
{
  "type": "module",
  "id": "py_helper",
  "name": "Python 助手",
  "lattice": "sidecar",
  "runtime": {
    "kind": "python",
    "entry": "backend.py",
    "protocol": "http",
    "port": 0,
    "gracefulTimeoutMs": 8000,
    "capabilities": {
      "fs.scope": "plugin-dir",
      "net.allow": ["api.example.com"],
      "spawn": []
    }
  }
}
```

- `runtime.kind` 必填（`node` / `python` / `deno`）；`runtime.entry` 必填（相对插件根）。
- `lattice: sidecar` 却缺 `runtime`、或非 sidecar 格却带 `runtime` → 解析期抛 `FormatException`（fail-closed）。
- 运行状态经 `GET /module/sidecars` 查询；生命周期由 `SidecarController` 统一管理（详见 `CLAUDE.md`）。

---

## 五、Composite 模式（PLAN_NOW 终局方向）

页面结构完全由 JSON 声明，无需 Dart 代码。

```
ModuleDescriptor
  └── pages[]                    ← 多页面
        ├── id / label           ← 页面标识和 Tab 标签
        ├── layout               ← 页面级布局（type/preset/features/slots）
        ├── process              ← 页面级 .exe（V1 别名 globalProcess）
        └── layout.slots         ← 栏目映射 {left, right, center, top, bottom, main}
              └── SlotDescriptor {component, config, process, events, expose_state}
```

### Slot 字段

| 字段 | 说明 |
|------|------|
| `component` | 组件声明 `{type, config, input, events, process}`（V2 为对象；旧字符串 `component: "chat"` 已不解析） |
| `config` | 组件专属配置（透传给 Widget） |
| `process` | 栏级后端进程（数组，可选） |
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
  "route": "/vocab-tutor",
  "nav": { "sidebar": { "section": "教育", "order": 20 } },

  "pages": [
    {
      "id": "learn", "label": "学习",
      "layout": {
        "type": "grid",
        "preset": { "columns": 2 },
        "slots": {
          "left": {
            "component": { "type": "type-check", "config": { "wordList": ["apple", "banana", "cherry"] } },
            "process": [{ "exe": "checker.exe" }],
            "events": { "emit": ["word_completed"] },
            "expose_state": { "events": ["word_completed"], "subdir": "type-check" }
          },
          "right": {
            "component": { "type": "data-table", "config": { "dataType": "progress" } },
            "events": { "subscribe": ["word_completed"] }
          }
        }
      }
    },
    {
      "id": "review", "label": "复习",
      "layout": {
        "slots": {
          "main": { "component": { "type": "flashcard", "config": { "mode": "spaced-repetition" } } }
        }
      }
    }
  ],

  "actions": [
    { "trigger": "button:export-progress", "label": "导出进度",
      "process": [{ "exe": "export.exe", "protocol": "stdio" }] }
  ]
}
```

---

## 六、多页多栏能力矩阵

以下字段在所有 UI 范式下均可用（`pages[]` + `layout.slots` 仅 composite）：

| 能力 | 字段（V2） | 层级 | 非 composite | composite |
|------|------|------|:-----------:|:---------:|
| 侧边栏子导航 | `nav.secondary[]` | 模块级（路由跳转） | ✅ | ✅ |
| 多页面 Tab | `pages[]` | 模块级（Tab 切换） | ✅ | ✅ |
| 多列分框布局 | `layout.preset.columns` + `slots` | 页面级（组件显式入栏） | ✅ | ✅ |
| 可滑出抽屉 | `layout.features.drawers` | 页面级（top/left/right/bottom） | ✅ | ✅ |
| 多页面 | `pages[]` | 模块级（Tab 切换） | ✅ | ✅ |
| 栏目映射 | `pages[].layout.slots` | 页面级（栏间事件总线） | ❌ | ✅ |
| 动作按钮 | `actionButtons[]` | 模块级 | ❌ | ✅ |
| 栏间事件 | `PageEventBus` | 页面级 | ❌ | ✅ |

> **层级关系**：`pages[]` 是一级页面 Tab；单页内的分栏由 `layout.slots` 表达（旧 `panels`/`grid` 顶层键已不解析）。
>
> **`nav.secondary[]`** 不是页面内 Tab，而是**侧边栏的二级导航条目**——切换即路由跳转，和点击侧边栏主条目行为一致。
>
> **`layout.features.drawers`** 是页面级布局面板（常驻区域），与 `media.mode: "drawer"`（媒体文件临时滑入）是不同概念。slot 与 drawer 之间无源码级映射，由渲染层约定。

---

## 七、示例

### 纯服务模块（无 UI）

```json
{
  "type": "module",
  "id": "background_service",
  "name": "后台服务",
  "process": [{ "exe": "service.exe", "protocol": "stdio" }]
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
  "nav": { "sidebar": { "section": "AI 工具", "order": 10 } },
  "pages": [
    {
      "id": "chat",
      "label": "对话",
      "layout": {
        "slots": {
          "main": {
            "component": {
              "type": "chat",
              "config": { "stream": { "enabled": true } },
              "input": { "mode": "free-text", "multiline": false, "sendOnEnter": true }
            }
          }
        }
      }
    }
  ],
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

### 带子导航 + 多页 + 抽屉的设置页

```jsonc
{
  "type": "module",
  "id": "settings",
  "name": "设置",
  "route": "/settings",
  "nav": {
    "sidebar": { "section": "系统", "order": 90 },
    // 侧边栏子导航：切换即路由跳转
    "secondary": [
      { "label": "通用", "routePath": "/settings/general", "section": "系统", "icon": "tune" },
      { "label": "账户", "routePath": "/settings/account", "section": "系统", "icon": "account_circle" },
      { "label": "关于", "routePath": "/settings/about", "section": "系统", "icon": "info" }
    ]
  },
  "pages": [
    {
      "id": "general",
      "label": "偏好",
      "route": "/settings/general",
      "default": true,
      "layout": { "features": { "drawers": ["right"] } }
    },
    {
      "id": "advanced",
      "label": "高级",
      "route": "/settings/general/advanced",
      "layout": { "features": { "drawers": ["right"] } }
    }
  ]
}
```

**说明**：`nav.secondary` 在侧边栏生成 3 个二级条目（通用/账户/关于），点击触发路由跳转；`pages[]` 提供页面内 Tab（偏好/高级），右侧 `drawers` 提供属性面板。

### 分框数据看板

```jsonc
{
  "type": "module",
  "id": "analytics",
  "name": "数据分析",
  "route": "/analytics",
  "layout": {
    "type": "grid",
    "preset": { "columns": 3, "gap": 12 },
    "features": { "drawers": ["left"] },
    "slots": {
      "c1": { "component": { "type": "chart", "config": { "dataType": "revenue" } } },
      "c2": { "component": { "type": "data-table", "config": { "dataType": "users", "display": "card" } } },
      "c3": { "component": { "type": "data-table", "config": { "dataType": "orders" } } }
    }
  }
}
```

**说明**：`preset.columns: 3` + 3 个 slot 分 3 列展示（revenue→图表，users→卡片，orders→表格），`features.drawers: ["left"]` 提供左侧筛选面板。

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
| 2.0 | 当前版本（见根 `README.md`） | `nav`/`template`/`lattice`/`runtime`/`pages[]` 树形结构；顶层 `ui`/`sidebar`/`secondaryNavs` 停用（静默忽略）；`process` 数组化 |

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
