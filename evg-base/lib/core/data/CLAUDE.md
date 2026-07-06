# Data 模块 — AI 协作文档

> 维护者：Data 工程师 | 最后更新：2026-07-06

---

## 模块架构概览

```
                    ┌──────────────────────┐
                    │   DataOrchestrator    │  ← 统一入口：register / get / refresh / status
                    └──────────┬───────────┘
                               │
          ┌────────────────────┼────────────────────┐
          ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  DataSourceLoader│  │     Cache       │  │  DataHttpServer │
│  (.exe 生命周期) │  │  (持久化缓存)    │  │  (REST 端点)    │
└────────┬────────┘  └─────────────────┘  └─────────────────┘
         │
         ▼
┌─────────────────┐
│  plugin.exe     │  ← 外部数据源进程（Python/Go/Rust/...）
│  HTTP 服务       │
└─────────────────┘
```

**数据流**：`DataSourceLoader` 启动外部 `.exe` → 健康检查 → 将 `DataType` + fetcher 注册到 `DataOrchestrator` → 消费者通过 `orch.get(type)` 获取数据 → `Cache` 持久化缓存 → `DataHttpServer` 暴露 REST 端点供外部查询。

---

## 目录结构

```
lib/core/data/
├── data.dart                    # Barrel 导出——消费者只需 import 'data.dart'
├── type.dart                    # DataType<T> 类型描述符
├── exceptions.dart              # DataTypeNotRegisteredException / DataFetchException
├── orchestrator.dart            # DataOrchestrator + DataSourceStatus（核心中枢）
├── cache.dart                   # Cache 持久化缓存单例（文件存储）
├── provider.dart                # Riverpod Provider（可选，需 flutter_riverpod）
├── data_http_server.dart        # HTTP 管理服务器（7 个 REST 端点）
├── plugin/
│   ├── data_source_manifest.dart  # DataSourceManifest / DataSourceTypeDecl 模型
│   ├── data_source_loader.dart    # .exe 进程生命周期管理 + scanAndLoadDataSources
│   └── data_source_fetcher.dart   # fetchRemoteManifestList / fetchRemoteManifest（远程拉取）
├── lib/
│   ├── core/log.dart            # Log 日志单例（本模块副本）
│   ├── path_provider_stub/      # path_provider 的纯 Dart stub（替代 Flutter 依赖）
│   └── flutter_riverpod_stub/   # flutter_riverpod 的纯 Dart stub（替代 Flutter 依赖）
├── docs/
│   ├── plugin-data-source.md    # 数据源插件开发规范 v2
│   └── plugin-authoring-guide-data.md  # Data 数据源插件撰写指南
├── example/
│   ├── example.dart             # 完整 API 使用示例
│   └── plugins/douban/          # 豆瓣 Top250 爬虫插件（真实可运行示例）
├── test/
│   ├── orchestrator_test.dart   # 36 用例：注册/获取/刷新/状态/连通性/自动刷新/持久化恢复
│   └── cache_test.dart          # 12 用例：读写/删除/清空/编码/批量
├── pubspec.yaml
├── dart_test.yaml               # concurrency: 1（缓存单例需要顺序执行）
├── README.md                    # 面向开发者的 API 文档
└── CLAUDE.md                    # 本文件
```

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
- `name` 作为全局唯一标识，支持覆盖注册（重复注册同一 name 覆盖旧 fetcher）
- `category` 支持按业务领域分组，`categories` / `statusByCategory` 用于过滤
- `persistentKey` 独立于 `name`，允许多个 DataType 共享同一缓存键
- `T` 泛型确保 `get/refresh` 返回值类型安全

### 2. 缓存策略

三级策略，通过 `orch.get()` / `orch.refresh()` / `orch.refreshAllStale()` 实现：

| 方法 | 策略 | 行为 |
|------|------|------|
| `get(type)` | 缓存优先 | 有缓存就返回（过期也返回），无缓存则拉取 |
| `refresh(type)` | 强制拉取 | 忽略缓存，合法数据覆写缓存，非法返回 null 不覆写 |
| `refreshAllStale()` | 批量过期刷新 | 遍历所有 isFresh==false 的源，逐一 refresh |
| `invalidate(type)` | 清缓存 | 异步删除磁盘缓存文件 |

