---
name: platform
role: Evergreen 脚本 / 构建 / 平台壳 OWNER
scope: evg-base/scripts/ + evg-base/tool/ + evg-base/windows/ + evg-base/android/
parent: root
---

# AGENT.md — platform（脚本/构建）职责书

> 本文件是「谁负责这里」的职责书。技术原理见 `scripts/README.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/scripts/` + `evg-base/tool/` + `evg-base/windows/` + `evg-base/android/`
- 一句话定位：Python 管线（含 pdf2zh_next）、打包、Inno Setup、CMake、Chaquopy 安卓壳、CI。

### 主要资产

| 资产 | 位置 | 职责 |
|------|------|------|
| Python 管线 | `scripts/pdf2zh_next/` + 嵌入式 Python（由 `setup_python.cmd` 预装） | PDF 翻译引擎 + OCR 运行时 |
| 安装脚本 | `scripts/installer.iss` / `installer_platform.iss` | Inno Setup 打包 |
| 环境脚本 | `scripts/setup_python.cmd` / `reload.cmd` | Python 环境 |
| 工具脚本 | `tool/`（bundle_plugins / bundle_scripts / gen_template_registry） | 资产打包 / 注册表生成 |
| Windows 壳 | `windows/`（CMake + runner） | Windows 平台 |
| Android 壳 | `android/`（Chaquopy Python） | Android 平台 |

## 2. 边界与红线

- ✅ 可以：改 `scripts/`/`tool/`/`windows/`/`android/` 内一切实现；新增工具脚本、打包流程、CI。
- ❌ 禁止：改动业务代码（core/renderer/plugins）；在 `scripts/python/` 里塞业务逻辑。
- ⚠️ 需协调：`gen_template_registry.dart` 与 `renderer-templates` 的 `templates_index.json` 强耦合；`bundle_plugins.dart` 与 `plugins` 的资产同步；安卓 Chaquopy 桥与 `app-shell` 的路径解析。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `templates_index.json` 生成 | `gen_template_registry.dart` | renderer-templates | 登记格式变更需同步 |
| `assets/plugins_bundle/` 打包 | `bundle_plugins.dart` | plugins | 插件资产变更后必须重跑 |
| Windows 构建 | CMake + Inno Setup | 全仓 | 构建参数变更需广播 |
| Android 构建 | Gradle + Chaquopy | 全仓 | Chaquopy 版本/abiFilter 变更需广播 |
| CI 工作流 | `.github/workflows/` | 全仓 | 流程变更需广播 |

## 4. 规则（本 OWNER 内必须遵守）

- 工具脚本统一放 `tool/`（非 `tools/`），沿用既有结构，不臆造目录。
- 修改 `plugins/` 资产后必须重跑 `bundle_plugins.dart`。
- 安卓构建：Chaquopy 用 `plugins {}` DSL；`abiFilters` 需含 x86_64（模拟器）+ arm64-v8a；`INTERNET` 权限 + `usesCleartextTraffic`。
- Windows 构建：media_kit 需预置正确 MD5 的 mpv/ANGLE 归档；`CMAKE_INSTALL_PREFIX` 遇 `C:/Program Files` 失败需删 CMakeCache 重配置。
- 长时构建（>300s）用 `schtasks` 脱离工具进程组。

## 5. 验收标准

- 改完必须：`flutter build windows` / `flutter build apk` EXIT=0；打包流程改动需实际出包验证。

## 6. 引用索引

- 模块说明：`scripts/README.md`
- 心智模型：根 `CLAUDE.md`
- 上层职责书：根 `AGENT.md`
