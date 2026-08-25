# Data 数据源插件撰写指南

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 README.md 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-data |
| 适用 | 数据源插件作者 |

> 面向插件开发者——如何编写符合 Evergreen 平台接口的数据源插件。
> 支持两种模型：**A. CLI 一次性脚本（推荐/规范化形态，新数据源一律走 A）** 与 **B. HTTP 长驻 `.exe` 服务（legacy）**。
> 平台规范见 `docs/plugin-data-source.md`。

---

## 一、目录结构

```
plugins/<plugin-name>/data/
├── manifest.json      ← 数据源声明（必填）
└── fetch.py           ← CLI 脚本（模型 A，推荐；manifest 的 script 相对 data/ 解析）
# 模型 B（legacy）：plugin.py + 编译产物 plugin.exe（PyInstaller 等，仅同平台）
```

---

## 二、manifest.json 字段

```json
{
  "type": "data-source",
  "id": "my-plugin",
  "name": "我的数据源",
  "script": "fetch.py",
  "runtime": "python",
  "androidSupport": true,
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
| `id` | string | ✓ | 全局唯一标识 |
| `name` | string | ✓ | 展示名 |
| `script` | string | 模型 A ✓ | CLI 脚本文件名（相对 `data/`），与 `process` 二选一 |
| `process` | string | 模型 B ✓ | 可执行文件名（相对 `data/`） |
| `runtime` | string | | 脚本运行时：`native`（默认）/ `python`（按 `.py` 扩展名也可推断） |
| `androidSupport` | bool | | 默认 true；false 时安卓跳过加载（C 扩展类插件安全网） |
| `preferredPort` | int | | 期望端口（模型 B），0 或不设为自动分配 |

### dataTypes 元素字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | ✓ | 数据类型唯一标识 |
| `typeArg` | string | | 传给 CLI 脚本的 `--type` 参数，默认同 name（模型 A） |
| `endpoint` | string | 模型 B ✓ | HTTP 路径，`{port}` 由平台自动替换 |
| `category` | string | | 分类标签，默认 `"未分类"` |
| `displayName` | string | | UI 展示名，默认同 name |
| `ttl` | string/int | | 缓存有效期：`"1h"` `"30m"` `"60s"` `"500ms"` 或秒数，默认 `"5m"` |
| `persistentKey` | string | | 持久化缓存键，不设则不缓存 |

---

## 三、模型 A：CLI 一次性脚本编写规范

平台每次拉取调用一次脚本，用完即退。**推荐优先使用此模型**（无需常驻进程、无需 HTTP 服务）。

### 调用约定

```
平台执行: <script> --type <typeArg> --project-root <projectRoot> --greenix-config <greenixConfigPath>
工作目录: <plugin>/data/
```

### 必须实现

1. **stdout 输出单个 JSON 对象**，UTF-8，**顶层必须是 `Map`**（列表型数据包 `{"items": [...]}`）
2. **成功**：退出码 0，stdout 为数据 JSON
3. **失败**：非零退出码，或 stdout JSON 含 `"error": "原因"` 字段（错误信息会进入 `DataSourceStatus.lastError`，旧缓存保留）

### 最小示例

```python
import json, sys

