# 02 · 侧边栏与路由

插件如何出现在导航系统中。

## 侧边栏入口

```json
{
  "sidebar": {
    "section": "AI 工具",
    "sectionOrder": 20,
    "order": 10,
    "badge": false
  }
}
```

| 字段 | 说明 |
|------|------|
| `section` | 分类标签。同标签的入口归为一组 |
| `sectionOrder` | 分类间排序。越小越靠前。默认 `50` |
| `order` | 分类内排序。越小越靠前。默认 `50` |
| `badge` | 是否显示角标。默认 `false` |

分类完全由插件自行定义，无内置分类。`section` 写什么就是什么。

## 多页面模块

一个模块可以声明多个侧边栏入口（比如"通知"子页面）：

```json
{
  "secondaryNavs": [
    {
      "icon": "notifications",
      "label": "通知",
      "routePath": "/my-plugin/notifications",
      "section": "AI 工具"
    }
  ]
}
```

| 字段 | 说明 |
|------|------|
| `icon` | 图标名 |
| `label` | 展示名 |
| `routePath` | 路由路径 |
| `section` | 所属分类标签 |

## 路由路径

模块的路由由以下字段自动收集：

- `route` — 主路由
- `layout.panels[].path` — 各 tab 面板路由
- `secondaryNavs[].routePath` — 子导航路由

框架层据此生成 GoRouter 路由表。

## 纯服务模块

不填 `route`、不填 `sidebar`、不填 `icon`——模块只提供后端服务，不出现在 UI 中。

```json
{
  "type": "module",
  "id": "background_service",
  "name": "后台服务",
  "process": { "exe": "service.exe" }
}
```

## 下一步

- [03 · 页面布局](03-layout.md) — 分框、分 tab、搜索栏
