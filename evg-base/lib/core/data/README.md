# Data Orchestrator

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 1.0 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | data 子包 |

> **快速导航**
> - 平台开发者 → `example/example.dart` | 测试：`test/orchestrator_test.dart` + `test/cache_test.dart`
> - 数据源插件开发者（开发者模式）→ `docs/plugin-authoring-guide-data.md` | 示例：`example/plugins/douban/`
> - HTML 插件作者 → 使用 `platform.data.*` JS Bridge 读取数据中枢，无需自建数据源
> - 核心源码 → `type.dart` `cache.dart` `orchestrator.dart` `data_http_server.dart` `plugin/`

## 平台开发 API

### DataType

| 属性 | 必填 | 说明 |
|------|------|------|
| `name` | ✓ | 唯一标识 |
| `category` | | 分类标签，默认 `"未分类"` |
| `displayName` | | UI 展示名，默认同 name |
| `ttl` | | 缓存有效期，默认 5 分钟 |
| `persistentKey` | | 持久化键，不设则不缓存 |

### DataOrchestrator

| 方法 | 说明 | 示例 |
|------|------|------|
| `register(type, fetcher)` | 注册数据类型与拉取方式 | `orch.register(scoresType, _fetchScores)` |
| | | 入: `DataType<T>`, `() → Future<T>` / 出: `void` |
| `registerAll(entries)` | 批量注册 | `orch.registerAll({scoresType: f1, newsType: f2})` |
| | | 入: `Map<DataType<T>, () → Future<T>>` / 出: `void` |
| `unregister(type)` | 注销并清除缓存 | `orch.unregister(scoresType)` |
| | | 入: `DataType` / 出: `void` |
| `get(type)` | 缓存优先获取 | `final data = await orch.get(scoresType)` |
| | | 入: `DataType<T>` / 出: `Future<T?>` |
| `refresh(type)` | 强制拉取，合法则覆写缓存 | `final data = await orch.refresh(scoresType)` |
| | | 入: `DataType<T>` / 出: `Future<T?>` |
| `refreshAllStale({types})` | 批量刷新过期数据 | `await orch.refreshAllStale()` |
| | | 入: `{List<DataType>?}` / 出: `Future<void>` |
| `invalidate(type)` | 清缓存（异步删除文件） | `await orch.invalidate(scoresType)` |
| | | 入: `DataType` / 出: `Future<void>` |
| `allStatuses` | 按分类排序的状态列表 | `final list = orch.allStatuses` |
| | | 出: `List<DataSourceStatus>` |
| `status(name)` | 按名称查询状态 | `final s = orch.status('scores')` |
| | | 入: `String` / 出: `DataSourceStatus?` |
| `statusByCategory(c)` | 按分类过滤 | `orch.statusByCategory('教务')` |
| | | 入: `String` / 出: `List<DataSourceStatus>` |
| `categories` | 所有分类名 | `orch.categories` |
| | | 出: `List<String>` |
| `connectedCount` | 已连通数 | `orch.connectedCount` → `int` |
| `freshCount` | 新鲜数 | `orch.freshCount` → `int` |
| `totalCount` | 总注册数 | `orch.totalCount` → `int` |
| `testConnectivity(name)` | 单源连通性测试 | `await orch.testConnectivity('scores')` |
| | | 入: `String` / 出: `Future<void>` |
| `testAllConnectivity()` | 全源测试 | `final r = await orch.testAllConnectivity()` |
| | | 出: `Future<Map<String, bool>>` |

### DataSourceStatus

| 属性 | 说明 |
|------|------|
| `name` / `category` / `displayName` | 基本信息 |
| `connected` | 连通状态 |
| `lastFetchedAt` / `lastError` | 最近拉取时间 / 最近错误 |
| `isFresh` | 是否在 TTL 内 |
| `freshnessLabel` | "新鲜" / "过期" / "从未" |
| `relativeTime` | "3 分钟前" 等人性化时间 |

### DataHttpServer

| 方法 | 说明 | 示例 |
|------|------|------|
| `DataHttpServer(orchestrator, {port})` | 构造，port=0 自动分配 | `final srv = DataHttpServer(orch);` |
| `start()` | 启动监听，返回实际端口 | `final port = await srv.start();` |
| `stop()` | 关闭服务器 | `await srv.stop();` |
| `isRunning` | 是否正在监听 | `srv.isRunning` → `bool` |
| `port` | 实际端口号 | `srv.port` → `int` |

端点：
- `GET /data/health` — 健康检查
- `GET /data/types` — 列出所有注册的数据类型
- `GET /data/types/:name` — 获取数据（缓存+刷新策略）
- `POST /data/types/:name/refresh` — 强制刷新
- `GET /data/status` — 所有数据源状态
- `GET /data/status/:name` — 单个数据源状态
- `POST /data/connectivity/test` — 测试全量连通性

