# Evergreen 插件目录

> 本目录下的所有插件会被 PluginBridge 自动发现并注册为 Agent 工具。
> 目录结构: `plugins/<name>/agent/manifest.json` + `<name>.exe`

## 已安装插件 (12)

### 计算与工具 (5)

| 插件 | 名称 | 模式 | 说明 |
|------|------|------|------|
| calculator | `calculator` | stdin | 四则运算+幂/取余，enum schema |
| password-gen | `password_gen` | flag args | 随机密码生成（长度/字符集/数量） |
| uuid-gen | `uuid_gen` | **positional** | UUID v1/v4 生成（展示位置参数模式） |
| base64 | `base64` | flag args | Base64 编解码（含 URL-safe） |
| unit-convert | `unit_convert` | flag args | 8 类单位换算（自动检测） |

### 文本处理 (4)

| 插件 | 名称 | 模式 | 说明 |
|------|------|------|------|
| text-utils | `text_utils` | flag args | 大小写/反转/统计/去空格 |
| json-format | `json_format` | flag args | JSON 美化/压缩/校验 |
| word-count | `word_count` | flag args | 文本统计+词频 TOP-N |
| url-encode | `url_encode` | flag args | URL 编解码（query/component） |

### 领域工具 (2)

| 插件 | 名称 | 模式 | 说明 |
|------|------|------|------|
| color-convert | `color_convert` | flag args | HEX↔RGB↔HSL 自动检测 |
| qr-text | `qr_text` | flag args | 文本→ASCII 二维码 |

### 文件系统 (1)

| 插件 | 名称 | 模式 | 说明 |
|------|------|------|------|
| mkdir | `mkdir` | flag args | 创建目录（**非只读** write-allowed） |

## 技术维度覆盖矩阵

| 维度 | 覆盖的插件 |
|------|-----------|
| **stdin 模式** | calculator |
| **flag args 模式** (--prefix) | text-utils, password-gen, base64, json-format, word-count, qr-text, color-convert, unit-convert, url-encode, mkdir |
| **positional 模式** | uuid-gen |
| **readOnly: true** | calculator, text-utils, password-gen, base64, json-format, word-count, uuid-gen, qr-text, color-convert, unit-convert, url-encode |
| **readOnly: false** | mkdir |
| **enum schema** | calculator (operation), text-utils (operation), json-format (operation), base64 (operation), url-encode (operation) |
| **短 flag 映射** | text-utils (-t/-o), password-gen (-l/-u/-w/-d/-s/-c), unit-convert (-v/-f/-t/-c), base64 (-t/-o/-u) |
| **默认参数** | password-gen (length=16), word-count (top_n=10), uuid-gen (version=4, count=1) |

## 如何添加新插件

```
plugins/
└── my-plugin/
    └── agent/
        ├── manifest.json   ← 工具描述 + JSON Schema + 参数模式
        ├── plugin.py       ← Python 源码
        └── my-plugin.exe   ← PyInstaller --onefile 编译产物
```

### manifest.json 模板

```json
{
  "name": "my_tool",
  "description": "工具描述（供 LLM 理解用途）。",
  "schema": { "type": "object", "properties": { ... }, "required": [...] },
  "readOnly": true,
  "argMode": "args",
  "argSpec": { "style": "flag", "prefix": "--" }
}
```

### 参数模式

| argMode | PluginBridge 行为 |
|---------|-------------------|
| `stdin` | JSON 写入进程 stdin |
| `args` | 根据 argSpec 构造命令行参数 |
| (argSpec.style=flag) | `--key value` |
| (argSpec.style=positional) | 按 order 顺序输出 value |
| (argSpec.style=json) | `--args=<json>` |

### 编译

```bash
pyinstaller --onefile --console --distpath plugins/<name>/agent plugin.py
mv plugins/<name>/agent/plugin.exe plugins/<name>/agent/<name>.exe
```
