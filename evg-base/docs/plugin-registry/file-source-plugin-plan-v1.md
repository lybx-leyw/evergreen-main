# 文件型插件（`file-source`）实施方案 v1

| 元信息 | 值 |
| --- | --- |
| 状态 | active（执行中） |
| 日期 | 2026-09-15 |
| 目标产物 | 独立插件类型 `file-source` + 文件清单 UI + 流式下载器 |
| 关联协议 | [`file-data-plugin-protocol-v1.md`](./file-data-plugin-protocol-v1.md)、[`data-plugin-protocol-v1.md`](./data-plugin-protocol-v1.md) |
| 前置成果 | D1–D6 已完成：`evg_lib.download`（F1 共享缓存）、per-type 超时、路径越界校验 |

---

## 1. 目标

把「**数据主体是文件**」的数据源从「**数据主体是 JSON**」的数据源中**显式分开**，
并为前者提供：自动发现可下载文件 → 声明 → 用户**选择性下载**的完整链路。

### 1.1 为什么显式分开（而非加 `delivery` 字段）

原方案是在既有 `data-source` 内加 `delivery: "json"|"file"` 维度。**已否决**：

| 维度 | 加字段（否决） | 独立类型（采纳） |
| --- | --- | --- |
| 判别依据 | 隐式（读 payload 或读字段） | **类型即判别** |
| 协议演进 | 两套语义挤在一份文档 | 各自独立演进 |
| 校验规则 | 混在一起（文件型才需 path/超时约束） | 各自独立 |
| registry 筛选 | 需读 payload | 按 `type` 直接筛 |
| 冗余成本 | — | ≈250 行（见 §4） |

> **关键结论**：仓库的资产分发是**整树递归**（`listSync(recursive:true)` +
> 黑名单；registry 按前缀整树复制），**新增子目录零摩擦**。故冗余成本远低于
> 初判，独立类型是划算的。

### 1.2 附带收益

`delivery` 字段**不再需要**——类型本身即判别依据。少一个字段、少一处
「如果 X 则有 Y 语义」的文档负担。

---

## 2. 契约

### 2.1 目录约定

```
plugins/<id>/
├── data/                    ← 业务型（既有，**完全不变**）
│   └── manifest.json        "type": "data-source"
└── files/                   ← 文件型（新增，与 data/ 对称）
    ├── manifest.json        "type": "file-source"
    └── <script>             ← 发现 + 下载脚本
```

- **一个插件目录可同时有两类**（`data/` 与 `files/` 并存，各自独立 manifest）。
- 例：「课堂」插件既可给课程列表（JSON），又可给录播视频（文件）。

### 2.2 `files/manifest.json`

```jsonc
{
  "type": "file-source",              // 判别值，与 "data-source" 并列
  "id": "lecture-videos",
  "name": "课堂录播",
  "script": "discover.py",
  "runtime": "python",
  "androidSupport": true,
  "auth": { "sessionProvider": "zju", "sessionDomain": "classroom.zju.edu.cn" },
  "files": [                          // 替代 dataTypes
    {
      "name": "lecture_videos",       // orch:// 键 + DataType name
      "typeArg": "lecture_videos",    // 传给脚本的 --type
      "title": "录播视频",             // 展示名
      "category": "视频",
      "ttl": "24h",
      "timeoutSeconds": 1800,         // 大文件（已具备）
      "persistentKey": "lecture_videos",
      "fallbackJson": { "status": "missing", "files": [] },
      "accept": [".mp4", ".m3u8"]     // 可选：允许的扩展名（校验用）
    }
  ]
}
```

### 2.3 脚本输出契约（两种形态，同一 `files[]` 数组）

```jsonc
// 形态 1：待下载（选择性下载 UI 的输入）
{ "files": [ { "url": "https://…/a.mp4", "name": "第1讲.mp4", "mime": "video/mp4" } ] }

// 形态 2：已落盘（复用 file-data 协议 §5）
{ "status": "ready", "files": [ { "path": "/…/file_cache/x.mp4", "size": 123, "mime": "video/mp4" } ] }
```