### 其他公共符号

| 符号 | 说明 |
|------|------|
| `Cache` | 持久化缓存单例，文件存储于 `web_cache/{key}.json` |
| `scanAndLoadDataSources({pluginsDir, orchestrator})` | 扫描 `plugins/*/data/manifest.json`，批量启动外部 `.exe` |
| `fetchRemoteManifestList(url)` / `fetchRemoteManifest(url)` | 从远程拉取 manifest |
| `DataSourceLoader` | 单个 `.exe` 生命周期（启动→健康检查→注册） |
| `DataSourceManifest` / `DataSourceTypeDecl` | 插件清单模型 |
| `DataTypeNotRegisteredException` / `DataFetchException` | 异常类型 |

---

## 插件开发说明

> 完整示例：`example/plugins/douban/`（豆瓣 Top250 爬虫，Python 标准库）。详细指南见 `docs/plugin-authoring-guide-data.md`。

### 第一步：写一个 HTTP 服务

插件就是一个 HTTP 服务，启动后监听 `127.0.0.1` 的随机端口，提供数据接口。

必须实现两个端点：
- `GET /health` → 返回 `200`，用于平台探测插件是否就绪
- 各数据接口 → 返回 JSON

以 Python 为例，完整的 `plugin.py`：

```python
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
        elif self.path == "/api/scores":
            data = [{"name": "张三", "score": 95}]
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())
        else:
            self.send_response(404)
            self.end_headers()

server = HTTPServer(("127.0.0.1", 0), Handler)
# 必须！平台靠这行知道端口号
print(f"PORT:{server.server_port}", flush=True)
server.serve_forever()
```

### 第二步：写 manifest.json

告诉平台：我叫什么、可执行文件是哪个、提供哪些数据。

```json
{
  "type": "data-source",
  "id": "scores",
  "name": "成绩数据源",
  "process": "plugin.exe",
  "dataTypes": [
    {
      "name": "scores",
      "category": "教务",
      "displayName": "成绩单",
      "endpoint": "/api/scores"
    }
  ]
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `type` | ✓ | 固定 `"data-source"` |
| `id` | ✓ | 唯一标识，不可与其他插件重复 |
| `name` | ✓ | 展示名 |
| `process` | ✓ | 可执行文件名 |
| `dataTypes` | ✓ | 数据类型声明数组 |
| `dataTypes[].name` | ✓ | 类型唯一标识 |
| `dataTypes[].endpoint` | ✓ | HTTP 路径，`{port}` 由平台自动替换 |
| `dataTypes[].category` | | 分类，默认 `"未分类"` |
| `dataTypes[].displayName` | | UI 展示名，默认同 name |
| `dataTypes[].ttl` | | 缓存有效期，如 `"1h"` `"30m"` `"60s"`，默认 5 分钟 |
| `dataTypes[].persistentKey` | | 持久化缓存键，不设则不缓存 |

### 第三步：构建 .exe

把代码编译成可执行文件，放在插件目录下。

| 语言 | 构建命令 |
|------|----------|
| Python | `pyinstaller --onefile plugin.py` |
| Go | `go build -o plugin.exe .` |
| Rust | `cargo build --release`（产物在 `target/release/`） |
| C# | `dotnet publish -c Release -r win-x64` |

### 第四步：部署

`manifest.json` 和 `.exe` 都放入 `data/` 子目录：

```
plugins/
└── scores/                  ← 一个插件一个目录
    └── data/                ← 数据源类型独占此目录
        ├── manifest.json    ← 插件清单（v2 路径）
        └── plugin.exe       ← 可执行文件
```

放到正确位置后，平台启动时会自动调用 `scanAndLoadDataSources` 扫描并加载：

```dart
final orch = ref.read(dataOrchestratorProvider);
await scanAndLoadDataSources(pluginsDir: 'plugins/', orchestrator: orch);
```

### 启动流程

平台加载插件时会自动执行以下步骤，开发者无需干预：

1. 启动 `.exe` 进程
2. 等待 stdout 输出 `PORT:xxxx`
3. 请求 `GET /health` 确认就绪
4. 将各 `dataType` 注册到 `DataOrchestrator`
5. 此后任何 `orch.get(type)` 都会走缓存 → HTTP 拉取

---

## 已知限制

| 问题 | 状态 |
|------|------|
| `scanAndLoadDataSources` 插件退出后 Dart event loop 不退出 | `stop()` 已加 `force:true` + `exit(0)` 兜底 |
| `Cache` 单例缺少并发安全 | 当前单线程访问，后续可加锁 |
