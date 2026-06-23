# Palace Core — 实施计划与记录

**版本：v1.0**
**日期：2026-06-23**
**状态：✅ 已完成**

---

## 〇、阶段目标

打通 **用户 → AI 对话 → 指挥 AI 写入 → 结构化存储 → 树状浏览** 的完整闭环。

一句话：用户可以在任何地方（Agent 对话 / 手动捕捉）将认知碎片存入 Palace，并能按类型 → 日期 → 卡片的三层树状视图浏览和检索。

---

## 一、Q&A 决策汇总

| # | 问题 | 决策 |
|---|------|------|
| Q1 | 事件 ID 生成 | UUID v4（`uuid` package，同 Session） |
| Q2 | emotionalValence 取值 | 用户手动输入（表情选择器） |
| Q3 | frontmatter 格式 | **独立 Palace schema**（不混入 MEMORY.md） |
| Q4 | 路径管理 | Palace 自己管理（`PalacePaths` 类），数据放在 `.greenix/palace/` |
| Q5 | 索引文件 | **三个索引**：按类型（`EVENTS_BY_TYPE.md`）、按标签（`EVENTS_BY_TAG.md`）、按日期（`EVENTS_BY_DATE.md`） |
| Q6 | 提炼入口 | Agent 工具 `capture_to_palace`，用户用自然语言指挥 AI 写入 |
| Q7 | 工具注册 | 直接在 `agent_provider.dart` 的 `registerAll` 末尾追加 |
| Q8 | 页面布局 | **树状视图**：按类型分组 → 日期 → 事件卡片 |
| Q9 | 快速捕捉 | `showDialog` 弹出对话框 |
| Q10 | DeepSeek 实例 | 共享 Agent 已有的 `DeepSeekProvider` |
| Q11 | AI 分析 | **同步**：写入 rawContent → 调 AI 补全（加载动画）→ 完整落盘 |
| Q12 | Provider 数量 | **第一阶段即成品**，覆盖所有模块 |

---

## 二、新增文件清单

### 2.1 `lib/core/palace/` — 平台层（不依赖 Flutter UI）

```
lib/core/palace/
├── palace.dart                         # 库入口，统一导出
├── models/
│   ├── consciousness_event.dart        # 事件模型 + 序列化
│   ├── context_snapshot.dart           # 情境快照模型
│   ├── structured_lesson.dart          # 结构化教训 + ApplicabilityCondition + CounterExample
│   └── echo_schedule.dart              # 回响调度模型（第二阶段用，先定义骨架）
├── storage/
│   ├── event_store.dart                # 文件 I/O + CRUD + 三重索引
│   └── palace_paths.dart               # .greenix/palace/ 路径管理
├── capture/
│   ├── context_capturer.dart           # 情境自动采集器
│   └── quick_capture_service.dart      # 捕捉业务逻辑（写入 → AI 补全 → 追问）
├── refinery/
│   ├── lesson_extractor.dart           # AI 教训提取
│   ├── question_generator.dart         # 苏格拉底追问
│   └── auto_tagger.dart                # 自动标签建议
└── tools/
    └── capture_to_palace_tool.dart      # Agent 工具：用户用自然语言指挥 AI 写入 Palace
```

### 2.2 `lib/features/palace/` — UI 层

```
lib/features/palace/
├── palace_feature.dart                 # 库入口
├── providers/
│   ├── palace_event_store_provider.dart # EventStore 单例
│   ├── palace_events_provider.dart      # 事件列表 + 过滤 + 刷新
│   ├── palace_capture_provider.dart     # 捕捉浮窗状态
│   ├── palace_lessons_provider.dart     # 教训列表 + 草稿
│   ├── palace_tags_provider.dart        # 全局标签云
│   └── palace_filter_provider.dart      # 当前过滤条件
├── screens/
│   └── palace_screen.dart              # 主页面（树状视图容器）
├── dialogs/
│   └── capture_dialog.dart             # 快速捕捉弹窗
└── widgets/
    ├── event_tree_view.dart            # 树状结构组件
    ├── event_card.dart                 # 事件卡片
    ├── event_detail_panel.dart         # 事件详情展开
    ├── emotion_selector.dart           # 情绪选择器
    ├── tag_chip_bar.dart               # 标签 chip 展示/选择
    └── type_filter_bar.dart            # 六类型过滤 tab
```

### 2.3 `test/` — 测试