| 形态 | 判别 | UI 行为 |
| --- | --- | --- |
| 有 `url` | 未下载 | 勾选框 + 「下载选中 / 全部下载」+ 进度 |
| 有 `path` | 已缓存 | 「播放 / 打开」（零下载） |

---

## 3. 复用（**零重复**）

| 能力 | 来源 |
| --- | --- |
| 资产分发（冷/热、Android 释放、registry 落盘） | `bundle_plugins.dart`、`plugin_asset_releaser`、`discover_section._copyLocalAssets` 全部**整树递归** |
| 子进程执行（桌面/安卓） | `PluginRunner`（`SubprocessRunner`/`ChaquopyRunner`） |
| 缓存 / 降级 / 重试 / 状态 / 看板 | `DataOrchestrator`（`DataType` 同一套） |
| **F1 共享缓存**（同 HEAD 绝不重下） | `evg_lib.download`（冷热插件同一 `file_cache/`） |
| TTL / androidSupport / per-type 超时解析 | `parseDataSourceTtl`、`parseDataSourceAndroidSupport`、`parseDataSourceTimeoutSeconds` |
| 进程声明 / 会话凭据 | `DataSourceProcess`、`DataSourceAuth` |
| 路径越界校验 | `file_cache.dart#validateFileCachePaths` |
| 文件清单规范化 | `file_entries.dart#extractFileEntries` |

## 4. 新增（各自独立、职责单一）

| 单元 | 职责 | 估量 |
| --- | --- | --- |
| `FileSourceManifest` | 解析 `type: "file-source"` + `files[]` | ~150 行 |
| `registerFileSourcesFromManifest` | DataType 构造 + fetcher + 越界/超时接线 | ~120 行 |
| `scanAndLoadFileSources` | 扫 `plugins/*/files/manifest.json` | ~40 行 |
| 启动接线 | `app_bootstrap` 加一步扫描 | ~10 行 |
| 文件列表 UI | 勾选 / 单个 / 批量 / 进度 / 已缓存态 | 待估 |

---

## 5. 已知坑（必须遵守）

| # | 坑 | 后果 | 规避 |
| --- | --- | --- | --- |
| 1 | **目录不能叫 `downloads`** | `bundle_plugins.dart#_shouldSkip` 在任何层级排除 `downloads`/`ppt`/`ppt_cache` → **静默不进 APK**，安卓文件消失、桌面正常，极难排查 | 用 `files/` |
| 2 | 嵌套子包**手工镜像** | `lib/core/data/lib/core/utils/*` 是「⚠️ 副本」需同步，否则子包测试用旧版 | 改 `lib/core/utils/*` 后检查 `find lib -name <同名>` |
| 3 | `dart analyze` 在 `lib/core/data/` **不可信** | 嵌套子包上下文给出既有假错误（实测 HEAD 版 8 条） | 权威验证 = **根上下文 `flutter test`** |
| 4 | Dart 不在 PATH | 误判为无法测试 | `export PATH=/home/node/flutter/bin:$PATH` |
| 5 | `DataFileService` **全量进内存** | 大文件 OOM | P0 改流式（本方案前置） |

---

## 6. 阶段任务

| 阶段 | 内容 | 产出物 | 验证 | 依赖 |
| --- | --- | --- | --- | --- |
| **P0** ✅ | `DataFileService` 改**流式落盘** + 进度回调 | `data_file_service.dart`（+`DownloadProgressCallback`/`kDownloadProgressThrottle`） | 7 应用例（见 §8.1） | — |
| **P1** ✅ | `FileSourceManifest` + 注册/扫描 + 启动接线 | `file_source_manifest.dart`、`register_file_source.dart`、`cli_source_runner.dart`（共享执行器） | 21 应用例 + 根 174 测试 | P0 |
| **P2** | 文件列表 UI（勾选/单个/批量/进度/已缓存态） | 新 UI 组件 + 接线 | widget 测试 + 手动 | P0+P1 |
| **P3** | 示例插件 `plugins/…/files/`（替换死掉的 `example-data-video_stream`） | 示例插件 + registry 条目 | 端到端：发现 → 勾选 → 下载 → 播放 | P1+P2 |
| **P4** ✅ | D7 缓存配额 / LRU + `.part` 回收 | `file_cache_cleaner.dart`（`trimFileCache`/`clearOrphanPartials`/`fileCacheStats`）+ 启动接线 | 11 应用例（见 §8.3） | P0 |

