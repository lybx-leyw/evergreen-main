# 03 · 页面布局

页面长什么样——分框、抽屉、搜索栏、缩放。

> V2 说明：`layout` 统一为 `{type, preset, features, slots}` 结构
> （旧版 `layout.mode/grid/panels` 顶层键已不解析；多 tab 由模块级 `pages[]` 表达）。

## 基本布局

```json
{
  "layout": {
    "type": "grid",
    "preset": { "columns": 2, "gap": 16 },
    "features": {
      "zoom": { "enabled": false },
      "search": { "enabled": true, "placeholder": "搜索..." },
      "drawers": ["left", "right"]
    }
  }
}
```

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `type` | `"grid"` | `grid` / `flex` / `fullscreen` / `absolute` / `dock` |
| `preset` | `{}` | 布局超参数：`columns` / `rows` / `direction` / `wrap` / `gap` / `justify` / `align` / `regions` |
| `features.zoom` | `enabled:false` | 缩放配置 |
| `features.search` | 无 | 搜索栏 |
| `features.drawers` | `[]` | 方向：`top` / `left` / `right` / `bottom` |
| `slots` | `{}` | 插槽映射：slotName → 组件/子容器 |

## 分框（grid）

`preset.columns` 控制并排分框数，`slots` 按名字挂组件：

```json
{
  "layout": {
    "type": "grid",
    "preset": { "columns": 2, "gap": 16 },
    "slots": {
      "left":  { "component": { "type": "data-table", "config": { "dataType": "courses" } } },
      "right": { "component": { "type": "chart", "config": { "dataType": "scores" } } }
    }
  }
}
```

左编辑器右预览（Overleaf 风）：

```json
{
  "layout": {
    "type": "grid",
    "preset": { "columns": 2, "gap": 0 },
    "slots": {
      "left":  { "component": { "type": "code-editor" } },
      "right": { "component": { "type": "document" } }
    }
  }
}
```

## 多 tab（pages）

多 tab 在 V2 由模块级 `pages[]` 表达（每个 page 一个 tab）：

```json
{
  "pages": [
    { "id": "main",   "label": "概览", "route": "/my-plugin",        "default": true },
    { "id": "detail", "label": "详情", "route": "/my-plugin/detail" }
  ]
}
```

| 字段 | 说明 |
|------|------|
| `id` | 页面标识 |
| `label` | tab 标签文本 |
| `route` | 路由路径 |
| `default` | 默认页面 |
| `layout` | 页面级布局（同上 V2 结构） |

## 抽屉（drawers）

```json
{ "layout": { "features": { "drawers": ["left", "right"] } } }
```

页面左右各一个可滑出的侧边面板。

## 搜索栏（search）

```json
{ "layout": { "features": { "search": { "enabled": true, "placeholder": "搜索内容..." } } } }
```

页面顶部渲染搜索框。输入触发后端 `GET /search?q=...` 。

## 缩放（zoom）

```json
{ "layout": { "features": { "zoom": { "enabled": true, "min": 0.5, "max": 3.0 } } } }
```

## 布局组合速查

| 场景 | 配置 |
|------|------|
| 单页列表 | `type: "grid"` + 一个 slot |
| 自适应页面 | `type: "fullscreen"` |
| 分框编辑器 | `type: "grid"` + `preset.columns: 2` |
| 带搜索的列表 | `features.search.enabled: true` |
| 多 tab 页 | 模块级 `pages[]` |
| 分框 + 多 tab | `pages[].layout.slots` |
| 带侧边抽屉 | `features.drawers: [...]` |

## 下一步

- [04 · 选一个 UI 范式](04-ui-paradigms.md)
