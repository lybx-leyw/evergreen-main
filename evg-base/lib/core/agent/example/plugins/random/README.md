# Random 插件（C 语言示例）

> 生成指定范围内的随机整数。用纯 C99 编写，零依赖，跨平台。
> 插件可用**任意语言**——Python / Go / Rust / C / C# / Node.js 均可。

## 快速上手

```bash
# GCC
gcc -o random.exe plugin.c

# MSVC
cl /Fe:random.exe plugin.c

# Clang
clang -o random.exe plugin.c
```

## 通信协议

args + flag 风格。Agent 调用 `{"min":1,"max":100}` 时实际命令行：

```
./random.exe --min 1 --max 100
```

stdout 示例：`42`

## 参数

| 参数 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `min` | `int` | `1` | 最小值 |
| `max` | `int` | `100` | 最大值 |

## 技术要点

- **纯 C99**：无第三方库依赖，仅用 `stdio.h` `stdlib.h` `string.h` `time.h`。
- **手动参数解析**：遍历 `argv`，匹配 `--key value` 对，无需 `getopt`。
- **边界保护**：`min > max` 时自动交换，不会因错误输入崩溃。
- **跨平台**：`rand()` + `srand(time(NULL))` 在 Windows / Linux / macOS 均可编译。
