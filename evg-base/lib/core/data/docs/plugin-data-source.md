# 数据源插件开发规范 v2

> 面向插件开发者——编写符合平台接口的外部数据源 .exe 插件。

---

## 一、目录结构

```
plugins/
└── <plugin-name>/
    └── data/                  ← 数据源插件的全部文件
        ├── manifest.json      ← 插件清单（必填，type: "data-source"）
        └── plugin.exe         ← 可执行文件
```

> 每种插件类型独占一个子目录（`data/`、`agent/`、`module/`、`theme/`、`config/`），互不干扰。

`scanAndLoadDataSources` 扫描 `plugins/*/data/manifest.json`，并以 `data/` 为工作目录启动 `.exe`。

---

## 二、manifest.json 格式

```json
{
  "type": "data-source",
  "id": "my-plugin",
  "name": "我的数据源",
  "process": "plugin.exe",
  "preferredPort": 0,
  "dataTypes": [
    {
      "name": "my_data",
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
| `process` | string | ✓ | 可执行文件名，相对于 `data/` 目录 |
| `preferredPort` | int | | 期望端口（>0 时平台通过 `--port N` 传给插件），0 表示自动分配 |
| `dataTypes` | array | ✓ | 数据类型声明，至少 1 个 |

### dataTypes 元素字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | ✓ | 类型唯一标识 |
| `endpoint` | string | ✓ | HTTP 路径，`{port}` 由平台自动替换为实际端口 |
| `category` | string | | 分类标签，默认 `"未分类"` |
| `displayName` | string | | UI 展示名，默认同 name |
| `ttl` | string/int | | 缓存有效期，支持 `"1h"` `"30m"` `"60s"` 或秒数，默认 `"5m"` |
| `persistentKey` | string | | 持久化缓存键，不设则每次重新拉取不缓存 |

---

## 三、插件 .exe 行为契约

### 3.1 启动

平台以 `data/` 为工作目录启动 `.exe`：

- 若 `preferredPort > 0`，传入 `--port <preferredPort>` 参数
- 等待 stdout 输出 `PORT:<数字>` 行
- 超时 10 秒未探测到端口 → 进程被终止
- 探测到端口后 → 请求 `GET /health`

### 3.2 健康检查

- 必须实现 `GET /health` 端点
- 返回 `200 OK`（body 可为空）
- 健康检查失败 → 进程被终止

### 3.3 数据接口

- 必须返回 `Content-Type: application/json`
- 返回 `200 OK` 时 body 必须为合法 JSON（数组或对象）
- 返回非 200 → 视为拉取失败，旧缓存保留

### 3.4 进程生命周期

- 平台退出时发送 SIGTERM → 2 秒超时 → SIGKILL
- 插件崩溃 → connected 状态变为 false，已注册的 DataType 保留

---

## 四、平台回调端点

插件可通过 HTTP 回调平台的数据管理能力。平台启动 `DataHttpServer` 后，插件可向 `http://127.0.0.1:<platform-port>` 发送请求：

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/data/health` | 平台健康检查 |
| `GET` | `/data/types` | 列出所有已注册的数据类型 |
| `GET` | `/data/types/:name` | 获取指定类型数据（缓存+刷新策略） |
| `POST` | `/data/types/:name/refresh` | 强制刷新指定类型数据 |
| `GET` | `/data/status` | 所有数据源状态 |
| `GET` | `/data/status/:name` | 单个数据源状态 |
| `POST` | `/data/connectivity/test` | 测试全量连通性 |

---

## 五、完整示例

> 参考 `example/plugins/douban/`——豆瓣电影 Top250 爬虫，真实可运行。

### Python 最小实现

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

### 构建命令

| 语言 | 命令 |
|------|------|
| Python | `pyinstaller --onefile plugin.py` |
| Go | `go build -o plugin.exe .` |
| Rust | `cargo build --release` |
| C# | `dotnet publish -c Release -r win-x64` |

---

## 六、变更记录

| 版本 | 日期 | 变更 |
|------|------|------|
| v2 | 2026-07 | manifest 路径改为 `data/manifest.json`；新增 `preferredPort` 字段；新增远程 manifest 拉取；新增 DataHttpServer 回调端点 |
| v1 | — | 初始版本 |