```
test/
├── core/palace/
│   ├── models/consciousness_event_test.dart
│   ├── models/structured_lesson_test.dart
│   ├── storage/event_store_test.dart
│   ├── storage/palace_paths_test.dart
│   ├── capture/context_capturer_test.dart
│   ├── refinery/lesson_extractor_test.dart
│   └── refinery/question_generator_test.dart
└── features/palace/
    ├── providers/palace_events_provider_test.dart
    ├── providers/palace_capture_provider_test.dart
    ├── widgets/event_tree_view_test.dart
    └── widgets/event_card_test.dart
```

### 2.4 已有文件的修改

| 文件 | 改动 | 行数 |
|------|------|------|
| `lib/features/agent/providers/agent_provider.dart` | import + `registerAll` 末尾追加 `CaptureToPalaceTool` | ~3 行 |
| `lib/app.dart` | `ShellRoute` 末尾追加 `GoRoute(path: '/palace')` | ~8 行 |
| `lib/widgets/sidebar.dart` | 4 处导航项列表末尾追加 "宫殿" | ~4 行 |
| `.gitignore` | 追加 `.greenix/palace/` | ~1 行 |

**合计修改已有文件：4 个，净增 ~16 行。**

---

## 三、数据模型详细设计

### 3.1 ConsciousnessEvent（`lib/core/palace/models/consciousness_event.dart`）

```dart
enum EventType { thought, lesson, decision, reflection, connection, milestone }
enum SourceTool { agent, manual, tutor, todo, scores, courses, classroom, wordpecker, external }

class ConsciousnessEvent {
  final String id;              // UUID v4
  final EventType type;
  final SourceTool source;
  final DateTime capturedAt;

  // 内容
  final String rawContent;      // 用户原始输入 / AI 对话片段
  final String? aiSummary;      // AI 自动摘要（同步补全）
  final List<String> tagIds;    // 如 ["深度工作", "效率"]

  // 情境
  final ContextSnapshot? context;

  // 关联
  final List<String> linkedEventIds;
  final String? lessonId;       // 如果被提炼为教训，指向 StructuredLesson.id

  // 元数据
  final double? emotionalValence;  // -1.0 ~ 1.0（用户手动选择）
  final bool isVerified;

  // 序列化
  String toFileContent();         // YAML frontmatter + Markdown body
  factory ConsciousnessEvent.fromFileContent(String content, String filename);
  Map<String, dynamic> toYamlFrontmatter();
}
```

**YAML frontmatter 格式（独立 Palace schema）：**

```yaml
---
id: a1b2c3d4-e5f6-7890-abcd-ef1234567890
event_type: thought
source: agent
captured_at: 2026-06-23T14:30:00+08:00
tags:
  - 深度工作
  - 效率
  - 专注
ai_summary: 用户认为上午 9-11 点是深度工作的黄金时段
emotional_valence: 0.6
is_verified: true
context:
  active_feature: agent
  active_task: 讨论工作习惯
  recent_actions:
    - 打开 AI 助手
    - 提问关于效率的话题
linked_events: []
lesson_id: ~
---

今天和 AI 聊到工作习惯，突然意识到我效率最高的时段是早上 9 点到 11 点。
这段时间应该严格保护，不开会、不回消息、只做需要深度思考的工作。

```
> 用 `null` 代替 `~`（纯文本用 `~` 表示 null）。
```

### 3.2 ContextSnapshot（`lib/core/palace/models/context_snapshot.dart`）

```dart
class ContextSnapshot {
  final String? activeFeature;     // 从 GoRouter 当前路由推断
  final String? activeTask;        // 从 Todo/Plan Provider 读取
  final List<String> recentActions; // 最近 5 条操作
  final String? triggerSource;     // 触发源描述
  final Map<String, String>? extra;

  // 序列化（YAML 内嵌，非独立文件）
  Map<String, dynamic> toYaml();
  factory ContextSnapshot.fromYaml(Map<String, dynamic>? map);
}
```

### 3.3 StructuredLesson（`lib/core/palace/models/structured_lesson.dart`）

```dart
class StructuredLesson {
  final String id;
  final String corePrinciple;
  final String elaboration;
  final List<String> sourceEventIds;
  final List<ApplicabilityCondition> conditions;
  final List<CounterExample> counterExamples;
  final int version;
  final List<LessonRevision> revisionHistory;

  String toFileContent();
  factory StructuredLesson.fromFileContent(String content, String filename);
}

class ApplicabilityCondition {
  final String condition;
  final double confidence;
  final List<String> supportingEventIds;
}

