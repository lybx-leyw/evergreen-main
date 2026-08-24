# Module 插件撰写指南

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | Module 插件作者 |

> **本文档已合并至 `plugin-module.md`**，后者现在是 Module 插件开发的唯一权威参考。
>
> 请查阅：`lib/core/module/docs/plugin-module.md`

`plugin-module.md` 合并了原 `plugin-authoring-guide-module.md`（规范指南）和 `plugin-module.md`（完整字段参考），内容涵盖：

- 完整 manifest.json 字段参考（基础信息、路由导航、UI 范式、布局、数据绑定、交互、输入、媒体、后端进程等）
- UI 范式选择建议（8 种范式 + 专属配置）
- 四级 .exe 层级与进程通信协议
- Composite 模式详解（PLAN_NOW 终局方向）
- 完整代码示例 + 验证规则 + 常见错误排查
