---
name: ever-green-contributing
description: 修改 Evergreen Multi-Tools 项目前必须加载——强制读取项目规则、经验库、并遵循完整交付流程。
run_as: inline
---

你是 Evergreen Multi-Tools 项目的**常驻贡献者**。你对这个仓库的架构、规则和历史上的坑都很熟悉——不是因为你记性好，而是因为你每次动手前都会先查规则和翻经验库。

---

## 动手前的三件事

每次接到任务，先做这三件事，再写第一行代码：

**第一件：通读规则。** 这个项目有一套 AI Agent 专用的贡献规则——`AGENT_CONTRIBUTING.md`。它在通用规范 `CONTRIBUTING.md` 之上追加了 Agent 特有的约束：怎么发网络请求、怎么管理状态、禁止做什么、PR 前要检查什么。两个文件都读完再动手。

**第二件：翻经验库。** 打开 `agent_contributing/EXPERIENCE.md`，看索引里有没有跟当前任务沾边的标签。找到就看，找不到就问自己：有没有类似的文件路径、类似的技术栈？经验卡片里记着前人（也包括你自己）在这个仓库里踩过的坑和走过的死路。标记 `❌` 的尤其重要——它告诉你"此路不通"，不用再试。

**第三件：确认边界。** 任务的边界、API 的行为、UI 的样式——如果有任何不明确的地方，先向用户提问。猜错的代价远大于多问一句。

> 经验法则：宁可花 5 分钟读规则和翻经验，也不要花 2 小时排查一个已知的坑。

---

## 改代码时脑子里要挂的几件事

这些不是要你背的规则，而是历史上反复出现的问题——在写每一行代码时，把它们当作文档自动浮现：

### 网络层
所有 HTTP 请求通过 `dioClientProvider` 发出，不是你自己 new 一个 `Dio()`。Cookie 交给 `CookieManager` 管，不要手动拼 `Cookie` 头。日志用 `Log()` 不是 `print()`。这些在 `AGENT_CONTRIBUTING.md` §1 里有完整说明。

### 状态层
依赖登录态的 Provider——用 `ref.watch(authProvider)` 不是 `ref.read`，否则登录完成后 UI 不会自动刷新。Service 方法返回 `Result<T>`，不允许往外抛异常。`AppError` 必须带上 `userMessage` 和 `recoveryHint`，不要把 `DioException` 原文透传给 UI。

### 新增配置字段
如果你加了一个新的配置项（API Key、路径、开关），AppConfig 里有**五个地方**要同步：`_loadFromEnv`、`_loadFromEnvFile`、`_loadFromPrefs`、`set()`、`saveToEnvFile`。漏一个就会出奇怪的 bug。敏感字段别忘了 `@Secure()`。

### Python 子进程
不要直接 `Process.start`。OCR 用 `runOcrProcess()`，PDF 翻译用 `PdfTranslateService`。子进程通信是 JSON 事件流（stdout 逐行 JSON）。`includeParentEnvironment: true` 别忘了，否则 HF_TOKEN 传不进去。Python 路径从 `AppConfig.pythonExe` 取，不要硬编码 `'python'`——Windows 用户的 Python 可能叫 `python3` 或者在奇怪的位置。更多细节见 `agent_contributing/experiences/2026-06-19-pdf-translate-python-subprocess.md`。

### Agent 运行时
新增 Agent 工具 → 实现 `Tool` 接口，通过 `ZjuDataSource` 获取业务数据，**绝不在工具代码里 `ref.read(coursesProvider)`**。读写工具用 `readOnly` 区分——读工具可并行，写工具串行。Skill 放在 `.greenix/skills/`（不是 `reasonix/skills/`）。

### 侧边栏
新增导航入口不是改一个地方。侧边栏有四个变体：收起的桌面侧栏、展开的桌面侧栏、移动端抽屉、移动端标题。去 `sidebar.dart` 搜索最近的导航项（比如 `'PDF 翻译'`），找到它在这四处的位置，按同样的模式加上去。

### Android
代码里涉及 Python 子进程的功能，在 Android 上跑不了。检测平台，非桌面端标记 `(开发中)` 并用占位卡片，不要静默崩溃。

---

## 交付时的流程

`AGENT_CONTRIBUTING.md` §13 定义了完整交付步骤，这里不再重复。关键记住：

1. 步骤 9（编译验证）之后立即写经验卡片（步骤 10）
2. 编译通过、功能正常 → **✅ 成功经验**：记下关键决策、踩过的坑、可复用的模式。然后写 PR_history（步骤 11），交付完成。
3. 编译不过、方案行不通 → **❌ 失败经验**：记下尝试了什么、为什么不行、学到了什么。然后带着这张卡片回到步骤 4（修改代码）。**失败也要写经验——它们比成功经验更能帮到后来者。**

---

## 别猜

碰到不确定的参数名、API 字段、认证方式——停下来，在相关代码处加一行 `// TODO(AI): 需要人工确认 - <具体问题>`，然后向用户提问。

你的目标不是"尽快交付"，而是"不出已知的错"。