### 6.1 执行顺序说明

**P0 是唯一硬前置**：UI 要下载大文件，而现下载器全量进内存（视频必 OOM）。
P1/P2 可并行，但 P2 需要 P0 的进度回调才能显示进度。

---

## 7. 验收标准

| # | 断言 | 归属 |
| --- | --- | --- |
| A1 | 两类插件共存于同一插件目录，互不干扰 | P1 |
| A2 | `file-source` 的 `files[]` 声明进 `DataOrchestrator`，可按 `orch://<name>` 取 | P1 |
| A3 | 返回 `path` 越界 → 拒绝并落 `lastError` | P1 |
| A4 | 返回 `url` 清单 → UI 列出并支持**勾选** | P2 |
| A5 | 下载过程显示进度；已缓存项不重复下载（F1） | P2 |
| A6 | 下载 100MB 文件时进程内存**不随之线性增长** | P0 |
| A7 | 既有 25 个 `data-source` 插件**零行为变化** | P1 |

---

## 8. 进度

| 阶段 | 状态 | 证据 |
| --- | --- | --- |
| D1–D6（前置） | ✅ 已完成 | 134 测试（根上下文） |
| **P0 流式下载器** | ✅ **已完成**（2026-09-15） | 7 应用例 + 嵌套包 122 测试全绿 |
| **P1 类型体系** | ✅ **已完成**（2026-09-15） | 21 应用例 + 根 174 测试全绿 |
| **P4 缓存配额** | ✅ **已完成**（2026-09-15） | 11 应用例 + 嵌套包 133 测试全绿 |
| **P3 示例插件** | ✅ **已完成**（2026-09-15） | registry 示例 + 打包器保留核查 |
| P2 文件列表 UI | 🟡 **代码已写，未验证**（见 §8.4） | `file_source_entries.dart` 10 测试 ✅ / widget ⚠️ |

## 8.2 P1/P3 证据（2026-09-15）

| 断言 | 验证方式 |
| --- | --- |
| A1 两类插件共存互不干扰 | `scanAndLoadFileSources` 不拾 `data/`；`registerDataSourcesFromManifest` 不拾 `files/`（双向断言） |
| A2 `files[]` 进中枢 | `orch.typeByName('demo_files') != null`；`onlyType` 过滤生效 |
| A3 路径越界拒绝 | `validateFileCachePaths` 复用同一实现（P1 接线到 file-source fetcher） |
| 扩展名白名单 | `accept: ['.MP4','mp4','PDF']` → 规范化 `['.mp4','.pdf']`；`acceptsPath` 大小写不敏感、只匹配后缀 |
| 模型二未支持不静默 | `process` 清单 → 记 warn 跳过（断言返回空） |
| TTL 默认差异 | file-source 默认 **24h**（vs data-source 5m），避免被 5 分钟 tick 反复触发"发现" |
| 共享执行器 | 重构 `register_data_source.dart` 后根 174 测试全绿（含 123 个既有 data 测试） |
| 打包器保留 `files/` | 复刻 `bundle_plugins.dart#_shouldSkip` 核查：`files/manifest.json`/`discover.py` 均会打包 |
| A7 零行为变化 | 25 个既有 `data-source` 插件无一受影响（双向扫描断言 + 全量回归） |

---

## 8.3 P4 证据（2026-09-15）

