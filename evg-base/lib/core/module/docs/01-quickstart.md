# 01 · 快速开始

5 分钟创建第一个插件模块。

## 目录结构

```
plugins/
  my_plugin/
    manifest.json    ← 唯一必需的文件
    plugin.exe       ← 可选，后端进程
```

## 最小 manifest

新建 `plugins/my_plugin/manifest.json`：

```json
{
  "type": "module",
  "id": "my_plugin",
  "name": "我的插件"
}
```

`type` 必须为 `"module"`。`id` 全局唯一。`name` 是展示名称。

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

```json
{
  "type": "module",
  "id": "my_plugin",
  "name": "我的插件",
  "icon": "extension",
  "route": "/my-plugin",
  "sidebar": { "section": "AI 工具", "order": 50 }
}
```

## 验证

将 manifest.json 放入 `plugins/my_plugin/`，启动应用。你的模块将出现在侧边栏的 "AI 工具" 分组中，点击进入页面。

## 下一步

- [02 · 侧边栏与路由](02-sidebar-route.md) — 自定义分类、多页面导航
- [03 · 页面布局](03-layout.md) — 分框、分 tab、搜索栏、缩放
- [04 · 选一个 UI 范式](04-ui-paradigms.md) — 对话 / 表格 / 文档 / 幻灯片
