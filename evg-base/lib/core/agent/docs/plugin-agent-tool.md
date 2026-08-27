# Agent 工具 .py 开发规范（.exe 为 legacy）

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 README.md 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-agent |
| 适用 | Agent 工具 .py 作者（.exe 仅存量兼容） |

> 面向插件开发者：如何编写一个可与 Evergreen Agent 桥接的 `.py` 工具。
> **统一 python 唯一路径**：新插件一律写 `.py`（纯标准库优先，跨平台
> 桌面解释器 / 安卓 Chaquopy 同一份脚本），`.exe` 仅作存量 legacy 兼容。

---

## 目录结构

```
plugins/<name>/
  agent/
    manifest.json    # 工具元数据（必写）
    <name>.py        # Python 脚本（统一主路径，runtime="python" 或扩展名推断，无需编译）
    <name>.exe       # （legacy）仅存量 .exe 插件；新插件不要产出
    README.md        # 插件说明（可选）
```

PluginBridge 扫描 `plugins/` 下每个子目录的 `agent/` 子目录：
- 必须有至少一个入口文件（**`.py` 优先**——同名 `<目录名>.py` 最高优先；仅当无任何
  `.py` 且 manifest 未声明 `"runtime": "python"` 时才回退 `.exe` legacy）
- 必须有 `manifest.json` 且 `name` 非空
- `.py` 入口建议在 manifest 中声明 `"runtime": "python"`（亦可由 `.py` 扩展名自动推断）

---

## manifest.json 规范

### 全部字段

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `name` | string | **是** | — | 蛇形命名，Agent 调用的工具标识符。空字符串 → 插件被跳过 |
| `description` | string | **是** | — | 给 LLM 看的用途说明，决定何时调用此工具 |
| `schema` | object | **是** | — | JSON Schema 参数定义，`type: "object"` + `properties` + `required` |
| `readOnly` | bool | 否 | `false` | `true`=只读（可并行）；`false`=写操作（串行） |
| `argMode` | string | 否 | `"stdin"` | `"stdin"`：JSON 写入标准输入；`"args"`：命令行参数传递 |
| `argSpec` | object | 否 | `{"style":"json"}` | 仅 `argMode="args"` 时生效，控制命令行构造方式 |
| `runtime` | string | 否 | `"native"` | `"native"`=直接执行入口（legacy `.exe`）；`"python"`=用 Python 解释器执行（`.py`，推荐） |
| `lifetime` | string | 否 | `"once"` | 进程生命周期：`"once"`=一次性（AI 调用后进程即结束，默认，向后兼容）；`"resident"`=常驻（AI 调用后持续运行，登记到后台进程注册表，直到 `kill_process` 结束）。缺省 / 未知值静默回退 `"once"` |

### 最小示例（stdin 模式）

```json
{
  "name": "date",
  "description": "返回当前日期。",
  "schema": {
    "type": "object",
    "properties": {
      "format": { "type": "string", "description": "日期格式：cn=中文, iso=ISO8601" }
    }
  },
  "readOnly": true
}
```

调用方式：Agent 启动 `date.py`（`runtime:"python"`），将 `{"format":"cn"}` 写入 stdin，读取 stdout。

### 完整示例（args + flag 模式）

```json
{
  "name": "weather",
  "description": "查询指定城市的天气。",
  "schema": {
    "type": "object",
    "properties": {
      "city": { "type": "string", "description": "城市名" },
      "days": { "type": "integer", "description": "预报天数，1-7" }
    },
    "required": ["city"]
  },
  "readOnly": true,
  "argMode": "args",
  "argSpec": {
    "style": "flag",
    "prefix": "--",
    "flags": { "city": "-c", "days": "-d" }
  }
}
```

调用方式：Agent 启动 `weather.py`（`runtime:"python"`），传参 `-c 北京 -d 3`。

### `lifetime`：一次性 vs 常驻（Task 三决策 3.1）

`lifetime` 声明 `tool.py` 进程的生命周期：

| 值 | 语义 | 行为 |
|----|------|------|
| `"once"`（**默认**） | 一次性 | AI 调用该 tool 后走 `runOnce`：进程运行、收集 stdout 返回给 AI，进程随即被回收 |
| `"resident"` | 常驻 | AI 调用后走 `startLong`：进程持续运行并登记到**后台进程注册表**（`AgentProcessRegistry`）；`execute` 立即返回「已后台启动」占位文本，输出在后台累积，AI 可经内置工具 `list_processes` 查看累积输出、`kill_process` 结束该进程 |

- **缺省 = `once`，未知值静默回退 `once`**（项目铁律「未知静默忽略」）——旧插件
  不声明该字段，行为与以前完全一致（向后兼容）。
- 常驻场景示例（监控 / 轮询 / 长连接）：AI 调用一次即启动，之后每次需要结果时
  用 `list_processes` 拉取累积输出，任务结束用 `kill_process` 收尾，避免重复启动
  与孤儿进程。
- 两种形态的 `tool.py` 写法差异：一次性脚本打印结果后正常退出；常驻脚本在打印
  首行后保持运行（如 `while True: time.sleep(1)`），直到被 `kill_process` 结束。

```json
{ "name": "watcher", "description": "常驻监控工具。", "schema": {"type": "object", "properties": {}},
  "readOnly": true, "runtime": "python", "argMode": "stdin", "lifetime": "resident" }
```

---

## argMode 详解

### `stdin`（默认）

- JSON 参数写入进程标准输入后立即关闭 stdin
- 进程处理完毕后将结果写入 stdout
- **适用场景**：参数复杂、嵌套深、JSON 原生输入的工具

