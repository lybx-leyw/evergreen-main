# 数据源插件开发规范

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 README.md 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-data |
| 适用 | 数据源插件作者 |

> 面向插件开发者——编写符合平台接口的数据源插件（两种模型：CLI 一次性脚本 / HTTP 长驻 .exe）。
> 平台侧实现见 `register_data_source.dart`（模型 A）与 `plugin/data_source_loader.dart`（模型 B）。

---

## 零、两种插件模型

| | 模型 A：CLI 一次性脚本 | 模型 B：HTTP 长驻服务 |
|--|------------------------|----------------------|
| manifest 关键字段 | `script`（+`runtime`/`typeArg`） | `process` + `dataTypes[].endpoint` |
| 运行方式 | 每次拉取执行一次脚本，stdout 输出 JSON | 长驻进程，`PORT:` 行 + `/health` 探测 |
| 数据返回 | stdout 顶层 JSON Map | HTTP 响应 JSON body |
| 典型场景 | 爬虫、设计器"一键生成数据源"、运行期热注册 | 有状态服务、多端点复用 |
| 注册入口 | `registerDataSourcesFromManifest` | `scanAndLoadDataSources` |

> 两种模型互斥：manifest 含 `script` 走 CLI，含 `process` 走 HTTP。

---

## 一、目录结构

```
plugins/
└── <plugin-name>/
    └── data/                  ← 数据源插件的全部文件
        ├── manifest.json      ← 插件清单（必填，type: "data-source"）
        ├── plugin.exe         ← 可执行文件（模型 B）
        └── fetch.py           ← CLI 脚本（模型 A）
```

> 每种插件类型独占一个子目录（`data/`、`agent/`、`module/`、`theme/`、`config/`），互不干扰。

平台以 `data/` 为工作目录：模型 B 由 `scanAndLoadDataSources` 扫描 `plugins/*/data/manifest.json` 启动 `.exe`；
模型 A 由 `registerDataSourcesFromManifest`（启动扫描或运行期 `POST /data/register` 热注册）注册 CLI fetcher。

---

## 二、manifest.json 格式

```json
{
  "type": "data-source",
  "id": "my-plugin",
  "name": "我的数据源",
  "script": "fetch.py",
  "runtime": "python",
  "androidSupport": true,
  "preferredPort": 0,
  "dataTypes": [
    {
      "name": "my_data",
      "typeArg": "my_data",
      "category": "资讯",
      "displayName": "我的数据",
      "ttl": "5m",
      "persistentKey": "my_data_cache",
      "endpoint": "/api/data"
    }
  ]
}
```

### 顶层字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | string | ✓ | 固定 `"data-source"` |
| `id` | string | ✓ | 全局唯一标识，不可与其他插件重复 |
| `name` | string | ✓ | 展示名 |
| `script` | string | 模型 A ✓ | CLI 脚本文件名，相对于 `data/` 目录（与 `process` 二选一） |
| `process` | string | 模型 B ✓ | 可执行文件名，相对于 `data/` 目录 |
| `runtime` | string | | 脚本运行时：`native`（默认）/ `python`（也可按 `.py` 扩展名自动推断） |
| `androidSupport` | bool | | 默认 `true`；设为 `false` 的数据源（如依赖 C 扩展的 OCR/PDF/ML 插件）在安卓自动跳过，避免崩溃 |
| `preferredPort` | int | | 期望端口（>0 时平台通过 `--port N` 传给插件，仅模型 B），0 表示自动分配 |
| `dataTypes` | array | ✓ | 数据类型声明，至少 1 个 |

### dataTypes 元素字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | ✓ | 类型唯一标识 |
| `typeArg` | string | | 传给 CLI 脚本的 `--type` 参数，默认同 `name`（仅模型 A） |
| `endpoint` | string | 模型 B ✓ | HTTP 路径，`{port}` 由平台自动替换为实际端口 |
| `category` | string | | 分类标签，默认 `"未分类"` |
| `displayName` | string | | UI 展示名，默认同 name |
| `ttl` | string/int | | 缓存有效期，支持 `"1h"` `"30m"` `"60s"` `"500ms"` 或秒数，默认 `"5m"` |
| `persistentKey` | string | | 持久化缓存键，不设则每次重新拉取不缓存 |

---

## 三、插件行为契约

### 3.1 模型 A：CLI 一次性脚本

1. 平台每次拉取执行：`<script> --type <typeArg> --project-root <projectRoot> --greenix-config <greenixConfigPath>`（工作目录 `data/`）
2. **stdout 顶层必须是 `Map<String, dynamic>`**（平台统一契约；列表型数据包 `{"items": [...]}`）
3. 输出必须为 UTF-8 编码的单个 JSON 对象；中文无需额外转义（`ensure_ascii=False`）
4. **失败约定**（任一即视为拉取失败，旧缓存保留）：
   - 非零退出码（错误信息取 stderr，或 stdout JSON 的 `error` 字段）
   - stdout JSON 含 `"error": "<原因>"` 字段
