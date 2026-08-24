# Data 模块 — AI 协作文档

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 README.md 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-data |
| 适用 | AI 协作者（data 子包） |

> 维护者：core-data OWNER | 最后更新：2026-08-25
>
> **HTML-first 事实**：HTML 插件通过 `platform.data.get/refresh/subscribe/testConnectivity` 消费数据中枢；
> 外部数据源插件（CLI 脚本 / `.exe`）属于开发者模式，用户侧优先复用内置/已有数据源。

---

## 模块架构概览

```
                    ┌──────────────────────────────────────┐
                    │          DataOrchestrator            │  ← 统一入口：register / get / fastRead / refresh / status / 事件
                    └──────────────────┬───────────────────┘
              ┌────────────────────────┼──────────────────────────┐
              ▼                        ▼                          ▼
    ┌──────────────────┐    ┌───────────────────┐    ┌────────────────────────┐
    │   Cache（两级）   │    │   DataHttpServer   │    │  变更通知（diff 事件）  │
    │   磁盘 + 内存     │    │   （REST 端点）    │    │  DataChangeEvent        │
    └────────┬─────────┘    └───────────────────┘    └───────────┬────────────┘
             │                                                   │
             ▼                                                   ▼
   ┌────────────────────────────────────────┐           renderer 订阅刷新 UI
   │             数据源（两种模型）            │
   ├────────────────────────────────────────┤
   │ 模型 A：CLI 一次性脚本（主流/新契约）      │
   │   registerDataSourcesFromManifest        │
   │   Process.run script --type <t>          │
   │   stdout 顶层 JSON Map → 注册 fetcher    │
   ├────────────────────────────────────────┤
   │ 模型 B：HTTP 长驻服务（.exe，开发者模式）  │
   │   DataSourceLoader：PORT: / health 探测  │
   │   orch.get(type) → HTTP {port}/endpoint  │
   └────────────────────────────────────────┘
```

**数据流（模型 A / CLI）**：`registerDataSourcesFromManifest` 读取 `data/manifest.json` → 为每个 `dataType` 注册「`Process.run <script> --type <typeArg> --project-root <root> --greenix-config <cfg>` + stdout JSON Map 解析」的 fetcher → 消费者 `orch.get(type)` 时一次性执行脚本拿数据 → `Cache` 持久化缓存 → 后台自动刷新时经 `data_diff` 计算变化并发出 `DataChangeEvent` → `DataHttpServer` 暴露 REST 端点（含运行期热注册 `POST /data/register`）供外部调用。

**数据流（模型 B / HTTP）**：`DataSourceLoader` 启动外部 `.exe`（长驻 HTTP 服务）→ 探测 `PORT:` 行 → `GET /health` 健康检查 → 注册 fetcher（每次 `orch.get` 转为 HTTP 拉取 `{port}/endpoint`）。

---

## 目录结构

```
lib/core/data/
├── data.dart                    # Barrel 导出（不含 provider.dart）
├── type.dart                    # DataType<T> 类型描述符
├── exceptions.dart              # DataTypeNotRegisteredException / DataFetchException
├── orchestrator.dart            # DataOrchestrator + DataSourceStatus + 变更事件（核心中枢）
├── cache.dart                   # Cache 持久化缓存单例（磁盘文件存储）
├── data_diff.dart               # DataDiff / DataChangeEvent / computeDataDiff（变更差异引擎）
├── provider.dart                # Riverpod Provider（可选，不被 barrel 导出）
├── data_http_server.dart        # HTTP 管理服务器（REST 端点）
├── register_data_source.dart    # CLI 数据源热注册：registerDataSourcesFromManifest
├── plugin/
│   ├── data_source_manifest.dart  # DataSourceManifest / DataSourceTypeDecl 模型
│   ├── data_source_loader.dart    # HTTP 长驻 .exe 生命周期 + scanAndLoadDataSources
│   └── data_source_fetcher.dart   # fetchRemoteManifestList / fetchRemoteManifest（远程拉取）
├── lib/                        # Stub 隔离层（纯 Dart 独立测试）
│   ├── flutter_stub/           #   Flutter SDK 最小签名（foundation / services）
│   ├── path_provider_stub/     #   path_provider 最小签名
│   ├── flutter_riverpod_stub/  #   flutter_riverpod 最小签名
│   └── core/                   #   根 core 副本：log / plugin_runner / utils（python_env、path_sandbox）
├── docs/
│   ├── plugin-data-source.md    # 数据源插件开发规范（CLI + HTTP 双模型）
│   └── plugin-authoring-guide-data.md  # Data 数据源插件撰写指南
├── example/
│   ├── example.dart             # 完整 API 使用示例
│   └── plugins/douban/          # 豆瓣 Top250 爬虫插件（HTTP 模型，真实可运行示例）
├── test/
│   ├── orchestrator_test.dart   # 用例：注册/获取/刷新/空数据/变更事件/状态/连通性/自动刷新
│   ├── cache_test.dart          # 用例：读写/删除/清空/编码/批量
│   └── data_diff_test.dart      # 用例：差异引擎
├── pubspec.yaml
├── dart_test.yaml               # concurrency: 1（缓存单例需要顺序执行）
├── README.md                    # 面向开发者的 API 文档
└── CLAUDE.md                    # 本文件
```