class CounterExample {
  final String description;
  final String? sourceEventId;
  final DateTime recordedAt;
}

class LessonRevision {
  final int version;
  final DateTime revisedAt;
  final String changeDescription;
  final String? previousCorePrinciple;
}
```

---

## 四、存储层设计

### 4.1 目录结构

```
.greenix/palace/
├── events/
│   ├── EVENTS_BY_DATE.md              # 索引：按日期倒序
│   ├── EVENTS_BY_TYPE.md              # 索引：按类型分组
│   ├── EVENTS_BY_TAG.md               # 索引：按标签分组
│   └── 2026/
│       └── 06/
│           ├── a1b2c3d4-....md        # UUID 文件名
│           └── e5f67890-....md
├── lessons/
│   ├── LESSONS.md                     # 索引：按版本倒序
│   └── {id}.md                        # 教训文件
```

### 4.2 EventStore（`lib/core/palace/storage/event_store.dart`）

```dart
class EventStore {
  final String eventsDir;

  // CRUD
  Future<void> save(ConsciousnessEvent event);
  Future<ConsciousnessEvent?> get(String id);
  Future<List<ConsciousnessEvent>> all();
  Future<void> delete(String id);
  Future<void> update(ConsciousnessEvent event);  // 覆盖写入

  // 索引
  void _rebuildIndexes();              // 每次写操作后重建三个索引
  String _buildDateIndex();
  String _buildTypeIndex();
  String _buildTagIndex();

  // 查询（读索引，不扫描文件）
  List<String> listByType(EventType type);   // 返回 event id 列表
  List<String> listByTag(String tag);
  List<String> listByDateRange(DateTime from, DateTime to);

  // 搜索（关键词匹配 title + rawContent，同 MemoryStore.search()）
  List<String> search(String query);
}
```

**设计要点：**
- 事件文件按 `{YYYY}/{MM}/{uuid}.md` 存储（懒加载：索引只存 id + 元数据，点击展开时才读全文）
- 索引在每次 `save`/`delete`/`update` 后自动重建（写操作为低频操作，重建成本可接受）
- `EVENTS_BY_DATE.md` 格式：`- 2026-06-23 | thought | <id> | <标题前 60 字>`
- `EVENTS_BY_TYPE.md` 格式：`## thought` → 其下日期倒序列表
- `EVENTS_BY_TAG.md` 格式：`## 深度工作` → 其下按日期倒序的事件列表
- 搜索走关键词匹配（对齐 `FileMemoryStore.search()`），不引入向量化

### 4.3 PalacePaths（`lib/core/palace/storage/palace_paths.dart`）

```dart
class PalacePaths {
  static String get baseDir => p.join(greenixBasePath, 'palace');
  static String get eventsDir => p.join(baseDir, 'events');
  static String get lessonsDir => p.join(baseDir, 'lessons');

  static String eventFilePath(String id, DateTime capturedAt);  // → eventsDir/YYYY/MM/{id}.md
  static String lessonFilePath(String id);                      // → lessonsDir/{id}.md

  static void ensureDirs();  // 创建所有需要的目录
}
```

---

## 五、采集层设计

### 5.1 ContextCapturer（`lib/core/palace/capture/context_capturer.dart`）

```dart
class ContextCapturer {
  /// 从当前应用状态自动采集情境快照。
  /// [ref] 是 Riverpod WidgetRef（由调用方传入，不持有）。
  ContextSnapshot capture(WidgetRef ref);
}
```

实现逻辑：
- `activeFeature`：遍历已知路由前缀（`/agent` → `agent`、`/courses` → `courses`），匹配当前 `GoRouterState`
- `activeTask`：读 `todoListProvider` 中最近一个未完成的待办标题
- `recentActions`：从应用级操作历史中取最近 5 条（可以是简单的内存 circular buffer）
- `triggerSource`：由调用方设置（如 `"Agent 对话中用户主动触发"`）

### 5.2 QuickCaptureService（`lib/core/palace/capture/quick_capture_service.dart`）

```dart
class QuickCaptureService {
  final EventStore _store;
  final DeepSeekProvider _llm;

  /// 用户从捕捉浮窗提交 → 写入 rawContent → 同步调 AI 补全 → 返回完整事件。
  /// [onProgress] 回调用于更新 UI 加载状态（"正在生成摘要..."→"正在提取教训..."→"正在生成追问..."）。
  Future<CaptureResult> capture({
    required String rawContent,
    required EventType type,
    required SourceTool source,
    required double? emotionalValence,
    required List<String> tags,
    required ContextSnapshot? context,
    void Function(String stage)? onProgress,
  });
}

class CaptureResult {
  final ConsciousnessEvent event;
  final StructuredLesson? lesson;           // AI 提取的教训草稿
  final List<String> followUpQuestions;     // AI 生成的追问
}
```

