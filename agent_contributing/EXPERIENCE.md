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
- [CI 测试修复：Python 进程悬挂 + analyze error + 默认值不一致](experiences/2026-06-22-ci-test-failures-python-env.md) — `ci` `testing` `python` `subprocess` `timeout` `analyze` — **坑：Process.start+Completer 模式悬挂 30min、--no-fatal-infos 不降级 error、Tesseract 二进制缺失**

### Agent 运行时

- [全局记忆回合内去重](experiences/2026-06-18-global-memory-dedup.md) — `agent` `memory` `controller` `performance` — **模式：回合级标记位避免重复 I/O**

### 数据架构

- [缓存优先架构迁移](experiences/2026-06-16-cache-first-architecture.md) — `cache` `offline` `architecture` `provider` — **坑：Agent 工具空数据、Provider autoDispose、ref.read→ref.watch**

### 数据拉取 / 缓存

- [getEverything 静默吞错误导致成绩缓存被空数据覆盖](experiences/2026-06-20-geteverything-silent-error-swallowing.md) — `zdbk` `cache` `error-handling` `provider` `grades` — **坑：编排方法静默折叠子调用错误、泛型缓存回退类型不匹配**
- [预存测试修复：浮点舍入 + Python PATH 兜底](experiences/2026-06-20-pre-existing-test-fixes.md) — `testing` `rounding` `python` `path-resolution` — **坑：浮点期望写错、resolvePythonExe 兜底逻辑导致测试误判**
- [缓存优先架构补全](experiences/2026-06-20-cache-first-completion.md) — `cache` `offline` `zdbk` `classroom` `courses` `performance` — **模式：`_tryFreshCache` 守卫 + Dashboard 去 invalidation + BackgroundRefresher 跳过新鲜数据**
- [数据新鲜度计算修复](experiences/2026-06-20-freshness-computation-fix.md) — `freshness` `data-status` `cacheKey` `timestamp` `ui-consistency` — **坑：cacheKey=null 源 `??= now` 导致永久"过期"、subtitle "在线"与 badge "过期"矛盾**

### Palace 认知中间件

- [Palace Core 实现 + Bug 修复](experiences/2026-06-23-palace-core.md) — `palace` `agent` `memory` `cognitive` `architecture` `integration` `bug-fix` — **模式：零侵入新模块添加 · EventStore 三重索引 · 共享 DeepSeekProvider · envFilePathOverride 测试隔离 · YAML context 缩进解析** — **⚠️ 坑：双重 EventStore 实例、📌 emoji 破坏日期解析、索引损坏无回退**

### CI / DevOps

- [Android CI 中国镜像兼容 + Release 双平台](experiences/2026-06-23-ci-android-china-mirrors.md) — `ci` `github-actions` `android` `gradle` `mirrors` `kotlin` `release` — **模式：标准仓库前置+阿里云镜像后备 · Release 双附件并行** — **⚠️ 坑：Kotlin 插件在 aliyun 镜像缺失、Tencent Cloud Gradle 镜像 CI 不可达**

### UI / 布局

- [页面溢出修复：Row Text + 窄屏滚动](experiences/2026-06-24-ui-overflow-fixes.md) — `ui` `overflow` `responsive` `scroll` `row` `expanded` `wrap` — **模式：Row 中可变 Text 包 Expanded+ellipsis · 多控件 Row 窄屏包 SingleChildScrollView**
- [Palace 过滤栏高度约束修复](experiences/2026-06-24-palace-filter-height-constraint.md) — `palace` `ui` `layout` `column` `constraint` `overflow` `height` — **模式：Column 中混用固定+Expanded 必须给头部高度约束，防止挤压内容区**

### 导航 / 异步陷阱

- [Navigator.pop 在 build 帧中触发 _debugLocked 黑屏](experiences/2026-06-24-navigator-pop-debuglocked.md) — `flutter` `navigator` `dialog` `async` `debugLocked` `black-screen` — **⚠️ 已被否决，方案不适用于 go_router，见下方死路卡片**
- [❌❌ addPostFrameCallback + Navigator.pop 死路](experiences/2026-06-24-addpostframecallback-pop-dead-end.md) — `flutter` `navigator` `go_router` `addPostFrameCallback` `dead-end` — **结论：延迟 pop 误弹 go_router 根路由导致路由栈清空黑屏，此路不通**

### 生命周期 / 异步安全

- [PdfPreviewWidget setState after dispose](experiences/2026-06-24-pdf-preview-setstate-after-dispose.md) — `flutter` `lifecycle` `async` `setState` `dispose` `mounted` `pdf-preview` — **模式：initState 启动的 async 方法每个 await 后必须 `if (!mounted) return`**

### 测试

- [❌ 培养方案测试 minCredits int→double 类型不匹配](experiences/2026-06-24-training-plan-test-type-mismatch.md) — `testing` `training-plan` `type-mismatch` `compilation` — **坑：写测试辅助函数时必须对照模型源码确认字段类型，int 不能直接传 double**

### 失败记录（❌ 此路不通，避免重蹈）

- [❌ dart test -p vm 导入 Flutter 依赖失败](experiences/2026-06-20-dart-test-vm-flutter-import.md) — `testing` `dart` `flutter` `import` — **结论：纯 VM 测试不能 import 任何触及 Flutter SDK 的 package（包括 result.dart → log.dart → flutter/foundation），需自包含类型**
- [❌ DeepSeek Vision / HuggingFace OCR 尝试](experiences/2026-06-xx-deepseek-vision-ocr-failed.md) — `ocr` `deepseek` `huggingface` `tesseract` — **结论：DeepSeek Chat 不支持 Vision API，HuggingFace 需要 Token+镜像，最终回退本地 Tesseract**

---

*最后更新：2026-06-24*
