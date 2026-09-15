# 文件型数据源协议 v1（File Data Source Protocol）

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 协议版本 | `data-source/file-v1` |
| 日期 | 2026-09-15 |
| 适用 | 「先下载 → 返回 JSON」形态的 data 插件（任意文件类型：视频/PDF/音频/图片/压缩包…） |
| 依赖 | 本文的**底层依赖**见 [§11](#11-底层依赖清单待补)（部分待实现） |
| 父协议 | [`data-plugin-protocol-v1.md`](./data-plugin-protocol-v1.md) |

> 本文扩展父协议，**不改变**任何既有字段语义。文件型数据源仍是普通 data 插件：
> 模型 A CLI 脚本 / 模型 B 常驻进程，输出单个 JSON 对象。区别只在**输出契约**。

---

## 1. 核心不变量

> ### ⭐ 不变量 F1：同 HEAD 指纹的文件，**绝不重新下载**
>
> 任一文件型 data 插件（**冷插件或热插件、模型 A 或模型 B**）在拉取时：
>
> 1. 先对源 URL 发 `HEAD`，取内容指纹；
> 2. 用**内容寻址**在共享缓存目录中查同指纹文件；
> 3. **命中 → 直接返回本地路径，不发 GET、不落盘、不校验**；
> 4. 未命中 → 下载到 `.part` 临时文件 → 原子改名入缓存。
>
> 该不变量对**所有插件共享同一份缓存**——插件 A 下过的文件，插件 B 命中即复用。

**实现要点**：缓存**不用索引文件**。**文件名本身即指纹**，命中判定 = 文件存在。
→ 无锁、无并发冲突、崩溃安全、可被平台任意裁剪（见 [§9](#9-缓存清理)）。

---

## 2. 缓存目录约定

```
<greenixBase>/file_cache/
├── a1b2c3d4e5f60718-9f8e7d6c5b4a3210.mp4     ← 已缓存文件（内容寻址命名）
├── a1b2c3d4e5f60718-9f8e7d6c5b4a3210.mp4.part ← 下载中临时文件（可能残留）
└── ...
```

| 项 | 规则 |
| --- | --- |
| **目录** | `<greenixBase>/file_cache/`，其中 `greenixBase = dirname(--greenix-config)` |
| **派生方式** | 脚本从 `--greenix-config` 路径取父目录 —— **不需要新增命令行参数** |
| 安卓回退 | `os.environ['GREENIX_CONFIG_PATH']`（见父协议 §6.4） |
| 创建 | 平台与脚本均可 `mkdir -p`（幂等） |
| 可写性 | ✅ 安卓为应用私有可写目录；桌面为项目根下 |

> **契约**：`--greenix-config` 指向 `.greenix/config.json`，故
> `file_cache = Path(greenix_config).parent / 'file_cache'`。
> 该派生规则是协议的一部分——**禁止**插件自选缓存目录。

---

## 3. 指纹算法

### 3.1 文件名构造

```
url_key = sha256(normalized_url).hex[:16]
fp_key  = sha256(fingerprint_string).hex[:16]
filename = f"{url_key}-{fp_key}{ext}"
```

| 符号 | 规则 |
| --- | --- |
| `normalized_url` | 去 fragment、保留 query；**大小写按原样**（path 大小写敏感） |
| `ext` | 由 URL path 末段扩展名派生（含点，如 `.mp4`）；无扩展名 → `.bin`；长度 >10 → `.bin` |
| `fingerprint_string` | 见 §3.2 优先级链 |

### 3.2 指纹优先级链

按顺序取**第一个可用**者：

| 优先级 | 来源 | `fingerprint_string` | 强度 |
| --- | --- | --- | --- |
| 1 | `HEAD` → `ETag` | `etag:<值>` | **强**（内容唯一） |
| 2 | `HEAD` → `Last-Modified` | `lm:<值>` | 中 |
| 3 | `HEAD` → `Content-Length` | `cl:<字节数>` | 弱（仅长度） |
| 4 | 以上皆无 | `nofp` | **最弱**（仅按 URL 去重） |

### 3.3 降级链

| 情形 | 行为 |
| --- | --- |
| `HEAD` 成功 | 按 §3.2 算键，走 F1 判定 |
| `HEAD` 405 / 501 / 403（源站不支持） | **降级到优先级 4**（`nofp`）；若该键文件已存在 → 复用，标记 `weak_cache: true` |
| `HEAD` 网络失败 | 同上降级，**不阻断**：已有 `nofp` 文件则复用 |
| `force = true` | 跳过 HEAD 与命中判定，直接重下（用于显式刷新） |

> **诚实说明**：降级到 `nofp` 后，源文件变了也**不会**重新下载。
> 这是刻意的取舍——F1 优先「绝不重下」，代价是弱键无法感知远端更新。
> 需要感知更新时用 `force`。

---

## 4. 下载与写盘

```
1. GET url （流式，带 headers）
2. 边读边写 <target>.part      ← 不整块进内存
3. 校验（若声明 expected_size → 必须相等；若声明 sha256 → 必须相等）
4. os.replace(<target>.part, <target>)   ← 原子改名，同目录同设备
```

| 规则 | 原因 |
| --- | --- |
| **必须流式落盘** | 视频可达数百 MB；`DataFileService` 的「全量进内存」不适用 |
| **必须 `.part` + 原子 `rename`** | 脚本被平台 60s 超时 kill 时，半成品**不得**污染缓存 |
| **失败必须清理 `.part`** | 否则残留占位，下次误判 |
| 同名 `.part` 并发 | 用 `f"{target}.part.{pid}"` 避免两个插件互相覆盖；失败时清理自己的 |
| 不落盘到缓存外 | 平台可校验返回的 `path` 必须在 `file_cache/` 内 |

---

## 5. 输出契约（脚本 → stdout）

顶层**单个 JSON 对象**（父协议 §6.2）。`status` 为判别字段。

### 5.1 `status: "ready"`（成功，文件已落盘）

```json
{
  "status": "ready",
  "path": "/abs/path/.greenix/file_cache/a1b2…-9f8e….mp4",
  "size": 12345678,
  "mime": "video/mp4",
  "source_url": "https://example.com/lecture01.mp4",
  "etag": "\"abc123\"",
  "last_modified": "Mon, 01 Sep 2026 10:00:00 GMT",
  "sha256": "9f86d081884c7d659a2feaa0c55ad015…",
  "cached": true,
  "weak_cache": false,
  "fetched_at": "2026-09-15T05:12:33Z"
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `status` | `string` | ✅ | `"ready"` |
| `path` | `string` | ✅ | **绝对路径**，必须位于 `file_cache/` 内 |
| `size` | `int` | ✅ | 字节数（消费方可与磁盘核对） |
| `mime` | `string` | 建议 | 供 `video`/`pdf` slot 分派 |
| `source_url` | `string` | ✅ | 溯源；也是下一次指纹计算的输入 |
| `etag` / `last_modified` | `string` | 可选 | 透传 HEAD，便于诊断 |
| `sha256` | `string` | 可选 | 下载后算得；有则消费方可做完整性校验 |
| `cached` | `bool` | ✅ | `true` = 本次**直接复用**（未发 GET）——用于验收 F1 |
| `weak_cache` | `bool` | 可选 | `true` = 走 `nofp` 弱键命中 |
| `fetched_at` | `string` | 建议 | ISO-8601 UTC，文件落盘时间 |

### 5.2 `status: "missing"`（未缓存且本次不允许下载）

```json
{ "status": "missing", "path": null, "reason": "head_failed_offline" }
```

用于「离线/无网」时优雅降级，**不报错**。配合父协议 `fallbackJson` 使用效果最佳。

### 5.3 `status: "failed"`

```json
{ "status": "failed", "path": null, "error": "403 Forbidden（登录态失效）", "source_url": "…" }
```

或直接走父协议的 `{"error": "..."}` 形态（两者等价，`status` 形态更利于 UI 分支）。

### 5.4 多文件

顶层 `files` 数组（每元素同 §5.1 结构）：

```json
{ "status": "ready", "files": [ { "path": "…", "size": 1, "mime": "…" }, … ] }
```

> ⚠️ **注意与既有 `files` 语义的冲突**：`core/data/file_entries.dart` 的 `extractFileEntries`
> 把 `files` 解析为**待下载的 URL 清单**（`FileEntry.url`）。
> 本协议的 `files[].path` 是**已落盘的本地路径**。
> **边界规则**：含 `path` 字段 → 视为已落盘（本协议）；含 `url` 字段 → 视为待下载清单（既有语义）。

### 5.5 状态机

```
                    ┌──────────────┐
   首次拉取 ─────────▶│  ready       │  ← 命中缓存（cached:true）或下载成功（cached:false）
                    └──────────────┘
   无网/HEAD失败 ────▶  missing        （降级，不报错）
   下载失败 ─────────▶  failed         （error 带可读原因）
```

> 本协议**不定义** `downloading` 状态（同步下载模型）。
> 长文件超时问题见 [§10](#10-超时与分阶段)。

---

## 6. 参考实现（脚本侧）

平台提供 `evg_lib.download`，**必须优先使用它**而非自行实现——这样 F1 对所有插件一致生效：

```python
from evg_lib.jsonio import emit
from evg_lib import download

data = download.ensure(
    "https://example.com/lecture01.mp4",
    headers={"User-Agent": "evergreen-data"},
    # 可选：expected_size=12345678, sha256="…", force=False
)
emit(data)          # 输出 §5 契约
```

`evg_lib` 随平台解释器分发（`PYTHONPATH=<greenix>/scripts/` 注入，见父协议 §6.1），
**冷插件与热插件拿到的是同一份实现** —— 这就是 F1 能跨插件成立的机制。

> 待实现，见 [§11](#11-底层依赖清单待补)。

---

## 7. 消费方契约

| 消费方 | 行为 |
| --- | --- |
| `video` / `pdf` / `audio` slot | 读 `path` 直接播/展示（本地文件，无需 headers） |
| 数据看板 | 读 `status` 分支；`ready` 显示大小/时间，`missing`/`failed` 显示原因 |
| 平台 | **可校验** `path` 必须位于 `file_cache/` 内（防越界写） |

> 返回**本地路径**后，`VideoSlot` 的 `resolvePluginAssetPath` 会收到一个**绝对路径**，
> 按其实现（`p.isAbsolute(raw)` 为真 → 原样返回）**可直接工作** —— 无需改 `VideoSlot`。
> 这正面规避了「http 直链被当相对路径拼接」的缺陷。

---

## 8. 与既有字段的关系

| 既有 | 关系 |
| --- | --- |
| `dataTypes[].file` | **正交**。`file` 声明「可下载文件清单/端点」（消费方主动导出）；本协议是「脚本已下载完，直接给路径」 |
| `dataTypes[].stream` | **替代关系**。流式未接线（父协议 §5.5）；本协议是当前**唯一可用**的媒体交付路径 |
| `fallbackJson` | **互补**。建议声明 `{"status":"missing","path":null}` 作为离线兜底 |
| `ttl` | 建议设**长**（如 `24h`）或配合 `persistentKey`。因 F1 保证不重下，`ttl` 只影响 JSON 元数据的新鲜度 |
| 父协议 §8.2 陷阱 1（60s 超时） | 本协议的主要约束，见 §10 |

---

## 9. 缓存清理

| 责任方 | 规则 |
| --- | --- |
| 平台 | **可随时清理** `file_cache/`（按 LRU/配额/手动）。平台不通知插件 |
| 插件 | **必须容忍缓存缺失**：每次拉取都重新走 HEAD + 命中判定，不得假设上次的文件还在 |
| `.part` 残留 | 平台可安全清理**所有** `.part*`（超过 1 小时未变更的） |
| 插件自清 | ❌ 不应删除非本次产生的缓存文件（可能被其他插件共享） |

> **重要**：正因为平台可随时清理，插件**不能**把 `path` 长期持有到下次进程。
> 每次 `get()` 都应重新输出当前有效的 `path`。

---

## 10. 超时与分阶段

### 10.1 现状约束

父协议 §8.2 陷阱 1：`kCliDataSourceTimeout = 60s` 且**超时会 kill 子进程**；
无 per-type 覆盖（**已于 2026-09-15 解除**，见 §10.2）。

### 10.2 per-type 超时（✅ 已落地）

manifest 声明 `dataTypes[].timeoutSeconds`（**整数秒，有效范围 1..3600**）：

```json
{ "name": "lecture_video", "ttl": "24h", "persistentKey": "lecture",
  "timeoutSeconds": 1800 }
```

| 语义 | 行为 |
| --- | --- |
| 声明且 `1 <= n <= 3600` | 该类型 CLI 拉取超时 = `n` 秒（超时仍会 kill 子进程） |
| 未声明 / `<= 0` / `> 3600` / 非整数 | 回落全局 `kCliDataSourceTimeout = 60s`（**不抛**，零行为变化） |
| 作用域 | **per-type**：同一插件可同时有「秒级」元数据源与「分钟级」文件源 |

> ⚠️ 与 `ttl` 的差异：`timeoutSeconds` **严格整数**，**不做字符串兜底**
> （写 `"1800"` 会回落 60s）。这是刻意的——避免静默误配导致长下载被 60s 杀掉。

### 10.3 配置建议

| 场景 | 建议 |
| --- | --- |
| 冷启动大文件（>50MB） | 显式声明 `timeoutSeconds`（如 `1800`）；按「带宽 × 文件大小」留 2 倍余量 |
| 小文件（<10MB） | 无需声明，默认 60s 足够 |
| 稳态（缓存已热） | HEAD + 查表 ≈ 毫秒级，任何超时都够 |
| **`ttl` 选型** | ⚠️ 平台每 **5 分钟**（时钟对齐）刷一轮所有 `isFresh == false` 的源，**失败源也重试**。`ttl` 设短 ⇒ 每 5 分钟重新"发现"一次（脚本要重跑，爬页面有开销）；设长（如 `24h`）⇒ 稳态几乎只有 HEAD。详见父协议 §8.4 |
| F1 的价值 | 正因为「绝不重下」，**稳态下本协议几乎不消耗超时预算** |

> **不要**用后台 detached 下载（安卓 Chaquopy 无独立进程，且平台超时会 kill 子进程）。
> 需要真正异步时，应走平台侧下载任务（尚未实现）。

---

## 11. 底层依赖清单（待补）

| # | 依赖 | 位置 | 状态 | 必要性 |
| --- | --- | --- | --- | --- |
| D1 | `evg_lib/download.py`（HEAD 指纹 + 内容寻址 + 流式落盘 + 原子改名） | `scripts/evg_lib/download.py` → `assets/scripts_bundle/evg_lib/` | ❌ 待建 | **阻塞**：无它则插件各自实现，F1 必然失效 |
| D2 | `evg_lib/__init__.py` 导出 `download` | `scripts/evg_lib/__init__.py` | ❌ 待补 | 阻塞 |
| D3 | `bundle_scripts.dart` 重跑（同步 assets + 重写 pubspec 标记块） | `tool/bundle_scripts.dart` | ✅ 机制已有，需执行 | 阻塞（否则安卓无此文件） |
| D4 | `dataTypes[].timeoutSeconds`（per-type 超时） | `core/data/plugin/data_source_manifest.dart#parseDataSourceTimeoutSeconds` + `register_data_source.dart` | ✅ **已完成**（2026-09-15） | 大文件必需 |
| D5 | 平台侧缓存目录常量 `greenixFileCacheDir` + `isUnderFileCache` | `core/utils/greenix_path.dart`（含子包镜像） | ✅ **已完成** | 建议（供清理/校验） |
| D6 | `path` 越界校验（必须在 `file_cache/` 内） | `core/data/file_cache.dart` + 模型 A/B 双 fetcher 接线 | ✅ **已完成** | 建议（安全） |
| D7 | 缓存清理/配额（LRU + `.part` 回收） | 新增 | ❌ 待建 | 建议（防磁盘膨胀） |

### 依赖关系

```
D1 ──▶ D2 ──▶ D3 ──▶ 插件可用（小文件立即可用）
D4 ───────────────▶ 大文件可用
D5 ──▶ D6, D7 ────▶ 平台可控（清理/校验）

当前状态：D1–D6 全部完成（123 个 data 域测试 + 越界/超时单测全绿）；
仅 **D7（LRU 配额 + `.part` 回收）** 待建。
```

---

## 12. 测试要点

> 本协议的价值之一是**可测试性**——全部断言都基于文件系统，不需要播放器/渲染器。

| # | 用例 | 断言 |
| --- | --- | --- |
| T1 | 首次拉取 | `status=ready`、`cached=false`、文件存在且 `size` 匹配 |
| T2 | **二次拉取（F1 核心）** | `status=ready`、`cached=true`、**`mtime` 不变**（证明未重下） |
| T3 | 同文件换 URL 参数（fragment 变化） | `url_key` 不变 → 命中 |
| T4 | 源 ETag 变化 | `fp_key` 变化 → 未命中 → 重新下载 |
| T5 | HEAD 返回 405 | 降级 `nofp`；二次拉取仍 `cached=true` |
| T6 | 下载中途 kill 脚本 | 缓存目录**无** `.part` 遗留污染；原文件完好 |
| T7 | 缓存文件被平台删除后拉取 | 不报错，重新下载（容忍缺失） |
| T8 | 无网 | `status=missing`，不抛异常 |
| T9 | 两个插件下同一 URL | 第二次 `cached=true`（跨插件共享） |
| T10 | `path` 越界（指向 `file_cache` 外） | 平台拒绝并记 `lastError` |

---

## 变更记录

| 日期 | 版本 | 变更 |
| --- | --- | --- |
| 2026-09-15 | v1 | 首版。定义文件型数据源契约、内容寻址缓存（F1 不变量）、7 项待补依赖 |