> **Barrel 注意**：`data.dart` 会 export `data_http_server.dart` / `register_data_source.dart` / `plugin/*`，
> 它们依赖根包 core 结构（`greenix_path` / `plugin_runner` 等）。子包独立 `dart test` 只覆盖纯数据文件，
> 测试文件精确 import（`../orchestrator.dart` 等）而非 barrel。

---

## 核心设计决策

### 1. DataSource 注册模型

每种数据源通过 `DataType<T>` 唯一标识，注册时绑定 `Future<T> Function()` 拉取函数。

```dart
const scoresType = DataType<Map<String, dynamic>>(
  name: 'scores',         // 全局唯一
  category: '教务',        // 分类标签
  displayName: '成绩单',   // UI 展示名
  ttl: Duration(minutes: 5),  // 缓存有效期
  persistentKey: 'scores',    // 持久化键，不设则不缓存
);
orch.register(scoresType, _fetchScores);
```

**设计理由**：
- `name` 作为全局唯一标识，支持覆盖注册（重复注册同一 name 覆盖旧 fetcher，Status 保留）
- `category` 支持按业务领域分组，`categories` / `statusByCategory` 用于过滤
- `persistentKey` 独立于 `name`，允许多个 DataType 共享同一缓存键
- `T` 泛型确保 `get/refresh` 返回值类型安全
- 字符串名称访问（`getByName` / `fastReadByName` / `refreshByName` / `typeByName`）供 Agent Tool、HTTP 端点等无类型参数场景使用

### 2. 缓存策略（两级缓存 + 空数据门控）

`DataOrchestrator` 持有**磁盘缓存（Cache）+ 内存缓存（_memCache）**两级：

| 方法 | 策略 | 行为 |
|------|------|------|
| `get(type)` | 缓存优先 | 有 persistentKey：读磁盘 → 命中写内存并返回（过期也返回）；未命中则拉取。无 persistentKey：每次拉取 |
| `fastRead(type)` | 内存快读 | 内存命中直接返回（零磁盘 I/O），未命中 fallback `get()`；模块页面进入时避免重复磁盘读 |
| `refresh(type)` | 强制拉取 | 忽略缓存；非空合法数据覆写磁盘+内存，空/非法返回 null 不覆写 |
| `refreshAllStale({types})` | 批量过期刷新 | 遍历 isFresh==false 的源逐一 refresh；默认 `notifyOnChange: true`（后台路径） |
| `refreshAllSerial({types})` | 串行全量拉取 | 启动期不再调用，保留给显式全量刷新；单源失败只记录不阻塞 |
| `invalidate(type)` | 清缓存 | 同步清内存 + 异步删磁盘文件 |

**空数据门控（`_isEmptyData`）**：拉取结果为空视为拉取失败，不覆写磁盘+内存缓存，旧数据保持可用：
null / 空白字符串 / 空 List / 空 Map / 空 Set。**注意**：`{'courses': []}` 这类「包装了空列表的非空 Map」不算空（结构合法，说明源可达），由消费方自行处理。

**设计理由**：
- 两级缓存避免性能灾难（fastRead 零 I/O；get 磁盘命中不触发真实拉取）
- 过期也返回保证数据可用性（用户不会看到空白）
- 空/非法数据不覆写保证缓存完整性（旧数据仍在）
- TTL 可配置，默认 5 分钟

**Cache 实现细节**：
- 文件存储：`{appSupportDir}/web_cache/{key}.json`
- 每个缓存条目包含 `{data, cachedAt}`（data 为 String 原文或 JSON 编码串）
- `Cache` 为异步初始化的单例（`getInstance()`），`instanceOrNull` 未初始化时返回 null
- 单线程访问，不保证并发安全（`dart_test.yaml` 设 `concurrency: 1`）

