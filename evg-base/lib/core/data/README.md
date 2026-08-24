# Data Orchestrator

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 README.md 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-data |
| 适用 | data 子包 |

> **快速导航**
> - 平台开发者 → `example/example.dart` | 测试：`test/orchestrator_test.dart` + `test/cache_test.dart` + `test/data_diff_test.dart`
> - 数据源插件开发者（开发者模式）→ `docs/plugin-authoring-guide-data.md` | 示例：`example/plugins/douban/`
> - HTML 插件作者 → 使用 `platform.data.*` JS Bridge 读取数据中枢，无需自建数据源
> - 核心源码 → `type.dart` `cache.dart` `orchestrator.dart` `data_diff.dart` `data_http_server.dart` `register_data_source.dart` `plugin/`

## 平台开发 API

### DataType

| 属性 | 必填 | 说明 |
|------|------|------|
| `name` | ✓ | 唯一标识 |
| `category` | | 分类标签，默认 `"未分类"` |
| `displayName` | | UI 展示名，默认同 name |
| `ttl` | | 缓存有效期，默认 5 分钟 |
| `persistentKey` | | 持久化键，不设则不缓存 |
| `label` | | getter：`displayName ?? name` |

### DataOrchestrator

| 方法 | 说明 | 示例 |
|------|------|------|
| `register(type, fetcher)` | 注册数据类型与拉取方式；重复覆盖 | `orch.register(scoresType, _fetchScores)` |
| | | 入: `DataType<T>`, `() → Future<T>` / 出: `void` |
| `registerAll(entries)` | 批量注册 | `orch.registerAll({scoresType: f1, newsType: f2})` |
| | | 入: `Map<DataType<T>, () → Future<T>>` / 出: `void` |
| `isRegistered(type)` | 是否已注册 | `orch.isRegistered(scoresType)` → `bool` |
| `registeredTypes` | 已注册类型名列表 | `orch.registeredTypes` → `List<String>` |
| `unregister(type)` | 注销并清除缓存 | `orch.unregister(scoresType)` |
| `get(type)` | 缓存优先获取（磁盘→内存→拉取） | `final data = await orch.get(scoresType)` |
| | | 入: `DataType<T>` / 出: `Future<T?>` |
| `fastRead(type)` | 内存快读（零磁盘 I/O），未命中 fallback get | `final data = await orch.fastRead(scoresType)` |
| `getByName(name)` | 按名称获取（供 Agent Tool 等） | `final data = await orch.getByName('scores')` |
| `fastReadByName(name)` | 按名称快读 | `await orch.fastReadByName('scores')` |
| `refreshByName(name)` | 按名称强制刷新 | `await orch.refreshByName('scores')` |
| `typeByName(name)` | 按名称查 DataType | `orch.typeByName('scores')` → `DataType?` |
| `refresh(type, {notifyOnChange})` | 强制拉取，合法则覆写缓存 | `final data = await orch.refresh(scoresType)` |
| | | 入: `DataType<T>`, `{bool}` / 出: `Future<T?>` |
| `refreshAllStale({types})` | 批量刷新过期数据（默认发变更事件） | `await orch.refreshAllStale()` |
| `refreshAllSerial({types})` | 串行全量拉取（单源失败不阻塞） | `await orch.refreshAllSerial()` |
| `startAutoRefresh({interval})` | 启动定时自动刷新（默认 5 分钟） | `orch.startAutoRefresh()` |
| `stopAutoRefresh()` | 停止自动刷新 | `orch.stopAutoRefresh()` |
| `invalidate(type)` | 清缓存（内存 + 磁盘） | `await orch.invalidate(scoresType)` |
| `dumpDataFormat(name)` | 打印缓存数据结构（不触发拉取） | `orch.dumpDataFormat('scores')` → `String?` |
| `refreshStatusFromDisk()` | 从磁盘缓存恢复 lastFetchedAt | `orch.refreshStatusFromDisk()` |
| `allStatuses` | 按分类+名称排序的状态列表 | `final list = orch.allStatuses` |
| `status(name)` | 按名称查询状态 | `final s = orch.status('scores')` |
| `statusByCategory(c)` | 按分类过滤 | `orch.statusByCategory('教务')` |
| `categories` | 所有分类名 | `orch.categories` |
| `connectedCount` / `freshCount` / `totalCount` | 已连通/新鲜/总注册数 | `orch.totalCount` → `int` |
| `testConnectivity(name)` | 单源连通性测试 | `await orch.testConnectivity('scores')` |
| `testAllConnectivity()` | 全源测试 | `final r = await orch.testAllConnectivity()` |
| `addDataChangeListener(fn)` | 订阅数据变更事件（后台刷新） | `orch.addDataChangeListener((e) => ...)` |
| `removeDataChangeListener(fn)` | 取消订阅变更事件 | `orch.removeDataChangeListener(fn)` |

