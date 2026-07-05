# 07 · 键盘交互

四种键盘输入模式——不只是输入框。

## 选择模式

```json
{
  "input": {
    "mode": "free-text",
    "autoFocus": true,
    "maxLength": 0
  }
}
```

`mode` 是核心选择：

| `mode` | 场景 | 渲染组件 |
|--------|------|---------|
| `"free-text"` | 聊天、评论 | 文本框 |
| `"type-check"` | 打字背词、听写 | 逐字比对输入 |
| `"code"` | 代码编辑 | 代码编辑器 |
| `"select"` | 单选 | 选项列表 |

---

## free-text（聊天输入）

```json
{
  "input": {
    "mode": "free-text",
    "multiline": true,
    "sendOnEnter": true,
    "autoFocus": true,
    "maxLength": 4096,
    "attachments": { "enabled": true, "types": ["image", "file"], "maxSizeMb": 10 },
    "voice": false,
    "slashCommands": true,
    "quickReplies": ["你好", "帮我写代码"]
  }
}
```

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `multiline` | `true` | 多行输入 |
| `sendOnEnter` | `true` | Enter 发送；`false` 则 Shift+Enter 发送 |
| `attachments.enabled` | `false` | 附件上传 |
| `attachments.types` | `["image","file"]` | 允许类型 |
| `attachments.maxSizeMb` | `0` | 单文件上限 |
| `voice` | `false` | 语音输入 |
| `slashCommands` | `false` | 斜杠命令（/help） |
| `quickReplies` | `[]` | 快捷回复建议 |

---

## type-check（打字练习）

```json
{
  "input": {
    "mode": "type-check",
    "autoFocus": true,
    "caseSensitive": true,
    "feedback": {
      "correct":   { "color": "#4caf50", "animation": "bounce" },
      "incorrect": { "color": "#f44336", "animation": "shake" }
    }
  }
}
```

逐字比对输入与正确答案。敲对弹绿 ✓ + bounce，敲错弹红 ✗ + shake。

---

## code（代码编辑）

```json
{
  "input": {
    "mode": "code",
    "language": "c",
    "autoIndent": true,
    "tabSize": 4
  }
}
```

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `language` | `""` | 语言标识（语法高亮） |
| `autoIndent` | `true` | 自动缩进 |
| `tabSize` | `2` | Tab 空格数 |

---

## select（单选）

```json
{
  "input": {
    "mode": "select",
    "options": ["选项 A", "选项 B", "选项 C"]
  }
}
```

---

## 下一步

- [08 · 文件与媒体](08-media.md)
