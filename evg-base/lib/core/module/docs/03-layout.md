# 03 · 页面布局

页面长什么样——分框、分 tab、抽屉、搜索栏、缩放。

## 基本布局

```json
{
  "layout": {
    "mode": "scroll",
    "grid": { "columns": 2, "gap": 16 },
    "zoom": { "enabled": false },
    "drawers": ["left", "right"],
    "search": { "enabled": true, "placeholder": "搜索..." },
    "panels": []
  }
}
```

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `mode` | `"scroll"` | `"scroll"` 滑动窗口 / `"fit"` 自适应缩放 |
| `grid` | 无 | 分框布局 |
| `zoom` | `enabled:false` | 缩放配置 |
| `drawers` | `[]` | 方向：`top` / `left` / `right` / `bottom` |
| `search` | 无 | 搜索栏 |
| `panels` | `[]` | 多 tab |

## 分框（grid）

`grid` 与 `panels` 是正交的：`panels` 是互斥 tab，`grid` 是同一页面内并排分框。

```json
{ "layout": { "grid": { "columns": 2, "gap": 16 } } }
```

`data` 和 `media` 绑定按声明顺序流入各框。

左编辑器右预览（Overleaf 风）：

```json
{ "layout": { "grid": { "columns": 2, "gap": 0 }, "mode": "fit" } }
```

## 多 tab（panels）

```json
{
  "layout": {
    "panels": [
      { "id": "main",   "label": "概览", "path": "/my-plugin",        "default": true },
      { "id": "detail", "label": "详情", "path": "/my-plugin/detail" }
    ]
  }
}
```

| 字段 | 说明 |
|------|------|
| `id` | 面板标识 |
| `label` | tab 标签文本 |
| `path` | 路由路径 |
| `default` | 默认面板 |

## 抽屉（drawers）

```json
{ "layout": { "drawers": ["left", "right"] } }
```

页面左右各一个可滑出的侧边面板。

## 搜索栏（search）

```json
{ "layout": { "search": { "enabled": true, "placeholder": "搜索内容..." } } }
```

页面顶部渲染搜索框。输入触发后端 `GET /search?q=...` 。

## 缩放（zoom）

```json
{ "layout": { "zoom": { "enabled": true, "min": 0.5, "max": 3.0 } } }
```

## 布局组合速查

| 场景 | 配置 |
|------|------|
| 单页面列表 | `mode: "scroll"` |
| 自适应页面 | `mode: "fit"` |
| 分框编辑器 | `grid + mode: "fit"` |
| 带搜索的列表 | `search.enabled: true` |
| 多 tab 页 | `panels: [...]` |
| 分框 + 多 tab | `grid + panels` |
| 带侧边抽屉 | `drawers: [...]` |

## 下一步

- [04 · 选一个 UI 范式](04-ui-paradigms.md)