**设计理由**：
- 缓存优先避免性能灾难（每次都强制刷新）
- 过期也返回保证数据可用性（用户不会看到空白）
- 非法数据不覆写保证缓存完整性（旧数据仍在）
- TTL 可配置，默认 5 分钟

**Cache 实现细节**：
- 文件存储：`{appSupportDir}/web_cache/{key}.json`
- 每个缓存条目包含 `{data, cachedAt}`
- `Cache` 为异步初始化的单例，`instanceOrNull` 未初始化时返回 null
- 单线程访问，不保证并发安全

### 3. 查询 vs 订阅模式

当前仅支持**拉取模式**（pull），不包含推送/订阅（push/subscribe）。数据新鲜度由消费者通过 TTL 和 `refreshAllStale` 定时刷新控制。

**设计理由**：Phase 2 阶段保持简洁，推送模式可后续通过 WebSocket 扩展。

### 4. 数据源生命周期

**内置数据源**：直接在 Dart 中定义 `DataType` + `Future<T> Function()` fetcher，注册到 `DataOrchestrator`。

**外部插件数据源**：通过 `DataSourceLoader` 管理 `.exe` 进程生命周期：
1. 启动 `.exe`（以 `data/` 为工作目录）
2. 等待 stdout 输出 `PORT:<数字>`
3. 请求 `GET /health` 确认就绪
4. 将各 `dataType` 注册到 `DataOrchestrator`
5. 此后 `orch.get(type)` → HTTP 调用 `.exe` 服务

**进程终止**：SIGTERM → 2 秒超时 → SIGKILL

### 5. DataSourceStatus 三态

| 状态 | 含义 | 判断依据 |
|------|------|----------|
| **连通** | `connected == true` | 最近一次拉取/连通测试成功 |
| **新鲜** | `isFresh == true` | `now - lastFetchedAt < ttl` |
| **错误** | `connected == false` | 最近一次拉取/连通测试失败 |

`freshnessLabel` 返回 `"新鲜"` / `"过期"` / `"从未"`；`relativeTime` 返回 `"刚刚"` / `"N 分钟前"` / `"N 小时前"` / `"N 天前"`。

---

## 开发约定

### 新增 DataType

```dart
const myType = DataType<List<MyModel>>(name: 'my_data', category: '业务域',
  displayName: '我的数据', ttl: Duration(hours: 1), persistentKey: 'my_data_cache');
orch.register(myType, _fetchMyData);
final data = await orch.get(myType);
```

### 扩展 DataHttpServer 端点

在 `_routes`（精确匹配）或 `_paramRoutes`（`:param` 占位符）中添加 `'METHOD /path'` 条目。

### 新增外部数据源插件

`plugins/<name>/data/manifest.json` → HTTP 服务（`/health` + 数据端点）→ 编译 `.exe` → `scanAndLoadDataSources`。详见 `docs/plugin-authoring-guide-data.md`。

---

## Stub 隔离说明

本模块通过 stub 包实现与 Flutter SDK 的隔离：

| Stub 包 | 路径 | 替代的真实包 |
|---------|------|------------|
| `path_provider_stub` | `lib/path_provider_stub/` | `path_provider` (Flutter) |
| `flutter_riverpod_stub` | `lib/flutter_riverpod_stub/` | `flutter_riverpod` (Flutter) |

**设计理由**：Data 模块是纯 Dart，不应依赖 Flutter SDK。stub 包提供最小签名，使 `dart analyze` 和 `dart test` 可独立运行。

---

## 测试策略

### orchestrator_test.dart（36 用例）

