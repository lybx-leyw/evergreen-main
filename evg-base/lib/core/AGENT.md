---
name: core
role: Evergreen 上游 core 层主 OWNER
scope: evg-base/lib/core/（顶层 + errors/log/result）
parent: root
---

# AGENT.md — core（上游主）职责书

> 本文件是「谁负责这里」的职责书。技术原理见 `evg-base/lib/core/CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/core/` 顶层 + `errors.dart` / `log.dart` / `result.dart` 三个基础文件
- 一句话定位：上游纯 Dart 服务层的总协调者，维护基础类型（`AppError`/`Result<T>`/`Log`），协调 7 个子 OWNER。

## 2. 边界与红线

- ✅ 可以：维护 `errors.dart`/`log.dart`/`result.dart`；制定跨子包接口规范；协调子 OWNER 的契约变更。
- ❌ 禁止：直接改动子 OWNER 目录内的实现（派发对应子 OWNER）；`core/` 引用 Flutter Widget；绕过子 OWNER 边界做跨包改动。
- ⚠️ 需协调：`AppError` 新增子类、`Result<T>` API 变更、`Log` 行为变更会影响所有子包，需广播。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `AppError` 体系（14 子类） | `errors.dart` | 全 core + renderer | 新增子类需同步工厂方法 |
| `Result<T>`（Ok/Err） | `result.dart` | 全 core + renderer | sealed class 变更影响穷尽检查 |
| `Log` 单例 | `log.dart` | 全 core + renderer | 输出行为变更需广播 |
| 6 个 HTTP Server 端口文件 | `.agent_port`/`.config_port`/`.data_port`/`.module_port`/`.theme_port`/`.core_port` | plugins .exe | 端口文件格式变更需通知 plugins |
| `PluginRunner.runOnce(timeout)`（超时 kill 子进程，T4） | `plugin/plugin_runner.dart`（**core/agent/data 三副本同步**） | core-data（CLI 数据源）/ core-agent / core-data 子包 | 副本必须三处同步，diff 仅差标记注释 |
| `PythonSession`（stdio JSON Lines 常驻会话，T5） | `plugin/python_session.dart` | 数据源/工具常驻场景 | 协议/终止语义变更需广播 |
| `DataFileService.downloadFile/downloadFiles`（T8a） | `services/data_file_service.dart` | renderer（文件导出 UI）/ 消费方 | 返回 `Result<String>`；签名变更需通知 renderer |

## 4. 规则（本 OWNER 内必须遵守）

- `core/` 是纯 Dart，禁止引用 Flutter Widget。
- 所有公开 Service 方法返回 `Result<T>`，不抛异常。
- 子包间通过公开 barrel 交互，禁止反向依赖。

## 5. 验收标准

- 改完必须：`cd evg-base/lib/core && dart test` 通过；`AppError`/`Result` 改动需全量 `flutter test` 无回归。

## 6. 引用索引

- 心智模型：`evg-base/lib/core/CLAUDE.md`
- 模块说明：`evg-base/lib/core/README.md`
- 上层职责书：根 `AGENT.md`
