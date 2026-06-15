# 06 — 记忆系统架构设计（细化版）

**层级：** 〇（设计阶段，零实现） | **估时：** 3 天（仅设计文档） | **关联 Bug：** BUG-16

---

## 1. 现状问题

### 1.1 已有但未启用

| 模块 | 位置 | 状态 |
|------|------|------|
| `Memory` — 记忆事实 | `memory/memory.dart:34` | ✅ 已实现——YAML frontmatter 文件 |
| `MemoryStore` — CRUD + MEMORY.md 索引 | `memory/memory.dart:92` | ✅ 已实现——文件 I/O 完整 |
| `MemorySet` — 会话级快照 | `memory/memory.dart:282` | ✅ 已实现——`toContextString()` |
| `Compactor` — 上下文压实 | `compact/compact.dart` | ✅ 已实现——4 级阈值自动压缩 |
| `Session` — 消息历史 | `agent/session.dart` | ✅ 已实现——JSON 可序列化 |
| Memory → LLM 管道 | `controller → agent → compose` | ⚠️ 作为裸 `String` 传递，未接 `MemorySet` |

### 1.2 缺失的架构层

| 缺失 | 后果 |
|------|------|
| **无 Scope** | conversation/feature/global 记忆混在一起，无隔离 |
| **无 Router** | 没有根据 scope 路由到不同存储后端的机制 |
| **无 Facade** | 到处是裸 `String`，没有统一 CRUD + search 接口 |
| **无 Recall** | 记忆启动时加载一次，会话中新增的记忆不回注 |
| **无 Archival** | Compactor 压实后的摘要直接丢弃，不写入 MemoryStore |
| **无 Search** | `MemoryStore` 只有 `byType()` 过滤，没有语义/关键词搜索 |

---

## 2. 设计目标

1. **Scope 隔离**：conversation 级临时记忆 → feature 级工具上下文 → global 级持久偏好，三层清晰分离
2. **统一接口**：`MemoryFacade` 对外暴露 `remember/recall/search/forget`，所有消费者通过一个入口操作记忆
3. **自动回注**：新记忆写入后自动更新 system prompt，无需手动调用 `setMemoryContext()`
4. **压实归档**：`Compactor` 压实会话时，摘要自动写入 conversation-scope MemoryStore
5. **渐进实现**：设计文档产出后，可在阶段四 Agent 实现中逐步编码

---

## 3. 核心类型设计

### 3.1 `MemoryScope` — 记忆作用域

```dart
// lib/core/agent/memory/scope.dart

/// 记忆的作用域——决定存储位置和生命周期。
enum MemoryScope {
  /// 单次对话（Agent 请求-响应循环内）。
  /// 生命周期：会话结束即丢弃。
  /// 存储：内存（Drift in-memory 或 Map）。
  conversation,

  /// 功能级（如"成绩追踪"、"课表查询"的上下文偏好）。
  /// 生命周期：App 运行期间持久。
  /// 存储：Drift SQLite。
  feature,

  /// 全局偏好（用户身份、工作风格、长期知识）。
  /// 生命周期：永久。
  /// 存储：文件系统（Markdown 文件 + MEMORY.md 索引）。
  global,
}
```

### 3.2 `MemoryRouter` — 按 Scope 路由

```dart
// lib/core/agent/memory/router.dart

/// 根据 [MemoryScope] 路由到对应的 MemoryStore 后端。
///
/// 三个后端：
/// │ Scope          │ 后端              │ 存储位置                │
/// │ conversation   │ InMemoryStore     │ Map<String, Memory>     │
/// │ feature        │ DriftMemoryStore  │ SQLite (drift)          │
/// │ global         │ FileMemoryStore   │ Markdown 文件 + MEMORY.md │
///
/// [MemoryRouter] 本身是无状态的——它只负责根据 scope 选择 store。
class MemoryRouter {
  final InMemoryStore _conversation;
  final DriftMemoryStore _feature;
  final FileMemoryStore _global;

  MemoryRouter({
    required InMemoryStore conversation,
    required DriftMemoryStore feature,
    required FileMemoryStore global,
  });

  /// 根据 scope 返回对应的 store。
  MemoryStore backend(MemoryScope scope) => switch (scope) {
    MemoryScope.conversation => _conversation,
    MemoryScope.feature => _feature,
    MemoryScope.global => _global,
  };
}

/// MemoryStore 统一接口——所有后端实现此接口。
abstract class MemoryStore {
  Future<void> save(Memory memory);
  Future<Memory?> get(String name);
  Future<List<Memory>> all();
  Future<List<Memory>> search(String query);
  Future<void> delete(String name);
  Future<String> buildContextString(); // ← 注入 system prompt
}
```

### 3.3 `MemoryFacade` — 统一门面

