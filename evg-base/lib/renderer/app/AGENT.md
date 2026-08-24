---
name: renderer-app
role: Evergreen 下游 renderer/app 子 OWNER
scope: evg-base/lib/renderer/app/
parent: renderer
---

# AGENT.md — renderer-app 职责书

> 本文件是「谁负责这里」的职责书。技术原理见 `../CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/renderer/app/`
- 一句话定位：应用壳 UI + 命令面板 + 模式栏 + DevMode Hub + 主题服务 + 全局 Provider。

### 主要文件

| 文件 | 职责 |
|------|------|
| `app_shell.dart` | 应用壳（侧边栏/模式切换） |
| `app.dart` | App 层入口 |
| `app_mode.dart` | 应用模式 |
| `command_palette.dart` | 命令面板 |
| `mode_rail.dart` | 模式栏 |
| `dev_mode_hub.dart` | 开发模式 Hub |
| `debug_error_bar.dart` | 调试错误栏 |
| `service/` | 全局 Provider（renderer_providers）、主题服务（ThemeProvider/RenderTokens）、数据变更通知 |

## 2. 边界与红线

- ✅ 可以：改 `app/` 内一切实现；新增壳层能力。
- ❌ 禁止：写业务逻辑；直调 HTTP；改动 core/ 或其他 renderer 子 OWNER。
- ⚠️ 需协调：`app_shell.dart` 侧边栏导航消费 `ModuleRegistry` 与插件状态，导航过滤逻辑变更需与 `core-module`/`renderer-page` 对齐（开关必须联动消费方）。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `AppShell` | `app_shell.dart` | app-shell | 壳结构变更需通知 app-shell |
| 主题 Provider | `service/theme/theme_provider.dart` | 全 renderer | 主题切换行为变更需广播 |
| 全局 Provider | `service/providers/renderer_providers.dart` | templates + page | Provider 增删需广播 |

## 4. 规则（本 OWNER 内必须遵守）

- 渲染层只画 UI，不写业务逻辑。
- 侧边栏/模式栏必须响应式消费状态源（Riverpod），禁止读死文件状态。

## 5. 验收标准

- 改完必须：相关 `flutter test` 通过；壳层改动需全量回归。

## 6. 引用索引

- 心智模型：`../CLAUDE.md`
- 上层职责书：`../AGENT.md`