5. 脚本文件缺失时平台仍会注册该类型（运行时拉取失败并记录日志）

### 3.2 模型 B：启动

平台以 `data/` 为工作目录启动 `.exe`：

- 若 `preferredPort > 0`，传入 `--port <preferredPort>` 参数（同时总传 `--project-root`、`--greenix-config`）
- 等待 stdout 输出 `PORT:<数字>` 行
- 超时 10 秒未探测到端口 → 进程被终止
- 探测到端口后 → 请求 `GET /health`

### 3.3 健康检查（模型 B）

- 必须实现 `GET /health` 端点
- 返回 `200 OK`（body 可为空）
- 健康检查失败 → 进程被终止

### 3.4 数据接口（模型 B）

- 必须返回 `Content-Type: application/json`
- 返回 `200 OK` 时 body 必须为合法 JSON（数组或对象）
- 返回非 200 → 视为拉取失败，旧缓存保留

### 3.5 进程生命周期（模型 B）

- 平台退出时发送 SIGTERM → 2 秒超时 → SIGKILL
- 插件崩溃 → connected 状态变为 false，已注册的 DataType 保留

### 3.6 数据格式约定（通用）

- 平台侧空数据门控：拉取结果为 null / 空白字符串 / 空 List / 空 Map / 空 Set 时视为失败，不覆写缓存
- `{"items": []}` 这类「非空 Map 包空列表」不算空（结构合法），由消费方自行处理

---

## 四、平台回调端点（DataHttpServer）

插件可通过 HTTP 回调平台的数据管理能力。平台启动 `DataHttpServer` 后，插件可向 `http://127.0.0.1:<platform-port>` 发送请求：

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/data/health` | 平台健康检查 |
| `GET` | `/data/types` | 列出所有已注册的数据类型 |
| `GET` | `/data/types/:name` | 获取指定类型数据（缓存+刷新策略；拉取失败返回 502） |
| `POST` | `/data/types/:name/refresh` | 强制刷新指定类型数据 |
| `GET` | `/data/status` | 所有数据源状态 |
| `GET` | `/data/status/:name` | 单个数据源状态 |
| `POST` | `/data/connectivity/test` | 测试全量连通性 |
| `POST` | `/data/register` | 运行期热注册 CLI 数据源；body `{"pluginDir": "<plugins>/data-<name>"}`，返回 `{"registered": [...]}` |

> 错误码约定：成功 `200`、未找到 `404`、拉取失败 `502`（含 `lastError` 详情）、参数缺失 `400`、内部错误 `500`。

---

## 五、完整示例

> 参考 `example/plugins/douban/`——豆瓣电影 Top250 爬虫（模型 B，HTTP 长驻），真实可运行。

### 模型 A：Python CLI 脚本最小实现

```python
import json, sys, urllib.request

# 平台调用参数：--type <typeArg> --project-root <root> --greenix-config <cfg>
# 本例忽略参数，直接返回静态数据（真实脚本按 typeArg 分发抓取逻辑）

data = {"items": [{"title": "肖申克的救赎", "rating": 9.7}]}
print(json.dumps(data, ensure_ascii=False))  # stdout 顶层 Map，UTF-8
```

### 模型 B：Python 长驻服务最小实现

```python
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
        elif self.path == "/api/top250":
            data = [{"title": "肖申克的救赎", "rating": "9.7"}]
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())
        else:
            self.send_response(404)
            self.end_headers()

server = HTTPServer(("127.0.0.1", 0), Handler)
print(f"PORT:{server.server_port}", flush=True)  # 必须！
server.serve_forever()
```

### 构建命令（模型 B）

| 语言 | 命令 |
|------|------|
| Python | `pyinstaller --onefile plugin.py` |
| Go | `go build -o plugin.exe .` |
| Rust | `cargo build --release` |
| C# | `dotnet publish -c Release -r win-x64` |

---

## 六、变更记录

| 日期 | 变更 |
|------|------|
| 2026-08 | 新增模型 A（CLI 一次性脚本）：`script`/`runtime`/`typeArg`/`androidSupport` 字段与 stdout JSON Map 契约；DataHttpServer 新增 `POST /data/register` 运行期热注册；补充 502 语义与空数据门控 |
| 2026-07 | manifest 路径改为 `data/manifest.json`；新增 `preferredPort` 字段；新增远程 manifest 拉取；新增 DataHttpServer 回调端点 |
| — | 初始版本 |