```python
# date.py（统一主路径；legacy 才需 PyInstaller 编译为 date.exe）
import sys, json
from datetime import datetime

args = json.loads(sys.stdin.read())
fmt = args.get("format", "iso")
if fmt == "cn":
    print(datetime.now().strftime("%Y年%m月%d日 %H:%M:%S"))
else:
    print(datetime.now().isoformat())
```

### `args`

- 根据 `argSpec` 将 JSON 参数映射为命令行参数
- **适用场景**：传统 CLI 工具（argparse、click、Go flag 等）

#### argSpec.style 三种风格

| style | 行为 | 示例（输入 `{"q":"hi","n":5}`） |
|-------|------|-------------------------------|
| `flag` | 每个 key → `--key value`，bool true → `--key` | `--q hi --n 5` |
| `positional` | 按 `order` 顺序输出纯 value | `hi 5` |
| `json` | 整个 JSON 作为 `--args=<json>` | `--args={"q":"hi","n":5}` |

#### argSpec 字段

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `style` | string | `"json"` | `"flag"` / `"positional"` / `"json"` |
| `prefix` | string | `"--"` | flag 前缀，`"-"`=短flag，`"/"`=Windows风格 |
| `flags` | object | `{}` | 按 key 覆盖 flag 名，如 `{"city":"-c"}` |
| `order` | object | schema.properties 声明顺序 | positional 模式的参数顺序 |

---

## stdout 约定

### 成功

- 正常退出（exit code 0）
- stdout 内容即为工具返回给 Agent 的文本
- 无输出时 Agent 显示 `_(no output)_`

### 失败

- 非零 exit code → Agent 报告 `[plugin "name" exited with code N]`
- stderr 内容自动追加到输出末尾
- 进程启动失败 → Agent 报告 `[plugin "name" error: ...]`

### 输出格式建议

- 纯文本优先（Agent 直接展示给用户）
- 如需结构化，使用 Markdown 表格或列表
- 避免输出过长（>4096 字符可能被 Agent 截断）
- 中文输出使用 UTF-8 编码

---

## 语言与构建

### Python（统一主路径，推荐）

> **无需编译**：PluginBridge 对 `.py` 入口直接以 Python 解释器运行
> （`runtime: "python"` 或 `.py` 扩展名自动推断）。**纯标准库优先**——
> 同一份 `.py` 在 Windows / Linux / macOS / 安卓（Chaquopy 进程内）均可执行，
> 同步中心导出/导入友好。示例 `example/plugins/` 全部为纯标准库实现。

```bash
# 直接用解释器运行（桌面嵌入式 Python 或系统 python 均可）
python weather.py -c 北京 -d 2
```

### legacy：编译为 .exe（仅存量插件，新插件不要产出）

> 仅当**存量 .exe 插件**需要继续运行（`runtime` 缺省/`"native"` 时 PluginBridge
> 回退 .exe）；新插件一律 .py。注意：manifest 声明 `"runtime": "python"` 却只提供
> `.exe` 属声明错配，插件会被跳过（fail 可见而非误跑）。

```bash
# Python → .exe（PyInstaller）
pip install pyinstaller
pyinstaller --onefile --console --name weather weather.py
# Go / C / C# → .exe（同上，仅 Windows 桌面，安卓无法 exec PE 格式）
GOOS=windows GOARCH=amd64 go build -o weather.exe main.go
gcc -o random.exe random.c
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

---

## 完整示例

参考 `example/plugins/` 下的插件模板（全部为 Python 标准库 + `runtime: "python"`）：

| 插件 | 语言 | argMode | 说明 |
|------|------|---------|------|
| `time` | Python | args + flag | 时区偏移 + 格式选择 |
| `date` | Python | stdin | 日期格式化 |
| `weather` | Python | args + flag + 短flag | 城市天气查询（模拟） |
| `random` | Python | args + flag | 随机数生成（原 C 实现的 python 等价物） |

每个插件的 `example/plugins/<name>/README.md` 包含运行和测试说明。

---

## 调试

### 手动测试 .py

```bash
# stdin 模式
echo '{"format":"cn"}' | python date/agent/plugin.py

# args 模式
python weather/agent/plugin.py -c 北京 -d 2
```

### 验证 manifest

- `name` 必须非空且蛇形命名（snake_case）
- `schema.properties` 每个属性必须有 `type` 和 `description`
- `schema.required` 列出必填参数
- `argMode="args"` 时 `argSpec.style` 必须是 `"flag"` / `"positional"` / `"json"` 之一

### 本地测试（无需真实 Agent）

开发插件时，可用 `ScriptedAgentHttpServer` 模拟 Agent HTTP 端点，无需 API Key：

```dart
final server = ScriptedAgentHttpServer(scenario: ScriptedAgentHttpServer.scenario3());
final port = await server.start();
// POST http://127.0.0.1:$port/agent/chat/stream → SSE 流
```

参见 `docs/api-contracts.md` § ScriptedAgentHttpServer。

### 常见问题

| 问题 | 原因 | 解决 |
|------|------|------|
| 插件未被发现 | 缺 `manifest.json` 或 name 为空 | 检查文件路径和 JSON 格式 |
| 进程无响应 | 未读取 stdin 或未 flush stdout | stdin 模式必须读 stdin；所有模式必须 flush stdout |
| 乱码 | 编码不是 UTF-8 | Python: `sys.stdout.reconfigure(encoding='utf-8')`；C: `SetConsoleOutputCP(CP_UTF8)` |
| 超时 | 进程执行时间过长 | Agent 默认 30s 超时，长任务考虑异步返回 |
