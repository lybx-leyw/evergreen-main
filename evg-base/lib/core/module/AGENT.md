---
name: core-module
role: Evergreen 上游 core/module 子包 OWNER
scope: evg-base/lib/core/module/
parent: core
---

# AGENT.md — core-module 职责书

> 本文件是「谁负责这里」的职责书。技术原理见同目录 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/core/module/`（全部 Dart 源文件、测试、内置模块与示例；gitignore 忽略的工具链产物不作为资产依据）
- 一句话定位：模块描述符 / 注册表 / 加载器 / 进程管理 + 六格契约（lattice）/ 权限 / sidecar / 插件市场（发现 / 审核 / 清单）。

## 2. 边界与红线

- ✅ 可以：改 `module/` 内一切实现；新增模块类型、市场源、审核规则。
- ❌ 禁止：引用 Flutter Widget；改动其他子包；绕过 `ModuleDescriptor.fromJson` 硬编码路由。
- ⚠️ 需协调：`ModuleDescriptor` 字段变更（如 `modle_route`）会影响 renderer 模板分发；`layout.preset` 是 Map 非 String；市场「id vs 文件夹名」不一致需在扫描层保存真实路径。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `ModuleDescriptor` | `module_descriptor.dart` | renderer | 字段增删需通知 renderer（含 `lattice`/`runtime`） |
| `ModuleRegistry`（register→seal） | `module_registry.dart` | renderer + app-shell | 生命周期变更需广播；`reloadModule`/`unregister` 供设计器热重载 |
| `ModuleHttpServer` | HTTP（`.module_port`） | plugins .exe | 端点（含 `/module/sidecars`）变更需通知 plugins |
| `Lattice` / `RuntimeDescriptor` | `lattice.dart` / `runtime.dart` | renderer + permission | 六格契约与 sidecar 能力沙箱，fail-closed |
| `ResolvedPlugin` | `resolved_plugin.dart` | registry / loader / permission | 单一事实源，模型变更需通知 renderer |
| `PermissionResolver` / `BridgeInterceptor` | `permission.dart` | renderer（bridge） | 权限裁决/审计变更需通知 renderer |
| `PluginManifest` | `plugin_manifest.dart` | renderer（marketplace） | 模型变更需通知 renderer |
| `RegistryPlugin` / `parsePluginRegistry` | `plugin_registry.dart` | renderer（marketplace） | registry 协议变更需通知 renderer |
| `ReviewQueue` / `aggregateReviews` | `plugin_review.dart` | renderer（marketplace） | 审核流变更需通知 renderer |

## 4. 规则（本 OWNER 内必须遵守）

- 纯 Dart，禁止 Flutter 依赖。
- `register → seal` 三段生命周期，seal 后不可变（`List.unmodifiable`）。
- 未知字段静默忽略（容错设计，非 bug）。
- 扫描插件时禁止用单一强类型解析器吞掉所有类型。

## 5. 验收标准

- 改完必须：`cd lib/core/module && dart test` 全量通过；`ModuleDescriptor` 变更需全量 `flutter test` 无回归。

## 6. 引用索引

- 心智模型：`CLAUDE.md`
- 模块说明：`README.md`
- 插件撰写唯一权威参考：`docs/plugin-module.md`
- 六格契约设计上游：`evg-base/docs/m0-lattice-contract-design.md`
- 上层职责书：`../AGENT.md`
