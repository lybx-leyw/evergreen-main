---
name: plugin-zju
role: Evergreen zju_modle 校园模板 OWNER
scope: evg-base/lib/renderer/templates/zju_modle/
parent: renderer-templates
---

# AGENT.md — plugin-zju 职责书

> 本文件是「谁负责这里」的职责书。技术原理见根 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/renderer/templates/zju_modle/`（纯模板，暂无独立插件声明）
- 一句话定位：浙大校园模块渲染模板——成绩/课程/考试/教师/教务（zdbk）/智云课堂（classroom）等校园子 UI 集合。

### 内部子域

| 子域 | 目录 | 职责 |
|------|------|------|
| 教务 zdbk | `zdbk/` | 成绩/课表/考试/开课等 |
| 智云课堂 | `classroom/` | 课程视频/PPT/字幕 |
| 学在浙大 | `courses/` | 课程活动/作业 |
| 考试/成绩 | `exams/`、`scores/` | 考试安排、成绩绩点 |
| 教师 | `teachers/` | 教师评分 |
| 认证 | `zju_auth/` | ZJU SSO/CAS 认证 |
| 共享 | `shared/` | 共享组件 |
| 数据源 | `zju_data_sources.dart` | 数据源声明 |

## 2. 边界与红线

- ✅ 可以：改 `zju_modle/` 内一切实现；新增校园子 UI。
- ❌ 禁止：改动 `core/data`/`core/config`（数据源与凭证引擎归对应 OWNER）；改动其他模板；在渲染层写业务逻辑。
- ⚠️ 需协调：`zju_data_sources.dart` 声明的数据源类型需与 `core-data` 对齐；ZJU 认证（CAS/SSO）逻辑归属 `core-data` 的 scraper 侧，渲染层不持登录态。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `zju` 模板 | `template_registry`（manifest `template` 字段） | app-shell + core-module | 模板名/路由变更需广播 |
| `zju_builtin_modules` | `zju_builtin_modules.dart` | core-module（内置模块注册） | 内置模块增删需通知 core-module |
| 数据源类型（12 个 `DataType`，`sessionProviderId:'zju'`，T9） | `zju_data_sources.dart` | core-data（DataOrchestrator） | 类型契约变更需通知 core-data |
| `ZjuSessionProvider`（`sessionProviderId:'zju'`）/ `zjuRefreshSession` / `zjuIsSessionExpiredError` | `zju_auth/zju_session.dart`（T9） | core-data（会话失效重登重拉） | 过期判定/重登语义变更需通知 core-data |
| `ZjuMediaRequestHeadersProvider` | `zju_auth/zju_session.dart`（T9） | renderer（`buildMedia` 播放接线） | 媒体请求头组装变更需广播 |

## 4. 规则（本 OWNER 内必须遵守）

- 渲染层只画 UI，不写业务逻辑、不持登录态。
- 模板只按 `modle_route` 渲染子视图，不内置 Tab/多 page（见根 CLAUDE.md 模板语义）。
- 数据经 Riverpod 从 core 取，禁止直调 HTTP。

## 5. 验收标准

- 改完必须：相关 `flutter test` 通过；模板/数据源类型变更需全量回归。

## 6. 引用索引

- 心智模型：根 `CLAUDE.md`
- 数据源契约（依赖）：`evg-base/lib/core/data/CLAUDE.md`
- 上层职责书：`../AGENT.md`（renderer-templates）
