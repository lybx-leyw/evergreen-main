# Agent 工具 .exe 开发规范

> 面向插件开发者：如何编写一个可与 Evergreen Agent 桥接的 `.exe` 工具。

---

## 目录结构

```
plugins/<name>/
  agent/
    manifest.json    # 工具元数据（必写）
    <name>.exe       # 可执行文件（必写，优先匹配目录同名 .exe）
    README.md        # 插件说明（可选）
```

PluginBridge 扫描 `plugins/` 下每个子目录的 `agent/` 子目录：
- 必须有至少一个 `.exe` 文件（优先匹配 `<目录名>.exe`）
- 必须有 `manifest.json` 且 `name` 非空

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

调用方式：Agent 启动 `date.exe`，将 `{"format":"cn"}` 写入 stdin，读取 stdout。

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

调用方式：Agent 启动 `weather.exe -c 北京 -d 3`。

---

## argMode 详解

### `stdin`（默认）

- JSON 参数写入进程标准输入后立即关闭 stdin
- 进程处理完毕后将结果写入 stdout
- **适用场景**：参数复杂、嵌套深、JSON 原生输入的工具

```python
# date.py → PyInstaller → date.exe
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

### Python → .exe（PyInstaller）

```bash
pip install pyinstaller
pyinstaller --onefile --console --name weather weather.py
# 输出: dist/weather.exe → 复制到 plugins/weather/agent/
```

### Go → .exe

```bash
GOOS=windows GOARCH=amd64 go build -o weather.exe main.go
```

### C → .exe（MinGW/MSVC）

```bash
gcc -o random.exe random.c
```

### C# → .exe

```bash
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

---

## 完整示例

参考 `example/plugins/` 下的 4 个插件：

| 插件 | 语言 | argMode | 说明 |
|------|------|---------|------|
| `time` | Python | args + flag | 时区偏移 + 格式选择 |
| `date` | Python | stdin | 日期格式化 |
| `weather` | Python | args + flag + 短flag | 城市天气查询 |
| `random` | C | args + flag | 随机数生成 |

每个插件的 `example/plugins/<name>/README.md` 包含构建和测试说明。

---

## 调试

### 手动测试 .exe

```bash
# stdin 模式
echo '{"format":"cn"}' | ./date.exe

# args 模式
./weather.exe -c 北京 -d 2
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