执行流程：
```
① 创建 ConsciousnessEvent（rawContent 已填，aiSummary=null）
② onProgress("正在生成摘要...")
③ 调 DeepSeekProvider → 生成 aiSummary → 回填到 event
④ onProgress("正在提取教训...")
⑤ 调 LessonExtractor → 生成 StructuredLesson 草稿
⑥ onProgress("正在生成追问...")
⑦ 调 QuestionGenerator → 生成 3 个追问
⑧ event 完整落盘（EventStore.save）
⑨ lesson 草稿落盘（暂存，用户确认后正式激活）
⑩ 返回 CaptureResult
```

### 5.3 CaptureToPalaceTool（`lib/core/palace/tools/capture_to_palace_tool.dart`）

```dart
class CaptureToPalaceTool extends Tool {
  @override String get name => 'capture_to_palace';
  @override String get description => '将当前对话中的关键洞察、反思、决定写入 Palace 意识库。'
      '用户可以用自然语言描述想记住什么，你会提取核心内容并结构化存储。';
  @override bool get readOnly => false;  // 写操作

  @override Map<String, dynamic> get schema => {
    'type': 'object',
    'properties': {
      'event_type': {
        'type': 'string',
        'enum': ['thought', 'lesson', 'decision', 'reflection', 'connection', 'milestone'],
        'description': '认知事件的类型',
      },
      'content': {
        'type': 'string',
        'description': '用户想要存入 Palace 的核心内容（一段话，尽可能保留原意）',
      },
      'tags': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': '相关标签（2-5 个）',
      },
      'emotional_valence': {
        'type': 'number',
        'description': '可选的情绪效价（-1.0 负面 到 1.0 正面）',
      },
    },
    'required': ['event_type', 'content'],
  };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    // 调用 QuickCaptureService.capture()
  }
}
```

**注意**：`CaptureToPalaceTool` 需要访问 `EventStore` 和 `DeepSeekProvider`。这两个依赖通过构造函数注入：
```dart
CaptureToPalaceTool(this._captureService);  // QuickCaptureService 在 agent_provider.dart 中创建并注入
```

---

## 六、AI 分析层设计

### 6.1 LessonExtractor

```dart
class LessonExtractor {
  final DeepSeekProvider _llm;

  /// 从事件的 rawContent + aiSummary 中提取结构化教训草稿。
  /// 返回的 StructuredLesson 的 version=0（草稿态），需用户确认后变为 version=1。
  Future<StructuredLesson> extract(ConsciousnessEvent event);
}
```

### 6.2 QuestionGenerator

```dart
class QuestionGenerator {
  final DeepSeekProvider _llm;

  /// 对一条新教训生成 3 个苏格拉底式追问。
  Future<List<String>> generate(StructuredLesson lesson);
}
```

### 6.3 AutoTagger

```dart
class AutoTagger {
  final DeepSeekProvider _llm;

  /// 从 rawContent 中提取 2-5 个标签建议。
  /// 如果用户已经手动打了标签，则跳过 AI 建议（返回 []）。
  Future<List<String>> suggest(String rawContent, {List<String> existingTags = const []});
}
```

---

## 七、Provider 层设计

### 7.1 `palaceEventStoreProvider`（`Provider<EventStore>`）

```dart
final palaceEventStoreProvider = Provider<EventStore>((ref) {
  PalacePaths.ensureDirs();
  return EventStore(PalacePaths.eventsDir);
});
```

### 7.2 `palaceEventsProvider`（`StateNotifierProvider`）

```dart
class PalaceEventsNotifier extends StateNotifier<List<ConsciousnessEvent>> {
  final EventStore _store;
  // 所有事件（内存缓存，从索引懒加载）
  // 支持增量刷新

  void refresh();
  void filterByType(EventType? type);
  void filterByTag(String tag);
  void filterByDateRange(DateTime? from, DateTime? to);
  void search(String query);
}
```

### 7.3 `palaceCaptureProvider`（`StateNotifierProvider`）

