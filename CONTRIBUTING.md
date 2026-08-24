# 贡献协议（CONTRIBUTING.md）

> 所有对 Evergreen Multi-Tools 的修改必须满足以下要求，否则将被驳回。
> 最后更新：2026-08-25

---

## 1. 贡献流程总览

```
Fork → 新建分支 → 开发（遵守 OWNER 边界）→ 本地测试 → 提交 → PR → OWNER 评审 → 合并
```

1. **先读**：根 `CLAUDE.md`（AI 协作总入口）、根 `AGENT.md`（OWNER 分工）。
2. **找 OWNER**：确定你要改的目录归属哪个 OWNER（见 §2），先读该 OWNER 的 `AGENT.md` 与 `CLAUDE.md`。
3. **跨边界先协调**：若改动涉及他人 OWNER 的公开契约，必须先登记变更并通知受影响 OWNER。
4. **提交前**：全量 `flutter test` + 相关子包 `dart test` 通过（见 §6）。

## 2. OWNER 分工速查

> 完整索引见根 `AGENT.md` §6。这里只列核心分层。

| 层 | OWNER | 管辖 |
|----|-------|------|
| 仓库级 | `root` | 根文档 |
| 上游 core | `core` + `core-agent`/`core-config`/`core-data`/`core-module`/`core-theme`/`core-services`/`core-infra` | `evg-base/lib/core/` |
| 下游 renderer | `renderer` + `renderer-app`/`renderer-page`/`renderer-templates` | `evg-base/lib/renderer/` |
| 应用壳/平台 | `app-shell` / `platform` | `evg-base/lib/` 顶层 / `scripts`+`tool`+`windows`+`android` |
| 中游插件 | `plugins` + `plugin-<id>` | `plugins/` |

## 3. 架构红线（三层职责 + 禁止事项）

```
上游 core/  ←──HTTP JSON 调用──  中游 plugins/  ──descriptor/Riverpod→  下游 renderer/
(纯 Dart 服务层)                  (JSON 声明 + .exe)                     (纯渲染层)
```

### 各层的「不」

| 层 | 不做什么 |
|----|---------|
| 上游 `core/` | 不画像素，不引用 Flutter Widget |
| 中游 `plugins/` | 不写 Dart UI 代码，不直接操作渲染 |
| 下游 `renderer/` | 不解析 manifest 管理进程，不写业务逻辑，不直调 HTTP API（同进程走 Riverpod） |

### 禁止的行为

- ❌ `renderer/` 写业务逻辑或直调 HTTP API
- ❌ `core/` 引用 Flutter Widget
- ❌ 绕过 `ModuleDescriptor` / `ModuleRegistry` 硬编码路由
- ❌ 修改正本目录（当前仓库是副本，路径含 `-副本`）
- ❌ 手动拼接 `Cookie` 头覆写 CookieManager
- ❌ 在 Widget `build()` 中触发网络请求/状态变更
- ❌ 用 `print()` / `debugPrint()` 代替 `Log()`（Android 核心层关键诊断除外，用 `print` 保证 logcat 可见）
- ❌ 删除暂时不可用功能的代码（应标记「开发中」并保留）
- ❌ Provider 中用 `ref.read(authProvider)` 替代 `ref.watch(authProvider)`（登录后不刷新）
- ❌ 设置/开关 UI 只写状态、消费方不读取（必须共用唯一响应式真相源）

## 4. 代码风格

### 4.1 Dart

- 遵循 `flutter_lints` 5.x 规则。
- `import` 排序：Dart SDK → Flutter → Riverpod → 项目内部（core → features）。
- 私有方法/类加 `_` 前缀。
- 不可变数据类必须提供 `copyWith` + `toJson` + `fromJson`。
- 敏感字段 `toString()` 必须脱敏。
- 所有公开 Service 方法返回 `Result<T>`（`Ok`/`Err`），禁止向外抛异常；`AppError` 必须含 `userMessage` + `recoveryHint`。

### 4.2 Widget

- 复用型 Widget 放对应 OWNER 目录（如 `renderer/components/shared/`）。
- 使用 `ConsumerWidget` / `ConsumerStatefulWidget`。
- `build()` 中不允许有副作用。
- 窄屏（<600px）必须 `LayoutBuilder` 检测，窄屏 Column 替代 Row。

### 4.3 测试

- 测试用 `package:flutter_test/flutter_test.dart`（**不是** `package:test`）。
- 被测逻辑若是纯逻辑，抽成领域层纯函数，用纯 Dart 单元测试验证（避免 widget 测试挂死）。
- 单元测试**禁止 import 巨型 widget 文件**（易触发 compiler crash）。
- 错误路径必须覆盖：成功、空数据、401/404、网络异常。
- 跨多文件改动，提交前必须跑一次**全量** `flutter test` 裁定编译（单文件绿 ≠ 全量绿）。

## 5. 提交规范

- Commit message 遵循 Conventional Commits：`<type>(<scope>): <subject>`。
- `type`：`feat` / `fix` / `refactor` / `docs` / `test` / `chore`。
- `scope`：尽量填 OWNER 名（如 `fix(session): ...`、`feat(core-module): ...`）。
- subject 用英文或中文简短描述，不含句号结尾。

## 6. 测试与验收

```bash
# 全量测试（flutter test 是编译裁定权威）
cd evg-base && flutter test

# 纯 Dart 子包独立测试
cd evg-base/lib/core/agent && dart test
cd evg-base/lib/core/config && dart test
cd evg-base/lib/core/data && dart test
cd evg-base/lib/core/module && dart test
cd evg-base/lib/core/theme && dart test

# 编译验证（本环境 flutter analyze 对 material 报全局假错，以 build 为准）
cd evg-base && flutter build windows
```

## 7. 文档同步义务

- 改代码同步更新该 OWNER 的 `CLAUDE.md`（架构变化）与 `AGENT.md`（契约变化）。
- 跨模块改契约（HTTP 端点、端口文件格式、`ModuleDescriptor` 字段）必须登记到对应 OWNER 的「对外契约」表。