### 3. 查询 vs 订阅：变更通知（DataChangeEvent）

传输层仍为**拉取模式**（pull），但新增**后台刷新变更通知**：`startAutoRefresh`（默认每 5 分钟）驱动
`refreshAllStale(notifyOnChange: true)`，成功覆写缓存且**内容实质变化**时发出 `DataChangeEvent`：

- **diff 基线**：覆写前的旧缓存（磁盘优先，其次内存）；首次拉取（无基线）不算变更
- **易变字段忽略**：`kVolatileDiffKeys`（`ts` / `timestamp` / `updatedAt` / `updated_at` / `lastFetchedAt` / `cachedAt` / `fetchedAt` / `fetched_at` / `at` / `time` / `refreshAt`）在比较时递归剥除，避免时间戳造成假变更
- **空数据不发事件**：空数据不覆写缓存，自然不发事件
- **API**：`addDataChangeListener(fn)` / `removeDataChangeListener(fn)`；事件含 `sourceName` / `displayName` / `diff`（`DataDiff`：added/removed/changed 计数 + 示例条目 + `summarize()` 中文摘要）
- 用户主动 `refresh()` 默认 `notifyOnChange: false`（不打扰）

**设计理由**：后台循环刷新是「变更通知源」，renderer 可据此刷新 UI；主动拉取是用户意图，不打扰。

### 4. 数据源生命周期（两种模型）

**内置数据源**：直接在 Dart 中定义 `DataType` + `Future<T> Function()` fetcher，注册到 `DataOrchestrator`。

**模型 A — CLI 一次性脚本（主流新契约）**：`registerDataSourcesFromManifest`（见 `register_data_source.dart`）
1. 读取 `plugins/<name>/data/manifest.json`（`type: "data-source"`，含 `script` 字段）
2. 每个 `dataType` 注册 fetcher：`Process.run <script> --type <typeArg> --project-root <projectRoot> --greenix-config <greenixConfigPath>`（工作目录为 `data/`，runtime 经 `sharedPluginRunner` 解析）
3. 解析 stdout：**顶层必须是 `Map<String, dynamic>`**（列表型包 `{"items": [...]}`）
4. `exitCode != 0` 或 stdout JSON 含 `error` key → 拉取失败（旧缓存保留）
5. 脚本缺失时仍注册（运行时拉取失败并记录日志）

**模型 B — HTTP 长驻服务（.exe）**：通过 `DataSourceLoader` 管理进程生命周期：
1. 启动 `.exe`（以 `data/` 为工作目录，`preferredPort > 0` 时传 `--port N`）
2. 等待 stdout 输出 `PORT:<数字>`（10 秒超时）
3. 请求 `GET /health` 确认就绪
4. 将各 `dataType` 注册到 `DataOrchestrator`（`orch.get(type)` → HTTP 调用 `{port}/endpoint`）

**进程终止（模型 B）**：SIGTERM → 2 秒超时 → SIGKILL。插件崩溃 → connected=false，已注册 DataType 保留。

**Android 安全网**：manifest `androidSupport: false`（如依赖 C 扩展 wheel 缺失的 OCR/PDF/ML 插件）在安卓自动跳过注册，避免崩溃。

### 5. DataSourceStatus 状态

| 状态 | 含义 | 判断依据 |
|------|------|----------|
| **连通** | `connected == true` | 最近一次拉取/连通测试成功 |
| **新鲜** | `isFresh == true` | `now - lastFetchedAt < ttl` |
| **错误** | `connected == false` | 最近一次拉取/连通测试失败 |

`freshnessLabel` 返回 `"新鲜"` / `"过期"` / `"从未"`；`relativeTime` 返回 `"刚刚"` / `"N 分钟前"` / `"N 小时前"` / `"N 天前"`（未拉取过返回 `"从未更新"`）。
`DataSourceStatus` 字段：`name` / `category` / `displayName` / `cacheKey` / `ttl` / `connected` / `lastFetchedAt` / `lastError`。
`refreshStatusFromDisk()` 在启动时从磁盘缓存恢复 `lastFetchedAt`。

---

## 开发约定

### 新增 DataType

```dart
const myType = DataType<List<MyModel>>(name: 'my_data', category: '业务域',
  displayName: '我的数据', ttl: Duration(hours: 1), persistentKey: 'my_data_cache');
orch.register(myType, _fetchMyData);
final data = await orch.get(myType);          // 缓存优先
final quick = await orch.fastRead(myType);    // 内存快读（模块页面进入时）
```

### 扩展 DataHttpServer 端点