```dart
// lib/core/agent/memory/facade.dart

/// 记忆系统统一入口。
///
/// 所有记忆操作通过此 Facade 进行——消费者不需要知道
/// 记忆存储在哪个后端、如何序列化、如何注入 system prompt。
///
/// ```dart
/// // 记住一个事实（全局偏好）
/// await facade.remember(
///   MemoryScope.global,
///   Memory(
///     name: 'prefer-chinese',
///     title: '用中文回答',
///     type: MemoryType.user,
///     body: '用户偏好使用简体中文回答，避免中英混用。',
///     priority: 'high',
///   ),
/// );
///
/// // 搜索功能级记忆
/// final results = await facade.search(MemoryScope.feature, '成绩 GPA');
///
/// // 获取 system prompt 注入块（所有 scope 合并）
/// final context = await facade.buildContext();
/// controller.setMemoryContext(context);
/// ```
class MemoryFacade {
  final MemoryRouter _router;

  MemoryFacade(this._router);

  /// 写入记忆。
  Future<void> remember(MemoryScope scope, Memory memory) async {
    await _router.backend(scope).save(memory);
  }

  /// 召回单条记忆。
  Future<Memory?> recall(MemoryScope scope, String name) async {
    return _router.backend(scope).get(name);
  }

  /// 搜索记忆（关键词匹配 title + body）。
  Future<List<Memory>> search(MemoryScope scope, String query) async {
    return _router.backend(scope).search(query);
  }

  /// 删除记忆。
  Future<void> forget(MemoryScope scope, String name) async {
    await _router.backend(scope).delete(name);
  }

  /// 构建 system prompt 注入块——合并三个 scope 的记忆。
  ///
  /// 格式：
  /// ```
  /// ## 对话上下文 (Conversation Memory)
  /// — 本次对话的临时事实
  ///
  /// ## 功能记忆 (Feature Memory)
  /// — App 运行期间持久的功能级偏好
  ///
  /// ## 项目记忆 (Global Memory)
  /// — 永久存储的用户偏好和项目知识
  /// ```
  Future<String> buildContext() async {
    final buf = StringBuffer();
    for (final scope in MemoryScope.values) {
      final ctx = await _router.backend(scope).buildContextString();
      if (ctx.isNotEmpty) {
        final label = switch (scope) {
          MemoryScope.conversation => '对话上下文 (Conversation Memory)',
          MemoryScope.feature => '功能记忆 (Feature Memory)',
          MemoryScope.global => '项目记忆 (Global Memory)',
        };
        buf.writeln('## $label');
        buf.writeln(ctx);
        buf.writeln();
      }
    }
    return buf.toString();
  }
}
```

### 3.4 与现有 `Memory` 类的兼容

现有的 [`Memory`](lib/core/agent/memory/memory.dart:34) 和 [`MemoryType`](lib/core/agent/memory/memory.dart:10) 类**保持不变**。Facade 层是对现有 `Memory` 模型的包装——不引入新的记忆数据结构。

`InMemoryStore` 和 `FileMemoryStore` 可直接复用现有 `MemoryStore` 的文件 I/O 逻辑。`DriftMemoryStore` 为新实现。

---

## 4. Agent 集成设计

### 4.1 `compose.dart` 改造

**现状（裸 String）：**
```dart
// compose.dart:32-34
if (memoryContext.isNotEmpty) {
  systemBuf.writeln('\n\n## 上下文记忆');
  systemBuf.writeln(memoryContext);
}
```

**改造后（MemoryFacade 注入）：**
```dart
// compose.dart 新签名
Future<List<Message>> compose({
  required ModelProvider provider,
  required Registry registry,
  required Session session,
  required MemoryFacade memory,       // ← 替换裸 String
  required bool deepThinking,
  required bool webSearchEnabled,
});

