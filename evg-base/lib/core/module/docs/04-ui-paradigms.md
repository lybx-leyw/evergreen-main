# 04 · UI 范式

组件的核心交互范式由**页面布局 slot 里的组件类型**决定。

> V2 说明：顶层 `ui` 字段（`"chat"` / `"spreadsheet"` 等）**已不再解析**。
> 范式现在由两条路径声明：
> 1. `template`（模块级）——路由到渲染器（`v4` / `html` / `scraper` / `zju` ...）；
> 2. `pages[].layout.slots.<k>.component.type`（v4 声明式模块）——决定页面内各栏位的组件范式。
> 各范式的专属配置（`thinking` / `toolCalls` / `bubble` / `stream` 等）放在 `component.config` 下。

## 七种组件范式

| `component.type` | 范式 | 适用场景 |
|------|------|---------|
| `data-table` | 通用列表/表格/卡片 | 成绩单、新闻列表、课程卡片 |
| `chat` | 对话 | AI 助手、客服机器人 |
| `spreadsheet` | 电子表格 | 成绩分析、数据表 |
| `document` | Word 级文档 | 论文写作、报告编辑 |
| `presentation` | PPT 级幻灯片 | 课件展示、汇报 |
| `chart` / `dashboard` | 仪表盘 | 数据看板、统计概览 |
| `code-editor` | 代码/文本编辑器 | C IDE、LaTeX 编辑器 |

---

## Chat（对话）

```json
{
  "pages": [
    {
      "id": "chat",
      "label": "对话",
      "layout": {
        "type": "grid",
        "slots": {
          "main": {
            "component": {
              "type": "chat",
              "config": {
                "thinking": { "visible": true, "transparent": false, "mode": "expand", "showDuration": true },
                "toolCalls": { "visible": true, "showArgs": true, "showResult": true, "autoCollapse": true },
                "bubble": { "style": "rounded", "avatarPosition": "left", "showTimestamp": true },
                "stream": { "enabled": true, "animation": "typewriter", "cursorStyle": "blinking" },
                "placeholder": "问点什么..."
              }
            }
          }
        }
      }
    }
  ]
}
```

### thinking（思考栏，`config.thinking`）

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `visible` | `true` | 展示思考栏 |
| `transparent` | `false` | 背景透明（DeepSeek 风） |
| `mode` | `"expand"` | `"expand"` 展开 / `"scroll"` 滑动窗口 |
| `showDuration` | `false` | 显示耗时 |

### toolCalls（工具调用，`config.toolCalls`）

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `visible` | `true` | 展示工具调用卡片 |
| `showArgs` | `true` | 展示调用参数 |
| `showResult` | `true` | 展示调用结果 |
| `autoCollapse` | `false` | 完成后自动折叠 |

### bubble（气泡，`config.bubble`）

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `style` | `"rounded"` | `"rounded"` / `"flat"` / `"minimal"` |
| `avatarPosition` | `"left"` | `"left"` / `"none"` |
| `showTimestamp` | `true` | 显示时间戳 |

### stream（流式输出，`config.stream`）

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `enabled` | `true` | 启用流式 |
| `animation` | `"typewriter"` | `"typewriter"` / `"fade"` / `"none"` |
| `cursorStyle` | `"blinking"` | `"blinking"` / `"static"` / `"none"` |

---

## Spreadsheet（电子表格，`config` 同前缀键）

```json
{
  "pages": [
    {
      "id": "sheet",
      "label": "表格",
      "layout": {
        "slots": {
          "main": {
            "component": {
              "type": "spreadsheet",
              "config": {
                "formulas": true,
                "charts": true,
                "sheets": true,
                "conditionalFormatting": true,
                "resizableColumns": true,
                "columns": 26,
                "rows": 100
              }
            }
          }
        }
      }
    }
  ]
}
```

---

## Document（Word，`config` 同前缀键）

```json
{
  "pages": [
    {
      "id": "doc",
      "label": "文档",
      "layout": {
        "slots": {
          "main": {
            "component": {
              "type": "document",
              "config": {
                "trackChanges": true,
                "comments": true,
                "tableOfContents": true,
                "footnotes": true,
                "headersFooters": false,
                "pageSetup": true,
                "exportFormats": ["pdf", "docx"]
              }
            }
          }
        }
      }
    }
  ]
}
```

---

## Presentation（PPT，`config` 同前缀键）

```json
{
  "pages": [
    {
      "id": "slides",
      "label": "幻灯片",
      "layout": {
        "slots": {
          "main": {
            "component": {
              "type": "presentation",
              "config": {
                "transitions": true,
                "animations": true,
                "speakerNotes": true,
                "presenterView": true,
                "slideMaster": true,
                "layouts": ["title", "content", "blank", "two-column"],
                "exportFormats": ["pdf", "pptx"]
              }
            }
          }
        }
      }
    }
  ]
}
```

---

## 下一步

- [05 · 数据绑定](05-data.md) — 让你的模块展示数据
- [06 · 鼠标/触摸交互](06-actions.md)
- [07 · 键盘交互](07-input.md)