在 `_routes`（精确匹配）或 `_paramRoutes`（`:param` 占位符）中添加 `'METHOD /path'` 条目。

### 注册 CLI 数据源（模型 A）

```dart
registerDataSourcesFromManifest(
  orch: orch,
  pluginDir: '<plugins>/data-<name>',
  projectRoot: projectRoot,
  // onlyType: 'type_name',   // 运行期定向热注册
);
```

### 新增 HTTP 数据源插件（模型 B）

`plugins/<name>/data/manifest.json` → HTTP 服务（`/health` + 数据端点）→ 编译 `.exe` → `scanAndLoadDataSources`。详见 `docs/plugin-authoring-guide-data.md`。

---

## Stub 隔离说明

本模块通过 stub 包实现与 Flutter SDK 的隔离（纯 Dart，可独立 `dart test`）：

| Stub 包 | 路径 | 替代的真实包 |
|---------|------|------------|
| `flutter_stub` | `lib/flutter_stub/` | 整个 Flutter SDK（`foundation`: debugPrint / visibleForTesting；`services`: MethodChannel / EventChannel） |
| `path_provider_stub` | `lib/path_provider_stub/` | `path_provider` (Flutter) |
| `flutter_riverpod_stub` | `lib/flutter_riverpod_stub/` | `flutter_riverpod` (Flutter) |

`lib/core/` 下是根 core 的**本地副本**（子包测试隔离用，与根包同步）：`log.dart`、`plugin/plugin_runner.dart`
（`SubprocessRunner` / `ChaquopyRunner` / `sharedPluginRunner`）、`utils/python_env.dart`、`utils/path_sandbox.dart`。

**设计理由**：Data 模块是纯 Dart，不应依赖 Flutter SDK。stub 包提供最小签名，使 `dart analyze` 和 `dart test` 可独立运行。
注意：`data_http_server.dart` / `register_data_source.dart` / `plugin/data_source_loader.dart` 还依赖根包 core（`greenix_path` 等），
子包独立测试只覆盖纯数据文件。

---

## 测试策略

### orchestrator_test.dart

| 分组 | 覆盖内容 |
|------|----------|
| 注册 | isRegistered/覆盖注册/Status 创建/批量注册/注销/注销未注册 |
| 获取 | 首次拉取/缓存命中/无 persistentKey 每次拉取/未注册异常/null 返回/异常处理 |
| 刷新 | 强制拉取/覆写缓存/null 不覆写/invalidate 清缓存 |
| 空数据门控 | 空 Map/空 List/空白字符串不覆写缓存 |
| 变更事件 | 首次无基线不发/内容变化发/未变不发/默认不打扰/空数据不发 |
| refreshAllStale | 全量过期刷新/指定 types 过滤 |
| 状态 | allStatuses 排序/categories 去重/statusByCategory 过滤/成功更新/失败更新/计数 |
| DataSourceStatus | 从未/新鲜/过期/relativeTime |
| 连通性 | 单源成功/单源失败/全源测试 |
| 自动刷新 | 启动/停止/未注册停止 |
| refreshStatusFromDisk | 从缓存恢复时间戳 |

### cache_test.dart

| 分组 | 覆盖内容 |
|------|----------|
| 基本读写 | 写入读取/不存在 key/覆盖写入/时间戳 |
| 删除 | 删除后读取/删除不存在/清空 |
| 编码 | 非 ASCII/JSON/空字符串 |
| 批量 | 批量写入不同 key/顺序覆写 |

### data_diff_test.dart

覆盖：相同数据无变化、Map 新增/移除 key、标量变化、嵌套 Map 递归、List 增删（标题字段标签）、
易变字段忽略、列表元素仅时间戳不同不算增删、字符串变化、类型变化、null 与空串、summarize 摘要、示例上限截断。

### 运行测试

```bash
dart pub get
dart test
# 或指定文件：
dart test test/cache_test.dart
dart test test/orchestrator_test.dart
dart test test/data_diff_test.dart
```

**注意**：`dart_test.yaml` 设置 `concurrency: 1`，因为 Cache 单例需要顺序执行避免文件竞争。
测试精确 import 纯数据文件（不 import barrel `data.dart`）。

---

## 跨模块接口契约

### DataHttpServer 端点