```dart
class PalaceCaptureState {
  final bool isOpen;               // 浮窗是否打开
  final String content;            // 当前输入的文本
  final EventType? selectedType;
  final double? emotionalValence;
  final List<String> tags;
  final bool isLoading;            // AI 补全中
  final String? loadingStage;      // "正在生成摘要..."
  final CaptureResult? lastResult; // 上一次捕捉的结果（展示给用户确认）
}

class PalaceCaptureNotifier extends StateNotifier<PalaceCaptureState> {
  void open({SourceTool? source, ContextSnapshot? context});
  void close();
  void updateContent(String text);
  void updateType(EventType type);
  void updateEmotion(double? valence);
  void addTag(String tag);
  void removeTag(String tag);
  Future<void> submit();  // 调 QuickCaptureService → 加载动画 → 写入 → 展示结果
  void confirm();         // 确认教训草稿 → 正式激活
  void dismiss();         // 丢弃（只保留事件，丢弃教训草稿）
}
```

### 7.4 `palaceLessonsProvider`（`StateNotifierProvider`）

```dart
class PalaceLessonsNotifier extends StateNotifier<List<StructuredLesson>> {
  void refresh();
  void confirm(String lessonId);   // 草稿 → 正式（version 0→1）
  void revise(String lessonId, String newPrinciple);
  void addCondition(String lessonId, ApplicabilityCondition condition);
  void addCounterExample(String lessonId, CounterExample example);
}
```

### 7.5 `palaceTagsProvider`（`Provider`）

从所有事件中聚合去重，生成全局标签云。每次 `palaceEventsProvider` 刷新后自动更新。

### 7.6 `palaceFilterProvider`（`StateNotifierProvider`）

当前过滤条件（类型 + 标签 + 日期范围 + 搜索词），驱动 `palaceEventsProvider` 的过滤。

---

## 八、UI 层设计

### 8.1 PalaceScreen（主页面）

```
┌──────────────────────────────────────────────┐
│  AppBar: 宫殿                                │
│  ┌──────────────────────────────────────────┐│
│  │ TypeFilterBar: [全部|想法|教训|决策|反思|连接|节点] ││
│  │ TagChipBar: [深度工作 ×] [效率 ×] [+ 添加标签]   ││
│  ├──────────────────────────────────────────┤│
│  │ 🌳 EventTreeView                         ││
│  │                                          ││
│  │  📌 thought (12)                         ││
│  │    ├── 2026-06-23 (3)                    ││
│  │    │   ├── 💎 上午 9-11 点是深度工作黄金时段   ││
│  │    │   ├── 💎 番茄钟 25+5 比 50+10 更可持续   ││
│  │    │   └── 💎 ...                         ││
│  │    ├── 2026-06-22 (2)                    ││
│  │    └── 2026-06-21 (7)                    ││
│  │  📌 lesson (5)                           ││
│  │    └── ...                               ││
│  │  📌 decision (3)                         ││
│  │    └── ...                               ││
│  └──────────────────────────────────────────┘│
│                                              │
│  [Fab: + 快速捕捉]                            │
└──────────────────────────────────────────────┘
```

### 8.2 EventTreeView（树状组件）

三层结构：
1. **类型节点**（展开/折叠）→ 图标 + 类型名 + 计数
2. **日期节点**（展开/折叠）→ 日期 + 当天计数
3. **事件卡片**（点击展开详情）→ 标题（rawContent 前 60 字）+ 情绪 emoji + 标签 chip

### 8.3 CaptureDialog（捕捉弹窗）

```
┌─────────────────────────────────────┐
│  捕捉到 Palace                  [×] │
│─────────────────────────────────────│
│  类型: [thought ▼]                  │
│                                     │
│  ┌─────────────────────────────────┐│
│  │                                 ││
│  │  (输入你想记住的内容...)         ││
│  │                                 ││
│  │                                 ││
│  └─────────────────────────────────┘│
│                                     │
│  情绪: 😄 😐 😟 😡 (可选)           │
│                                     │
│  标签: [深度工作 ×] [效率 ×] [+ 添加]│
│                                     │
│  来源: Agent 对话                   │
│  情境: 讨论工作习惯                 │
│                                     │
│  ┌─────────────────────────────────┐│
│  │         💎 存入宫殿              ││
│  └─────────────────────────────────┘│
└─────────────────────────────────────┘
```

---

## 九、任务执行顺序