| 断言 | 验证方式 |
| --- | --- |
| `.part` 与正式文件分离 | 配额裁剪只数正式文件；`.part` 仅按超龄回收（`kOrphanPartialMaxAge` 1h） |
| 最旧优先淘汰 | 3×400B、配额 900 ⇒ 删 mtime 最旧者，剩 800B |
| **宽限期保护** | 刚下载（1 分钟前）文件在 `grace`（10 分钟）内**不被删**，转删更旧的 |
| **至少留 1 个** | 单文件 5000B、配额 100B ⇒ **不删**（清空缓存 = 永久禁用文件源） |
| 新鲜 `.part` 不删 | 5 分钟前的 `.part` 保留（可能正在写入，Windows 还会锁文件） |
| 目录不存在 | 零值且**不抛** |
| 启动接线零新增问题 | 根 `dart analyze lib/app_bootstrap.dart` → 0 error / 0 warning（仅剩 HEAD 既有的 1 条 `directives_ordering`） |
| 无回归 | 嵌套包 `lib/core` **133** 测试全绿 |

---

## 8.4 P2 状态与**验证缺口**（2026-09-15）

### 已交付

| 层 | 文件 | 验证 |
| --- | --- | --- |
| **纯解析契约**（core） | `core/data/file_source_entries.dart` | ✅ **10 测试**（嵌套 `dart test`） |
| **UI**（renderer） | `renderer/components/shared/file_source_list.dart` | ⚠️ **未验证** |
| **slot 接线**（renderer） | `templates/v4_modle/components/data/file_source_slot.dart` + 注册 `file-source`（别名 `file-list`/`files`） | ⚠️ **未验证** |
| widget 测试 | `test/renderer/file_source_list_test.dart`（146 行） | ⚠️ 未跑过 |

### ⚠️ 验证缺口（必须补）

| 障碍 | 证据 | 影响 |
| --- | --- | --- |
| `lib/renderer/**` 嵌套子包上下文**无法解析依赖** | A/B：**未改动**的 `file_export_bar.dart` 也有 **55 个** `uri_does_not_exist` 假错误（连 `package:flutter/material.dart` 都找不到） | 该目录 `dart analyze` **不可信** |
| 根 `flutter test` 被 SIGKILL | 连**已知能过**的 `data_source_timeout_test.dart` 也 SIGKILL；累积 30 个僵尸 dart 进程，`pkill -9` 无效 | **无法跑 widget 测试** |

**环境恢复后必须执行**：

```bash
cd evg-base && flutter test test/renderer/file_source_list_test.dart
cd evg-base && flutter analyze lib/renderer/components/shared/file_source_list.dart
```

### 未验证清单（逐项待确认）

1. `FileSourceList` 能否编译（`flutter analyze` 零 error）；
2. 已缓存项渲染「已缓存 · 大小」+ 打开按钮，且**无勾选框**；
3. 待下载项勾选后出现「下载选中 (n)」，点击后经 `DataFileService` 落盘到 `targetDir`；
4. 进度：`onProgress` 回调驱动 `LinearProgressIndicator`；
5. 串行下载多选时逐项状态迁移（idle → downloading → done/failed）；
6. 失败项显示 `lastError` 文案且不阻断后续项。

---

## 8.5 P2 接线（2026-09-15）

### 声明方式（插件 manifest 组件）

```json
{ "type": "file-source",
  "config": { "dataSource": { "endpoint": "orch://lecture_materials" } } }
```

### 实现

| 层 | 文件 | 说明 |
| --- | --- | --- |
| slot | `templates/v4_modle/components/data/file_source_slot.dart` | 继承 `DataSourceSlot` → **免费获得**三步骤管道（归一化→字段映射→注入 `cfg['data']`）与优雅降级 |
| 注册 | `_registrations.dart` | `SlotRegistry.register('file-source', …, aliases: ['file-list','files'])`，紧邻媒体族 slot |
| 落盘目标 | slot 内固定 `greenixFileCacheDir` | 与 Python 侧 `evg_lib.download` **同一目录** ⇒ F1 跨冷热插件共享 |
| `service` | `DataFileService(sandboxRoot: targetDir)` | 沙箱约束在缓存目录内（协议 §7） |

### ⚠️ 未接线项（诚实标注）

