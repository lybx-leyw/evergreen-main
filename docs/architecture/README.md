# Evergreen 架构演示图 — 统一位置与图目录

> 本目录是 Evergreen 全部**架构演示图**的统一位置（`docs/architecture/`）。
> 7 张图与统一入口 `index.html` 均遵循 **墨白风**（墨/白两极 + 绿色强调，明暗双色）风格规范，
> 规范唯一依据为 [`STYLE_GUIDE.md`](STYLE_GUIDE.md)，共享基座为 [`_shared/`](_shared/)。
>
> - 入口页：**`docs/architecture/index.html`**（打开它即可浏览全部 7 张图）
> - 明暗切换：每页右上角「白/墨」按钮；审查截图可用 `?theme=light` / `?theme=dark` 固定
> - 动效降级：所有动图遵循 `prefers-reduced-motion`，静态态可读可截屏

---

## 目录结构

```
docs/architecture/
├── index.html               ← 统一入口页（卡片导航 · 品牌 logo 与 pet 装饰）
├── README.md                ← 本文档
├── STYLE_GUIDE.md           ← 墨白风风格规范（唯一风格依据，v1.0）
├── _shared/
│   ├── evg-style.css        ← 主题变量（明暗双色）+ 组件类 + 动效（唯一样式依赖）
│   ├── evg-common.js        ← 明暗切换 / 滚动入场 / countUp / SVG 路径与箭头工具
│   ├── preview.html         ← 风格基座预览/自查页（非架构图）
│   └── branding/            ← logo.svg · logo-ink.svg · pet.svg · pet_leafcat.svg · pet_sleep.svg
├── data-hub.html            （T2）数据中枢演示图
├── agent-architecture.html  （T3）Agent 架构思维导图
├── flywheel.html            （T4）插件飞轮模型
├── workshops.html           （T4）四工坊泳道图
├── agent-workflow.html      （T5）Agent 自动工作流
├── three-view.html          （T5）平台三视图
└── plugin-architecture.html （T7）三角通讯链架构（HTML-first 修正版）
```

> `_shared/preview-notes/` 为审查过程产物（截图/脚本），不属于交付物。

---

## 各图用途一览

| # | 文件 | 演示主题 | 用途 / 看点 | 动效 |
|---|------|---------|------------|------|
| 01 | [`data-hub.html`](data-hub.html) | 数据中枢 DataHub | L1–L4 栈式分层；并发拉取 / 登录域调度 / 失败重试（2s 退避 ×3 上限）/ 订阅刷新与 diff 变更通知；机制卡 ×6 + 拉取阶段链 | 13 相循环调度演示、流动线、重试阶梯、阶段链、countUp |
| 02 | [`agent-architecture.html`](agent-architecture.html) | Agent 架构 · 一中心多核心 | 六个核心分支思维导图（Skill 加载 / 奥尔波特五维记忆 / Agent Tool 插件 / 工作区视觉 / 循环与安全网 / 平台桥接），点击分支联动详情，hash 直达 | 思维连线流动、自动演示点亮、循环图四阶段、countUp |
| 03 | [`flywheel.html`](flywheel.html) | 插件飞轮 · 创作与发现闭环 | 五站闭环（创作→采集→展示→安装→集成→再创作），中心 logo 圆盘放映，飞轮动力计数 | 绿环流动、站点轮播高亮、放映、悬浮、countUp |
| 04 | [`workshops.html`](workshops.html) | 四工坊泳道 · 开发者模式 DIY | 网页→scraper→数据源包裹→四工坊泳道→平台组合器→仓库→用户；七类插件包裹与 7 个装配 Loader | 水流带流动、气泡漂浮、浮起包裹 |
| 05 | [`agent-workflow.html`](agent-workflow.html) | Agent 自动工作流 · 插件供应链 | skill→auto-workflow-skill→一支笔→AI 产线装配线；队长按 AGENT.md §6 向 9 OWNER 扇形派发 | 传送带 chip 无缝右移、回流线、脉冲状态点 |
| 06 | [`three-view.html`](three-view.html) | 平台三视图 · 插件资源分发 | 底层资源层→前端运行时→三路分发（AI 助手 / 插件 / 开发者模式），开发者模式⇄底层资源双向回流 | 三路流动线、SMIL 光点移动、回流闭环 |
| 07 | [`plugin-architecture.html`](plugin-architecture.html) | 三角泳道 · 通讯链演示 | 三角泳道演示动图：上游 core/（纯 Dart 服务层）→ 中游 plugins/（HTML-first 主路径）→ 下游 renderer/（模板路由）三条泳道 + 三条通讯链（HTTP JSON / 视图分发 / import 直调）；细节全部外置详情卡（子模块 / 端口体系 / ModuleDispatch 规则 / 模板注册表 / AppBootstrap 25 步 / JS Bridge 能力表），泳道节点可点击跳转 | 三条通讯链流动（视图分发为主视觉流）+ 数据点下落、装配 25 步逐站点亮、放映、悬浮、节点点击联动 |

统一入口 [`index.html`](index.html) 以卡片形式列出上述 7 图，并附风格基座链接（STYLE_GUIDE / preview）。

---

## 如何打开与演示

1. **直接双击** 任意 HTML 文件（file:// 独立可用，无需服务器、无外部依赖）。
2. **统一入口**：打开 `index.html` 按卡片进入各图。
3. **明暗双色**：右上角「白/墨」按钮切换并持久化（localStorage）；未手动设置时跟随系统。
   审查/截图固定主题：`data-hub.html?theme=dark`（优先级：URL 参数 > localStorage > 系统）。
4. **动效降级**：系统开启「减弱动态效果」（prefers-reduced-motion: reduce）时全部动图静止为可读终态。
5. **响应式**：窄屏下网格/泳道/思维导图自动降级为单列，无横向滚动。

---

## 维护约定

- **新增架构图**：按 `STYLE_GUIDE.md` §8 接入（`<link _shared/evg-style.css>` + `<script _shared/evg-common.js>` + `data-evg-theme-toggle`），
  颜色一律 `var(--evg-*)`，组件只用基座类；完成后在 `index.html` 加卡片、在本文档表格加一行。
- **品牌资源**：logo/宠物一律引用 `_shared/branding/`（灰度待机 → 悬停/放映彩色），使用约定见 STYLE_GUIDE §6。
- **动效节奏**：只使用基座动画 token（`--evg-dur-*` / `--evg-reel` / `--evg-float` / `--evg-pulse` 与 `evg-dash` / `evg-float` / `evg-pulse` / `evg-msg-in` / `evg-focus-pulse` 关键帧），不要自造时长。
- **不要改动 `_shared/` 基座文件**（evg-style.css / evg-common.js / branding）以迁就单张图；需要新组件时先更新基座与 STYLE_GUIDE，再让各图接入。
- **自查清单**：绘制/修改后对照 STYLE_GUIDE §9 逐条自查（接入、无硬编码色值、双主题截图、组件类、branding、动效降级）。
