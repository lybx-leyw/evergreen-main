# 课程表（class-schedule）

HTML 模块插件（`template: "html"`）：周视图课程表查看器，含 7 天 × 13 节次表格、某天课表、
增删改课程、颜色标签、明暗主题适配。

## 数据来源（优先级）

1. **真实课表（优先）**：启动时防御式探测平台数据中枢，依次尝试
   `platform.data.get('zju_timetable')` → `zju_schedule`（名称取决于用户环境，
   先经 `platform.data.list()` 过滤可用源）。命中后展示为**只读真实课表**
   （点击课程查看教师/周次/学期详情），并按当前学期位掩码过滤；数据更新经
   `platform.data.subscribe` 自动刷新，也提供手动「刷新」按钮。
2. **手动课表（降级）**：`data.get` 返回 null / 未注册 / 无 bridge 环境时**静默降级**，
   不报错。用户可手动添加/编辑/删除课程；「载入示例课表」写入的 4 门课程为
   **示例数据（非真实课表）**，按钮与确认弹窗均已明确标注。

## 存储

手动课表与视图偏好（`real`/`manual`/`auto`）持久化到 `localStorage`
（key：`evg.class-schedule`），由平台 bridge 的 localStorage polyfill 自动落盘到
插件私有目录，无需额外配置；读写均有 try/catch，异常时降级为「会话内有效」。

## 主题

全部颜色走平台注入的 `--evg-*` CSS 变量（background/surface/text/accent/border/error），
明暗主题自动适配；`:root` 内为独立预览兜底值。

## 结构

```
module/
├── index.html     # 自包含页面（无外部 CDN 依赖）
└── manifest.json  # schemaVersion 2.0 / template html / id class-schedule
```
