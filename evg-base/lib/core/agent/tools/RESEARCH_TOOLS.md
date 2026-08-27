# 专业研究检索 Tools

Skill 深寻 Agent 使用 OpenAI-compatible Tool Calling 调用以下来源：

| Tool | 来源 | 适用场景 | 结果重点 |
|---|---|---|---|
| `arxiv_search` | arXiv API | 预印本、计算机/物理/数学论文 | 标题、作者、摘要、年份、PDF |
| `crossref_search` | Crossref API | 正式出版物、DOI、期刊论文 | DOI、作者、期刊、发表时间 |
| `github_search` | GitHub Search API | 开源实现、代码仓库、工具链 | 仓库、语言、Stars、更新时间 |
| `web_search` | Bing HTML | 补充发现、官方网页、新闻 | 候选链接和摘要 |

专业来源优先，`web_search` 只作为补充发现和交叉验证。所有结果进入深寻证据层后必须带 URL、抓取时间、指纹和可信度；PDF 额外记录页码和原文摘录。

## web_search 多来源召回（Task 二 R2）

`web_search` 支持 `mode` 参数，将 arxiv / github 作为与网络来源并列的搜索来源统一入口，
避免 AI 记忆和多次调用多个 tool 的负担：

| mode | 行为 |
|---|---|
| `network`（缺省） | 现状网络搜索，**零行为变化**（缺省/非法 mode 均回退到此值，未知静默忽略） |
| `arxiv` | 单来源 arXiv 论文检索（复用 `arxivSearchShared`，不重复实现网络请求） |
| `github` | 单来源 GitHub 仓库检索（复用 `githubSearchShared`） |
| `all` | 三来源（网络 + arxiv + github）三合一一并召回，每条结果带 `[网络]` / `[arxiv]` / `[github]` 来源标记 |

**`mode=all` 下 `max_results` 分配策略**（`WebSearchTool._splitForAll`）：三来源均分，
余数优先给网络、其次 arxiv、最后 github；分配为 0 的来源直接跳过（不发起请求）。
例：`max_results=5` → 网络 2 / arxiv 2 / github 1；`=10` → 4/3/3；`=1` → 1/0/0。

**失败语义**：单来源失败不阻塞其余来源（结果末尾附 `[部分来源失败: ...]`）；三来源全部失败才返回整体 `[搜索失败: ...]` 并汇总各来源原因。

**注册点**：不新增工具名——`web_search` 仍是同一工具，三处注册点（`app_bootstrap.dart` /
`agent_runtime.dart` / `agent_factory.dart`）与 `essentialToolNames`、联网开关禁用逻辑均不受影响；
`arxiv_search` / `github_search` 独立工具保留不动。

## 验收清单

- 未配置 API Key/Base URL 时，界面显示接入提示，不进入 Tool 循环。
- 专业 Tool 返回空列表、限流或网络错误时，Agent 能收到明确错误并重试/换来源。
- 同一 URL/标题重复命中时，证据层去重。
- GitHub、arXiv、Crossref 返回结果可被 `web_fetch` 打开或交叉验证。