### DataSourceStatus

| 属性 | 说明 |
|------|------|
| `name` / `category` / `displayName` | 基本信息 |
| `cacheKey` / `ttl` | 缓存键（persistentKey）/ 有效期 |
| `connected` | 连通状态 |
| `lastFetchedAt` / `lastError` | 最近拉取时间 / 最近错误 |
| `isFresh` | 是否在 TTL 内 |
| `freshnessLabel` | "新鲜" / "过期" / "从未" |
| `relativeTime` | "3 分钟前" 等人性化时间 |

### DataChangeEvent / DataDiff（数据变更通知）

后台自动刷新覆写缓存且内容实质变化（忽略易变字段）时发出：

| 成员 | 说明 |
|------|------|
| `DataChangeEvent.sourceName` / `displayName` / `diff` / `at` | 事件负载 |
| `DataDiff.added` / `removed` / `changed` | 新增/移除/更新计数 |
| `DataDiff.addedItems` / `removedItems` / `changedItems` | 示例条目（最多 5 条） |
| `DataDiff.hasChanges` / `summarize()` | 是否有变化 / 中文摘要（如「新增 2 项、移除 1 项 · 线性代数；高等数学」） |
| `computeDataDiff(before, after)` | 计算结构差异（忽略 `kVolatileDiffKeys` 易变字段） |

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
- `GET /data/types/:name` — 获取数据（缓存+刷新策略；拉取失败 502）
- `POST /data/types/:name/refresh` — 强制刷新
- `GET /data/status` — 所有数据源状态
- `GET /data/status/:name` — 单个数据源状态
- `POST /data/connectivity/test` — 测试全量连通性
- `POST /data/register` — 运行期热注册 CLI 数据源（body: `{"pluginDir": "<plugins>/data-<name>"}`）

### 其他公共符号

| 符号 | 说明 |
|------|------|
| `Cache` | 持久化缓存单例，文件存储于 `web_cache/{key}.json` |
| `scanAndLoadDataSources({pluginsDir, orchestrator, projectRoot})` | 扫描 `plugins/*/data/manifest.json`，批量启动外部 `.exe`（HTTP 模型） |
| `registerDataSourcesFromManifest({orch, pluginDir, projectRoot, onlyType})` | 读取 manifest 注册 CLI 数据源（返回注册的类型名列表） |
| `cliDataSourceSupportedOn(json, {isAndroid})` | 安卓支持判断（`androidSupport` 安全网） |
| `fetchRemoteManifestList(url)` / `fetchRemoteManifest(url)` | 从远程拉取 manifest（失败返回空/null，不抛） |
| `DataSourceLoader` | 单个 `.exe` 生命周期（启动→健康检查→注册，HTTP 模型） |
| `DataSourceManifest` / `DataSourceTypeDecl` | 插件清单模型（含 `runtime` / `androidSupport` / `typeArg`） |
| `DataTypeNotRegisteredException` / `DataFetchException` | 异常类型 |
| `dataOrchestratorProvider` | Riverpod Provider（`provider.dart`，不被 barrel 导出；renderer 侧使用） |

---

## 插件开发说明

> 完整示例：`example/plugins/douban/`（豆瓣 Top250 爬虫，HTTP 长驻模型，Python 标准库）。
> 详细指南见 `docs/plugin-authoring-guide-data.md` 与规范 `docs/plugin-data-source.md`。

数据源插件支持**两种模型**，manifest 中二选一：

| 模型 | manifest 关键字段 | 执行方式 | 适用场景 |
|------|------------------|----------|----------|
| **A. CLI 一次性脚本** | `script`（+`runtime`/`typeArg`/`androidSupport`） | 每次拉取执行脚本，stdout 输出 JSON Map | 爬虫/一次性抓取、设计器"一键生成数据源"、运行期热注册 |
| **B. HTTP 长驻服务** | `process` + `dataTypes[].endpoint` | 常驻进程，`PORT:` 行 + `/health` 探测 | 有状态服务、多端点复用 |

