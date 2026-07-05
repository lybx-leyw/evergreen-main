# 09 · 文件工作区

用户与 AI 共享的文件池——知识库、文献管理、AI 文件生成。

与 `media`（展示文件）和 `input.attachments`（上传到消息）不同，workspace 是一个可浏览、可管理的持久文件集合。

## 基本配置

```json
{
  "workspace": {
    "enabled": true,
    "accept": "*.pdf,*.docx,*.txt,*.md,*.csv",
    "maxFiles": 50,
    "maxSizeMb": 30,
    "aiCreatable": ["docx", "pdf", "pptx", "xlsx"],
    "persistAcrossSessions": true
  }
}
```

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `enabled` | `false` | 启用工作区 |
| `accept` | `"*.pdf,*.docx,..."` | 接受的文件后缀 |
| `maxFiles` | `20` | 最大文件数；`0` = 不限制 |
| `maxSizeMb` | `50` | 单文件最大体积；`0` = 不限制 |
| `aiCreatable` | `[]` | AI 可生成格式 |
| `persistAcrossSessions` | `true` | 跨会话持久 |

## 三种使用场景

### 1. 知识库 RAG

```json
{ "workspace": { "enabled": true, "accept": "*.pdf,*.docx,*.txt", "maxFiles": 100, "aiCreatable": [] } }
```

用户上传文献 PDF → 后端索引 → AI 对话时引用知识库内容作答。

### 2. AI 论文生成

```json
{ "workspace": { "enabled": true, "accept": "*.pdf,*.bib,*.docx", "aiCreatable": ["docx", "pdf", "tex"] } }
```

AI 分析参考文献 → 生成论文 `.docx` → 存回工作区。

### 3. AI PPT 生成

```json
{ "workspace": { "enabled": true, "accept": "*.txt,*.md,*.jpg", "aiCreatable": ["pptx", "pdf"] } }
```

用户上传大纲 + 配图 → AI 生成 PPT。

## 后端协议

workspace 由 `process.exe` 实现。新增端点：

| 端点 | 方法 | 说明 |
|------|------|------|
| `/workspace/files` | GET | 列出文件 |
| `/workspace/upload` | POST | 上传 |
| `/workspace/files/:id` | GET | 下载 |
| `/workspace/files/:id` | DELETE | 删除 |
| `/workspace/generate?format=pptx` | POST | AI 创建 |

## 下一步

- [10 · 高级组件](10-advanced.md) — 时间线、地图、表单
