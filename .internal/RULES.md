# EVG 项目规则

> AI 每次启动时应加载此文件。

---

## 一、工作规范

### 1. 先确认再动手
接到任何任务后、动手之前，必须向用户确认两件事：(1) **可修改范围**——哪些文件/目录可以改、哪些不能碰；(2) **目标交付物**——最终要产出什么、以什么形式交付。未确认清楚这两点之前，禁止动手改代码。

### 2. EXPERIENCE 经验库
每次处理问题前，先读取 `.internal/EXPERIENCE.md`，检查是否有类似踩坑记录，避免重复犯错。当用户**纠正你对项目的理解**时（如架构职责、渲染链路等），必须将该经验写入 `.internal/experiences/` 目录下，文件格式遵循 `2026-06-25-module-registry-plugin-architecture.md` 的规范（YAML frontmatter + 做了什么/关键决策/踩过的坑/可复用的模式）。

### 3. 复杂需求先搜索可复用代码
遇到复杂项目需求时，先不要动手写代码。依次检查：(1) 网上是否有可复用的开源实现或库；(2) `.reference/` 目录下是否有可复用的参考代码。确定无可复用代码后，再开始计划和解决。禁止重复造轮子。

---

## 二、常见圈套

### 1. 用对 Shell
你在 Windows 上。Bash = Git Bash (POSIX sh)，PowerShell = PowerShell 5.1。禁止在 Bash 中运行 `Get-ChildItem`、`Select-Object`、`Test-Path`、`Get-Content` 等 PS cmdlet；禁止在 PowerShell 中使用 `ls`、`grep`、`find` 等 Unix 命令。

### 2. 安全操作必须确认
以下操作禁止自动执行：修改 hosts/SSH known_hosts、删除用户文件、`git push -f`/`git reset --hard`、解压文件到用户目录、`dangerouslyDisableSandbox`。`git pull` 前必须检查本地是否领先于远程，有未推送提交时禁止 pull。

### 3. 禁止伪造/隐瞒/偷懒
禁止编造数据、凭印象写数字、thinking 中知道问题但隐瞒用户、声称完成但未验证、被告知 copy 参考代码时自己写。不确定就说"不确定"，发现障碍立即告知用户。

### 4. 保护敏感信息
禁止明文输出 API 密钥/密码/token。读取含敏感信息的文件后脱敏显示。

---

## 三、Bug 处理

### 1. 3 次失败 = 熔断
同一方法连续失败 3 次后，停止、告知用户尝试了什么、提出本质上不同的替代方案。禁止全盘搜索 (`find /`)，Glob 超时后缩小范围而非扩大。

### 2. 测试要求
你必须为新增的代码撰写对应的test。你需要确保自己添加的代码符合当前风格且有足够的 debug 断点。