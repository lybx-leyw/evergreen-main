---
name: core-config
role: Evergreen 上游 core/config 子包 OWNER
scope: evg-base/lib/core/config/
parent: core
---

# AGENT.md — core-config 职责书

> 本文件是「谁负责这里」的职责书。技术原理见同目录 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/core/config/`
- 一句话定位：设置 / 权限 / 插件源 + `ConfigHttpServer`。

## 2. 边界与红线

- ✅ 可以：改 `config/` 内一切实现；新增设置项、权限、插件源。
- ❌ 禁止：引用 Flutter Widget；改动其他子包；在 `initSettings` 之外注册设置项（动态注册走 `ConfigHttpServer.registerSetting`，见下）。
- ⚠️ 需协调：新增配置 key 若需写入 `.greenix/config.json`（Android/scraper 凭证降级路径），必须在对应插件的 `config/config.json` 声明或通过 `ConfigHttpServer.registerSetting` 动态注册，否则 `syncConfigToGreenix()` 不写入。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `initSettings` / `getAllSettings` / `setSetting` | `settings.dart` | renderer（settings_view） | 设置项增删需通知 renderer |
| `getSetting` / `getSettingOrNull` | `config.dart` | renderer + plugins | 读接口变更需广播 |
| `ConfigHttpServer` | HTTP（`.config_port`） | plugins .exe + scraper | 端点变更需通知 plugins |
| `registerSetting` / `unregisterSetting` / `syncConfigToGreenix` | `.greenix/config.json` | scraper（Android 主路径） | 同步行为变更影响凭证 |
| 权限体系 | `permissions.dart` | renderer + module | 权限分级变更需广播 |

## 4. 规则（本 OWNER 内必须遵守）

- 设置项必须通过 `initSettings` 注册，敏感项加 `@Secure()`。
- Android 上关键诊断用 `print`（非 `stderr.writeln`），保证 logcat 可见；禁止 `catch(_){}` 静默吞异常。
- 设置写入必须联动消费方（响应式 Provider），禁止「写 A、读 B」割裂。

## 5. 验收标准

- 改完必须：`cd lib/core/config && dart test` 通过；设置项增删需全量 `flutter test` 无回归。

## 6. 引用索引

- 心智模型：`CLAUDE.md`
- 模块说明：`README.md`
- 上层职责书：`../AGENT.md`
