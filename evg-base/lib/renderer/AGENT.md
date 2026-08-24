---
name: renderer
role: Evergreen 下游 renderer 层主 OWNER
scope: evg-base/lib/renderer/（顶层 + atomic + components/shared）
parent: root
---

# AGENT.md — renderer（下游主）职责书

> 本文件是「谁负责这里」的职责书。技术原理见同目录 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/renderer/` 顶层（`renderer.dart` barrel）+ `atomic/` + `components/shared/`
- 一句话定位：纯 UI 渲染层的总协调者，维护原子取数原语 + 共享组件 + 顶层 barrel。

### 主要子域（本 OWNER 内，子域独立 OWNER 见 §6）

| 子域 | 目录 | 职责 |
|------|------|------|
| 原子取数原语 | `atomic/` | DataSourceResolver / JSONPath / JsonTree / TransformRegistry |
| 共享组件 | `components/shared/` | TemplateEngine / SlotScale / Chat / 表格 / 编辑器 / 媒体 / 市场等 |

## 2. 边界与红线

- ✅ 可以：改 `atomic/`、`components/shared/`、顶层 barrel；协调各子 OWNER。
- ❌ 禁止：写业务逻辑；直调 HTTP API（同进程走 Riverpod）；引用 `core/` 之外的业务实现；改动子 OWNER（app/page/templates）内部实现。
- ⚠️ 需协调：`renderer.dart` barrel 导出变更影响所有消费方；共享组件被 templates 广泛复用，改动需通知 `renderer-templates`。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `renderer.dart` barrel | barrel | app-shell + templates | 导出增删需广播 |
| 原子取数原语 | `atomic/atomic.dart` | templates | 取数原语签名变更需通知 templates |
| 共享组件 | `components/shared/shared.dart` | templates + page | 组件 API 变更需广播 |

## 4. 规则（本 OWNER 内必须遵守）

- renderer 只消费 `core/` 的 barrel 公共 API，禁止直调 HTTP。
- 同进程数据走 Riverpod `dataOrchestratorProvider`，禁止 HTTP 绕圈。
- 窄屏 <600px 必须 `LayoutBuilder` 检测。
- 共享组件是「v4_modle 全部具名 slot（注册清单见 `templates/v4_modle/_registrations.dart`）+ `placeholder-*` 预留扩展」的统一外壳，改动需考虑全部 slot 内部布局。

## 5. 验收标准

- 改完必须：相关 `flutter test` 通过；共享组件改动需全量 `flutter test` 无回归。

## 6. 引用索引

- 心智模型：`CLAUDE.md`
- 模块说明：`README.md`
- 子 OWNER：`app/AGENT.md`、`page/AGENT.md`、`templates/AGENT.md`
- 上层职责书：根 `AGENT.md`