| # | 任务 | 依赖 | 文件 |
|---|------|------|------|
| 1 | 创建目录结构 + `PalacePaths` + `.gitignore` | 无 | `palace_paths.dart` |
| 2 | 数据模型：`ConsciousnessEvent` + 序列化 | 1 | `consciousness_event.dart` |
| 3 | 数据模型：`ContextSnapshot` | 1 | `context_snapshot.dart` |
| 4 | 数据模型：`StructuredLesson` + 相关类 | 1 | `structured_lesson.dart` |
| 5 | 数据模型：`EchoSchedule`（骨架） | 1 | `echo_schedule.dart` |
| 6 | `EventStore` + 三重索引 | 2 | `event_store.dart` |
| 7 | `ContextCapturer` | 3 | `context_capturer.dart` |
| 8 | `LessonExtractor` | 4 | `lesson_extractor.dart` |
| 9 | `QuestionGenerator` | 4 | `question_generator.dart` |
| 10 | `AutoTagger` | 2 | `auto_tagger.dart` |
| 11 | `QuickCaptureService` | 6, 7, 8, 9, 10 | `quick_capture_service.dart` |
| 12 | `CaptureToPalaceTool` | 11 | `capture_to_palace_tool.dart` |
| 13 | 库入口 `palace.dart` | 2-12 | `palace.dart` |
| 14 | Provider：`palaceEventStoreProvider` | 6 | `palace_event_store_provider.dart` |
| 15 | Provider：`palaceFilterProvider` | 无 | `palace_filter_provider.dart` |
| 16 | Provider：`palaceEventsProvider` | 14, 15 | `palace_events_provider.dart` |
| 17 | Provider：`palaceCaptureProvider` | 11, 14 | `palace_capture_provider.dart` |
| 18 | Provider：`palaceLessonsProvider` | 4 | `palace_lessons_provider.dart` |
| 19 | Provider：`palaceTagsProvider` | 14 | `palace_tags_provider.dart` |
| 20 | Feature 库入口 | 14-19 | `palace_feature.dart` |
| 21 | Widget：`EmotionSelector` | 无 | `emotion_selector.dart` |
| 22 | Widget：`TagChipBar` | 19 | `tag_chip_bar.dart` |
| 23 | Widget：`TypeFilterBar` | 15 | `type_filter_bar.dart` |
| 24 | Widget：`EventCard` | 2 | `event_card.dart` |
| 25 | Widget：`EventDetailPanel` | 2, 4 | `event_detail_panel.dart` |
| 26 | Widget：`EventTreeView` | 24, 25 | `event_tree_view.dart` |
| 27 | Dialog：`CaptureDialog` | 17, 21, 22 | `capture_dialog.dart` |
| 28 | Screen：`PalaceScreen` | 26, 23, 22, 27 | `palace_screen.dart` |
| 29 | 注册路由（`app.dart`） | 28 | `app.dart` |
| 30 | 注册侧栏导航（`sidebar.dart`） | 28 | `sidebar.dart` |
| 31 | 注册 Agent 工具（`agent_provider.dart`） | 12 | `agent_provider.dart` |
| 32 | 全量测试：`flutter test` | 1-31 | 全部测试文件 |
| 33 | 构建验证：`flutter build windows` | 32 | — |

---

## 十、自检清单（提交 PR 前逐项检查）

- [ ] `git diff main -- lib/core/agent/` 返回空（Agent 运行时零修改）
- [ ] `git diff main -- lib/features/` 仅含 `lib/features/palace/` 新增 + `agent_provider.dart` 的 3 行追加
- [ ] `git diff main -- lib/app.dart` 仅含 `/palace` 路由追加
- [ ] `git diff main -- lib/main.dart` 返回空
- [ ] `git diff main -- lib/widgets/sidebar.dart` 仅含 4 个 Palace 导航项追加
- [ ] `.gitignore` 已追加 `.greenix/palace/`
- [ ] 所有网络请求通过 `dioClientProvider`（Palace 的 DeepSeek 调用复用 `DeepSeekProvider`）
- [ ] 日志使用 `Log()`，没有 `print()` / `debugPrint()`
- [ ] Service 返回 `Result<T>`，不抛异常
- [ ] 所有 `AppError` 包含 `userMessage` + `recoveryHint`
- [ ] 新增 Agent 工具 `capture_to_palace` 通过 `ZjuDataSource` 模式注入依赖
- [ ] 所有新代码在 `lib/core/palace/` 或 `lib/features/palace/` 中
- [ ] 测试覆盖：模型序列化、EventStore CRUD、CaptureDialog UI
- [ ] `flutter test` 全量通过
- [ ] Android 平台兼容处理（Palace 功能在移动端可打开，依赖 Python 的部分不做）