| 方法 | 路径 | 说明 | 响应格式 |
|------|------|------|----------|
| `GET` | `/data/health` | 健康检查 | `{"status": "ok"}` |
| `GET` | `/data/types` | 列出所有注册类型 | `{"types": [{name, category, displayName, isFresh, connected}]}` |
| `GET` | `/data/types/:name` | 获取指定类型数据 | `{"data": ...}`；拉取失败 `502 {"error","name"}`；未注册 `404` |
| `POST` | `/data/types/:name/refresh` | 强制刷新指定类型 | 同上 |
| `GET` | `/data/status` | 所有数据源状态 | `{"statuses": [...], "summary": {total, connected, fresh}}` |
| `GET` | `/data/status/:name` | 单个数据源状态 | 状态 JSON 或 404 |
| `POST` | `/data/connectivity/test` | 测试全量连通性 | `{"results": {"name1": true, "name2": false}}` |
| `POST` | `/data/register` | 运行期热注册 CLI 数据源（body `{"pluginDir": "..."}`） | `{"registered": [...], "pluginDir": ...}`；缺参 `400`；未注册到 `404` |

> `GET/POST /data/types/:name` 与 `POST /data/register` 会优先复用中枢已注册的 DataType（携带
> persistentKey/ttl），未注册时兜底空壳 DataType（拉取路径退化为异常/502）。

### 数据格式约定

- 所有响应为 `application/json`，包含 `Access-Control-Allow-Origin: *`
- 成功返回 `200`，未找到返回 `404`，拉取失败返回 `502`，内部错误返回 `500`
- 外部插件数据源需返回 `Content-Type: application/json`，body 为合法 JSON
- `DataSourceStatus` 序列化包含：`name, category, displayName, connected, isFresh, freshnessLabel, relativeTime, lastFetchedAt, lastError`

### 数据源插件 manifest.json 格式（双模型）

```json
{
  "type": "data-source",
  "id": "plugin-id",
  "name": "展示名",
  "script": "fetch.py",              // 模型 A（CLI）：脚本文件名，相对 data/ 目录
  "runtime": "python",               // 可选：native | python（默认 native，按扩展名也可推断）
  "androidSupport": true,            // 可选：false 时安卓跳过该数据源
  "dataTypes": [
    {
      "name": "type_name",
      "typeArg": "type_name",        // 可选：传给脚本的 --type 参数（默认同 name）
      "category": "分类",
      "displayName": "展示名",
      "ttl": "5m",
      "persistentKey": "cache_key",
      "endpoint": "/api/data"        // 仅模型 B（HTTP 长驻）使用
    }
  ]
}
```

> **模型 A（CLI）**：必填 `script`；每次拉取执行 `script --type <typeArg> --project-root <root> --greenix-config <cfg>`，
> stdout 顶层必须是 `Map<String, dynamic>`（列表型包 `{"items": [...]}`），`exitCode != 0` 或含 `error` key 视为失败。
> **模型 B（HTTP）**：必填 `process` + `endpoint`；长驻 HTTP 服务，`PORT:` 行 + `/health` 探测，`{port}` 由平台替换。
> 两种模型互斥：有 `script` 走 CLI，有 `process` 走 HTTP。

### 插件行为契约

**CLI 脚本（模型 A）**：
1. 接收参数 `--type <typeArg> --project-root <projectRoot> --greenix-config <greenixConfigPath>`
2. stdout 输出单个 JSON 对象（顶层 Map），UTF-8
3. 失败时：非零 exitCode，或 stdout JSON 含 `error` 字段（字符串错误信息）

**HTTP .exe（模型 B）**：
1. 监听 `127.0.0.1` 的随机端口
2. stdout 输出 `PORT:<数字>`（必须 flush）
3. 实现 `GET /health` → `200 OK`
4. 数据端点返回 `200 OK` + JSON body
5. 平台 10 秒超时未探测到端口 → 进程终止
6. 接收 SIGTERM → 2 秒 → SIGKILL

---

## 依赖关系

```
data 模块（pubspec.yaml，name: evergreen_base）
├── path: ^1.8.0
├── meta: ^1.9.0
├── flutter (stub) → lib/flutter_stub        # 替代 Flutter SDK
├── path_provider (stub) → lib/path_provider_stub
├── flutter_riverpod (stub) → lib/flutter_riverpod_stub
└── test: ^1.24.0 (dev)

被依赖：
├── Agent 模块 → orch.get(type) / getByName 获取运行时数据
├── Module 模块 → orch.get(type) / fastRead 获取模块数据
├── Renderer 层 → orch.allStatuses / statusByCategory 状态可视化 + DataChangeEvent 订阅刷新
├── HTML 插件 → platform.data.* JS Bridge（get/refresh/subscribe/testConnectivity）
└── 外部消费者 → DataHttpServer REST 端点
```
