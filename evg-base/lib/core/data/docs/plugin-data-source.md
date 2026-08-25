# 数据源插件开发规范

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 README.md 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-data |
| 适用 | 数据源插件作者 |

> 面向插件开发者——编写符合平台接口的数据源插件（两种模型：**模型 A CLI 一次性脚本（推荐/规范化形态）** / 模型 B HTTP 长驻 .exe（legacy））。
> 平台侧实现见 `register_data_source.dart`（模型 A）与 `plugin/data_source_loader.dart`（模型 B）。

---

## 零、两种插件模型

| | 模型 A：CLI 一次性脚本（推荐） | 模型 B：HTTP 长驻服务（legacy） |
|--|------------------------|----------------------|
| manifest 关键字段 | `script`（+`runtime`/`typeArg`） | `process` + `dataTypes[].endpoint` |
| 运行方式 | 每次拉取执行一次脚本，stdout 输出 JSON | 长驻进程，`PORT:` 行 + `/health` 探测 |
| 数据返回 | stdout 顶层 JSON Map | HTTP 响应 JSON body |
| 跨平台 | ✅ 桌面解释器 / 安卓 Chaquopy 同一份 .py | ❌ 平台二进制（.exe 仅 Windows，需 platform 标记） |
| 典型场景 | 爬虫、设计器"一键生成数据源"、运行期热注册、同步中心导入 | 有状态服务、多端点复用 |
| 注册入口 | `registerDataSourcesFromManifest` | `scanAndLoadDataSources` |