| 分组 | 用例数 | 覆盖内容 |
|------|--------|----------|
| 注册 | 7 | 注册/未注册/重复覆盖/Status 创建/批量注册/注销/注销未注册 |
| 获取 | 6 | 首次拉取/缓存命中/无缓存 key/未注册异常/null 返回/异常处理 |
| 刷新 | 4 | 强制拉取/覆写缓存/null 不覆写/invalidate 清缓存 |
| refreshAllStale | 2 | 全量过期刷新/指定 types 过滤 |
| 状态 | 6 | allStatuses 排序/categories 去重/statusByCategory 过滤/成功更新/失败更新/计数 |
| DataSourceStatus | 4 | 从未/新鲜/过期/relativeTime |
| 连通性 | 3 | 单源成功/单源失败/全源测试 |
| 自动刷新 | 3 | 启动/停止/未注册停止 |
| refreshStatusFromDisk | 1 | 从缓存恢复时间戳 |

### cache_test.dart（12 用例）

| 分组 | 用例数 | 覆盖内容 |
|------|--------|----------|
| 基本读写 | 4 | 写入读取/不存在 key/覆盖写入/时间戳 |
| 删除 | 3 | 删除后读取/删除不存在/清空 |
| 编码 | 3 | 非 ASCII/JSON/空字符串 |
| 批量 | 2 | 批量写入不同 key/顺序覆写 |

### 运行测试

```bash
dart pub get
dart test
# 或指定文件：
dart test test/cache_test.dart
dart test test/orchestrator_test.dart
```

**注意**：`dart_test.yaml` 设置 `concurrency: 1`，因为 Cache 单例需要顺序执行避免文件竞争。

---

## 跨模块接口契约

### DataHttpServer 端点（7 个）

| 方法 | 路径 | 说明 | 响应格式 |
|------|------|------|----------|
| `GET` | `/data/health` | 健康检查 | `{"status": "ok"}` |
| `GET` | `/data/types` | 列出所有注册类型 | `{"types": [{name, category, displayName, isFresh, connected}]}` |
| `GET` | `/data/types/:name` | 获取指定类型数据 | `{"data": ...}` 或 `{"error": "..."}` |
| `POST` | `/data/types/:name/refresh` | 强制刷新指定类型 | `{"data": ...}` 或 `{"error": "..."}` |
| `GET` | `/data/status` | 所有数据源状态 | `{"statuses": [...], "summary": {total, connected, fresh}}` |
| `GET` | `/data/status/:name` | 单个数据源状态 | `{"name": ..., "connected": ..., ...}` 或 404 |
| `POST` | `/data/connectivity/test` | 测试全量连通性 | `{"results": {"name1": true, "name2": false}}` |

### 数据格式约定

- 所有响应为 `application/json`，包含 `Access-Control-Allow-Origin: *`
- 成功返回 `200`，未找到返回 `404`，内部错误返回 `500`
- 外部插件数据源需返回 `Content-Type: application/json`，body 为合法 JSON
- `DataSourceStatus` 序列化包含：`name, category, displayName, connected, isFresh, freshnessLabel, relativeTime, lastFetchedAt, lastError`

### 数据源插件 manifest.json 格式

```json
{
  "type": "data-source",
  "id": "plugin-id",
  "name": "展示名",
  "process": "plugin.exe",
  "preferredPort": 0,
  "dataTypes": [
    {
      "name": "type_name",
      "category": "分类",
      "displayName": "展示名",
      "ttl": "5m",
      "persistentKey": "cache_key",
      "endpoint": "/api/data"
    }
  ]
}
```

### 插件 .exe 行为契约

1. 监听 `127.0.0.1` 的随机端口
2. stdout 输出 `PORT:<数字>`（必须 flush）
3. 实现 `GET /health` → `200 OK`
4. 数据端点返回 `200 OK` + JSON body
5. 平台 10 秒超时未探测到端口 → 进程终止
6. 接收 SIGTERM → 2 秒 → SIGKILL

---

## 依赖关系

```
data 模块
├── path: ^1.8.0
├── meta: ^1.9.0
├── path_provider (stub) → 文件系统目录
├── flutter_riverpod (stub) → provider.dart 签名
└── test: ^1.24.0 (dev)

被依赖：
├── Agent 模块 → orch.get(type) 获取运行时数据
├── Module 模块 → orch.get(type) 获取模块数据
├── Renderer 层 → orch.allStatuses / statusByCategory 状态可视化
└── 外部消费者 → DataHttpServer REST 端点
```