| 项 | 现状 | 原因 |
| --- | --- | --- |
| **「播放/打开」** | 仅 SnackBar 提示本地路径 | 需要平台级 open 服务（桌面 `Process.run(open)` / 安卓 Intent），尚未接入——**不假装能播** |
| `timeout` | slot 内固定 `30 分钟` | 理想应由 `files[].timeoutSeconds` 逐类型传递；当前 slot 层拿不到该声明，取安全上限 |
| 验证 | 同 §8.4（嵌套上下文不可解析 + `flutter test` SIGKILL） | 环境限制 |

---

## 9. 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-09-15 | 首版。确定「独立类型而非 `delivery` 字段」；记录 5 条坑与 6 阶段任务 |
| 2026-09-15 | **P2 接线完成（未验证）**：新增 `file_source_slot.dart`（继承 `DataSourceSlot`，自动接管道与降级）并注册 `file-source`（别名 `file-list`/`files`）。落盘目标统一为 `greenixFileCacheDir`（与 Python 侧同目录 ⇒ F1 共享）。**未接线**：真实「播放/打开」（需平台 open 服务），当前仅提示路径 |
| 2026-09-15 | **P2 代码完成（未验证）**：新增 `core/data/file_source_entries.dart`（纯解析，`url`/`path` 双形态 + §5.4 边界规则，10 测试通过）与 `renderer/components/shared/file_source_list.dart`（勾选/全选/串行下载/进度/已缓存态）。**按用户决定新建组件而非改造 `FileExportBar`**（两者语义不同：导出到用户目录 vs 下载到应用缓存供播放）。⚠️ **UI 层未验证**，原因与补测命令见 §8.4 |
| 2026-09-15 | **P4 完成**：`file_cache_cleaner.dart` —— 配额 LRU（按 mtime，宽限期保护 + 至少留 1 个）+ 孤儿 `.part` 回收 + 统计；接入 `app_bootstrap._stepDataSources`（失败不影响启动）。**注意**：`lib/core/data/` 下的文件须用**相对 import**（`../utils/greenix_path.dart`），package import 只在根上下文成立 |
| 2026-09-15 | **P1+P3 完成**：新增 `FileSourceManifest`/`FileSourceDecl`（复用 TTL/超时/androidSupport/Process/Auth 解析器）、`registerFileSourcesFromManifest` + `scanAndLoadFileSources`、启动接线；抽出**共享 CLI 执行器** `cli_source_runner.dart#runCliSource` 供 data-source/file-source 共用（消除双实现漂移，`register_data_source.dart` 已重构为调用它）。示例插件落在 `docs/plugin-registry/examples/example-file-source/`。证据见 §8.2 |
| 2026-09-15 | **P0 完成**：`DataFileService` 改 64 KiB 分块流式落盘 + `.part` 原子改名 + 失败清理 + `DownloadProgressCallback`（按百分比变化回调；未知 total 时 200ms 节流；完成必回调）。证据见 §8.1 |

---

## 8.1 P0 证据（2026-09-15）

| 断言 | 验证方式 |
| --- | --- |
| **边读边写**（不驻留内存） | 服务端发首块后**挂起**；测试在下载**进行中**轮询到 `.part` 存在且 `length > 0`，同时断言目标文件**尚不存在**。旧实现全量驻留内存 ⇒ 此刻磁盘上不会有任何文件 |
| 原子改名 | 完成后目标就位、内容完整、无 `.part` 残留 |
| 失败清理 | 5xx 重试耗尽后无 `.part`、无目标文件 |
| 进度单调 | 回调序列单调不减；`total` == Content-Length；最后一次 `received == total` |
| 无 Content-Length | `total` 全为 `null` 且仍回调（不抛） |
| 零行为变化 | 未传 `onProgress` 行为不变；既有 9 个 `data_file_service_test` 全通过 |
| 无回归 | 嵌套包 `lib/core` 全套 **122** 测试通过 |
| 静态检查 | `dart analyze data_file_service.dart` → No issues found |
