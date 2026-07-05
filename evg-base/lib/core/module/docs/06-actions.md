# 06 · 鼠标/触摸交互

列表项能点什么、能划什么、怎么选、怎么增删改。

## 完整配置

```json
{
  "actions": {
    "itemTap": "detail",
    "itemLongPress": "context_menu",
    "itemSwipe": "delete",
    "selection": "multi",
    "refresh": { "enabled": true, "pullToRefresh": true, "autoInterval": 60 },
    "sortable": ["name", "date"],
    "creatable": true,
    "editable": true,
    "deletable": { "enabled": true, "confirm": true },
    "exportable": ["csv", "pdf"]
  }
}
```

## 列表项手势

| 字段 | 值 | 效果 |
|------|-----|------|
| `itemTap` | `"detail"` | 点击跳详情页 |
| | `"select"` | 点击选中 |
| | `"none"` | 不响应 |
| | 不填 | 不响应 |
| `itemLongPress` | `"context_menu"` | 长按弹出菜单 |
| | `"none"` | 不响应 |
| `itemSwipe` | `"delete"` | 侧滑删除 |
| | `"archive"` | 侧滑归档 |

## 选择模式

| `selection` | 效果 |
|-------------|------|
| `"none"` | 无选择 |
| `"single"` | 单选 |
| `"multi"` | 多选（列表出现 checkbox） |

## 刷新

```json
{ "refresh": { "enabled": true, "pullToRefresh": true, "autoInterval": 60 } }
```

| 字段 | 说明 |
|------|------|
| `enabled` | 启用刷新 |
| `pullToRefresh` | 下拉刷新 |
| `autoInterval` | 自动刷新间隔（秒）。`0` = 不自动 |

## 排序

```json
{ "sortable": ["name", "date"] }
```

表中这些列头可点击排序。

## 增删改

| 字段 | 效果 |
|------|------|
| `creatable: true` | 显示"新增"按钮 |
| `editable: true` | 显示"编辑"按钮 |
| `deletable.enabled: true` | 显示"删除"按钮 |
| `deletable.confirm: true` | 删除前弹确认弹窗 |

## 导出

```json
{ "exportable": ["csv", "pdf", "json"] }
```

## 与后端的配合

每种操作对应后端的一个 HTTP 端点：

| 操作 | 端点 |
|------|------|
| 创建 | `POST /items` |
| 编辑 | `PUT /items/:id` |
| 删除 | `DELETE /items/:id` |
| 批量删除 | `DELETE /items/batch` |
| 导出 | `GET /export?format=csv` |

## 下一步

- [07 · 键盘交互](07-input.md)
