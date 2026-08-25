# Agent 工具插件撰写指南

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 README.md 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-agent |
| 适用 | Agent 工具插件作者 |

> **面向**：插件开发者（编写 `.py` 工具供 Agent 调用；`.exe` 为存量 legacy）
> **统一 python 唯一路径**：新插件一律 `.py` 纯标准库优先（桌面解释器 / 安卓 Chaquopy 同一份脚本）。
> **完整示例**：见本文档 §6（包含 date、weather 等可运行的完整示例）

---

## 目录

1. [插件目录结构规范](#1-插件目录结构规范)
2. [manifest.json 完整字段说明](#2-manifestjson-完整字段说明)
3. [plugin.py 编写规范](#3-pluginpy-编写规范)
4. [编译为 .exe（legacy，仅存量）](#4-编译为-exelegacy仅存量)
5. [测试与调试](#5-测试与调试)
6. [完整示例](#6-完整示例)

---

## 1. 插件目录结构规范

```
plugins/<name>/                     ← 插件根目录，name 为蛇形命名
└── agent/                          ← Agent 工具子目录（必写）
    ├── manifest.json               ← 工具声明（必写，PluginBridge 扫描入口）
    ├── <name>.py                   ← Python 入口（统一主路径，runtime="python"，无需编译）
    ├── <name>.exe                  ← legacy 入口（仅存量 .exe 插件；新插件不要产出）
    ├── plugin.py                   ← 源码（可选，推荐保留用于调试）
    └── README.md                   ← 插件说明（可选）
```

**发现规则**（PluginBridge 扫描逻辑）：

1. 遍历 `plugins/` 下所有子目录
2. 读取 `agent/manifest.json`，`name` 非空即为有效插件
3. 在 `agent/` 中查找入口文件，**`.py` 优先**（同名 `<目录名>.py` 最高优先）；
   仅当无任何 `.py` 且 manifest 未声明 `runtime:"python"` 时才回退 `.exe`（legacy）
4. 构造 `PluginTool` 并注册到 `Registry`

> **注意**：`.py` 入口直接执行——`PluginRunner` 按 `manifest.runtime`（`"python"`）
> 或 `.py` 扩展名自动拼出 `python <entry>`，无需编译（Windows 桌面；安卓走 Chaquopy
> 进程内执行）。manifest 声明 `runtime:"python"` 却只有 `.exe` 属声明错配，插件被跳过。

---

## 2. manifest.json 完整字段说明

### 2.1 当前支持字段（PluginBridge 现状）

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `name` | `string` | **是** | — | 蛇形命名（snake_case），Agent 调用的工具标识符，全局唯一 |
| `description` | `string` | **是** | — | 工具用途描述，**注入 LLM system prompt**，决定 Agent 何时调用 |
| `schema` | `object` | **是** | — | JSON Schema 参数定义。必须包含 `type: "object"`、`properties`；建议包含 `required` |
| `readOnly` | `bool` | 否 | `false` | `true`=只读工具（可并行调用）；`false`=写操作（串行执行） |
| `argMode` | `string` | 否 | `"stdin"` | `"stdin"`=JSON 写入标准输入；`"args"`=命令行参数传递 |
| `argSpec` | `object` | 否 | `{"style":"json"}` | 仅 `argMode="args"` 时生效，控制命令行参数构造方式 |
| `runtime` | `string` | 否 | `"native"` | `"native"`=直接执行入口；`"python"`=用 Python 解释器执行 `.py` |

#### `argSpec` 子字段

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `style` | `string` | `"json"` | `"flag"` → `--key value`；`"positional"` → 纯 value 按序排列；`"json"` → `--args=<json>` |
| `prefix` | `string` | `"--"` | flag 前缀。`"-"`=短 flag，`"/"`=Windows 风格 |
| `flags` | `object` | `{}` | 按 key 覆盖 flag 名，如 `{"city":"-c"}` |
| `order` | `array` | schema properties 声明顺序 | positional 模式的参数顺序 |

### 2.2 规划中字段（当前 PluginBridge 不识别）

以下字段为全局工程师规划的扩展方向，**暂未实现**，请勿在 manifest.json 中使用：

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `string` | 固定 `"agent"`，标识插件类型 |
| `version` | `string` | 语义化版本（如 `"1.0.0"`） |
| `entry` | `string` | 入口命令（`"python plugin.py"` 或 `.exe` 路径），替代当前硬编码的 `.exe` 发现逻辑 |
| `permissions` | `string[]` | 权限声明：`"read-only"` / `"write-allowed"` / `"network"` |
| `timeout_ms` | `int` | 超时毫秒数（默认 30000） |
| `env` | `object` | 环境变量键值对 |

> **实现状态**：当前 PluginBridge 使用 `_findEntry` 发现入口（**`.py` 优先**，同名优先；
> 仅无 `.py` 且 runtime≠python 时回退 `.exe`）+ `PluginManifest`（含 `runtime` 字段）。
> 扩展方向中 `runtime` 已落地；其余字段（`type`/`version`/`entry`/`permissions`/`timeout_ms`/`env`）仍需 Agent 工程师后续实现。

### 2.3 三种 argMode 对比

| 模式 | `argMode` | `argSpec.style` | 调用方式 | 适用场景 |
|------|-----------|-----------------|----------|---------|
| stdin | `"stdin"` | — | JSON → stdin | 复杂参数、嵌套结构 |
| args + flag | `"args"` | `"flag"` | `./tool --key value` | CLI 工具、可选参数多 |
| args + positional | `"args"` | `"positional"` | `./tool val1 val2` | 参数固定、顺序明确 |

完整 JSON 示例见 [§6](#6-完整示例)。

---

## 3. plugin.py 编写规范

### 3.1 stdin 模式（JSON → stdin → stdout）

Agent 将参数 JSON 写入进程 stdin 后立即关闭，进程处理完毕将结果写入 stdout。

```python
"""date plugin — stdin 模式。"""
import sys
import json
from datetime import datetime


def main():
    # 1. 从 stdin 读取 Agent 传入的 JSON 参数
    args = json.loads(sys.stdin.read())
    fmt = args.get("format", "iso")

    # 2. 执行逻辑
    now = datetime.now()
    if fmt == "cn":
        result = now.strftime("%Y年%m月%d日")
    elif fmt == "us":
        result = now.strftime("%m/%d/%Y")
    else:
        result = now.isoformat()

    # 3. 结果写入 stdout
    print(result)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # 错误写入 stderr（不影响 stdout）
        print(f'{{"success": false, "error": "{str(e)}"}}', file=sys.stderr)
        sys.exit(1)
```

### 3.2 args + flag 模式（命令行参数 → stdout）

Agent 根据 `argSpec` 将 JSON 参数映射为命令行参数。

```python
"""time plugin — args + flag 风格。"""
import argparse
from datetime import datetime, timedelta, timezone


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--offset", type=int, default=8)
    parser.add_argument("--format", type=str, default="24h")
    args = parser.parse_args()

    tz = timezone(timedelta(hours=args.offset))
    now = datetime.now(tz)
    fmt = "%I:%M:%S %p" if args.format == "12h" else "%H:%M:%S"
    print(now.strftime(fmt))


if __name__ == "__main__":
    main()
```

### 3.3 args + positional 模式

```python
"""greet plugin — positional 风格。"""
import sys


def main():
    if len(sys.argv) < 2:
        print("用法: greet <name> [language]")
        sys.exit(1)

    name = sys.argv[1]
    lang = sys.argv[2] if len(sys.argv) > 2 else "zh"

    if lang == "zh":
        print(f"你好，{name}！")
    else:
        print(f"Hello, {name}!")


if __name__ == "__main__":
    main()
```

### 3.4 输出格式规范

| 场景 | stdout | stderr | exit code |
|------|--------|--------|-----------|
| 成功 | 结果文本（纯文本或 Markdown） | 可选调试日志 | `0` |
| 业务失败 | — | 错误信息 | `非0` |
| 进程崩溃 | — | 异常堆栈 | `非0` |

**约定**：
- **stdout** 内容直接返回给 Agent 作为工具结果
- **stderr** 内容自动追加到输出末尾（Agent 格式化：`[stderr]\n...`）
- 非零退出码 → Agent 报告 `[plugin "name" exited with code N]`
- 无 stdout 输出 → Agent 显示 `_(no output)_`
- **输出建议**：纯文本优先，需要结构化时用 Markdown 表格/列表，避免超长输出（>4096 字符可能被截断）

### 3.5 错误处理最佳实践

```python
import sys
import json
import traceback


def main():
    try:
        args = json.loads(sys.stdin.read())
        # ... 业务逻辑 ...
        result = do_work(args)
        print(result)

    except json.JSONDecodeError as e:
        print(f"[错误] 无效的 JSON 输入: {e}", file=sys.stderr)
        sys.exit(2)
    except KeyError as e:
        print(f"[错误] 缺少必填参数: {e}", file=sys.stderr)
        sys.exit(3)
    except Exception as e:
        # 完整异常写入 stderr 供调试
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
```

### 3.6 日志与调试输出

- **调试日志** → `stderr`（不影响 Agent 读取结果）
- **工具结果** → `stdout`（Agent 直接使用）
- Python 示例：`print("debug: processing...", file=sys.stderr)`

---

## 4. 编译为 .exe（legacy，仅存量）

> **新插件不要编译 .exe**——`.py` 入口直接运行（`runtime: "python"`），无需编译；
> 同一份 `.py` 跨平台（Windows / Linux / macOS / 安卓 Chaquopy）。本节约定的
> `.exe` 路径仅用于**存量 .exe 插件**的维护（PluginBridge 在无 `.py` 且 manifest
> 未声明 `runtime:"python"` 时回退 .exe 执行，向后兼容）。

### 4.1 PyInstaller（Python）

```bash
# 安装
pip install pyinstaller

# 编译（单文件、控制台模式）
pyinstaller --onefile --console --name weather plugin.py

# 产物路径
# dist/weather.exe → 复制到 plugins/weather/agent/weather.exe
```

**注意事项**：
- `--console`：必须，Agent 通过 stdin/stdout 通信
- `--name`：产物名应与插件目录名一致
- 编译后保留 `plugin.py` 源码在 `agent/` 目录下便于调试
- ⚠️ `.exe` 仅 Windows 桌面可执行；安卓无法 exec PE 格式（统一 .py 的核心动机）

### 4.2 各语言编译命令（legacy 参考）

| 语言 | 命令 | 产物 |
|------|------|------|
| Python | `pyinstaller --onefile --console --name <name> plugin.py` | `dist/<name>.exe` |
| Go | `GOOS=windows GOARCH=amd64 go build -o <name>.exe main.go` | `<name>.exe` |
| C (MinGW) | `gcc -o <name>.exe <name>.c` | `<name>.exe` |
| C (MSVC) | `cl /Fe:<name>.exe <name>.c` | `<name>.exe` |
| Rust | `cargo build --release` | `target/release/<name>.exe` |
| C# (.NET) | `dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true` | `publish/<name>.exe` |

### 4.3 部署检查清单

- [ ] 新插件：`<name>.py` + `manifest.json`（`"runtime":"python"`）在 `plugins/<name>/agent/` 目录
- [ ] 存量 .exe 插件：`<name>.exe` 与 `manifest.json` 同目录，manifest 未声明 `runtime:"python"`
- [ ] 手动测试通过（见 [§5](#5-测试与调试)）

---

## 5. 测试与调试

### 5.1 独立测试（无需 Agent）

```bash
# stdin 模式 — 直接管道输入
echo '{"format":"cn"}' | python plugin.py

# args + flag 模式 — 模拟 Agent 命令行
python plugin.py --offset 8 --format 12h
```

### 5.2 平台内集成测试

插件放入 `plugins/<name>/agent/` 后，启动 Evergreen 平台即可自动发现。验证方法：

1. 确认 `manifest.json` 和入口文件（`.py` 优先）在 `plugins/<name>/agent/` 目录
2. 启动平台，Agent 自动扫描并注册工具
3. 在 Agent 对话中直接调用工具名（如 `date`、`weather`）
4. 观察 Agent 是否成功调用并返回结果

### 5.3 使用模拟 Agent 测试

开发插件时，无需 API Key 即可测试端到端流程：

```bash
# 平台启动后，通过 HTTP API 手动调用工具
curl -X POST http://127.0.0.1:PORT/agent/tool/call \
  -H "Content-Type: application/json" \
  -d '{"tool":"date","args":{"format":"cn"}}'
```

### 5.4 常见问题排查

| 问题 | 可能原因 | 解决方案 |
|------|---------|---------|
| 插件未被发现 | 缺 `manifest.json` 或 `name` 为空 | 检查 `plugins/<name>/agent/manifest.json` 存在且 `name` 非空 |
| 插件未被发现 | 无 `.py`/`.exe` 入口文件 | 确认 `plugins/<name>/agent/<name>.py`（优先）或 legacy `<name>.exe` 存在 |
| 插件未被发现 | manifest `runtime:"python"` 却只有 `.exe` | 声明错配被跳过（fail 可见）；提供 `.py` 或去掉 runtime 声明 |
| 进程无响应/挂起 | 未读取 stdin 或未 flush stdout | stdin 模式必须 `sys.stdin.read()`；确保 `print()` 后 stdout 已刷新 |
| 乱码 | 编码不是 UTF-8 | Python: `sys.stdout.reconfigure(encoding='utf-8')`；Windows 管道输入带 BOM 时先剥离 `\ufeff` |
| 超时 | 进程执行时间过长 | Agent 默认 30s 超时，优化逻辑或考虑异步返回 |
| `argMode="args"` 参数不匹配 | `argSpec` 与 `argparse` 定义不一致 | `argSpec.flags` 中的短 flag 映射需与 argparse 一致 |
| stderr 混入输出 | 错误写入 stdout | 调试信息使用 `print(..., file=sys.stderr)` |

---

## 6. 完整示例

### 6.1 示例 1：stdin 模式 — date 插件

**目录结构**：
```
plugins/date/agent/
├── manifest.json
├── date.py           ← 统一主路径（无需编译，runtime:"python"）
└── plugin.py         ← 源码（可选，便于调试）
```

**manifest.json**：
```json
{
  "name": "date",
  "description": "返回当前日期，支持指定格式。",
  "schema": {
    "type": "object",
    "properties": {
      "format": { "type": "string", "description": "日期格式：iso / cn / us，默认 iso", "enum": ["iso", "cn", "us"] }
    },
    "required": []
  },
  "readOnly": true,
  "runtime": "python",
  "argMode": "stdin"
}
```

**plugin.py**：
```python
"""date plugin — stdin 模式，空输入容错，三种格式。"""
import sys
import json
from datetime import datetime


def main():
    try:
        raw = sys.stdin.read().strip()
        args = json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        args = {}

    fmt = args.get("format", "iso")
    now = datetime.now()

    if fmt == "cn":
        print(now.strftime("%Y年%m月%d日"))
    elif fmt == "us":
        print(now.strftime("%m/%d/%Y"))
    else:
        print(now.isoformat())


if __name__ == "__main__":
    main()
```

**运行**（无需构建）：
```bash
echo '{"format":"cn"}' | python plugin.py
```

**测试**：
```bash
echo '{"format":"cn"}' | python plugin.py
# 输出：2026年07月06日
```

### 6.2 示例 2：args + flag 模式 — weather 插件

**manifest.json**：
```json
{
  "name": "weather",
  "description": "查询指定城市天气（模拟）。",
  "schema": {
    "type": "object",
    "properties": {
      "city": { "type": "string", "description": "城市名" },
      "days": { "type": "integer", "description": "预报天数，默认 1" }
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

**plugin.py**：
```python
"""weather plugin — args + flag + 短 flag 映射。"""
import argparse
import random


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--city", type=str, required=True)
    parser.add_argument("-d", "--days", type=int, default=1)
    args = parser.parse_args()

    conditions = ["晴", "多云", "小雨", "阴", "晴转多云"]
    print(f"{args.city}未来{args.days}天：")
    for i in range(args.days):
        h, l = random.randint(15, 35), random.randint(5, 20)
        print(f"  第{i+1}天：{random.choice(conditions)}，{l}°C ~ {h}°C")
    print("(模拟数据)")


if __name__ == "__main__":
    main()
```

**运行**（无需构建）：
```bash
python plugin.py -c 北京 -d 2
```

**测试**：
```bash
python plugin.py -c 北京 -d 2
# 输出：
# 北京未来2天：
#   第1天：晴，12°C ~ 28°C
#   第2天：多云，15°C ~ 32°C
# (模拟数据)
```

### 6.3 更多示例

本文档 §6.1 和 §6.2 已提供 `date`（stdin）和 `weather`（args + flag）两个完整可运行示例，覆盖了最常用的两种 argMode。其他模式的组合可参考：

| 插件 | 语言 | argMode | 说明 |
|------|------|---------|------|
| `date` | Python | stdin | JSON → stdin，空输入容错，多格式日期输出 |
| `weather` | Python | args + flag + 短flag | `--city` / `-c` 短长 flag 映射，模拟天气 |
| `time` | Python | args + flag | `--offset` 时区偏移，12h/24h 格式切换 |
| `random` | Python | args + flag | `--min` / `--max` 范围随机整数（原 C 实现的 python 等价物） |

> 以上插件对应 `example/plugins/` 下完整模板（manifest + 源码 + README），全部为
> 纯标准库 + `runtime: "python"`，同一份 `.py` 跨平台执行。
> 写操作示例（`readOnly: false`）可参考 `random` 的 manifest 结构，将 `readOnly` 置为 `false` 并实现目录创建逻辑。

**通用模板**：
1. 选择 argMode（stdin 适合复杂参数，args+flag 适合 CLI 工具）
2. 编写 manifest.json（字段：name/description/schema/readOnly/argMode/argSpec/runtime）
3. 编写 plugin.py（见 §3 三种模式的代码模板；`.py` 入口声明 `runtime: "python"` 即可直接运行）
4. 独立测试（见 §5.1 `python plugin.py`）

---

## 附录：PluginBridge 工作原理

**发现**：扫描 `plugins/<name>/agent/` → 读 manifest → **`.py` 优先**（同名 `<目录名>.py` 最高优先；无 `.py` 且 runtime≠python 才回退 `.exe`）→ 注册 `PluginTool`。

**调用**：`registry.call(name, json)` → `PluginRunner.runOnce`（桌面 `SubprocessRunner` 子进程 / 安卓 `ChaquopyRunner` 进程内）→ stdin/args 传入参数 → 收集 stdout + stderr → 返回结果。

**生命周期**：`registerAll`（启动时）→ `refresh`（运行时增量同步）→ `remove`（插件卸载）。
