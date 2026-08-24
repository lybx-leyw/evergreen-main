---
name: core-services
role: Evergreen 上游 core/services 子包 OWNER
scope: evg-base/lib/core/services/
parent: core
---

# AGENT.md — core-services 职责书

> 本文件是「谁负责这里」的职责书。技术原理见同目录 `README.md`（暂无 CLAUDE.md）。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/core/services/`（Dart 服务 + `services.dart` barrel + README）
- 一句话定位：平台级基础服务——`CoreHttpServer`、OCR 管线、DeepSeek OCR、PDF 翻译、GitHub 克隆/星标、插件安装、应用更新、UI 操作日志。

### 主要文件

| 文件 | 职责 |
|------|------|
| `services.dart` | barrel 导出（纯 Dart 服务；含 Flutter 依赖的服务直接 import） |
| `core_http_server.dart` | 微服务网格（REST 端点） |
| `ocr_pipeline.dart` | 两级 OCR 降级管线 + 并行 + 就绪诊断 |
| `deepseek_ocr_service.dart` | DeepSeek Vision API 封装 |
| `pdf_translate_service.dart` | PDF 翻译 |
| `translate_queue.dart` | 翻译队列 |
| `github_clone.dart` / `github_metadata.dart` / `github_stars.dart` | GitHub 集成 |
| `plugin_installer.dart` | 插件生命周期管理 |
| `release_downloader.dart` | 发布下载 |
| `update_service.dart` | 应用更新检查 |
| `ui_operation_log.dart` | UI 操作日志 |

## 2. 边界与红线

- ✅ 可以：改 `services/` 内一切实现；新增服务。
- ❌ 禁止：引用 Flutter Widget；改动其他子包；OCR/翻译绕过降级管线。
- ⚠️ 需协调：`CoreHttpServer` 端点变更需通知 plugins；`PluginInstaller` 安全模型（签名/沙箱/崩溃监控）变更需广播。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `CoreHttpServer`（8 端点） | HTTP（`.core_port`） | plugins .exe | 端点变更需通知 plugins |
| `PluginInstaller.install/uninstall` | `plugin_installer.dart` | renderer（marketplace） | 签名变更需通知 renderer |
| `OcrPipeline.recognizeFile/Url` | `ocr_pipeline.dart` | renderer | 降级行为变更需广播 |
| `UpdateService.checkForUpdate` | `update_service.dart` | app-shell | 更新源变更需通知 app-shell |

## 4. 规则（本 OWNER 内必须遵守）

- 纯 Dart，禁止 Flutter 依赖。
- OCR 走两级降级（DeepSeek → Tesseract），失败返回 null 或空字符串，不抛异常。
- `PluginInstaller` 遵守 SHA-256 签名 + ZIP slip 防护 + 沙箱隔离。

## 5. 验收标准

- 改完必须：相关 `dart test` / `flutter test` 通过；`CoreHttpServer` 端点变更需全量回归。

## 6. 引用索引

- 模块说明：`README.md`
- 心智模型：暂无 CLAUDE.md（可待补齐）
- 上层职责书：`../AGENT.md`
