# Data 数据源插件撰写指南

> 面向插件开发者——如何编写符合 Evergreen 平台接口的外部数据源 `.exe` 插件。

---

## 一、目录结构

```
plugins/<plugin-name>/data/
├── manifest.json      ← 数据源声明（必填）
├── plugin.py          ← 源码（Python 示例）
└── plugin.exe         ← 编译产物
```

---

## 二、manifest.json 字段

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
| `id` | string | ✓ | 全局唯一标识 |
| `name` | string | ✓ | 展示名 |
| `process` | string | ✓ | 可执行文件名（相对 `data/`） |
| `preferredPort` | int | | 期望端口，0 或不设为自动分配 |

### dataTypes 元素字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | ✓ | 数据类型唯一标识 |
| `endpoint` | string | ✓ | HTTP 路径，`{port}` 由平台自动替换 |
| `category` | string | | 分类标签，默认 `"未分类"` |
| `displayName` | string | | UI 展示名，默认同 name |
| `ttl` | string/int | | 缓存有效期：`"1h"` `"30m"` `"60s"` `"500ms"` 或秒数，默认 `"5m"` |
| `persistentKey` | string | | 持久化缓存键，不设则不缓存 |

---

## 三、plugin.py 编写规范

平台与插件通过 **HTTP** 通信。启动流程：

```
平台启动 .exe → 等待 stdout 输出 PORT:N → GET /health → GET /api/xxx → 返回 JSON
```

### 必须实现

1. **端口输出**：`print(f"PORT:{port}", flush=True)` — 平台靠此行探测端口
2. **健康检查**：`GET /health` → `200 OK`
3. **数据端点**：返回 `Content-Type: application/json` + 合法 JSON

### 最小示例

```python
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
        elif self.path == "/api/data":
            body = json.dumps({"data": [{"id": 1, "title": "示例"}]}, ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # 禁止 HTTP 日志输出到 stderr

if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 0), Handler)
    print(f"PORT:{server.server_port}", flush=True)
    server.serve_forever()
```

### 关键契约

| 规则 | 说明 |
|------|------|
| 监听地址 | 必须 `127.0.0.1`，不接受外部连接 |
| 端口输出 | `print(f"PORT:{port}", flush=True)`，不可省略 |
| 健康检查 | `GET /health` → `200` |
| JSON 响应 | `Content-Type: application/json` |
| 编码 | UTF-8，中文需 `charset=utf-8` |
| 进程终止 | 平台发 SIGTERM → 2 秒超时 → SIGKILL |
| 超时 | 平台 10 秒内未探测到端口 → 进程终止 |

---

## 四、缓存策略

| 数据特征 | 建议 TTL | 示例 |
|----------|----------|------|
| 实时性极高 | `10s` ~ `1m` | 股票价格 |
| 中等实时性 | `5m` ~ `30m` | 新闻、天气 |
| 低实时性 | `1h` ~ `24h` | 电影排行、课程表 |
| 几乎不变 | `24h`+ | 静态配置 |

**缓存行为**：
- `persistentKey` 未设置 → 每次 `get()` 都重新拉取
- TTL 内 → 缓存命中，不发起 HTTP 请求
- TTL 过期 → 缓存仍可返回，后台自动刷新
- 用户可调用 `orch.refresh(type)` 强制拉取忽略 TTL

---

## 五、编译为 .exe

| 语言 | 命令 |
|------|------|
| Python | `pyinstaller --onefile plugin.py` |
| Go | `go build -ldflags="-s -w" -o plugin.exe .` |
| Rust | `cargo build --release` |
| C# | `dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true` |

**PyInstaller 提示**：第三方库（`requests`、`bs4` 等）会自动检测打包；隐式导入需 `--hidden-import` 显式声明。

---

## 六、完整示例

以下是一个完整的数据源插件示例——豆瓣电影 Top250 爬虫：

**manifest.json**：
```json
{
  "type": "data-source",
  "id": "douban-top250",
  "name": "豆瓣电影 Top250",
  "process": "plugin.exe",
  "dataTypes": [
    {
      "name": "douban_top250",
      "category": "影音",
      "displayName": "豆瓣 Top250",
      "ttl": "1h",
      "persistentKey": "douban_top250",
      "endpoint": "/api/top250"
    }
  ]
}
```

---

## 七、测试与调试

### 独立测试

```bash
python plugin.py
# 输出: PORT:12345
curl http://127.0.0.1:12345/health    # → 200
curl http://127.0.0.1:12345/api/data  # → JSON
```

### 通过平台测试

将插件放入 `plugins/<name>/data/` 目录，启动平台后自动发现并加载。验证方法：

```bash
# 查看已注册的数据类型
curl http://127.0.0.1:PORT/data/types

# 手动拉取数据
curl http://127.0.0.1:PORT/data/types/my_data

# 强制刷新
curl -X POST http://127.0.0.1:PORT/data/types/my_data/refresh
```

### HTTP 端点测试

```bash
curl http://127.0.0.1:<port>/data/health
curl http://127.0.0.1:<port>/data/types
curl http://127.0.0.1:<port>/data/types/my_data
curl -X POST http://127.0.0.1:<port>/data/types/my_data/refresh
curl http://127.0.0.1:<port>/data/status
curl -X POST http://127.0.0.1:<port>/data/connectivity/test
```

### 常见问题

| 问题 | 原因 | 解决 |
|------|------|------|
| 平台无法探测端口 | stdout 未输出 `PORT:N` | 确保 `print(f"PORT:{port}", flush=True)` |
| 健康检查失败 | `/health` 未返回 200 | 检查端点实现 |
| 数据返回 null | fetcher 异常 | 检查 stderr 日志 |
| 缓存不生效 | `persistentKey` 未设置 | manifest 中添加 `persistentKey` |
| 进程不退出 | event loop 阻塞 | 使用 `stop()` + `force:true` |
