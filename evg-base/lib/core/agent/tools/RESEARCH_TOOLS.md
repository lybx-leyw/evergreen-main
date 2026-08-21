# 专业研究检索 Tools

Skill 深寻 Agent 使用 OpenAI-compatible Tool Calling 调用以下来源：

| Tool | 来源 | 适用场景 | 结果重点 |
|---|---|---|---|
| `arxiv_search` | arXiv API | 预印本、计算机/物理/数学论文 | 标题、作者、摘要、年份、PDF |
| `crossref_search` | Crossref API | 正式出版物、DOI、期刊论文 | DOI、作者、期刊、发表时间 |
| `github_search` | GitHub Search API | 开源实现、代码仓库、工具链 | 仓库、语言、Stars、更新时间 |
| `web_search` | Bing HTML | 补充发现、官方网页、新闻 | 候选链接和摘要 |

专业来源优先，`web_search` 只作为补充发现和交叉验证。所有结果进入深寻证据层后必须带 URL、抓取时间、指纹和可信度；PDF 额外记录页码和原文摘录。

## 验收清单

- 未配置 API Key/Base URL 时，界面显示接入提示，不进入 Tool 循环。
- 专业 Tool 返回空列表、限流或网络错误时，Agent 能收到明确错误并重试/换来源。
- 同一 URL/标题重复命中时，证据层去重。
- GitHub、arXiv、Crossref 返回结果可被 `web_fetch` 打开或交叉验证。

