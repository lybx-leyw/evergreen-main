# 11 · 后端进程

需要后端逻辑？放一个 `.exe`，或者用 `lattice: "sidecar"` 跑语言运行时。

## 基本配置（.exe）

> V2 起 `process` 为**数组**（可声明多个进程）；V1 单对象仍兼容。

```json
{
  "process": [
    {
      "id": "backend",
      "exe": "plugin.exe",
      "protocol": "http",
      "preferredPort": 0
    }
  ]
}
```

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `id` | — | 进程唯一标识（V2 新增） |
| `exe` | — | 可执行文件名（相对于 manifest.json 所在目录）；`runtime:"python"` 时可写 `.py` 入口 |
| `runtime` | `"native"` | `"native"` 直接执行 exe / `"python"` 用 Python 解释器执行 .py |
| `protocol` | `"http"` | `"http"` localhost / `"stdio"` stdin/stdout JSON |
| `scope` | `"long"` | `"long"` 长期运行 / `"short"` 一次性任务 |
| `autoStart` | `true` | 是否自动启动 |
| `autoRestart` | `false` | 崩溃后自动重启（仅 long） |
| `preferredPort` | `0` | 首选端口；`0` = 系统分配 |

## 启动流程

1. 框架 `Process.start(exe)` 启动进程
2. 进程向 stdout 输出 `PORT:8080`
3. 框架 `GET http://localhost:8080/health` → 200 = 就绪
4. 注册完成，开始路由请求

## 你需要实现的端点

框架根据 manifest 中的交互声明自动路由。你只需要实现模块实际需要的端点：

| 交互声明 | 端点 | 方法 |
|---------|------|------|
| `search.enabled` | `/search?q=&page=&limit=` | GET |
| `sortable: [...]` | `/data?sort=&order=&page=&limit=` | GET |
| `refresh.enabled` | `/data?since=<timestamp>` | GET |
| `itemTap: "detail"` | `/items/:id` | GET |
| `creatable: true` | `/items` | POST |
| `editable: true` | `/items/:id` | PUT |
| `deletable.enabled` | `/items/:id` | DELETE |
| `selection: "multi"` + `deletable` | `/items/batch` | DELETE |
| `exportable: [...]` | `/export?format=csv` | GET |
| `workspace.enabled` | `/workspace/files` | GET/POST/DELETE |

所有端点返回 JSON。

## `protocol: "stdio"` 模式

用换行分隔的 JSON 行（JSONL）通过 stdin/stdout 通信。适用于同进程内管道交互。

## sidecar：语言运行时后端（Node / Python / Deno）

不想编 exe？用 `lattice: "sidecar"` + `runtime` 声明直接跑脚本，并带能力沙箱：

```json
{
  "type": "module",
  "id": "py_helper",
  "name": "Python 助手",
  "lattice": "sidecar",
  "runtime": {
    "kind": "python",
    "entry": "backend.py",
    "protocol": "http",
    "port": 0,
    "gracefulTimeoutMs": 8000,
    "capabilities": {
      "fs.scope": "plugin-dir",
      "net.allow": ["api.example.com"],
      "spawn": []
    }
  }
}
```

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `runtime.kind` | — | `node` / `python` / `deno`（必填） |
| `runtime.entry` | — | 相对插件根的入口路径（必填） |
| `runtime.protocol` | `"http"` | `http`（端口 + JSON RPC）/ `stdio`（行协议） |
| `runtime.port` | `0` | 监听端口；`0` = 宿主自动分配（16384 起） |
| `runtime.gracefulTimeoutMs` | `8000` | 优雅停机超时，超时强杀（下限 1000ms） |
| `runtime.capabilities` | deny-all | `fs.scope`（`none`/`plugin-dir`/`app-data`）+ `net.allow`（白名单，禁 `*` 与 `file://`）+ `spawn`（可执行名白名单） |

**红线**：能力只窄不宽——三字段缺省 = 零权限；`lattice: sidecar` 却缺 `runtime`、或非 sidecar 格却带 `runtime` 都会在解析期抛错（fail-closed）。

sidecar 生命周期由 `SidecarController` 统一管理（启动 → 健康检查 → 注册端口 → 切走/卸载时优雅停 + 强杀兜底）。
运行状态可通过 `GET /module/sidecars` 查询。

## 完整示例

Python 后端：

```python
import json, sys, http.server

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health': self.send_response(200); self.end_headers()
        elif self.path.startswith('/search'): self._json([])
        elif self.path.startswith('/data'): self._json([])

    def do_POST(self):
        if self.path == '/items': self._json({"id": "1"}, 201)

    def _json(self, data, code=200):
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

port = 8080
print(f'PORT:{port}', flush=True)
http.server.HTTPServer(('127.0.0.1', port), Handler).serve_forever()
```

## 下一步

- [12 · 完整示例](12-examples.md)
