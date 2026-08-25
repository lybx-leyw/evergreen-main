---
name: core-data
role: Evergreen 上游 core/data 子包 OWNER
scope: evg-base/lib/core/data/
parent: core
---

# AGENT.md — core-data 职责书

> 本文件是「谁负责这里」的职责书。技术原理见同目录 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/core/data/`
- 一句话定位：数据谱仪器——`DataOrchestrator` + 缓存 + 数据源注册 + `DataHttpServer`。

## 2. 边界与红线

- ✅ 可以：改 `data/` 内一切实现；新增数据源类型、缓存策略。
- ❌ 禁止：引用 Flutter Widget；改动其他子包；绕过 `DataOrchestrator` 直连 HTTP（renderer 同进程调数据应走 Riverpod，不绕 HTTP）。
- ⚠️ 需协调：数据源注册契约（scraper stdout 顶层必须是 Map，列表型包 `{"items": [...]}`）变更需通知 plugins。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `DataOrchestrator.get/register/refresh` | `orchestrator.dart` | renderer（data_dashboard） | 签名变更需通知 renderer |
| `DataOrchestrator.registerStream/streamOf/streamByName` | `orchestrator.dart`（T3） | renderer（html_modle subscribe 事件驱动） | 流式契约变更需通知 renderer |
| `DataOrchestrator.registerFile/fileOf/fileByName` | `orchestrator.dart`（T8a） | renderer（文件导出） | 文件声明契约变更需通知 renderer |
| `DataType<T>`（含 `sessionProviderId`/`fallback`） | `type.dart` | renderer + plugins | 类型契约变更需广播 |
| `SessionProvider`/`SessionCoordinator` | `session_provider.dart`（T2） | renderer（zju 接入）/ 任何需登录数据源 | 登录锁/重登语义变更需广播 |
| `DataHttpServer`（含 `/data/stream/:name`、`/data/events` SSE） | HTTP（`.data_port`） | plugins .exe / renderer | 端点变更需通知 plugins |
| `registerDataSourcesFromManifest` | `register_data_source.dart` | plugins（热加载） | stdout Map 契约变更需通知 plugins |
| `DataSourceManifest`（auth/stream/file/process 增强，T1） | `plugin/data_source_manifest.dart` | plugins（manifest 作者） | 新字段缺省零行为变化；字段变更需通知 plugins |
| `FileEntry`/`extractFileEntries` | `file_entries.dart`（T8a） | renderer（文件导出） | 解析形态变更需通知 renderer |

## 4. 规则（本 OWNER 内必须遵守）

- 纯 Dart，禁止 Flutter 依赖。
- 数据源 stdout 顶层必须是 `Map<String, dynamic>`（平台统一契约）。
- 同进程消费数据走 Riverpod `dataOrchestratorProvider`，禁止 HTTP 绕圈。

## 5. 验收标准

- 改完必须：`cd lib/core/data && dart test` 通过；数据契约变更需全量 `flutter test` 无回归。

## 6. 引用索引

- 心智模型：`CLAUDE.md`
- 模块说明：`README.md`
- 上层职责书：`../AGENT.md`
