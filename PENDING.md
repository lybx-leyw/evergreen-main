# 未竟之事（Remaining Work）

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 日期 | 2026-09-15 |
| 本轮主题 | 文件型插件（`file-source`）：独立类型 + 协议 + 流式下载 + 选择性下载 UI |
| 方案文档 | `evg-base/docs/plugin-registry/file-source-plugin-plan-v1.md` |
| 验证清单 | [`UNVERIFIED.md`](./UNVERIFIED.md) |

---

## A. 必须先补的验证（阻塞项）

| # | 事项 | 为什么 | 命令 |
| --- | --- | --- | --- |
| **A1** | **U4/U6 端到端**：「启动扫描 → 注册 → slot 渲染 → 下载 → 打开」全链路 | 当前只有单元/冒烟测试，**没有任何一次真实端到端**。启动接线（`app_bootstrap`）只过了 `dart analyze` | 造一个真实 `plugins/<id>/files/` 目录，`flutter run` 观察启动日志 `FileSource 扫描完成` / `文件缓存维护完成` |
| A2 | `DataSourceSlot` 父类降级行为 | 「拉取失败保留静态 config 不白屏」依赖父类既有实现，未单独验证 | 用 `orch://不存在的类型` 声明组件，确认不白屏 |
| A3 | 合并回归 | 环境退化导致 consolidated 回归（`test/renderer/ + test/core/data/`）中途失败 | `cd evg-base && flutter test test/renderer/ test/core/data/ test/core/utils/` |

> 环境提示：`lib/core/**`、`lib/renderer/**` 是**嵌套子包**，在目录内跑 analyze 会有大量
> **假错误**（实测未改动文件也有 55 个 `uri_does_not_exist`）。用**根上下文**验证。

---

## B. 功能性缺口（本轮已知未做）

| # | 缺口 | 现状 | 建议 |
| --- | --- | --- | --- |
| **B1** | slot 的 `timeout` **硬编码 30 分钟** | `file_source_slot.dart` 写死 `Duration(minutes: 30)`。理想应由数据源清单的 `files[].timeoutSeconds` 逐类型决定，但 **slot 层拿不到该声明**（它在 manifest 里，不在组件 config 里） | 两条路：① 组件 config 支持 `timeoutSeconds` 覆盖；② 数据中枢暴露「按类型查超时」的 API 给 slot |
| **B2** | **模型二（`process` 常驻）file-source 不支持** | `registerFileSourcesFromManifest` 遇到 `process` 记 warn 跳过（**不静默**，已诚实标注） | 复用 `DataSourceLoader`，或抽出 file-source 专用 loader。23/25 真实插件是模型一，故优先级中 |
| **B3** | 示例插件未收录 registry | `docs/plugin-registry/examples/example-file-source/` 已存在，但**未登记进 `plugins.json`** | 按 registry schema 补条目 |
| **B4** | 生成器链路未打通 | 爬虫（scraper）/ HTML 创作中心**无法产出** `file-source` 清单 | 属「接入生态」阶段，需改生成器 |
| **B5** | 「打开」动作未跨平台实测 | 走 `url_launcher`（含 Android Intent），**只测了 Err 分支**（空路径/文件不存在） | 真机验证成功分支 |
| **B6** | 下载进度未做「按项归因」优化 | `FileSourceList` 串行下载，进度按当前项归因；批量时只能逐项看 | 若需总体进度条，加聚合层 |

---

## C. 既有债务（本轮**发现但未处理**）

> 以下均为排查过程中**确证**的既有问题，与本轮改动无关，但会持续造成困惑。

| # | 问题 | 证据 | 影响 |
| --- | --- | --- | --- |
| **C1** | `scanAndLoadDataSources` **无 `process == null` 守卫** | 加载器对模型一（23 个插件）会尝试启动**空路径**进程 | 每个模型一插件在启动期产生一条「加载失败」**假错误日志** |
| **C2** | `autoRestart` 声明**与行为相反** | 默认 `false`，但 `_scheduleRestart()` **无条件执行**（1s/3s/9s×3） | 写 `"autoRestart": false` 拦不住重启 |
| **C3** | `dataTypes[].stream` **已声明未接线** | `registerStream` **零生产调用点**；SSE 端点 `GET /data/stream/:name` **恒 404** | 文档+示例齐全但零效果（最易误导作者） |
| **C4** | `file` 声明**模型 B 未接线** | 模型 B `_registerAllTypes` 不调 `registerFile` ⇒ `fileOf()` 恒 `null` | 模型 B 的文件下载声明失效 |
| **C5** | `DataFileService` 默认 `timeout = 30s` | 大文件偏短 | 大文件必须显式传更长超时（已在文档标注） |
| **C6** | 死代码：`FileExportBar`/`FileExportButton`（**0 使用方**）、`MediaHost`（**0 使用方**） | 全仓库引用统计 | 与 `stream` 同类的「写了没接」；语义漂移风险 |
| **C7** | `process.scope` / `protocol` / `autoStart` **数据域不读** | 硬编码 `startLong` + HTTP GET | 声明无效 |
| **C8** | 两份旧 data 文档与代码**漂移** | `data-plugin-protocol-v1.md` §9 列出 5 处 | 作者按旧文档写会踩坑 |
| **C9** | 两份旧文档**字段表重复维护** | `plugin-data-source.md` 与 `plugin-authoring-guide-data.md` 内容重叠 | 漂移温床，建议瘦身指向新协议 |

---

## D. 建议处理顺序

```
A1（端到端）→ A3（合并回归）→ B1（超时传递）→ C1/C2（低成本清理假日志与语义矛盾）
   → B3（registry 收录）→ C3/C4（stream/file 接线或明确降级）→ C6（删死代码）→ C9（文档瘦身）
```

**理由**：先证明全链路可用（A1），再清低成本高困惑项（C1/C2），最后处理需要产品决策的
（C3 流式形态、C6 死代码归属）。

---

## E. 本轮已完成（对照）

| 阶段 | 内容 | 验证 |
| --- | --- | --- |
| 前置 D1–D6 | `evg_lib.download`（F1 内容寻址）、per-type 超时、路径越界校验 | 134 测试 |
| P0 | `DataFileService` 流式落盘 + 进度回调 | 7 应用例 |
| P1 | `FileSourceManifest` + 注册/扫描 + 共享 CLI 执行器 | 21 应用例 |
| P2 | `FileSourceList` + `FileSourceSlot` + 注册 + `openLocalFile` | widget 5/5 + 冒烟 4/4 |
| P3 | 示例插件 + 打包器核查 | — |
| P4 | 缓存配额 LRU + 孤儿 `.part` 回收 | 11 应用例 |

详见 `evg-base/docs/plugin-registry/file-source-plugin-plan-v1.md` §8。

---

## 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-09-15 | 首版。汇总 A 验证阻塞项、B 功能缺口、C 既有债务（9 项）、D 处理顺序 |
