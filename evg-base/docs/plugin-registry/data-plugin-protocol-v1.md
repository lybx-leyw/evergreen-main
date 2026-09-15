# 外部数据源插件协议 v1（Data Plugin Protocol）

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 协议版本 | `data-source/v1` |
| 日期 | 2026-09-15 |
| 适用范围 | `plugins/<id>/data/manifest.json`（外部数据源插件） |
| 权威来源 | **代码**，非本文档 |

> ## 本文档的定位
>
> 本文**由代码逆向重写**，用于消除 `lib/core/data/docs/plugin-data-source.md` 与
> `lib/core/data/docs/plugin-authoring-guide-data.md` 与实现之间的漂移。
>
> **凡本文与代码冲突，以代码为准。** 每个字段都给出**符号级代码锚点**（`文件#符号`），
> 而非行号——行号会随重构漂移，符号不会。
>
> 已确认的 5 处漂移见 [§9](#9-与既有文档的漂移更正)。

### 代码锚点索引

| 关注点 | 锚点 |
| --- | --- |
| manifest 模型 / 解析 / 校验 | `core/data/plugin/data_source_manifest.dart` |
| 模型 A 注册 + CLI 调用 | `core/data/register_data_source.dart#registerDataSourcesFromManifest` |
| 模型 B 生命周期 | `core/data/plugin/data_source_loader.dart#DataSourceLoader` |
| 子进程执行（桌面/安卓） | `core/plugin/plugin_runner.dart` |
| 运行时类型 / 缓存 / 兜底 | `core/data/type.dart#DataType`、`core/data/orchestrator.dart` |
| 保留字段消费方（画板层） | `renderer/templates/scraper_modle/board/data_source_binding.dart#DataSourceInfo.fromPluginDir` |

---

## 1. 明确支持的参数类型

这一节是协议的**规范核心**：只有下列类型被平台保证。JSON 是唯一输入格式。

### 1.1 类型表

| 协议类型 | JSON 表示 | 缺省/非法时的行为 | 示例 |
| --- | --- | --- | --- |
| `string` | `"abc"` | 缺省 → 字段默认值 | `"zju_grades"` |
| `string?`（可空） | `"abc"` / `null` / 空串 | 空串按**未提供**处理（部分字段） | `"scraper.py"` |
| `int` | `90`（**必须是 JSON 整数**） | 类型不符 → 字段默认值；**不做字符串兜底** | `preferredPort: 0` |
| `bool` | `true` / `false` | 见 [§1.3 fail-closed](#13-三档失败语义) | `"androidSupport": true` |
| `duration` | `"30m"` / `90` | 无法识别 → `null` → 调用方回落 `5m` | `"ttl": "30m"` |
| `object` | `{...}` | `null` 或**空对象** `{}` → 视为未声明 | `auth` |
| `enum<string>` | `"long"` | **平台不校验**，任意字符串均被接受（见 [§1.4](#14-enum-的诚实说明)） | `"scope": "long"` |
| `array<string>` | `["A","B"]` | 非 `List` → 空数组 `[]` | `credentialKeys` |
| `array<object>` | `[{...}]` | **非空数组强制**；空数组或非数组 → `FormatException` | `dataTypes` |
| `map<string,any>` | `{"k":1}` | 非 `Map` → `null` | `fallbackJson` |
| `relpath` | `"fetch.py"` | 相对 `<pluginDir>/data/` 解析；**文件不存在仅告警，仍注册** | `script` |
| `urltemplate` | `"/data/{port}"` | 含 `{port}` 占位符；缺失则 `StateError` | `endpoint` |

### 1.2 `duration` 类型完整语义

解析器唯一实现：`core/data/plugin/data_source_manifest.dart#parseDataSourceTtl`。
正则：`^(\d+)\s*(h|m|s|ms)$` —— **大小写敏感**。

| 写法 | 解析结果 | 备注 |
| --- | --- | --- |
| `"30m"` | 30 分钟 | ✅ 推荐写法 |
| `"1h"` / `"6h"` / `"24h"` | 小时 | ✅ |
| `"60s"` / `"30s"` | 秒 | ✅ |
| `"500ms"` | 毫秒 | ✅ |
| `"10 m"` | 10 分钟 | `\s*` 容忍空格 |
| `90`（JSON 整数） | 90 秒 | ✅ |
| `"90"`（数字字符串） | 90 秒 | ✅ |
| `"10M"` | ⚠️ **解析失败 → 静默回落 5 分钟** | 大写单位不支持 |
| `"5 minutes"` | ⚠️ 静默回落 5 分钟 | 不支持中文/英文单位词 |
| `null` / 缺省 | 5 分钟（默认） | |

> **陷阱**：无法识别的 `ttl` **不报错**，静默使用默认 5 分钟。插件作者若写了 `"1H"`，
> 会得到 5 分钟缓存且无任何提示。序列化输出统一为 `_fmtDuration` 形式
> （`1h` / `30m` / `60s` / `500ms`）。

### 1.3 三档失败语义

平台对非法输入有三种截然不同的处理，**这是最容易踩坑的地方**：

| 档位 | 触发 | 行为 | 涉及字段 |
| --- | --- | --- | --- |
| **fail-fast** | 结构性问题 | 抛 `FormatException`，插件**整体被跳过**并记日志 | `type`、`dataTypes`（空/非数组）、`script`+`process` 同时存在/同时缺失、`process` 非 string/object |
| **fail-closed** | `androidSupport` 类型不符 | 视为 `false`（**不加载**），避免 C 扩展在安卓崩溃 | `androidSupport` |
| **silent-drop** | 单字段类型不符 | 使用默认值或忽略，**无任何提示** | `ttl`、`category`、`id`、`name`、`runtime`、`endpoint`、`credentialKeys`、`fallbackJson`、**全部未知字段** |

`androidSupport` 的 fail-closed 是刻意的：
`parseDataSourceAndroidSupport` 注释明确「非 bool 不再视为 true，避免把 `"false"`
这类笔误误判为『支持安卓』而触发 C 扩展崩溃」。因此 `"androidSupport": "false"`
（**字符串**）等价于 `false`，而 `"androidSupport": 1` 也等价于 `false`。

### 1.4 `enum` 的诚实说明

以下字段**文档上**是枚举，**代码上**是自由字符串——平台不校验、不报错、不回退：

| 字段 | 文档约定取值 | 代码行为 |
| --- | --- | --- |
| `runtime` | `native` / `python` | 任意字符串接受；非 `python` 且入口非 `.py` → 按原生可执行文件处理 |
| `process.scope` | `long` / `short` | 任意接受（且**数据域根本不读**，见 §8） |
| `process.protocol` | `http` / `stdio` | 任意接受（且**数据域根本不读**） |
| `stream.protocol` | `hls` / `mp4` / `http-flv` / `sse` / `stdio-jsonl` | 任意接受（且**流式整体未接线**） |

> 协议 v1 只保证上表「文档约定取值」可用。写别的值**不会报错**，但行为未定义。
> v2 计划对枚举引入严格校验（fail-fast）。

---

## 2. 目录与文件约定

```
plugins/<id>/                      ← 插件根（<id> = 目录名，用于 id 缺省派生）
└── data/
    ├── manifest.json              ← 本协议
    └── <script>                   ← 模型 A 入口脚本（相对 data/）
        <server>                   ← 模型 B 长驻进程入口
```

- 平台扫描路径：`plugins/*/data/manifest.json`（`scanAndLoadDataSources` /
  `registerDataSourcesFromManifest` 双路径，同一份解析）。
- 缺失 `manifest.json` → 安静跳过。
- `type != "data-source"` → 安静跳过。

---

## 3. 顶层字段

| 字段 | 类型 | 必填 | 默认 | 生效状态 | 说明 |
| --- | --- | --- | --- | --- | --- |
| `type` | `string` | ✅ | — | ✅ | **必须精确等于 `"data-source"`**，否则 `FormatException`（`_requireField`） |
| `id` | `string` | 模型 A 可选 | `""` | ✅ | 供日志/身份识别；留空由消费方回落目录名 |
| `name` | `string` | 可选 | `""` | ✅ | 展示名 |
| `script` | `relpath` | A：与 `process` 二选一 | `null` | ✅ | 空串视为未提供 |
| `process` | `string \| object` | B：与 `script` 二选一 | `null` | ✅ | 字符串形态 = `{exe: <string>}` 全默认 |
| `runtime` | `enum<string>` | 建议显式 | `"native"` | ✅ | `python` 触发解释器前缀 + `PYTHONPATH` 注入 |
| `preferredPort` | `int` | 可选 | `0` | ✅ | 顶层与 `process.preferredPort` 并存时，**`process` 内非 0 值优先** |
| `dataTypes` | `array<object>` | ✅ | — | ✅ | **必须非空**；元素见 §5 |
| `androidSupport` | `bool` | 可选 | `true` | ✅ | fail-closed；仅 Android 生效 |
| `auth` | `object` | 可选 | `null` | ✅ | 空对象视为未声明；见 §4 |
| `boardId` | `string` | 可选 | — | ⚠️ 保留字段 | 非核心层；画板层读取，见 §7 |
| `boundBoardId` | `string` | 可选 | — | ⚠️ 保留字段 | 由画板**回写**，优先于 `boardId` |
| `createdBy` | `string` | 可选 | — | ⚠️ 保留字段 | `scraper*` 前缀被识别为「爬虫创建」 |
| 其它任意字段 | — | — | — | ❌ **静默忽略** | 不报错、不生效（见 §9 漂移 #3） |

**模式互斥规则**（`DataSourceManifest.fromJson`）：

```
script == null && process == null   → FormatException('缺少必填字段: script 或 process（二选一）')
script != null && process != null   → FormatException('script 与 process 互斥，只能二选一')
```

---

## 4. `auth` 段（凭据 / 会话引用）

| 字段 | 类型 | 默认 | 生效状态 | 说明 |
| --- | --- | --- | --- | --- |
| `sessionProvider` | `string` | `null` | ✅ | 会话提供者标识（如 `"zju"`）；会话失效时经 `SessionCoordinator` 单点重登后**重拉一次** |
| `sessionDomain` | `string` | `null` | ✅ | **登录锁分组键**（如 `"zdbk.zju.edu.cn"`）。按域分组去重重登；缺省回退按 `sessionProvider` 分组 |
| `credentialKeys` | `array<string>` | `[]` | ❌ **数据层不消费** | 仅 `scraper_exporter.dart` 读取用于生成；凭据实际经 `--greenix-config` 由脚本自读 |

**设计约束（必须遵守）**：`auth` 只**引用** `.greenix/config.json` 中已声明的凭据 key，
**不得重复声明凭据值**——避免双真相源。凭据值的唯一来源是 config。

> 同一 `sessionDomain` 应声明同一 `sessionProvider`（域决定登录实现归属）。

---

## 5. `dataTypes[]` 段

`dataTypes` 是**数组**，每个元素声明一个数据类型（= 一个可 `orch://<name>` 引用的数据源）。
**25 个真实 manifest 中 33 个 type 声明**，字段使用分布见 §8.3。

### 5.1 必填

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `name` | `string` | — | **必填**（`_require`）。同一 `dataTypes` 内应唯一；也是 `orch://<name>` 的键 |

### 5.2 元数据

| 字段 | 类型 | 默认 | 生效状态 | 说明 |
| --- | --- | --- | --- | --- |
| `typeArg` | `string` | `null` → 回退 `name` | ✅ 模型 A | 传给脚本的 `--type` 值 |
| `category` | `string` | `"未分类"` | ✅ | UI 分组标签。**自由字符串，无枚举**（实测出现 `zju_grades2`、`成绩` 等不一致值） |
| `displayName` | `string` | `null` → 回退 `name` | ✅ | UI 展示名 |
| `ttl` | `duration` | `5m` | ✅ | 缓存有效期 |
| `persistentKey` | `string` | `null` | ✅ | 持久化键；**不设则不落盘缓存** |
| `timeoutSeconds` | `int` | `null` → 回落 `60s` | ✅ **模型 A** | 本类型 CLI 拉取超时（**整数秒，1..3600**）；越界/非整数回落全局 `kCliDataSourceTimeout`。文件型数据源冷启动大文件必需，见 [`file-data-plugin-protocol-v1.md`](./file-data-plugin-protocol-v1.md) §10 |

### 5.3 模型 B 专用

| 字段 | 类型 | 默认 | 生效状态 | 说明 |
| --- | --- | --- | --- | --- |
| `endpoint` | `urltemplate` | `null` | ✅ 模型 B | HTTP 路径；`{port}` 由平台替换为实际端口。缺失时 `buildUrl()` 抛 `StateError` |

### 5.4 `fallbackJson`（静态兜底 / 第三级降级）

| 字段 | 类型 | 默认 | 生效状态 |
| --- | --- | --- | --- |
| `fallbackJson` | `map<string,any>` | `null` | ✅ |

降级链（`DataOrchestrator`）：

1. **拉取成功且非空** → 覆写缓存；
2. **拉取失败/空** → 返回 `null`，保留旧缓存，`connected=false`，`lastError` 记录原因；
3. **声明了 `fallbackJson` 且无旧缓存** → 返回静态兜底，`lastError` 标记「使用静态兜底」。

> 未声明时（`null`）行为与历史完全一致——**零行为变化**。这是本协议的设计基调。

### 5.5 `stream`（流式声明）—— ⚠️ **已解析，未接线**

| 字段 | 类型 | 默认 |
| --- | --- | --- |
| `stream.enabled` | `bool` | `false` |
| `stream.protocol` | `enum<string>` | `null` |
| `stream.mime` | `string` | `null` |
| `stream.credentialed` | `bool` | `false` |

> ### ❌ 实现状态：声明后对运行时**零效果**
>
> - 模型层**会解析**并保留这 4 个字段（`DataSourceStreamDecl`）；
> - 但 `DataSourceTypeDecl#toDataType()` **不携带** stream；
> - 两条注册路径（模型 A `registerDataSourcesFromManifest`、模型 B `_registerAllTypes`）
>   **都不调用** `DataOrchestrator#registerStream`；
> - 结果：`GET /data/stream/:name`（SSE 端点）**恒返回 404**。
>
> 生产代码中 `registerStream` / `streamOf` / `streamByName` 的调用点：
> `orchestrator.dart`（定义）与 `data_http_server.dart`（SSE 端点）。**无任何 manifest 驱动路径调用它。**
>
> **协议 v1 立场**：`stream` 为**预留字段**，声明不报错但不生效。
> 需要流式能力的插件**当前无法只靠 manifest 实现**，必须等平台接线。

### 5.6 `file`（文件下载声明）

| 字段 | 类型 | 默认 | 生效状态 |
| --- | --- | --- | --- |
| `file.enabled` | `bool` | `false` | 见下 |
| `file.downloadEndpoint` | `string` | `null` | 见下 |

> ### ⚠️ 两条注册路径接线**不对称**
>
> | 模型 | 是否调用 `orch.registerFile` | `orch.fileOf(type)` 结果 |
> | --- | --- | --- |
> | **A（script）** | ✅ 调用（`register_data_source.dart`） | 返回声明 |
> | **B（process）** | ❌ **不调用**（`_registerAllTypes` 只 `register`） | **恒为 `null`** |
>
> 即：**模型 B + `file` 声明当前无效**。既有文档称「模型 B 则用 `file.downloadEndpoint`
> 作为统一下载端点」与代码不符（漂移 #2）。

---

## 6. 运行时契约

### 6.1 通用：运行时决定解释器前缀

`plugin_runner.dart#SubprocessRunner._buildExec`：

```
_isPython(entry, runtime) := (runtime == "python") || entry.endsWith(".py")

python  → [ <pythonExe>, <entry>, ...args ]
其它    → [ <entry>, ...args ]
```

- `runtime == "python"` 但解释器不可用 → `StateError('Python 解释器不可用…')`。
- Python 入口自动注入 `PYTHONPATH=<.greenix/scripts/>`，使 `import evg_lib` 可用而无需拷贝。
  非 Python 入口**不注入**（保持原生子进程环境契约）。

### 6.2 模型 A：CLI 一次性脚本

**调用命令**

```
[pythonExe] <pluginDir>/data/<script> \
  --type <typeArg> \
  --project-root <projectRoot> \
  --greenix-config <greenixConfigPath>
```

| 项 | 值 | 锚点 |
| --- | --- | --- |
| 工作目录 | `<pluginDir>/data` | `register_data_source.dart` |
| 超时 | **60 秒**（`kCliDataSourceTimeout`） | 同上 |
| stdin | **不写入**（`stdinJson` 未传） | `runOnce` 调用 |
| 环境变量 | `PYTHONPATH` 见 §6.1 | `_withPythonPath` |

**stdout / 退出码契约**

| 情形 | 平台行为 | `lastError` 文案 |
| --- | --- | --- |
| `exitCode == 0` 且 stdout 为 JSON 对象且**无 `error` 键** | ✅ 成功，返回该 Map | — |
| `exitCode == 0` 但 stdout 含 `"error"` | ❌ 失败 | `error` 字段值 |
| `exitCode != 0` 且 stdout 可解析为含 `error` 的 JSON | ❌ 失败 | **`error` 字段值优先于 stderr** |
| `exitCode != 0` 且 stderr 非空 | ❌ 失败 | stderr 全文（trim） |
| `exitCode != 0` 且 stderr 为空 | ❌ 失败 | `<script> 异常退出 (code <N>)` |
| 超时（>60s） | ❌ 失败，**kill 子进程** | `数据脚本 "<script>" 执行超时（>60s），已终止子进程` |
| 无法启动进程 | ❌ 失败 | `无法启动数据脚本 "<script>": <msg>` |

> **关键约定**：
> 1. stdout **必须是单个 JSON 对象**（顶层 `Map`），不允许数组或纯文本。
> 2. **stderr 不是错误信号**——成功时 stderr 仅作诊断日志（最多记录 2000 字符）。
> 3. 表达业务失败用 `{"error": "..."}` + `exit 0`，可获得最干净的文案。
> 4. 脚本崩溃时的 `error` 字段**优先于 stderr**（便于给出面向用户的中文原因）。

### 6.3 模型 B：HTTP 长驻进程

**启动参数**

```
[pythonExe] <pluginDir>/data/<process.exe> \
  --project-root <projectRoot> \
  --greenix-config <greenixConfigPath> \
  [--port <preferredPort>]        ← 仅当 preferredPort > 0
```

**启动握手序列**（`DataSourceLoader._startInternal`）

| 步骤 | 契约 | 超时/失败 |
| --- | --- | --- |
| 1. 启动进程 | `startLong`，工作目录 `<pluginDir>/data` | 失败 → `ProcessException` |
| 2. **端口探测** | stdout 中**任意一行**匹配正则 `PORT:(\d+)` | **10 秒**超时 → kill 进程并抛 `TimeoutException` |
| 3. **健康检查** | `GET http://localhost:<port>/health` 必须 **200** | 非 200 / 连接失败 → **kill 进程**并抛 `HttpException` |
| 4. 注册类型 | 逐 `dataTypes` 注册 `decl.buildUrl(port)` 为 fetcher URL | — |

**数据接口**

```
GET http://localhost:<port><endpoint>     ← endpoint 中 {port} 已被替换
必须 HTTP 200，响应体必须为 JSON（jsonDecode）
```

失败语义：未就绪 → `StateError('数据源 <id> 未就绪，无法获取 <name>')`；
非 200 → `HttpException('获取 <name> 失败: <code>')`。

**日志格式要求**：端口行必须**原样**输出 `PORT:<十进制端口>`。可混在其它日志中
（逐行扫描），但**不能**写成 `PORT: 12345`（带空格）或 `port:12345`（小写）。

**崩溃重启**：见 §8.2 —— 由平台强制，**不受 `autoRestart` 控制**。

### 6.4 脚本侧可移植性要求（桌面 / 安卓同一份代码）

| 维度 | 桌面（SubprocessRunner） | 安卓（ChaquopyRunner） |
| --- | --- | --- |
| 进程模型 | 真子进程 | **进程内** Chaquopy |
| `sys.argv` | `[entry, *args]` | `[entry, *args]`（Kotlin 显式设置） |
| 工作目录 | `<pluginDir>/data` | **`/`（根目录）** |
| `--project-root` | argv | argv **+** `os.environ['PROJECT_ROOT']` |
| `--greenix-config` | argv | argv **+** `os.environ['GREENIX_CONFIG_PATH']` |
| `PYTHONPATH` | Dart 注入 | Kotlin 注入 |

> **强制性约束**（违反会在安卓上静默失败）：
> 1. **不要依赖相对路径 / cwd**——安卓 CWD 是 `/`。
>    始终用 `--project-root` 或 `os.environ['PROJECT_ROOT']` 拼绝对路径。
> 2. 读凭据优先走 `--greenix-config` 指定的 `config.json`，
>    回退 `os.environ['GREENIX_CONFIG_PATH']`；不要硬编码 `.greenix/config.json` 相对路径。
> 3. 只依赖 Python 标准库（Chaquopy 无法安装任意 C 扩展包）；
>    依赖 C 扩展的插件必须声明 `"androidSupport": false`。

---

## 7. 保留字段（非核心层）

以下字段**不被 `core/data` 解析**，仅靠「未知字段静默忽略」得以共存，
由**画板层**（`scraper_modle/board/data_source_binding.dart#DataSourceInfo.fromPluginDir`）直接读原始 JSON：

| 字段 | 位置 | 消费方 | 说明 |
| --- | --- | --- | --- |
| `fields` | `dataTypes[0].fields` | 画板层 | 字段 schema（`array<object>`）。**仅读第 0 个元素**；为空时回退读 config |
| `boardId` | 顶层 | 画板层 | 关联画板 id |
| `boundBoardId` | 顶层 | 画板层 | 画板**回写**，优先级高于 `boardId` |
| `createdBy` | 顶层 | 画板层 | `scraper*` 前缀 → 认定为「爬虫创建」 |

> **协议立场**：这些字段属于**画板层的私有扩展**，不在 `data-source/v1` 保证范围内。
> 核心层不校验、不使用、不承诺兼容。插件作者**不应**依赖它们。

---

## 8. 实现状态矩阵（先读这一节再动手）

### 8.1 字段生效矩阵

| 字段 | 解析 | 模型 A 生效 | 模型 B 生效 |
| --- | --- | --- | --- |
| `type` / `id` / `name` | ✅ | ✅ | ✅ |
| `script` | ✅ | ✅ | — |
| `process.exe` | ✅ | — | ✅ |
| `process.preferredPort` | ✅ | — | ✅ |
| `process.scope` | ✅ | ❌ **未读取**（硬编码 `startLong`） | ❌ |
| `process.protocol` | ✅ | ❌ **未读取**（`_fetch` 硬编码 HTTP GET） | ❌ |
| `process.autoStart` | ✅ | ❌ **未读取**（总是启动） | ❌ |
| `process.autoRestart` | ✅ | ⚠️ **未读取，且行为相反**（见 §8.2） | ⚠️ |
| `runtime` | ✅ | ✅ | ✅ |
| `preferredPort`（顶层） | ✅ | ✅（B 专用） | ✅ |
| `androidSupport` | ✅ | ✅ | ✅ |
| `auth.sessionProvider` | ✅ | ✅ | ✅ |
| `auth.sessionDomain` | ✅ | ✅ | ✅ |
| `auth.credentialKeys` | ✅ | ❌ 数据层不读 | ❌ |
| `dataTypes[].name` | ✅ | ✅ | ✅ |
| `dataTypes[].typeArg` | ✅ | ✅ | — |
| `dataTypes[].category` | ✅ | ✅ | ✅ |
| `dataTypes[].displayName` | ✅ | ✅ | ✅ |
| `dataTypes[].ttl` | ✅ | ✅ | ✅ |
| `dataTypes[].persistentKey` | ✅ | ✅ | ✅ |
| `dataTypes[].timeoutSeconds` | ✅ | ✅（CLI 超时） | —（模型 B 无 per-fetch 超时） |
| `dataTypes[].endpoint` | ✅ | — | ✅ |
| `dataTypes[].fallbackJson` | ✅ | ✅ | ✅ |
| `dataTypes[].stream` | ✅ | ❌ **未接线** | ❌ **未接线** |
| `dataTypes[].file` | ✅ | ✅ | ❌ **未接线** |
| `boardId` / `boundBoardId` / `createdBy` / `fields` | ❌ 核心层忽略 | ⚠️ 画板层 | ⚠️ 画板层 |

### 8.2 已知行为陷阱

| # | 陷阱 | 影响 | 建议 |
| --- | --- | --- | --- |
| 1 | `autoRestart` 声明无效，**但平台总是自动重启**（1s/3s/9s，最多 3 次，用尽后 `connected=false` + 「进程崩溃且自动重启次数用尽」） | 写 `"autoRestart": false` **不会**阻止重启，与语义相反 | 不要依赖该字段；如需禁止重启，目前只能不声明 `process` |
| 1b | ~~60s 全局超时无法覆盖~~ | **已解除**（2026-09-15）：模型 A 可用 `dataTypes[].timeoutSeconds` 声明 1..3600 秒 | 见 §5.2 |
| 2 | 模型 A 清单会被模型 B 加载器**误拾取** | `scanAndLoadDataSources` **无 `process == null` 守卫**，`processExe` 返回 `''` → 启动空路径进程失败 → 每个模型 A 插件在启动期产生一条「加载失败」错误日志 | 仅噪音，不影响功能；修复方式为加载器加守卫 |
| 3 | `ttl` 大写单位静默回落 5 分钟 | 缓存策略静默失效 | 单位一律小写 |
| 4 | `endpoint` 缺 `{port}` | 会请求固定端口 | 模型 B 务必用 `{port}` |
| 5 | `category` 无枚举 | 实测出现 `zju_grades2`、`成绩` 等不一致值，UI 分组混乱 | 复用既有分类词表（教务/校园/生活/财经/开发/资讯/娱乐…） |

### 8.3 真实清单的字段使用分布（25 个 manifest 实测）

```
模型分布：A(script) = 23   B(process) = 2

顶层字段：type 25/25 · runtime 25/25 · dataTypes 25/25 · id 23/25 · name 23/25
          script 23/25 · androidSupport 20/25 · auth 5/25
          boardId 2/25 · createdBy 2/25 · process 2/25 · preferredPort 2/25

dataTypes[] 字段：name 33 · category 33 · displayName 33 · ttl 33
                  persistentKey 31 · typeArg 30 · fallbackJson 19
                  stream 2 · fields 2 · endpoint 2

ttl 实测取值：30m×10 · 5m×5 · 6h×4 · 1h×4 · 24h×3 · 30s×3 · 60m×2 · 15m · 10m
```

> 注：`fields` 出现 2 次即漂移 #3 中爬虫生成的那两份清单。

---

## 8.4 后台自动刷新（影响 `ttl` 选型）

平台在 App 启动后即进入**时钟对齐的周期调度**（锚点：`lib/app.dart#startAutoRefresh` →
`core/data/orchestrator.dart#startAutoRefresh` → `_runAutoRefreshTick`）：

| 行为 | 细节 |
| --- | --- |
| 启动即刷一轮 | `app.dart` 首帧后 `refreshAllStale()`（不 await，不阻塞 UI） |
| 周期 | 默认 **5 分钟**，对齐时钟刻度（相位锁定 Timer，非"启动后每 5 分钟"） |
| 刷谁 | 所有 `isFresh == false` 的源 |
| **失败源** | **周期性重试**（「报错 ≠ 终态」）；UI 显示 `lastError` 但会自动恢复 |
| 变更通知 | 刷新完成经 `DataChangeEvent` 推给 UI（前端始终读磁盘缓存，不等拉取） |

### 对插件作者的三条含义

1. **`ttl` 决定重拉频率**——不是"过期后某天"，而是"下一个 5 分钟刻度检查时"。
   元数据源建议 `30m`~`24h`；**别设过短**，否则每 5 分钟真的重拉一次。
2. **失败不会永久卡住**——拉取失败会保持 `lastError` 并 `connected=false`，
   但下一个 tick 仍会重试。插件无需自己做重试循环。
3. **超时预算按"每 tick 一个源"评估**——一轮 tick 会串行刷所有过期源；
   若某源冷启动耗时接近其 `timeoutSeconds`（最长 3600s），会拖长整轮。

---

## 9. 与既有文档的漂移更正

以下 5 处经代码核对，**以本节为准**：

| # | 既有文档表述 | 代码实况 | 影响 |
| --- | --- | --- | --- |
| 1 | `process.scope/autoStart/autoRestart/protocol` 列为有默认值的生效字段（`plugin-data-source.md` §「process 对象增强」表） | `DataSourceLoader` **完全不读这四个字段**（仅 `core/module/module_descriptor.dart` 即 **module 域**读取） | 插件作者会以为设了有效 |
| 2 | 「**模型 B** 则用 `file.downloadEndpoint` 作为统一下载端点」（同文档 `file` 段） | 模型 B `_registerAllTypes` **不调用** `registerFile` → `orch.fileOf()` 恒 `null` | 模型 B 的文件下载声明失效 |
| 3 | 未提及 `fields` / `boardId` / `createdBy` 的归属 | 这 3 个字段**核心层不解析**，仅画板层读原始 JSON；爬虫生成器**正在产出**它们 | 作者误以为核心层支持 |
| 4 | `stream` 描述为可用能力并附完整示例（`plugin-data-source.md` §「stream」+ `example-data-video_stream`） | `registerStream` **无生产调用点**，SSE 端点恒 404 | 声明后零效果 |
| 5 | 未声明 `ttl` 大小写敏感性 | 正则大小写敏感，`"10M"` 静默回落 5 分钟 | 缓存静默失效 |

**两份既有文档的关系**：`plugin-data-source.md`（规范）与
`plugin-authoring-guide-data.md`（指南）内容高度重叠，同一字段在两处各维护一份
——**这正是漂移的温床**。建议：
- 本文作为**唯一字段定义源**；
- 既有两份文档瘦身为「快速上手 + 指向本文」，不再各自维护字段表。

---

## 10. 兼容与演进政策

### 10.1 v1 兼容承诺

- **新增可选字段**：小版本内追加，缺省时**零行为变化**（本协议既有风格）。
- **未知字段**：继续静默忽略（不升级为错误——否则存量清单会集体失效）。
- **破坏性变更**：必须升 `v2`，且平台需并行支持 v1 至少一个发布周期。

### 10.2 manifest 显式声明协议版本（建议，暂未实现）

当前 manifest **没有版本字段**，平台也无法区分 v1/v2。
建议后续在顶层引入：

```json
{ "protocol": "data-source/v1", ... }
```

缺省视为 `v1`（零行为变化）。**在该字段落地前，请勿在清单中写入它**
（会被静默忽略，造成「写了没生效」的困惑）。

### 10.3 待接线清单（按优先级）

| 优先级 | 项 | 说明 |
| --- | --- | --- |
| P0 | `process` 守卫 | `scanAndLoadDataSources` 跳过无 `process` 的清单，消除 23 个假错误日志 |
| P0 | `autoRestart` 语义对齐 | 要么接线（读字段决定是否重启），要么从协议的「生效字段」中移除 |
| P1 | `file` 模型 B 接线 | `_registerAllTypes` 补 `registerFile` |
| P1 | `stream` 接线或降级 | 接线 `registerStream`，或在协议中明确标记为「实验/未实现」 |
| P2 | 枚举严格校验 | `runtime`/`scope`/`protocol` 引入 fail-fast 校验 |
| P2 | `ttl` 容错 | 支持大写单位，或对无法识别的值**告警**而非静默 |

---

## 附录 A：最小可用清单（模型 A）

```json
{
  "type": "data-source",
  "id": "my-source",
  "name": "我的数据源",
  "script": "fetch.py",
  "runtime": "python",
  "androidSupport": true,
  "dataTypes": [
    {
      "name": "my_data",
      "typeArg": "my_data",
      "category": "教务",
      "displayName": "我的数据",
      "ttl": "30m",
      "persistentKey": "my_data_v1",
      "fallbackJson": { "items": [] }
    }
  ]
}
```

```python
#!/usr/bin/env python3
"""最小模型 A 实现：只要 stdout 输出单个 JSON 对象。"""
import json, os, sys

def arg(flag):
    a = sys.argv
    return a[a.index(flag) + 1] if flag in a else None

# 桌面走 argv；安卓除 argv 外还有环境变量兜底
project_root = arg('--project-root') or os.environ.get('PROJECT_ROOT')
greenix_config = arg('--greenix-config') or os.environ.get('GREENIX_CONFIG_PATH')
which = arg('--type') or 'my_data'

# 注意：不要用相对路径（安卓 CWD=/）
try:
    print(json.dumps({"items": []}, ensure_ascii=False))
except Exception as e:
    print(json.dumps({"error": f"抓取失败：{e}"}, ensure_ascii=False))
```

## 附录 B：最小可用清单（模型 B）

```json
{
  "type": "data-source",
  "id": "my-server",
  "name": "我的服务型数据源",
  "process": { "exe": "server.py" },
  "runtime": "python",
  "preferredPort": 0,
  "dataTypes": [
    { "name": "my_status", "category": "系统", "displayName": "状态",
      "ttl": "30s", "endpoint": "/status" }
  ]
}
```

```python
#!/usr/bin/env python3
"""最小模型 B 实现：打印 PORT:<n>，提供 /health 与 endpoint。"""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def _send(self, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        if self.path == '/health':
            self._send({"ok": True})
        elif self.path == '/status':
            self._send({"connected": True})
        else:
            self.send_response(404); self.end_headers()
    def log_message(self, *a): pass

srv = HTTPServer(('127.0.0.1', 0), H)
# 必须原样输出 PORT:<十进制端口>，平台逐行扫描，10 秒内未探测到即 kill
print(f"PORT:{srv.server_port}", flush=True)
srv.serve_forever()
```

---

## 变更记录

| 日期 | 版本 | 变更 |
| --- | --- | --- |
| 2026-09-15 | v1 | 首版。由代码逆向重写，取代既有两份文档的字段定义；记录 5 处漂移与 5 项待接线 |
