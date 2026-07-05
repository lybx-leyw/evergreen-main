# Weather 插件（args + flag + 短 flag 示例）

> 查询指定城市天气（模拟数据），演示 `flags` 自定义短 flag 映射。
> 本示例用 Python 标准库编写，插件可用**任意语言**。

## 快速上手

```bash
pip install pyinstaller
pyinstaller --onefile plugin.py
cp dist/plugin.exe ./weather.exe
```

## 通信协议

args + flag 风格，配合 `flags` 映射将长参数名映射为短 flag。

manifest.json 中 `flags: {"city":"-c","days":"-d"}`，Agent 调用 `{"city":"北京","days":3}` 时实际命令行：

```
./weather.exe -c 北京 -d 3
```

stdout 示例：

```
北京未来3天：
  第1天：晴，18°C ~ 32°C
  第2天：多云，20°C ~ 30°C
  第3天：小雨，22°C ~ 28°C
(模拟数据)
```

## 参数

| 参数 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `city` | `string` | —（必填） | 城市名 |
| `days` | `int` | `1` | 预报天数 |

## 技术要点

- **短 flag 映射**：`flags` 将 `city`→`-c`、`days`→`-d`，减少命令行长度。
- **仅用标准库**：`argparse` 解析、`random` 模拟天气。
- **容错**：城市名任意，不会因为"不支持的城市"报错；数据标注 `(模拟数据)` 防止 AI 误信。
