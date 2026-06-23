---
task_type: feature
tags: [palace, agent, memory, cognitive, architecture, integration]
files_touched:
  - lib/core/palace/** (28 new files)
  - lib/features/palace/** (13 new files)
  - lib/features/agent/providers/agent_provider.dart
  - lib/app.dart
  - lib/widgets/sidebar.dart
  - .gitignore
  - test/core/palace/** (6 new test files)
  - test/features/palace/** (2 new test files)
  - lib/core/config/app_config_notifier.dart
  - test/core/config/app_config_notifier_test.dart
difficulty: medium
outcome: success
date: 2026-06-23
related_pr: 2026-06-23-palace-core-phase1.md
---

## 做了什么

实现了 Palace Core Phase 1——个人世界宫殿认知中间件的第一阶段。28 个新增文件（15 core + 13 feature），4 个已有文件修改，42 个新增测试，全量 1067 tests 通过。

## 关键决策

### 1. 零侵入原则（硬约束）
Palace 是 Evergreen 的新栏目。所有代码放在 `lib/core/palace/` 和 `lib/features/palace/` 两个纯新增目录。对已有文件的修改严格限制为：
- `app.dart`: +2 行（import + route）
- `sidebar.dart`: +7 行（4 处导航项追加）
- `agent_provider.dart`: +10 行（import + QuickCaptureService 构造 + tool 注册）
- `.gitignore`: +1 行

Agent 运行时核心循环、已有 Feature、已有路由、已有侧边栏项全部零修改。

### 2. 共享 DeepSeekProvider
Palace 的 AI 调用直接复用 Agent 运行时已创建的 `DeepSeekProvider` 实例（通过 `agentRuntimeProvider` 注入），不重复配置 API Key/Dio/重试策略。验证确认 DeepSeek API 撑得住并发调用。

### 3. 文件系统存储 + 三重索引
事件存储复用 Memory 系统的 YAML frontmatter + Markdown body 模式，但采用**独立 schema**（不混入 MEMORY.md）。索引按日期、类型、标签三个维度各建一个 Markdown 文件，每次写操作后自动重建。选择文件系统而非数据库的理由：人类可读、Git 可追踪、与现有 Memory 系统一致。

### 4. 独立 frontmatter schema
虽然文件格式与 Memory 系统相同（YAML frontmatter + Markdown body），但字段完全不同（`event_type`/`source`/`captured_at`/`tags` vs `name`/`title`/`type`/`priority`）。这样 Palace 数据和 Agent 记忆数据物理隔离，互不污染。

### 5. 同步 AI 补全
用户提交捕捉后→加载动画→AI 摘要→教训提取→追问生成→完整落盘。选择同步模式的理由：用户期望即时反馈，数据量小（单次 LLM 调用< 2s）。

### 6. Tree view UI
主页面采用类型→日期→卡片三层可折叠树状结构，而非传统时间线。每个类型节点 + 日期节点都可独立展开/折叠。

## 踩过的坑

### 1. ProviderEventKind 导入路径
`ProviderEventKind` 定义在 `core/agent/provider.dart`，不是 `core/agent/event.dart`。5 个 Palace 文件全部用错了导入路径，`flutter analyze` 报 `undefined_shown_name`。修复：统一改为 `import '../../agent/provider.dart' show Provider, ProviderEventKind`。

### 2. ActionChip 不支持 selected/onDeleted
Flutter 的 `ActionChip` 没有 `selected` 和 `onDeleted` 参数。需要用 `InputChip`（有 `onDeleted`）或 `FilterChip`（有 `selected`）。Palace 的 TagChipBar 做了分支处理：编辑模式用 `InputChip`，选择模式用 `FilterChip`。

### 3. YAML context 解析缩进 bug
`_parseContextMap` 用 `line.trim()` 去空格后检查缩进，导致永远检测不到"缩进行"。修复：使用原始 `line` 前导空格判断 `isIndented = line.startsWith(' ')`。

### 4. EventStore 索引路径硬编码
初版 EventStore 从 `palace_paths.dart` 读取全局路径写索引文件，导致测试中索引写到 `.greenix/palace/` 而非测试临时目录。修复：EventStore 改为实例属性 `_dateIndexPath`/`_typeIndexPath`/`_tagIndexPath`，索引写入自己的 `_eventsDir`。

### 5. AppConfigNotifier 测试的 .env 文件泄漏
`settings_service_test.dart` 和 `app_config_notifier_test.dart` 的 `saveAll` 测试调用 `_persistToEnvFile` 写入真实 `.env` 文件，后续测试读取到残留值。修复：`AppConfigNotifier` 增加 `@visibleForTesting envFilePathOverride` 字段，每个测试使用 `Directory.systemTemp.createTemp()` 创建隔离的临时文件。

## 可复用的模式

### 零侵入新模块添加
- 新模块代码全部放独立目录
- 对已有文件的修改限制为 import + 列表末尾追加（route/nav/tool）
- `git diff main -- lib/core/agent/` 为空作为合规检查

### EventStore 索引模式
- 事件文件按 `{YYYY}/{MM}/{uuid}.md` 存储
- 索引文件格式化 Markdown（`- date | type | id | title`）
- 每次写操作后自动重建（低频写入，重建成本可接受）
- 读操作纯内存索引，不扫描文件

## 注意事项
- Palace 的数据写入 `.greenix/palace/` 而非 `.greenix/memories/`，确保与 Agent 记忆系统物理隔离
- `CaptureToPalaceTool` 依赖 `QuickCaptureService`，后者需要 `EventStore` + `DeepSeekProvider`，均在 `agent_provider.dart` 中构造
- 侧边栏的 Palace 导航项需要追加到 4 处：`_CollapsedSidebar`（三数组）、`_ExpandedSidebar`（ListView）、`_MobileDrawer`（Drawer）、`_MobileShell._mobileTitle`（switch）
- 使用 `palaceEventsDir` 全局路径时需先调用 `ensurePalaceDirs()`

---

## Phase 1 修复（2026-06-23 第二轮）

### 修复 1: EventStore 双重实例导致索引不同步

**问题**：`agentRuntimeProvider` 在初始化时创建了独立的 `EventStore(palaceEventsDir)`，而 `palaceEventStoreProvider` 也创建了自己的 EventStore。两个实例有独立的 `_index` 内存映射。Agent 工具 `capture_to_palace` 写入到前者，Palace UI 从后者读取——Agent 工具存入的事件永远不会出现在 UI 中。

**修复**：`agent_provider.dart` 改为 `ref.read(palaceEventStoreProvider)` 获取全局单例 EventStore，确保全应用共享同一份索引。删除了重复的 `EventStore()` 构造。

### 修复 2: 📌 emoji 导致日期索引 DateTime.tryParse 失败

**问题**：`_writeDateIndex` 在今天的事件日期后附加 `📌`（如 `2026-06-23 📌`），但 `_loadIndexes` 用 `DateTime.tryParse('2026-06-23 📌')` 解析——emoji 导致返回 null，所有今天的事件从索引中静默丢失。

**修复**：`_loadIndexes` 解析前用 `replaceAll(RegExp(r'[📌]'), '')` 剥离标记符号。同时将正则改为字符类 `[📌]` 以支持未来可能的多个标记。

### 修复 3: 索引损坏时无法恢复（缺少文件系统扫描回退）

**问题**：`_loadIndexes` 只从索引文件读取；如果索引损坏，catch 块调用 `_rebuildIndexes()`——但 `_rebuildIndexes` 只把内存 `_index` 写到磁盘。当 `_index` 为空时（索引已清空），所有事件永久丢失。

**修复**：新增 `_scanEventsDir()` 方法，递归扫描 `_eventsDir` 下所有 `.md` 文件（跳过 `EVENTS_BY_*` 索引文件），从每个事件文件的 YAML frontmatter 解析出 id/type/capturedAt/title/tagIds 并重建 `_index`。`_loadIndexes` 在索引缺失/损坏时自动调用此回退。

### 修复 4: all() 方法空断言崩溃

**问题**：`all()` 用 `ids.map((id) => get(id)!).toList()`，当 `get(id)` 因文件损坏返回 null 时，`!` 引发空断言崩溃。

**修复**：改为 `ids.map((id) => get(id)).whereType<ConsciousnessEvent>().toList()`，安全跳过损坏的事件。

### 修复 5: _captureService 每次访问都重新创建

**问题**：`PalaceCaptureNotifier._captureService` 是计算属性 getter，每次 `submit()` 调用都创建新的 `QuickCaptureService`（含新的 `AutoTagger`、`LessonExtractor`、`QuestionGenerator` 实例）。

**修复**：增加 `_cachedCaptureService` 字段，使用 `??=` 懒缓存模式，首次访问后复用。
