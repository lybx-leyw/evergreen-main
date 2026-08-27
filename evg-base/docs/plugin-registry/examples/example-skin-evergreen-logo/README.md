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
| A（R2-4） | 对话背景图分横竖屏：`background.type="image"` + `imageDesktop`（宽屏 `bg_desktop.svg`）/ `imageMobile`（竖屏 `bg_mobile.svg`） |
| B1 | 工具栏按钮显隐：`buttons.inputBar.bgProcess=false`（隐藏「后台进程」入口） |
| B2 | 消息操作按钮显隐：`buttons.messageActions`（本示例全显示） |
| C1 | 思考栏配色：`thinking.colors.*`（header/容器/边框/文本/四类 chip）+ 顶层 `effortColor`/`toolActiveColor` |
| D1 / R2-3 | 气泡样式：`bubble.borderRadius` + 用户气泡底色/文字色（`userBackgroundColor`/`userTextColor`） |
| E（R2-4） | 空状态装饰图标：`assets.emptyIcon`（**横竖屏一致的单一图标** `empty_icon.svg`）+ `emptyState.title` 自定义欢迎语 |
| R2-3 | 用户头像底色：`avatar.userBackgroundColor`；AI 头像引用皮肤内图标 `avatar.assistant` |

## 新语义速记（R2-4，避免语义漂移）

- **空白对话页装饰图标 = `assets.emptyIcon`（单一图标，横竖屏一致，不区分方向）**。
- **对话时的背景图 = `background.type:"image"` + `imageDesktop`（横屏/宽屏）/
  `imageMobile`（竖屏）**，渲染层按屏幕宽高比选择。
- 旧键 `assets.logoDesktop` / `logoMobile` / `assets.backgroundImage` 保留
  向后兼容读（渲染层可回退），示例与文档已迁移到新语义。

## manifest schema 速记

- `type` 必填且为 `"skin"`；`id`/`name` 建议必填；其余全部可选，未知键静默忽略。
- hex 颜色支持 `#RGB` / `#RRGGBB` / `#AARRGGBB`；图片引用相对 manifest 路径。
- `null` = 跟随主题默认（渲染层回退现有默认值，零行为变化）。
- 资源目录：`plugins/<id>/skin/`（与 manifest 同级）。
