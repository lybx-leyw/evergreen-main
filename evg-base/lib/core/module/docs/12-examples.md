# 12 · 完整示例

从真实应用场景学会组合字段。

---

## AI 助手（Chat）

```json
{
  "type": "module", "id": "agent", "name": "AI 助手",
  "icon": "auto_awesome", "route": "/agent",
  "ui": "chat",
  "sidebar": { "section": "AI 工具", "sectionOrder": 20, "order": 10 },
  "layout": { "mode": "scroll", "drawers": ["right"] },
  "chat": {
    "thinking": { "visible": true, "mode": "expand", "showDuration": true },
    "toolCalls": { "visible": true, "autoCollapse": true },
    "bubble": { "style": "rounded" },
    "stream": { "enabled": true, "animation": "typewriter", "cursorStyle": "blinking" }
  },
  "input": { "mode": "free-text", "attachments": { "enabled": true }, "slashCommands": true },
  "workspace": { "enabled": true, "aiCreatable": ["docx","pdf","pptx"] },
  "process": { "exe": "agent_bridge.exe", "protocol": "http" }
}
```

---

## 课程表

```json
{
  "type": "module", "id": "schedule", "name": "课程表",
  "icon": "calendar_month", "route": "/schedule",
  "ui": "default",
  "sidebar": { "section": "学习", "order": 10 },
  "timeline": { "mode": "calendar", "view": ["day","week","month"], "defaultView": "week", "creatable": true },
  "actions": { "itemTap": "detail", "creatable": true },
  "form": { "submitLabel": "添加课程",
    "fields": [
      { "key": "name", "label": "课程名", "type": "text", "required": true },
      { "key": "room", "label": "教室", "type": "text" },
      { "key": "time", "label": "时间", "type": "datetime" }
    ]
  }
}
```

---

## 成绩分析表（Excel）

```json
{
  "type": "module", "id": "grades", "name": "成绩分析",
  "icon": "assessment", "route": "/grades",
  "ui": "spreadsheet",
  "spreadsheet": { "formulas": true, "charts": true, "sheets": true, "conditionalFormatting": true },
  "data": [{ "type": "grades", "display": "table", "filter": true }],
  "actions": { "sortable": ["学号","姓名","成绩"], "exportable": ["csv","xlsx"] }
}
```

---

## Overleaf 风 LaTeX 编辑器

```json
{
  "type": "module", "id": "latex", "name": "LaTeX 编辑器",
  "icon": "code", "route": "/latex",
  "ui": "editor",
  "layout": { "mode": "fit", "grid": { "columns": 2, "gap": 0 }, "drawers": ["left"] },
  "input": { "mode": "code", "language": "latex", "autoIndent": true, "tabSize": 2 },
  "media": { "accept": "*.pdf", "mode": "inline", "document": { "zoomable": true } },
  "actions": { "editable": true, "exportable": ["tex","pdf"] },
  "process": { "exe": "latex_compiler.exe" }
}
```

---

## 打字背词 App

```json
{
  "type": "module", "id": "vocab", "name": "单词练习",
  "icon": "translate", "route": "/vocab",
  "ui": "default",
  "input": {
    "mode": "type-check", "caseSensitive": true,
    "feedback": {
      "correct":   { "color": "#4caf50", "animation": "bounce" },
      "incorrect": { "color": "#f44336", "animation": "shake" }
    }
  },
  "actions": { "refresh": { "enabled": true, "autoInterval": 0 } },
  "data": [{ "type": "wordlist", "display": "card" }]
}
```

---

## 校园地图

```json
{
  "type": "module", "id": "campus_map", "name": "校园地图",
  "icon": "map", "route": "/map",
  "ui": "default",
  "map": { "center": { "lat": 39.9, "lng": 116.4 }, "zoom": 16, "markers": true, "search": true, "route": true }
}
```

---

## AI 论文写作

```json
{
  "type": "module", "id": "thesis", "name": "论文助手",
  "icon": "menu_book", "route": "/thesis",
  "ui": "document",
  "layout": { "grid": { "columns": 2, "gap": 0 } },
  "document": { "trackChanges": true, "comments": true, "tableOfContents": true, "footnotes": true },
  "chat": { "stream": { "enabled": true }, "bubble": { "style": "minimal" } },
  "workspace": { "enabled": true, "accept": "*.pdf,*.bib,*.docx", "aiCreatable": ["docx","pdf","tex"] },
  "actions": { "editable": true, "exportable": ["pdf","docx","tex"] },
  "process": { "exe": "thesis_ai.exe" }
}
```

---

## 全部组件速查

| 你想做… | 关键字段 |
|---------|---------|
| AI 聊天 | `ui:"chat"` + `chat` + `input` |
| 打字练习 | `input.mode:"type-check"` + `feedback` |
| 代码编辑器 | `ui:"editor"` + `input.mode:"code"` |
| 电子表格 | `ui:"spreadsheet"` + `spreadsheet` |
| Word 文档 | `ui:"document"` + `document` |
| PPT 幻灯片 | `ui:"presentation"` + `presentation` |
| 课程表 | `timeline.mode:"calendar"` + `form` |
| 地图 | `map` + `markers` |
| 视频播放 | `media.accept:"*.mp4"` + `mode:"fullscreen"` |
| PDF 讲义 | `media.accept:"*.pdf"` + `mode:"dropdown"` |
| 知识库 | `workspace.enabled` |
| 表单提交 | `form` + `actions.creatable` |
| 后端服务 | `process` |
