# 搜索 Tools（统一入口：web_search mode）

Skill 深寻 Agent 使用 OpenAI-compatible Tool Calling 调用搜索能力。
**Task 二 R2-5 起搜索工具统一入口为 `web_search`**——arxiv / github / crossref 不再作为
独立工具注册/显示（AI 助手可见工具仅 `web_search` + `web_fetch`），全部经 `mode` 参数调用：

| 来源 | 统一入口 mode | 底层 API | 结果重点 |
|---|---|---|---|
| 网络搜索 | `web_search` mode=`network`（缺省） | Bing HTML | 候选链接和摘要、来源域名 |
| arXiv 论文 | mode=`arxiv` | arXiv API | 标题、作者、摘要、年份、PDF |
| GitHub 仓库 | mode=`github` | GitHub Search API | 仓库、语言、Stars、更新时间 |
| Crossref 出版物 | mode=`crossref` | Crossref API | DOI、作者、期刊、发表时间 |
| 全部来源 | mode=`all` | 四合一 | 上述全部，结果带来源标记 |

`web_fetch` 保留独立注册（抓取 URL 内容，与搜索不同语义，且与联网搜索开关
`webSearchEnabledProvider` 绑定）。

所有结果进入深寻证据层后必须带 URL、抓取时间、指纹和可信度；PDF 额外记录页码和原文摘录。

## web_search mode 语义（Task 二 R2 / R2-5）

| mode | 行为 |
|---|---|
| `network`（缺省） | 现状网络搜索，**零行为变化**（缺省/非法 mode 均回退到此值，未知静默忽略） |
| `arxiv` | 单来源 arXiv 论文检索（复用 `arxivSearchShared`，不重复实现网络请求） |
| `github` | 单来源 GitHub 仓库检索（复用 `githubSearchShared`） |
| `crossref` | 单来源 Crossref 出版物检索（复用 `crossrefSearchShared`） |
| `all` | 四来源（网络 + arxiv + github + crossref）四合一一并召回，每条结果带 `[网络]` / `[arxiv]` / `[github]` / `[crossref]` 来源标记 |

**`mode=all` 下 `max_results` 分配策略**（`WebSearchTool._splitForAll`）：四来源均分
（`max_results ~/ 4`），余数全部优先给网络；分配为 0 的来源直接跳过（不发起请求）。
例：`max_results=5` → 网络 2 / arxiv 1 / github 1 / crossref 1；`=10` → 4/2/2/2；
`=1` → 1/0/0/0；`=4` → 1/1/1/1。

**失败语义**：单来源失败不阻塞其余来源（结果末尾附 `[部分来源失败: ...]`）；四来源全部
失败才返回整体 `[搜索失败: ...]` 并汇总各来源原因。

**注册点**：不新增工具名——`web_search` 仍是同一工具；四处注册点（`app_bootstrap.dart` /
`agent_runtime.dart` / `agent_factory.dart` / `skill_creator_agents.dart`）已移除
`arxiv_search` / `github_search` / `crossref_search` 独立注册（类定义保留在
`research_search.dart`，供探针 `search_recall_probe.dart` 直接引用与共享检索函数复用）；
`essentialToolNames`（providers.dart）与 `webSearchEnabledProvider` 禁用逻辑（仅
`web_search` / `web_fetch`）不受影响。

## 验收清单

- 未配置 API Key/Base URL 时，界面显示接入提示，不进入 Tool 循环。
- 各来源返回空列表、限流或网络错误时，Agent 能收到明确错误并重试/换来源（mode=all 单来源失败不阻塞）。
- 同一 URL/标题重复命中时，证据层去重。
- GitHub、arXiv、Crossref 返回结果可被 `web_fetch` 打开或交叉验证。
