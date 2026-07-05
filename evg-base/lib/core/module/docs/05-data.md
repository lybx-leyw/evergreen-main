# 05 · 数据绑定

让模块展示数据。

## 基本用法

```json
{
  "data": [
    { "type": "scores", "display": "table", "filter": true },
    { "type": "news",   "display": "list",  "filter": false },
    { "type": "courses", "display": "card" }
  ]
}
```

| 字段 | 说明 |
|------|------|
| `type` | 指向 data/ 模块的 `DataType.name` |
| `display` | 展示方式 |
| `filter` | 是否显示前端筛选栏 |

## 展示方式

| `display` | 效果 | 适用 |
|-----------|------|------|
| `"table"` | 数据表格 | 成绩单、用户列表 |
| `"list"` | 列表 | 新闻、通知 |
| `"card"` | 卡片 | 课程、商品 |
| `"raw"` | 原始文本 | 调试 |

## 配上交互

```json
{
  "data": [{ "type": "courses", "display": "card" }],
  "actions": {
    "itemTap": "detail",
    "sortable": ["name", "date"],
    "refresh": { "enabled": true, "pullToRefresh": true }
  }
}
```

`itemTap: "detail"` → 点击卡片跳详情。`sortable` → 列头可排序。`refresh` → 下拉刷新。

## 配上分框

```json
{
  "layout": { "grid": { "columns": 3, "gap": 12 } },
  "data": [
    { "type": "scores", "display": "chart" },
    { "type": "news",   "display": "card" },
    { "type": "events", "display": "list" }
  ]
}
```

三个 data 绑定流入 3 列网格。顺序一一对应。

## 下一步

- [06 · 鼠标/触摸交互](06-actions.md)
