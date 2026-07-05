# 11 · 后端进程

需要后端逻辑？放一个 `.exe`。

## 基本配置

```json
{
  "process": {
    "exe": "plugin.exe",
    "protocol": "http",
    "preferredPort": 0
  }
}
```

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `exe` | — | 可执行文件名（相对于 manifest.json 所在目录） |
| `protocol` | `"http"` | `"http"` localhost / `"stdio"` stdin/stdout JSON |
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
