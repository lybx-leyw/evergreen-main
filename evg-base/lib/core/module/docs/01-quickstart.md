# 01 · 快速开始

5 分钟创建第一个插件模块。

## 目录结构

```
plugins/
  my_plugin/
    module/
      manifest.json    ← 唯一必需的文件
      plugin.exe       ← 可选，后端进程
```

> `ModuleLoader` 只扫描 `plugins/<name>/module/manifest.json`（`type: "module"`）。
> 一个插件可同时提供多种能力：`module/`、`agent/`、`data/`、`config/`、`theme/` 各放一类声明。

## 最小 manifest

新建 `plugins/my_plugin/module/manifest.json`：

```json
{
  "type": "module",
  "id": "my_plugin",
  "name": "我的插件"
}
```

`type` 必须为 `"module"`。`id` 全局唯一。`name` 是展示名称。
（`schemaVersion` 缺省 `"2.0"`；`template` 缺省 `"v4"`，声明式组件模块。）

## 加一个页面

```json
{
  "type": "module",
  "id": "my_plugin",
  "name": "我的插件",
  "icon": "extension",
  "route": "/my-plugin"
}
```

`icon` 是 Material Icons 名称。`route` 以 `/` 开头。

## 出现在侧边栏

V2 导航统一放在 `nav` 下（旧版顶层 `sidebar` 键已不解析）：

```json
{
  "type": "module",
  "id": "my_plugin",
  "name": "我的插件",
  "icon": "extension",
  "route": "/my-plugin",
  "nav": {
    "sidebar": { "section": "AI 工具", "sectionOrder": 50, "order": 10 }
  }
}
```

## 验证

将 `module/manifest.json` 放入 `plugins/my_plugin/module/`，启动应用。你的模块将出现在侧边栏的 "AI 工具" 分组中，点击进入页面。

## 下一步

- [02 · 侧边栏与路由](02-sidebar-route.md) — 自定义分类、多页面导航
- [03 · 页面布局](03-layout.md) — 分框、分 tab、搜索栏、缩放
- [04 · 选一个 UI 范式](04-ui-paradigms.md) — 对话 / 表格 / 文档 / 幻灯片
