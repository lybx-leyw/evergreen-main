# 10 · 高级组件

时间线、地图、表单——三个专用交互组件。

---

## 时间线 / 日历

```json
{
  "timeline": {
    "mode": "calendar",
    "view": ["day", "week", "month"],
    "defaultView": "week",
    "itemTap": "detail",
    "creatable": true
  }
}
```

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `mode` | `"timeline"` | `"calendar"` 月/周/日 / `"timeline"` 时间线 / `"agenda"` 日程列表 |
| `view` | `["day","week","month"]` | 可用视图 |
| `defaultView` | `"week"` | 默认视图 |
| `itemTap` | 无 | 点击事件：`"detail"` / `"edit"` |
| `creatable` | `false` | 允许创建事件 |

### 模式选择

| 场景 | `mode` | 效果 |
|------|--------|------|
| 课程表 | `"calendar"` | 月/周/日网格 |
| 学习进度 | `"timeline"` | 垂直时间线 |
| 待办清单 | `"agenda"` | 日期分组列表 |

---

## 地图

```json
{
  "map": {
    "center": { "lat": 39.9, "lng": 116.4 },
    "zoom": 15,
    "markers": true,
    "search": true,
    "route": true
  }
}
```

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `center` | 无 | 中心坐标 `{lat, lng}` |
| `zoom` | `15` | 缩放级别 |
| `markers` | `true` | 显示标记点 |
| `search` | `false` | 地图搜索 |
| `route` | `false` | 路线规划 |

---

## 表单

当 `actions.creatable` 或 `actions.editable` 为 `true` 时，用 `form` 定义字段。

```json
{
  "form": {
    "submitLabel": "发布作业",
    "validateOnBlur": true,
    "fields": [
      { "key": "title",    "label": "标题", "type": "text",     "required": true, "placeholder": "作业标题" },
      { "key": "content",  "label": "内容", "type": "textarea", "required": true },
      { "key": "category", "label": "分类", "type": "select",   "options": ["学习","生活","活动"] },
      { "key": "deadline", "label": "截止", "type": "datetime" },
      { "key": "file",     "label": "附件", "type": "file" }
    ]
  }
}
```

### FormField 字段类型

| `type` | 渲染 |
|--------|------|
| `"text"` | 单行输入 |
| `"textarea"` | 多行输入 |
| `"select"` | 下拉选择 |
| `"datetime"` | 日期时间选择器 |
| `"number"` | 数字输入 |
| `"file"` | 文件选择 |
| `"checkbox"` | 布尔开关 |

## 下一步

- [11 · 后端进程](11-backend.md)
