# Time 插件（args + flag 示例）

> 获取当前时间，支持时区偏移和 12/24 小时制。
> 本示例用 Python 标准库编写，插件可用**任意语言**。

## 快速上手

统一 python 路径：`.py` 入口直接运行（manifest `runtime: "python"`，无需编译）。

```bash
python plugin.py --offset 8 --format 24h
```

## 通信协议

args + flag 风格。Agent 调用 `{"offset":8,"format":"24h"}` 时实际命令行：

```
python plugin.py --offset 8 --format 24h
```

stdout 示例：`14:30:00`

## 参数

| 参数 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `offset` | `int` | `8` | UTC 时区偏移（小时） |
| `format` | `string` | `"24h"` | `"12h"` 或 `"24h"` |

## 技术要点

- **仅用标准库**：`argparse` 解析参数，`datetime` 计算时间。
- **可选参数**：两个参数都有默认值，Agent 可不传。
- **时区计算**：通过 `timedelta` 构造 `timezone`，纯标准库实现。