> 两种模型互斥：manifest 含 `script` 走 CLI，含 `process` 走 HTTP。
> **新数据源一律优先模型 A（.py 纯标准库优先）**：无 PyInstaller 产物、跨平台一致、
> 同步中心导出/导入友好（迁移单元 = manifest + 脚本，无平台二进制）。

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
  "id": "my-plugin",            // 可选（模型 A 缺省时由插件目录 basename 派生）
  "name": "我的数据源",          // 可选
  "script": "fetch.py",         // 模型 A：CLI 脚本（与 process 二选一）
  "runtime": "python",
  "androidSupport": true,
  "auth": {                     // 可选：凭据/会话引用，缺省零行为变化
    "sessionProvider": "zju",
    "credentialKeys": ["ZJU_USERNAME", "ZJU_PASSWORD"]
  },
  "dataTypes": [
    {
      "name": "my_data",
      "typeArg": "my_data",
      "category": "资讯",
      "displayName": "我的数据",
      "ttl": "5m",
      "persistentKey": "my_data_cache",
      "stream": { "enabled": true, "protocol": "sse", "mime": "text/event-stream" },
      "file": { "enabled": true, "downloadEndpoint": "/download" }
    }
  ]
}
```

> 模型 B（HTTP 长驻，legacy）顶层用 `process` 替代 `script`：字符串形态
> `"process": "plugin.exe"` 与对象形态 `"process": { "exe": "plugin.py", "scope": "long",
> "autoStart": true, "autoRestart": false, "protocol": "http", "preferredPort": 0 }` 均支持。

### 顶层字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | string | ✓ | 固定 `"data-source"` |
| `id` | string | | 全局唯一标识。**可选**：模型 A 缺省时由插件目录 basename 派生 |
| `name` | string | | 展示名。**可选**（消费方缺省回落） |
| `script` | string | 模型 A ✓ | CLI 脚本文件名，相对于 `data/` 目录（与 `process` **互斥二选一**） |
| `process` | string/object | 模型 B ✓ | 可执行文件名（字符串）或进程声明（对象，见下）。与 `script` **互斥二选一** |
| `runtime` | string | | 脚本运行时：`native`（默认）/ `python`（也可按 `.py` 扩展名自动推断） |
| `androidSupport` | bool | | **严格 bool**：仅真实 `true`/`false` 有效；缺省 `true`；字符串/数字等非 bool 值视为 `false`（fail-closed，安卓跳过） |
| `preferredPort` | int | | 期望端口（>0 时平台通过 `--port N` 传给插件，仅模型 B），0 表示自动分配；对象形态 `process.preferredPort` 优先 |
| `auth` | object | | **可选，缺省零行为变化**：`{sessionProvider?, credentialKeys?[]}`，见下 |
| `dataTypes` | array | ✓ | 数据类型声明，至少 1 个 |

### dataTypes 元素字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | ✓ | 类型唯一标识 |
| `typeArg` | string | | 传给 CLI 脚本的 `--type` 参数，默认同 `name`（仅模型 A） |
| `endpoint` | string | 模型 B ✓ | HTTP 路径，`{port}` 由平台自动替换为实际端口；**模型 A 可缺省** |
| `category` | string | | 分类标签，默认 `"未分类"`（模型 A/B 统一语义） |
| `displayName` | string | | UI 展示名，默认同 name |
| `ttl` | string/int | | 缓存有效期，支持 `"1h"` `"30m"` `"60s"` `"500ms"` 或秒数，默认 `"5m"`（模型 A/B 统一解析器） |
| `persistentKey` | string | | 持久化缓存键，不设则每次重新拉取不缓存 |
| `stream` | object | | **可选，缺省零行为变化**：`{enabled, protocol?, mime?, credentialed?}`，见下 |
| `file` | object | | **可选，缺省零行为变化**：`{enabled, downloadEndpoint?}`，见下 |
| `fallbackJson` | object | | **可选，缺省零行为变化**：静态兜底（顶层 Map）；拉取失败且无旧缓存时由中枢返回并标记 lastError「使用静态兜底」，见下 |

### 可选声明字段（新增，缺省零行为变化）

> 以下字段全部可选：**未声明时行为与旧版完全一致**；未知字段一律静默忽略（不抛错、不改注册行为）。

**顶层 `auth`（凭据/会话引用）**——仅**引用** `.greenix/config.json` 已声明的凭据 key，**不在此重复声明凭据值**（复用 config 的 `isSecure`，避免双真相源）：

| 字段 | 类型 | 说明 |
|------|------|------|
| `auth.sessionProvider` | string | 会话提供者标识（如 `"zju"`），供上层 SessionProvider 路由 |
| `auth.credentialKeys` | string[] | 引用的凭据 key 列表（对应 config.json 已声明 key） |

**顶层 `process` 对象增强**（吸收 module `ProcessDescriptor` 语义；字符串形态等价 `{exe: "..."}` 全默认）：

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `process.exe`（或 `entry`） | string | — | 可执行文件/脚本入口名 |
| `process.scope` | string | `"long"` | `"long"` 常驻 / `"short"` 一次性 |
| `process.autoStart` | bool | `true` | 是否自动启动 |
| `process.autoRestart` | bool | `false` | 崩溃后是否自动重启（仅 `long` 作用域） |
| `process.protocol` | string | `"http"` | `"http"` / `"stdio"` |
| `process.preferredPort` | int | `0` | 优先端口（`http` 协议），0 = 自动分配 |

**dataTypes[].`stream`（流式声明）**：

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `stream.enabled` | bool | `false` | 是否启用流式 |
| `stream.protocol` | string | — | `hls` / `mp4` / `http-flv` / `sse` / `stdio-jsonl` |
| `stream.mime` | string | — | 媒体 MIME（如 `video/mp4`） |
| `stream.credentialed` | bool | `false` | 拉流是否需携带凭据头 |

**dataTypes[].`file`（文件下载声明）**：

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `file.enabled` | bool | `false` | 是否启用文件下载 |
| `file.downloadEndpoint` | string | — | 下载端点（`{port}` 由平台替换，仅模型 B） |

> 声明了 `file.enabled: true` 的类型表示「该数据源可导出/下载文件」。**模型 A** 的下载清单
> 由脚本 stdout 提供（见 §3.7）；**模型 B** 则用 `file.downloadEndpoint`（`{port}` 由平台替换）作为
> 统一下载端点。消费方经 `orch.fileOf(type)` / `fileByName(name)` 读取该声明（未声明返回 null）。

**dataTypes[].`fallbackJson`（静态兜底，第三级降级）**：

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `fallbackJson` | object | — | 静态兜底数据（顶层 Map）。拉取失败/返回空**且无旧缓存**时由 DataOrchestrator 返回该值并标记 `lastError`「使用静态兜底」；有旧缓存时保留旧缓存、不使用兜底 |

> 这是降级链的**第三级**：① 拉取成功非空 → 覆写缓存；② 拉取失败/空 → 返回 null 保留旧缓存 +
> `connected=false`；③ **声明了 `fallbackJson` 且无旧缓存** → 返回静态兜底。未声明时行为与旧版完全一致。

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

### 3.7 文件型数据源（file 下载契约，T8a）

声明了 `dataTypes[].file.enabled: true` 的类型，其 stdout（模型 A）需在**顶层 JSON 里附「文件清单」**，
消费方据此逐项下载到本地（导出 UI 见 T8b）。清单键按优先级识别（core 侧 `extractFileEntries` 纯函数）：

| 形态 | 示例 | 说明 |
|------|------|------|
| `files` 列表 | `"files": [{"url": "https://…/a.pdf", "name": "a.pdf", "mime": "application/pdf"}]` | 元素为对象：`url` 必填，`name`/`mime` 可选（别名 `filename`/`fileName`、`mimeType`/`type`/`contentType` 亦可）；元素为字符串时视为纯 URL |
| `downloads` / `attachments` / `fileList` | 同上 | 等价备选键 |
| `file` 单对象 | `"file": {"url": "…", "name": "…"}` | 单文件形态（`downloadEndpoint` 亦可用作 url） |
| `downloadEndpoint` 字符串 | `"downloadEndpoint": "https://…"` | 模型 B 风格单端点 |

规范：

1. 顶层仍是 `Map<String, dynamic>`（含 `files` 等键；其余数据键照常）；`files` 缺省/为空/未知结构 → 空清单（不报错）。
2. 消费方拿到 `List<FileEntry>` 后经 `DataFileService.downloadFile(url, targetPath, headers)` 下载到**用户自选路径**；
   支持自定义 `headers`（凭据头，供会话中心导出注入）、超时、失败重试（退避）。
3. **路径安全**：`targetPath` 经 `path_sandbox` 校验（构造 `DataFileService(sandboxRoot: …)`），越界拒绝写入，防目录穿越。

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

> 参考 `example/plugins/douban/`——豆瓣电影 Top250 爬虫（**模型 A，CLI 一次性脚本**，纯标准库），真实可运行。
> 该示例原为模型 B（HTTP 长驻 .exe），已随 python 统一迁移为模型 A（见其 README「从模型 B 迁移到模型 A 的改动」）。

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

### 构建命令（模型 B，legacy）

> ⚠️ 模型 B 已标注 legacy——平台二进制仅同平台可用，同步中心导出受限。新数据源优先模型 A（.py）。

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
| 2026-08-25 | **T8a 文件型数据源契约**：新增 §3.7「文件下载契约」——`file.enabled` 声明 + stdout `files`/`downloads`/`attachments`（或 `file` 单对象 / `downloadEndpoint` 字符串）文件清单约定；core 提供 `extractFileEntries` 纯函数、`orch.fileOf`/`fileByName` 声明查询、`DataFileService.downloadFile`（headers/超时/重试/沙箱）下载 |
| 2026-08-25 | **T1 manifest 契约统一**：模型 A/B 解析收敛为单一 typed model（`DataSourceManifest`/`DataSourceTypeDecl`）；`script`/`typeArg` 补入 typed model、`script`/`process` 互斥二选一、`endpoint` 模型 A 可缺省、`category` 默认统一「未分类」、TTL 统一解析器（s/m/h/ms/纯秒数）、`androidSupport` 严格 bool（非 bool 不再视为 true）；新增可选 `auth`/`stream`/`file`/`process` 增强声明（缺省零行为变化） |
| 2026-08-25 | **t13 阶段1·主题1**：douban 示例迁移模型 A(.py)（原模型 B .exe），清理 PyInstaller 产物；模型 A 标注为推荐/规范化形态，模型 B 标注 legacy；同步中心数据源导出以模型 A 为基准 |
| 2026-08 | 新增模型 A（CLI 一次性脚本）：`script`/`runtime`/`typeArg`/`androidSupport` 字段与 stdout JSON Map 契约；DataHttpServer 新增 `POST /data/register` 运行期热注册；补充 502 语义与空数据门控 |
| 2026-07 | manifest 路径改为 `data/manifest.json`；新增 `preferredPort` 字段；新增远程 manifest 拉取；新增 DataHttpServer 回调端点 |
| — | 初始版本 |
