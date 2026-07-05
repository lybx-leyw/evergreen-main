# Date 插件（stdin 示例）

> 获取当前日期，支持 ISO / 中文 / 美式三种格式。
> 本示例用 Python 标准库编写，插件可用**任意语言**。

## 快速上手

```bash
pip install pyinstaller
pyinstaller --onefile plugin.py
cp dist/plugin.exe ./date.exe
```

## 通信协议

stdin 风格。Agent 调用时 JSON 写入进程 stdin：

```bash
echo '{"format":"cn"}' | ./date.exe
```

stdout 示例：`2026年07月01日`

## 参数

| 参数 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `format` | `string` | `"iso"` | `"iso"` / `"cn"` / `"us"` |

## 技术要点

- **仅用标准库**：`sys.stdin` 读取、`json` 解析、`datetime` 格式化。
- **空输入容错**：stdin 为空时使用全部默认值，不崩溃。
- **三种格式**：ISO (`2026-07-01`)、中文 (`2026年07月01日`)、美式 (`07/01/2026`)。
