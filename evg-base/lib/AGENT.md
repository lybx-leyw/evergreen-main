---
name: app-shell
role: Evergreen 应用壳 OWNER（启动组装 / 路由 / 全局 Provider）
scope: evg-base/lib/ 顶层（main.dart / app.dart / app_bootstrap.dart / providers.dart / evergreen_base.dart）
parent: root
---

# AGENT.md — app-shell（应用壳）职责书

> 本文件是「谁负责这里」的职责书。技术原理见 `lib/README.md` 与根 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/` 顶层（`main.dart`、`app.dart`、`app_bootstrap.dart`、`providers.dart`、`evergreen_base.dart`）
- 一句话定位：横跨三层的**组装者**——AppBootstrap 步骤序列启动（core HttpServer + Module + ScraperBridge）→ 扫描插件 → 解析 manifest → 注册 → 注入 Riverpod → runApp。

### 主要文件

| 文件 | 职责 |
|------|------|
| `main.dart` | 启动入口（全局错误处理 / AppBootstrap 步骤序列 / Web 提前退出） |
| `app.dart` | MaterialApp.router + 动态路由生成 + 主题 + 键盘快捷键 |
| `app_bootstrap.dart` | 启动引导（逐步骤 `[BOOT] N/total` 日志，致命步骤 greenix-paths） |
| `providers.dart` | 应用级 Riverpod Provider 声明（canonical，清单见文件） |
| `evergreen_base.dart` | 包入口 barrel |

## 2. 边界与红线

- ✅ 可以：改 `lib/` 顶层组装逻辑；调整启动顺序、路由、Provider 注入。
- ❌ 禁止：写业务逻辑到壳层（应下沉到 core）；改动 core/renderer 内部实现；绕过 `ModuleRegistry` 硬编码路由。
- ⚠️ 需协调：启动顺序（`windowManager.show()` 必须在 `runApp` 之后，避免白屏）；`.greenix` 路径在 Android 必须用 path_provider；`runApp` 前任何抛异常都会导致窗口不显示。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `providers.dart` Provider | Riverpod | 全 renderer + core | Provider 增删需广播 |
| 路由表 | `app.dart` | 全 renderer | 路由变更需广播 |
| 启动组装流程 | `main.dart` | platform（打包） | 初始化顺序变更需通知 platform |
| 全局错误处理 | `main.dart`（FlutterError.onError） | 全仓 | 错误处理变更需广播 |

## 4. 规则（本 OWNER 内必须遵守）

- 组装者职责：启动服务 → 扫描 → 注册 → seal → 注入 → runApp。
- `windowManager.show()` 必须在 `runApp` 之后。
- 防御式初始化：`SharedPreferences` / `windowManager` / 项目根解析都要 try-catch 降级。
- `runApp` 之前的代码禁止抛未处理异常（否则窗口永不显示）。
- 安卓：持久化目录用 `getApplicationSupportDirectory()`，禁止 `Directory.current` 拼路径。

## 5. 验收标准

- 改完必须：`flutter build windows` EXIT=0（编译权威）；启动顺序改动需实跑验证无白屏。

## 6. 引用索引

- 心智模型：根 `CLAUDE.md`
- 模块说明：`lib/README.md`
- 上层职责书：根 `AGENT.md`
