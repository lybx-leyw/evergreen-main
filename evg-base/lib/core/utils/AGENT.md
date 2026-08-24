---
name: core-infra
role: Evergreen 上游 core 基础设施 OWNER（utils + plugin + feedback）
scope: evg-base/lib/core/utils/ + plugin/ + feedback/
parent: core
---

# AGENT.md — core-infra 职责书

> 本文件是「谁负责这里」的职责书。技术原理见同目录各 `README.md`（暂无 CLAUDE.md）。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/core/utils/` + `evg-base/lib/core/plugin/` + `evg-base/lib/core/feedback/`
- 一句话定位：路径/沙箱/Python 环境/资产释放/Token 估算 + PluginRunner + 反馈/截图/Issue 发布。

### 主要文件

| 文件 | 职责 |
|------|------|
| `utils/greenix_path.dart` | 运行时路径管理（路径唯一真理来源） |
| `utils/path_sandbox.dart` | 路径沙箱 |
| `utils/python_env.dart` | Python 环境管理 |
| `utils/plugin_asset_releaser.dart` | 插件资产释放 |
| `utils/file_utils.dart` | 文件管理 |
| `utils/safe_parse.dart` | 安全类型转换 |
| `utils/token_estimator.dart` | Token 估算 |
| `plugin/plugin_runner.dart` | 插件运行器 |
| `feedback/feedback_bar.dart` | 可拖动反馈浮窗入口 |
| `feedback/feedback_dialog.dart` | 反馈表单弹窗 |
| `feedback/feedback_writer.dart` + `github_issue_publisher.dart` | 反馈写入 + Issue 发布 |
| `feedback/screenshot.dart` | 截图 |

## 2. 边界与红线

- ✅ 可以：改 `utils/`/`plugin/`/`feedback/` 内一切实现；新增工具函数。
- ❌ 禁止：引用 Flutter Widget；改动其他子包；`greenix_path` 硬编码相对路径（移动端必须 path_provider）。
- ⚠️ 需协调：`greenix_path.dart` 的 `greenixWorkspaceDir(moduleId)` 是路径唯一真理，UI 侧禁止用宿主 `descriptor.id` 拼工作区路径；`plugin_asset_releaser` 幂等逻辑变更影响 APK 资产释放。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `greenixPath` 系列 getter | `greenix_path.dart` | 全 core + renderer + plugins | 路径语义变更需广播 |
| `PluginRunner` | `plugin_runner.dart` | renderer | 运行器契约变更需通知 renderer |
| `plugin_asset_releaser` | `plugin_asset_releaser.dart` | app-shell | 资产释放逻辑变更需通知 app-shell |

## 4. 规则（本 OWNER 内必须遵守）

- 纯 Dart，禁止 Flutter 依赖。
- 文件系统路径必须以 `greenix_path` / provider 解析，禁止硬编码相对路径。
- 幂等型「一次性释放」逻辑必须校验产物完整性（数量/哈希），不能只看标记存在。

## 5. 验收标准

- 改完必须：相关 `dart test` / `flutter test` 通过；路径语义变更需全量回归。

## 6. 引用索引

- 模块说明：`utils/README.md`
- 心智模型：暂无 CLAUDE.md（可待补齐）
- 上层职责书：`../AGENT.md`
