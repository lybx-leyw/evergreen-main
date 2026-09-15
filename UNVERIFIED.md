# 未验证文件清单（待一起 debug）

| 元信息 | 值 |
| --- | --- |
| 状态 | **大部分已验证**（2026-09-15 环境恢复后补测；见 §0） |
| 日期 | 2026-09-15 |
| 范围 | 文件型插件（`file-source`）接线改动 |
| 方案 | `evg-base/docs/plugin-registry/file-source-plugin-plan-v1.md` |

---

## 0. 补测结果（2026-09-15 环境恢复后）

环境一度恢复，**renderer 层已补测**，并抓到 4 个真实问题：

| 测试 | 结果 |
| --- | --- |
| `test/renderer/file_source_list_test.dart`（U1/U5） | ✅ **5/5 通过** |
| `test/renderer/file_source_wiring_test.dart`（U2/U3 编译冒烟 + 行为） | ✅ **4/4 通过** |
| `test/core/data/data_source_timeout_test.dart`（环境探活） | ✅ 11/11 |
| 嵌套包 `lib/core` | ✅ 133/133 |

### debug 中抓到的真实问题（均已修复）

| # | 问题 | 性质 | 修复 |
| --- | --- | --- | --- |
| **B1** | **`buildStatic` 写在了 `FileSourceSlot`（Widget）上，而它属于 `DataSourceSlotState`（State）** | 🔴 **真实结构 bug**——`context` 不存在、slot 无法工作 | 重构为 `Widget.createState()` + `_FileSourceSlotState extends DataSourceSlotState<FileSourceSlot>`（对齐 `CardListSlot` 既有模式） |
| B2 | widget 测试 `pumpAndSettle` **永久卡死** | 测试 bug——下载中 `LinearProgressIndicator` 在未知 total 时是无限动画 | 改 `pump()` + 自定义 `pumpUntil()` 轮询 |
| B3 | widget 测试里做**真实 HTTP**，永不完成 | 测试 bug——`testWidgets` 在 fake-async zone，真实 socket 回调不被推进 | 注入 `FakeDownloadService extends DataFileService`（真实下载链路由 core 测试覆盖） |
| B4 | `find.textContaining('已缓存')` 匹配到 2 个 widget | 测试 bug——条目名与副标题撞词 | 条目改名 + 断言用 `'已缓存 ·'` |

> **B1 印证了这份清单的价值**：若只跑 `dart analyze` 或只做静态检查，这个 bug 会被
> 85 个假错误淹没而漏掉；是**根上下文编译冒烟测试**把它抓出来的。

> **为什么有这份清单**：本轮开发期间沙箱环境出现两个障碍，导致 **renderer 层
> 的改动无法验证**。core 层全部已验证（见下方对照）。此清单用于集中记录
> 「写了但没跑过」的文件，供环境恢复后一起 debug。

---

## 1. 环境障碍（均有实证）

| # | 障碍 | 证据 | 后果 |
| --- | --- | --- | --- |
| E1 | **`lib/renderer/**` 与 `lib/core/data/**` 是嵌套子包**，其 analyzer 上下文无法解析依赖 | A/B：**未改动**的 `file_export_bar.dart` 也有 **55 个** `uri_does_not_exist`（连 `package:flutter/material.dart` 都找不到）；`register_data_source.dart` 在 HEAD 版本就有 8 个同类假错误 | 这些目录的 `dart analyze` **不可信**（假错误淹没真错误） |
| E2 | **根 `flutter test` 被 SIGKILL** | 连**已知能过**的 `test/core/data/data_source_timeout_test.dart` 也 SIGKILL；累积 30 个僵尸 dart 进程，`pkill -9` 无效 | **跑不了 widget 测试**，也跑不了根上下文回归 |

**恢复后请先确认 E2 已解除**（`flutter test` 能跑通既有测试），再执行第 3 节。

---

## 2. 未验证文件

| # | 文件 | 类型 | 未验证原因 |
| --- | --- | --- | --- |
| U1 | `.../components/shared/file_source_list.dart` | 选择性下载 UI 组件 | ✅ **已验证**（widget 5/5） |
| U2 | `.../components/shared/file_opener.dart` | 平台「打开文件」服务 | ✅ **已验证**（冒烟 3/3，含 Err 分支） |
| U3 | `.../components/data/file_source_slot.dart` | slot（接线 U1 + U2） | ✅ **已验证**（修复 B1 后冒烟通过） |
| U4 | `.../v4_modle/_registrations.dart` | 注册 `file-source` | 🟡 **未跑端到端**（仅确认注册符号编译通过） |
| U5 | `test/renderer/file_source_list_test.dart` | widget 测试 | ✅ 已跑通 5/5 |
| U6 | `lib/app_bootstrap.dart` | 启动接线（文件型扫描 + 缓存维护） | 🟡 **未跑端到端**（仅 `dart analyze` 0 error/0 warning） |

### 仍未验证（2 项）

- **U4/U6 端到端**：需要真机/真插件目录才能跑通「启动扫描 → 注册 → slot 渲染 → 下载 → 打开」全链路。环境仍不稳定（consolidated 回归中途 harness 报 PTY/动态库错误）。
- **U3 的父类降级行为**（拉取失败保留静态 config 不白屏）：依赖 `DataSourceSlot` 既有实现，未单独测。