// compose.dart 新实现
final context = await memory.buildContext();
if (context.isNotEmpty) {
  systemBuf.writeln(context); // 已含 scope 标签
}
```

### 4.2 Controller 改造

**现状：**
```dart
String _memoryContext = '';
void setMemoryContext(String context) => _memoryContext = context;
```

**改造后：**
```dart
final MemoryFacade _memory;
// 不再需要 setMemoryContext()——构建时自动读取最新记忆
```

### 4.3 Compactor → MemoryStore 归档

**现状：** Compactor 压实后只在 `session.messages` 中替换，摘要丢弃。

**改造后：** 压实完成后，摘要自动写入 `conversation` Scope 的 MemoryStore：

```dart
// compact.dart 新增
Future<void> _archiveCompaction(String summary) async {
  await _memory.remember(
    MemoryScope.conversation,
    Memory(
      name: 'compaction-${DateTime.now().millisecondsSinceEpoch}',
      title: '上下文压实摘要',
      type: MemoryType.reference,
      body: summary,
      priority: 'medium',
    ),
  );
}
```

---

## 5. `MemoryIndex` — Conversation 级轻量索引

```
┌─────────────────────────────────────────────────┐
│ Conversation Memory Index (Drift in-memory)     │
│                                                 │
│ id │ name            │ type    │ tokens │ ts    │
│  1 │ user-pref-lang  │ user    │     45 │ 10:01 │
│  2 │ compact-001     │ refer.  │    312 │ 10:15 │
│  3 │ feedback-style  │ feedback│     67 │ 10:22 │
│                                                 │
│ Search: "偏好" → hits #1                        │
│ Search: "风格" → hits #3                        │
└─────────────────────────────────────────────────┘
```

**设计要点：**
- Conversation 级索引仅存于内存中（不写盘）
- 全文搜索使用 `body.contains(query)`（简单但有效）
- Feature 和 Global 索引复用 `MEMORY.md` 文件（已有实现）
- 索引不包含完整 body——通过 `name` 去 `MemoryStore.get(name)` 懒加载

---

## 6. 数据流图

```
┌──────────────┐    remember/recall    ┌──────────────┐
│   Agent      │ ───────────────────→ │ MemoryFacade │
│  (tool call) │ ←─────────────────── │              │
└──────────────┘    search/forget     └──────┬───────┘
                                             │
                                    ┌────────▼────────┐
                                    │  MemoryRouter   │
                                    │                 │
                                    │ scope=?         │
                                    └──┬──────┬──────┘
                                       │      │      │
                              conv.    │ feat.│      │ global
                                       │      │      │
                              ┌────────▼┐ ┌───▼───┐ ┌▼──────────┐
                              │InMemory │ │Drift  │ │File Store │
                              │ Store   │ │Store  │ │(.md+MEMO) │
                              └────────┘ └───────┘ └───────────┘

┌──────────────┐    buildContext()    ┌──────────────┐
│  Controller  │ ←────────────────── │ MemoryFacade │
│              │   (合并 3 scope)      │              │
└──────┬───────┘                      └──────────────┘
       │ setMemoryContext(ctx)
       ▼
┌──────────────┐
│  compose()   │ → system prompt
└──────────────┘
```

---

## 7. 迁移方案

### 7.1 阶段映射

| 阶段 | 内容 | 依赖 |
|------|------|------|
| **当前（设计）** | 产出本文档 | 无 |
| **阶段四-A** | `MemoryStore` 接口 + `InMemoryStore` | 本文档 |
| **阶段四-B** | `DriftMemoryStore`（SQLite 后端） | Drift 集成 |
| **阶段四-C** | `MemoryRouter` + `MemoryFacade` | A + B |
| **阶段四-D** | Compactor 归档改造 | C |
| **阶段四-E** | `compose.dart` / Controller 改造 | C |
| **阶段四-F** | Agent 工具接入（remember/recall/search/forget tools） | C |

### 7.2 向后兼容

- 现有 `MemoryType`、`Memory`、`MemoryStore`、`MemorySet` 类**不删除**
- `FileMemoryStore` 就是对 `MemoryStore` 的适配包装
- 旧 `setMemoryContext(String)` 保留为 `@Deprecated`，内部委托给 `MemoryFacade.buildContext()`

---

## 8. 验收标准

- [ ] `MemoryScope` 三枚举值定义明确，各有用例说明
- [ ] `MemoryRouter` 接口定义了三个后端的路由逻辑
- [ ] `MemoryFacade` 四个方法签名完整（remember/recall/search/forget）
- [ ] `MemoryStore` 抽象接口包含 `buildContextString()` 方法
- [ ] `compose.dart` 改造方案明确了签名变更
- [ ] Compactor 归档流程有伪代码描述
- [ ] 数据流图覆盖从 Agent Tool → Facade → Router → Store → Context 的完整链路
- [ ] 迁移方案有清晰的分阶段步骤
- [ ] 设计文档可作为阶段四直接实现参考

---

## 9. 风险

| 风险 | 缓解 |
|------|------|
| `DriftMemoryStore` 引入新依赖，增加编译时间 | Drift 已被项目使用（`WebCacheDatabase`），无额外依赖 |
| 记忆膨胀——conversation scope 记忆过多导致 system prompt 超长 | 继承 `Compactor` 的 token 估算逻辑，context 超限时触发 conversation 记忆压缩 |
| `FileMemoryStore` 的 `.md` 文件与用户手动编辑冲突 | `MEMORY.md` 文件顶部加注释 `<!-- 此文件由 MemoryFacade 自动管理，手动编辑请在下方分隔线之后 -->` |
| InMemoryStore 重启丢失 | 设计中已明确 conversation scope 的生命周期就是"会话结束即丢弃" |
