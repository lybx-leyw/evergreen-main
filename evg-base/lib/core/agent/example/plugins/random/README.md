# Random 插件（Python 标准库示例）

> 生成指定范围内的随机整数。用**纯 Python 标准库**（`argparse` + `random`）编写，
> 统一 python 唯一路径，manifest `runtime: "python"`，无需编译。
> 原 C 源码（`plugin.c`）保留作 legacy 参考——曾用 MSVC/GCC/Clang 编译为 `random.exe`。

## 快速上手

统一 python 路径：`.py` 入口直接运行（无需编译）。

```bash
python plugin.py --min 1 --max 100
```

## 通信协议

args + flag 风格。Agent 调用 `{"min":1,"max":100}` 时实际命令行：

```
python plugin.py --min 1 --max 100
```

stdout 示例：`42`

## 参数

| 参数 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `min` | `int` | `1` | 最小值 |
| `max` | `int` | `100` | 最大值 |

## 技术要点

- **纯标准库**：`argparse` 解析参数，`random.randint` 生成闭区间随机整数。
- **边界保护**：`min > max` 时自动交换（与原 C 实现行为一致），不会因错误输入崩溃。
- **跨平台**：同一份 `.py` 在 Windows / Linux / macOS / 安卓（Chaquopy）均可执行。