# 平台参数：--type <typeArg> --project-root <root> --greenix-config <cfg>
# 可按 typeArg 分发不同数据源的抓取逻辑；本例忽略参数返回静态数据
data = {"items": [{"id": 1, "title": "示例"}]}
print(json.dumps(data, ensure_ascii=False))
```

### 关键契约

| 规则 | 说明 |
|------|------|
| stdout 顶层 | 必须是 `Map<String, dynamic>`（列表型包 `{"items": [...]}`） |
| 编码 | UTF-8；中文用 `ensure_ascii=False` |
| 失败信号 | 非零退出码，或 stdout JSON 的 `error` 字段 |
| 错误详情 | 非零退出时优先取 stderr 文本，其次取 stdout JSON `error` |
| 空数据 | 返回空 Map/List 会被平台视为拉取失败（空数据门控），不覆写旧缓存 |

---

## 四、模型 B：HTTP 长驻服务编写规范（legacy）

> ⚠️ **legacy**：模型 B 需要编译平台二进制（.exe），仅同平台可用；同步中心导出/导入需 platform 标记。
> 新数据源优先模型 A（CLI .py）。本节省略仅供存量插件参考。

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

## 五、缓存策略

| 数据特征 | 建议 TTL | 示例 |
|----------|----------|------|
| 实时性极高 | `10s` ~ `1m` | 股票价格 |
| 中等实时性 | `5m` ~ `30m` | 新闻、天气 |
| 低实时性 | `1h` ~ `24h` | 电影排行、课程表 |
| 几乎不变 | `24h`+ | 静态配置 |

**缓存行为**：
- `persistentKey` 未设置 → 每次 `get()` 都重新拉取
- TTL 内 → 缓存命中，不发起拉取
- TTL 过期 → 缓存仍可返回，后台自动刷新（内容变化会发出变更事件）
- 用户可调用 `orch.refresh(type)` 强制拉取忽略 TTL
- 拉取返回空/非法 → 不覆写缓存，旧数据保持可用

---

## 六、编译为 .exe（模型 B，legacy）

> ⚠️ 模型 B 已标注 legacy。新数据源优先模型 A（.py 纯标准库优先，无需编译）。

| 语言 | 命令 |
|------|------|
| Python | `pyinstaller --onefile plugin.py` |
| Go | `go build -ldflags="-s -w" -o plugin.exe .` |
| Rust | `cargo build --release` |
| C# | `dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true` |

**PyInstaller 提示**：第三方库（`requests`、`bs4` 等）会自动检测打包；隐式导入需 `--hidden-import` 显式声明。

---

## 七、完整示例

以下是一个完整的数据源插件示例——豆瓣电影 Top250 爬虫（**模型 A CLI**，见 `example/plugins/douban/`，纯 Python 标准库）：

**目录结构**：
```
plugins/douban-top250/data/
├── manifest.json
└── plugin.py          # CLI 脚本（urllib + html.parser，零第三方依赖）
```

**manifest.json**：
```json
{
  "type": "data-source",
  "id": "douban-top250",
  "name": "豆瓣电影 Top250",
  "script": "plugin.py",
  "runtime": "python",
  "dataTypes": [
    {
      "name": "douban_top250",
      "typeArg": "douban_top250",
      "category": "影音",
      "displayName": "豆瓣 Top250",
      "ttl": "1h",
      "persistentKey": "douban_top250"
    }
  ]
}
```

**脚本输出**（stdout 顶层 Map，列表型包 `{"items": [...]}`）：
```json
{"items": [{"rank": 1, "title": "肖申克的救赎", "rating": 9.7, "quote": "希望让人自由。"}]}
```

> 该示例原为模型 B（HTTP 长驻 .exe），已随 python 统一迁移为模型 A；模型 B 的完整示例见本指南第四节（legacy）。

---

## 八、测试与调试

### 模型 A：独立测试

```bash
python fetch.py --type my_data --project-root . --greenix-config .greenix/config.json
# stdout 应输出单个 JSON 对象（顶层 Map）
```

### 模型 B：独立测试

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

# 运行期热注册 CLI 数据源（模型 A）
curl -X POST http://127.0.0.1:PORT/data/register \
  -H "Content-Type: application/json" \
  -d '{"pluginDir": "plugins/data-my_source"}'
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
| 平台无法探测端口（模型 B） | stdout 未输出 `PORT:N` | 确保 `print(f"PORT:{port}", flush=True)` |
| 健康检查失败（模型 B） | `/health` 未返回 200 | 检查端点实现 |
| 数据返回 null | fetcher 异常 / 空数据门控 | 检查 stderr 日志与 stdout JSON 合法性 |
| CLI 数据源拉取失败 | 退出码非 0 或 stdout 含 `error` 字段 | 检查脚本异常输出与 `error` 字段内容 |
| 缓存不生效 | `persistentKey` 未设置 | manifest 中添加 `persistentKey` |
| 安卓上数据源不加载 | `androidSupport: false` | 确认该插件是否依赖 C 扩展（Pillow/onnxruntime 等） |
| 进程不退出（模型 B） | event loop 阻塞 | 使用 `stop()` + `force:true` |