### 2.1 已排除的疑点（debug 时可跳过）

- **U4 的 import 顺序**：已按字母序修正，`dart analyze` 复查后只剩 1 条 **HEAD 既有的** `directives_ordering`（A/B 证实非本轮引入）。
- **U2 放 renderer 而非 core**：`url_launcher` 是 renderer 包依赖，core 包未声明（实测 core 上下文报 2 个 `uri_does_not_exist`）。放 renderer 是刻意为之，非疏漏。
- **U3 早期版本的 `ComponentContext.maybeOf()`**：系我臆造的不存在 API，**已修正**为 `ScaffoldMessenger.maybeOf(context)`。

---

## 3. 恢复后的验证命令

```bash
# 0) 先确认 E2 已解除
cd evg-base && flutter test test/core/data/data_source_timeout_test.dart

# 1) 编译检查（根上下文才可信；别在嵌套子包目录里跑 analyze）
cd evg-base && flutter analyze \
    lib/renderer/components/shared/file_source_list.dart \
    lib/renderer/components/shared/file_opener.dart \
    lib/renderer/templates/v4_modle/components/data/file_source_slot.dart \
    lib/renderer/templates/v4_modle/_registrations.dart

# 2) widget 测试
cd evg-base && flutter test test/renderer/file_source_list_test.dart

# 3) 既有回归（确认没破坏 audio/video 等兄弟 slot 注册）
cd evg-base && flutter test test/core/data/ test/scraper/p5_runtime_register_test.dart
```

---

## 4. debug 检查清单（逐条确认）

### U1 `FileSourceList`
- [ ] 编译通过（无 error）
- [ ] 空列表 → 显示 `emptyHint`
- [ ] **已缓存项**（`path`）：显示「已缓存 · 大小」+ 打开按钮，且**无勾选框**
- [ ] **待下载项**（`url`）：有勾选框，副标题「待下载 · 大小」
- [ ] 勾选后出现「下载选中 (n)」；全选/取消全选切换正确
- [ ] 点击下载 → 文件落盘到 `targetDir` → 状态转「已下载」
- [ ] 进度：`onProgress` 驱动 `LinearProgressIndicator`（未知 total 时为不确定态）
- [ ] 串行多选：逐项 idle → downloading → done/failed
- [ ] 失败项显示错误文案，且**不阻断后续项**

### U2 `openLocalFile`
- [ ] 路径为空 → `Err`
- [ ] 文件不存在 → `Err`
- [ ] 存在的文件 → 调起系统默认应用；无默认应用时返回 `Err` 而非崩溃
- [ ] 安卓：确认 `url_launcher` 的 Intent 路径可用

### U3 `FileSourceSlot`
- [ ] 声明 `{"type":"file-source","config":{"dataSource":{"endpoint":"orch://x"}}}` 能渲染出列表
- [ ] 拉取失败 → **保留静态 config，不白屏**（父类降级行为）
- [ ] 点击已缓存项 → 调起 `openLocalFile`
- [ ] 落盘目录确为 `greenixFileCacheDir`（与 Python 侧 `evg_lib.download` **同目录** ⇒ F1 共享）

### U4 `_registrations.dart`
- [ ] `file-source` / `file-list` / `files` 三个名字都能解析到 slot
- [ ] 兄弟 slot（`video-player`/`audio-player`/…）注册未受影响

### U6 `app_bootstrap.dart`
- [ ] 启动日志出现 `FileSource 扫描完成`（有文件型插件时）
- [ ] 启动日志出现 `文件缓存维护完成`（有清理时）
- [ ] 缓存维护失败**不阻断启动**
- [ ] 既有 25 个 `data-source` 插件**零行为变化**

---

## 5. 已验证对照（无需 debug）

| 层 | 证据 |
| --- | --- |
| core 解析/注册/超时/越界/清理 | 嵌套包 **133/133** + 根 **174/174**（E2 前） |
| `evg_lib.download`（F1） | Python 侧 10 组用例，含真实 HTTP 服务器计数验证「同 HEAD 绝不重下」 |
| P0 流式下载 | 7 应用例（含「下载进行中 `.part` 已存在」证明边读边写） |
| P1 类型体系 | 21 应用例 |
| P4 缓存配额 | 11 应用例 |
| 解析契约 `parseFileSourceEntries` | 10 应用例 |

---

## 6. debug 提示：两个容易浪费时间的坑

1. **别在 `lib/core/**` 或 `lib/renderer/**` 目录里直接跑 `dart analyze`** —— 它们是嵌套子包，会产出大量假错误（E1）。用**根上下文** `flutter analyze <file>`。
2. **嵌套子包内必须用相对 import** —— `lib/core/data/` 下用 `package:evergreen_base/...` 会失败（实测 `No such file or directory`），应写 `../utils/greenix_path.dart`。而 `lib/renderer/` 下**反而**沿用 `package:` 导入（既有约定，如 `file_export.dart`）。两边规则不同，改文件前先看邻居怎么写。

---

## 7. 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-09-15 | 首版。记录 U1–U6 未验证文件、E1/E2 环境障碍、验证命令与 debug 清单 |
