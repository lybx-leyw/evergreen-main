# example-skin-evergreen-logo —— 示例皮肤包（agent 皮肤包）

AI 视图皮肤包示例：`plugins/<id>/skin/manifest.json` + 图片资源（png/svg）。
皮肤包只覆盖 AI 视图内部消费点的「功能色 / 局部渲染」，**不触碰**主题语义色。

## 安装

- 随包分发：`docs/plugin-registry/plugins.json` 中 `"lattice":"skin"` 条目
  （`manifest.source: local`，`install` 为空 = 随包分发），在「发现插件」页安装。
- 安装后落盘 `plugins/example-skin-evergreen-logo/skin/`，下次启动自动扫描加载。

## 切换

设置面板「外观 · 皮肤包」下拉切换，或经 `active_skin_id`（SharedPreferences）
持久化；ChangeNotifier 链路热切换，无需重启。

## 本示例演示的 DIY 项

| 候选 | 演示内容 |
|------|---------|
| A1 | 对话背景渐变：`background.type="gradient"`（#E8F5E9 → #FFFFFF，135°） |
| B1 | 工具栏按钮显隐：`buttons.inputBar.bgProcess=false`（隐藏「后台进程」入口） |
| B2 | 消息操作按钮显隐：`buttons.messageActions`（本示例全显示） |
| C1 | 思考栏配色：`thinking.colors.*`（header/容器/文本/四类 chip）+ 顶层 `effortColor`/`toolActiveColor` |
| D1 | 气泡圆角：`bubble.borderRadius=18` |
| E | AI 头像 / 空状态 logo：`avatar.assistant` / `emptyState.logo` 引用皮肤内 svg，`emptyState.title` 自定义欢迎语 |

## manifest schema 速记

- `type` 必填且为 `"skin"`；`id`/`name` 建议必填；其余全部可选，未知键静默忽略。
- hex 颜色支持 `#RGB` / `#RRGGBB` / `#AARRGGBB`；图片引用相对 manifest 路径。
- `null` = 跟随主题默认（渲染层回退现有默认值，零行为变化）。
- 资源目录：`plugins/<id>/skin/`（与 manifest 同级）。