### 模型 A：CLI 一次性脚本

脚本每次被平台调用一次（`Process.run`），完成后退出：

1. 平台执行 `<script> --type <typeArg> --project-root <root> --greenix-config <cfg>`（工作目录为 `data/`）
2. 脚本向 **stdout** 输出单个 JSON 对象（UTF-8），**顶层必须是 `Map`**（列表型数据包 `{"items": [...]}`）
3. 失败约定：非零退出码，或 stdout JSON 含 `"error": "原因"` 字段

最小 Python 示例（`fetch.py`）：

```python
import json, sys

# 参数：--type <typeArg> --project-root <root> --greenix-config <cfg>
args = sys.argv[1:]
print(json.dumps({"items": [{"title": "示例", "rating": 9.7}]}, ensure_ascii=False))
```

对应 `data/manifest.json`：

```json
{
  "type": "data-source",
  "id": "my-cli-source",
  "name": "我的 CLI 数据源",
  "script": "fetch.py",
  "runtime": "python",
  "dataTypes": [
    { "name": "my_data", "category": "资讯", "displayName": "我的数据",
      "ttl": "5m", "persistentKey": "my_data_cache" }
  ]
}
```

### 模型 B：HTTP 长驻服务

#### 第一步：写一个 HTTP 服务

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

#### 第二步：写 manifest.json

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
| `process` | ✓（模型 B） | 可执行文件名 |
| `script` | ✓（模型 A） | CLI 脚本文件名（与 process 二选一） |
| `runtime` | | 脚本运行时：`native`（默认）/ `python`（也可按 `.py` 扩展名推断） |
| `androidSupport` | | 默认 true；`false` 时安卓跳过加载（C 扩展类插件安全网） |
| `dataTypes` | ✓ | 数据类型声明数组 |
| `dataTypes[].name` | ✓ | 类型唯一标识 |
| `dataTypes[].typeArg` | | 传给 CLI 脚本的 `--type` 参数，默认同 name（仅模型 A） |
| `dataTypes[].endpoint` | ✓（模型 B） | HTTP 路径，`{port}` 由平台自动替换 |
| `dataTypes[].category` | | 分类，默认 `"未分类"` |
| `dataTypes[].displayName` | | UI 展示名，默认同 name |
| `dataTypes[].ttl` | | 缓存有效期，如 `"1h"` `"30m"` `"60s"` `"500ms"`，默认 5 分钟 |
| `dataTypes[].persistentKey` | | 持久化缓存键，不设则不缓存 |

#### 第三步：构建 .exe（模型 B）

把代码编译成可执行文件，放在插件目录下。

| 语言 | 构建命令 |
|------|----------|
| Python | `pyinstaller --onefile plugin.py` |
| Go | `go build -o plugin.exe .` |
| Rust | `cargo build --release`（产物在 `target/release/`） |
| C# | `dotnet publish -c Release -r win-x64` |

#### 第四步：部署

`manifest.json` 和 `.exe`（或脚本）都放入 `data/` 子目录：

```
plugins/
└── scores/                  ← 一个插件一个目录
    └── data/                ← 数据源类型独占此目录
        ├── manifest.json    ← 插件清单
        ├── plugin.exe       ← 可执行文件（模型 B）
        └── fetch.py         ← CLI 脚本（模型 A）
```

放到正确位置后，平台启动时会自动扫描并加载（HTTP 模型走 `scanAndLoadDataSources`，CLI 模型走 `registerDataSourcesFromManifest`）：

```dart
final orch = ref.read(dataOrchestratorProvider);
await scanAndLoadDataSources(
  pluginsDir: 'plugins/',
  orchestrator: orch,
  projectRoot: projectRoot,
);
// CLI 数据源运行期热注册（如设计器一键生成后）：
registerDataSourcesFromManifest(
  orch: orch,
  pluginDir: 'plugins/data-my_source',
  projectRoot: projectRoot,
);
```

### 启动流程（模型 B）

平台加载插件时会自动执行以下步骤，开发者无需干预：

1. 启动 `.exe` 进程（`preferredPort > 0` 时传 `--port N`）
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
| barrel `data.dart` 依赖根包 core（greenix_path 等） | 子包独立 `dart test` 需精确 import 纯数据文件（`../orchestrator.dart` 等），见测试文件头注释 |
| `example/plugins/douban/` 提交了 PyInstaller 构建产物（`build/`、`dist/`） | 仓库卫生问题，建议后续清理 |
