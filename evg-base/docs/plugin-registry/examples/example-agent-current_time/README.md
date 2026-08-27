# 示例：Agent 工具插件 —— 当前时间（`example-agent-current_time`）

> 本示例是 **agent 型插件**（Task 三决策 3.1）的「声明 + 契约」样板：演示
> `PluginBridge` 自动注册、stdin JSON 参数、以及 manifest 新增的 **`lifetime`
> 一次性 / 常驻** 声明。插件放入 `plugins/<id>/` 后，AI 助手即自动获得
> `current_time` 工具。

## 目录结构

```
example-agent-current_time/
└── agent/
    ├── manifest.json        ← 工具元数据（必写：name/description/schema/...）
    └── tool.py              ← 纯标准库 Python 脚本（stdin JSON → stdout 文本）
```

> 结构对齐 agent 插件统一路径：`plugins/<id>/agent/{manifest.json, <entry>.py}`。
> 与 data 插件的区别：data 插件由平台自动定时跑脚本爬数据；**agent 插件由 AI
> 主动调用**——AI 决定何时运行 `tool.py`，平台运行并把 stdout 返回给 AI。

## manifest 契约要点（可被 `PluginManifest.fromJson` 解析）

| 字段 | 值 | 说明 |
|------|-----|------|
| `name` | `current_time` | 蛇形命名，Agent 调用的工具标识符（必填，空 → 插件被跳过） |
| `description` | 中文 + 英文 | 给 LLM 看的用途说明，决定 AI 何时调用（必填） |
| `schema` | `{type:"object", properties:{tz_offset}, required:[]}` | JSON Schema 参数定义；`tz_offset` 为可选时区偏移（小时） |
| `readOnly` | `true` | 只读工具（可并行执行） |
| `runtime` | `"python"` | 用 Python 解释器执行 `.py`（统一主路径） |
| `argMode` | `"stdin"` | JSON 参数写入标准输入（最小示例风格） |
| `lifetime` | `"once"` | **新增字段（Task 三）**：进程生命周期声明，见下节 |

## 一次性 vs 常驻（`lifetime` 语义）

`lifetime` 声明 `tool.py` 进程的生命周期（JSON 不支持注释，语义以本文档为准）：

| 值 | 语义 | 行为 |
|----|------|------|
| `"once"`（**默认**） | 一次性 | AI 调用该 tool 后，`runOnce` 直跑，输出直接返回给 AI，进程即被回收 |
| `"resident"` | 常驻 | AI 调用后 `startLong` 启动并登记到**后台进程注册表**，进程持续运行；execute 返回「已后台启动」占位文本，输出在后台累积，AI 可用内置工具 `list_processes` 查看、`kill_process` 结束 |

- **缺省 = `once`，未知值静默回退 `once`**（项目铁律「未知静默忽略」）——旧插件
  不声明该字段，行为与以前完全一致（向后兼容）。
- 本示例为一次性工具：`tool.py` 读一次 stdin、打印当前时间、正常退出。
- 若需要常驻形态（如监控、轮询、长连接），把 manifest 的 `lifetime` 改为
  `"resident"`，并让脚本在打印首行后保持运行（如 `while True: time.sleep(1)`），
  配合 `list_processes` / `kill_process` 管理。

## 独立验证

### 1) 手动跑 `tool.py`（无需 AI / 无需平台）

```bash
# stdin JSON 模式（与 PluginBridge 调用方式一致）
echo '{"tz_offset": 8}' | python3 tool.py
# 期望 stdout（UTC+8，北京时区）：
#   2026-08-26 15:30:00 +0800
#   时区偏移: 8 小时

# 空参数（缺省 UTC）
echo '{}' | python3 tool.py
```

### 2) 放入 plugins/ 后 AI 自动注册（验收路径）

1. 把 `example-agent-current_time/` 目录复制为
   `plugins/current_time/`（agent 插件根目录，子目录结构保持
   `plugins/current_time/agent/{manifest.json, tool.py}`）。
2. 启动 Evergreen，AI 助手「工具」弹窗中应出现 `current_time` 开关
   （`PluginBridge` 启动时自动扫描 `plugins/<id>/agent/` 注册）。
3. 让 AI「返回当前时间」→ AI 调用 `current_time` → 平台运行 `tool.py` →
   stdout 返回给 AI → 回复中显示当前时间。

> 期望输出形态：`2026-08-26 15:30:00 +0800`（可让 AI 附带时区偏移参数）。
