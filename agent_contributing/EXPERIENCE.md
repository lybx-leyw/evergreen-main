# Agent 经验库

> 这里是 Agent 在本仓库中工作的**实战经验积累**。每次完成任务后，Agent 必须在此写入经验卡片。
> 每次开始新任务前，Agent 必须先阅读本索引和相关经验卡片。
>
> **定位**：关于"怎么在这个仓库里干活"的经验，不是用户特质（`.greenix/memories/`），也不是通用规则（`AGENT_CONTRIBUTING.md`）。

## 使用方法

### 读取（任务开始前）

1. 阅读本索引，找到与当前任务相关的 tags
2. 打开匹配的经验卡片，了解上次的坑和有效模式
3. 将这些经验融入你的实施计划

### 写入（任务完成后）

1. 在 `experiences/` 下创建 `YYYY-MM-DD-<简短描述>.md`
2. 按模板填写 frontmatter 和正文
3. 在本文件中添加索引条目

---

## 经验索引

### Python 子进程 / 外部依赖

- [PDF 翻译 Python 子进程环境管理](experiences/2026-06-19-pdf-translate-python-subprocess.md) — `python` `subprocess` `pdf2zh` `pip` `translate` — **坑：Windows 中文路径、SharedPreferences 类型残留、?? 运算符优先级**
- [嵌入式 Python 与翻译 UX 修复](experiences/2026-06-20-pdf-translate-embedded-python.md) — `python` `bundle` `embed` `ux` `stage` — **模式：安装包自带 Python + 阶段管线 UI**

### Agent 运行时

- [全局记忆回合内去重](experiences/2026-06-18-global-memory-dedup.md) — `agent` `memory` `controller` `performance` — **模式：回合级标记位避免重复 I/O**

### 数据架构

- [缓存优先架构迁移](experiences/2026-06-16-cache-first-architecture.md) — `cache` `offline` `architecture` `provider` — **坑：Agent 工具空数据、Provider autoDispose、ref.read→ref.watch**

### 失败记录（❌ 此路不通，避免重蹈）

- [❌ DeepSeek Vision / HuggingFace OCR 尝试](experiences/2026-06-xx-deepseek-vision-ocr-failed.md) — `ocr` `deepseek` `huggingface` `tesseract` — **结论：DeepSeek Chat 不支持 Vision API，HuggingFace 需要 Token+镜像，最终回退本地 Tesseract**

---

*最后更新：2026-06-19*
