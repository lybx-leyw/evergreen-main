/// Session 对话会话 — 对应 reasonix/internal/agent/session.go。
///
/// # 会话树（Task 三 R3 会话树形分支）
///
/// 对话不再是「一条直线」而是「一棵树」：任一轮对话都可以长出多个后续走向
/// （分支），用户可随时回到某个分叉点左右切换查看不同分支。
///
/// 数据结构：Session 级新增 [Round] 树（轮次 = 树节点）。
/// - 轮次边界 = 平铺 messages 中的 user 消息（一条 user 消息及其后的
///   assistant/tool 消息 = 一轮）；`loopId` = 树深（0-based，可由结构推导，
///   不引入独立计数器）。
/// - `children` 有序 = 孩子兄弟链：`children[i]` 的 nextSibling 即 `children[i+1]`，
///   switch（分支切换）即下标 i±1。
/// - Session 保留平铺 `messages` 作为**活动路径**双写（序列化主字段不变 →
///   旧版读入零变化；compose/compact/merge 仍只读活动路径）；新增 `tree`
///   字段（可选）为树权威，`messages` 由树派生。
/// - 序列化：`Message.toJson` 冻结不动（`session_merge._sameMessage` 用
///   `jsonEncode(m.toJson())` 判相等，Message 加字段会破坏跨版本前缀判定）；
///   `tree` 缺失（旧数据）→ 由 messages 按 user 消息边界推导单路径树
///   （旧直线数据零行为变化；未知字段静默忽略）。
///
/// 双写一致性：所有会话变更入口（[add]/[addAll]/[forkRound]/[switchRound]/
/// [removeFrom]/[removeLastTurn]/[setSystemMessage]/[removeSystemMessage]/
/// [adoptFrom]/[clearMessages]）内建轮次感知，维护不变式
/// `messages == flatten(活动路径)`；直接改 `messages` 的调用方（如 legacy
/// forkSessionProvider、测试构造）在下次树操作时由 [_ensureTree] 懒采纳。
library;

import 'package:uuid/uuid.dart';

import '../message.dart';
import '../event.dart';

// ═══════ Round ═══════

/// 一轮对话 = 一条 user 消息 + 其 assistant/tool 消息（轮次 = 树节点）。
///
/// 兄弟分支 = 同一父轮下的多个 [children]（孩子兄弟链）；`loopId` = 树深
/// （0-based，根轮 = 0，可由结构推导）。
class Round {
  /// 轮次深度（0-based；= 树深）。
  int loopId;

  /// 本轮消息（通常以 user 消息起始，至下一轮 user 消息前）。
  final List<Message> messages = [];

  /// 下一轮的各分支（有序 = 孩子兄弟链；switch 即 i±1）。
  final List<Round> children = [];

  /// 活动子分支下标（[children] 中当前延续的分支）。
  ///
  /// 运行时导航态；序列化保留（`active_child`）以保证跨重启「切换后继续」
  /// 指向正确分支。树内不写入 updatedAt 等易变字段（合并判定稳定）。
  int activeChild = 0;

  Round({
    required this.loopId,
    List<Message>? messages,
    List<Round>? children,
    this.activeChild = 0,
  }) {
    if (messages != null) this.messages.addAll(messages);
    if (children != null) this.children.addAll(children);
  }

  /// 深拷贝（切换会话 / 序列化恢复用）。
  Round clone() => Round(
        loopId: loopId,
        messages: List.of(messages),
        children: [for (final c in children) c.clone()],
        activeChild: activeChild,
      );

  Map<String, dynamic> toJson() => {
        'loop_id': loopId,
        'messages': messages.map((m) => m.toJson()).toList(),
        if (children.isNotEmpty)
          'children': children.map((c) => c.toJson()).toList(),
        if (activeChild != 0) 'active_child': activeChild,
      };

  factory Round.fromJson(Map<String, dynamic> json) {
    final round = Round(loopId: (json['loop_id'] as num?)?.toInt() ?? 0);
    final msgs = json['messages'] as List? ?? const [];
    for (final m in msgs) {
      if (m is Map<String, dynamic>) round.messages.add(_messageFromJson(m));
    }
    final children = json['children'] as List? ?? const [];
    for (final c in children) {
      if (c is Map<String, dynamic>) round.children.add(Round.fromJson(c));
    }
    round.activeChild = (json['active_child'] as num?)?.toInt() ?? 0;
    return round;
  }

  @override
  String toString() =>
      'Round(loop=$loopId msgs=${messages.length} children=${children.length})';
}

// ═══════ Session ═══════

/// 会话状态。
class Session {
  /// 消息历史（活动路径展平，序列化主字段不变）。
  ///
  /// 树形会话下由树派生（[forkRound]/[switchRound]/轮次感知 [add] 后重建），
  /// 始终与树中活动节点一致；旧直线数据保持原语义。
  final List<Message> messages = [];

  /// 会话元数据。
  String id;
  String title;
  DateTime createdAt;
  DateTime updatedAt;

  /// 派生元数据（同步中心契约，见 docs/superpowers/specs/egsync-sync-center-spec-v1.md §七）。
  ///
  /// [parentId]：本会话派生的父会话 id；`null` = 根会话（默认）。
  /// [forkTurn]：分叉点在父会话 `messages` 中的 0-based 索引——子会话继承父消息
  /// `[0..forkTurn)` 后路径分化；`null` = 未分叉（普通续写，父消息全继承）。
  ///
  /// 约束：`forkTurn != null` 时 `parentId` 必须非空（写入方保证，读取方容忍不一致）。
  ///
  /// ⚠️ R3 起新分叉一律走树内 [forkRound]（不再写 parent_id/fork_turn）；
  /// 本字段仅保留给旧 A6 fork 数据的懒迁移读兼容。
  String? parentId;
  int? forkTurn;

  /// Token 统计（累计）。
  int totalPromptTokens = 0;
  int totalCompletionTokens = 0;
  int totalCacheHitTokens = 0;
  int totalCacheMissTokens = 0;

  /// 当前回合的 token 用量（最后一次 LLM 调用）。
  TokenUsage? lastUsage;

  /// 树根轮（深度 0 分支链；常规会话长度 1，[forkRound] 在根轮分叉后长度 > 1）。
  final List<Round> _roots = [];

  /// 活动路径（根轮 → 当前活动轮，跟随各轮 [Round.activeChild] 到叶子）。
  final List<Round> _activePath = [];

  /// 活动根轮下标（[_roots] 中当前活动的深度 0 轮）。
  int _activeRoot = 0;

  Session({
    String? id,
    this.title = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.parentId,
    this.forkTurn,
  })  : id = id ?? _generateId(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 深度 0 分支链（树根轮；只读视图）。
  List<Round> get roots => List.unmodifiable(_roots);

  /// 活动路径（根轮 → 当前活动轮；只读视图）。
  List<Round> get activePath => List.unmodifiable(_activePath);

  /// 添加一条消息到历史（轮次感知：user 消息开新轮 append 到当前轮 children；
  /// assistant/tool 消息 append 当前轮）。树与活动路径同步维护。
  void add(Message message) {
    _ensureTree();
    if (_roots.isEmpty) {
      // 首个消息：建立根轮（可能含 system 等头消息）。
      final root = Round(loopId: 0);
      _roots.add(root);
      _activePath.add(root);
      root.messages.add(message);
    } else {
      final last = _activePath.last;
      if (message.isUser && last.messages.any((m) => m.isUser)) {
        // 当前轮已有 user 消息 → 开新轮（下一层分支）。
        final child = Round(loopId: _activePath.length);
        last.children.add(child);
        last.activeChild = last.children.length - 1;
        _activePath.add(child);
        child.messages.add(message);
      } else {
        last.messages.add(message);
      }
    }
    _rebuildMessages();
    updatedAt = DateTime.now();
  }

  /// 添加多条消息（逐条走轮次感知 [add]）。
  void addAll(List<Message> msgs) {
    for (final m in msgs) {
      add(m);
    }
  }

  /// 获取最后 N 条消息。
  List<Message> last(int n) {
    if (n >= messages.length) return List.from(messages);
    return messages.sublist(messages.length - n);
  }

  /// 获取系统提示消息（第一条 role=system 的消息）。
  Message? get systemMessage {
    try {
      return messages.firstWhere((m) => m.role == Role.system);
    } catch (_) {
      return null;
    }
  }

  /// 移除第一条系统提示消息（用于替换）。树同步维护。
  void removeSystemMessage() {
    for (final r in _roots) {
      _removeSystemInRound(r);
    }
    _rebuildMessages();
    updatedAt = DateTime.now();
  }

  void _removeSystemInRound(Round round) {
    round.messages.removeWhere((m) => m.role == Role.system);
    for (final c in round.children) {
      _removeSystemInRound(c);
    }
  }

  /// 更新系统提示消息（替换已有的或追加到开头）。树同步维护。
  void setSystemMessage(String content) {
    removeSystemMessage();
    if (_roots.isEmpty) {
      final root = Round(loopId: 0);
      _roots.add(root);
      _activePath.add(root);
      root.messages.add(Message.system(content));
    } else {
      _roots.first.messages.insert(0, Message.system(content));
    }
    _rebuildMessages();
    updatedAt = DateTime.now();
  }

  /// 累计 token 用量。
  void accumulateUsage(TokenUsage usage) {
    totalPromptTokens += usage.promptTokens;
    totalCompletionTokens += usage.completionTokens;
    totalCacheHitTokens += usage.promptCacheHitTokens ?? 0;
    totalCacheMissTokens += usage.promptCacheMissTokens ?? 0;
    lastUsage = usage;
  }

  /// 缓存的命中率（累计）。
  double get cacheHitRate {
    final total = totalCacheHitTokens + totalCacheMissTokens;
    if (total == 0) return 0;
    return totalCacheHitTokens / total;
  }

  /// 总 token 数。
  int get totalTokens => totalPromptTokens + totalCompletionTokens;

  /// 消息数量。
  int get messageCount => messages.length;

  /// 估算的上下文 token 数（近似，用于压实判断）。
  int get estimatedContextTokens {
    int total = 0;
    for (final msg in messages) {
      total += msg.content.length ~/ 2; // 粗略估算：~2 chars/token for Chinese
      total += msg.reasoningContent.length ~/ 2;
      if (msg.hasToolCalls) {
        for (final tc in msg.toolCalls) {
          total += tc.name.length ~/ 2;
          total += tc.arguments.length ~/ 2;
        }
      }
    }
    return total;
  }

  /// 移除从指定索引开始的所有消息（含该索引）。
  /// 用于编辑：删除原用户消息及其后续所有 AI 回复 / 工具调用。
  ///
  /// 树形会话下按「包含该索引的轮」整轮移除（含其全部子树分支）。
  void removeFrom(int index) {
    if (index < 0 || index >= messages.length) return;
    _ensureTree();
    if (_roots.isEmpty) {
      messages.removeRange(index, messages.length);
      updatedAt = DateTime.now();
      return;
    }
    final roundIdx = _roundIndexAtMessageIndex(index);
    if (roundIdx < 0) return;
    _removeRoundAt(roundIdx);
    updatedAt = DateTime.now();
  }

  /// 移除最后一轮对话（最后一条 user 消息及其后续所有消息）。
  /// 用于重新生成：删除最后一对 user+assistant，让 AI 重新回答。
  /// 返回被移除的最后一条 user 消息内容，无 user 消息则返回 null。
  ///
  /// 树形会话下移除活动路径上最后一个「含 user 消息」的轮及其全部子树分支。
  String? removeLastTurn() {
    _ensureTree();
    if (_roots.isEmpty) {
      // 无树：退化为旧直线逻辑。
      final userIdx = messages.lastIndexWhere((m) => m.role == Role.user);
      if (userIdx < 0) return null;
      final userContent = messages[userIdx].content;
      messages.removeRange(userIdx, messages.length);
      updatedAt = DateTime.now();
      return userContent;
    }
    var idx = _activePath.length - 1;
    while (idx >= 0 && !_activePath[idx].messages.any((m) => m.isUser)) {
      idx--;
    }
    if (idx < 0) return null;
    final userMsg = _activePath[idx].messages.firstWhere((m) => m.isUser);
    final userContent = userMsg.content;
    _removeRoundAt(idx);
    updatedAt = DateTime.now();
    return userContent;
  }

  /// 树内分叉：以活动路径上 [loopId] 轮为分叉点，在同一父轮下插入一个
  /// **空** sibling 轮（无消息、无子树），并把活动路径切换到新分支。
  ///
  /// [editedUserText]：分叉后待提交的用户消息文本——由调用方在发送时经
  /// 轮次感知 [add] 写入新轮（避免与 Agent.run 的 `add(user)` 重复），
  /// 本方法不预置消息。
  ///
  /// - 同一会话，不产生新 session id，不触碰工作区；
  /// - 与旧「分支 = 独立会话」不同：父轮保持原样，旧分支内容完整保留，
  ///   可通过 [switchRound] 切回；
  /// - 返回是否成功（loopId 越界 / 树缺失返回 false）。
  bool forkRound(int loopId, String editedUserText) {
    _ensureTree();
    final path = _activePath;
    if (loopId < 0 || loopId >= path.length) return false;
    if (loopId == 0) {
      // 根轮分叉：新根轮追加到深度 0 分支链并切换。
      _roots.add(Round(loopId: 0));
      _activeRoot = _roots.length - 1;
    } else {
      final parent = path[loopId - 1];
      parent.children.add(Round(loopId: loopId));
      parent.activeChild = parent.children.length - 1;
    }
    _rebuildActivePath();
    _rebuildMessages();
    updatedAt = DateTime.now();
    return true;
  }

  /// 树内切换：把活动路径上 [loopId] 轮切换到其兄弟链中的第 [siblingIndex] 个
  /// 分支（0-based；0 = 第一个分支），重建活动路径与消息。
  ///
  /// 切换不改变会话 id、不产生新会话；返回是否成功。
  bool switchRound(int loopId, int siblingIndex) {
    _ensureTree();
    final path = _activePath;
    if (loopId < 0 || loopId >= path.length) return false;
    if (loopId == 0) {
      if (siblingIndex < 0 || siblingIndex >= _roots.length) return false;
      _activeRoot = siblingIndex;
    } else {
      final parent = path[loopId - 1];
      if (siblingIndex < 0 || siblingIndex >= parent.children.length) {
        return false;
      }
      parent.activeChild = siblingIndex;
    }
    _rebuildActivePath();
    _rebuildMessages();
    updatedAt = DateTime.now();
    return true;
  }

  /// 用 [other] 的整体状态替换本会话（切换会话用）。
  ///
  /// 拷贝 id / title / 派生元数据 / token 统计 / 树（深拷贝）并重建活动路径
  /// 与消息。createdAt / updatedAt 同步为 [other] 的值（重新保存时元数据不漂移）。
  void adoptFrom(Session other) {
    id = other.id;
    title = other.title;
    createdAt = other.createdAt;
    updatedAt = other.updatedAt;
    parentId = other.parentId;
    forkTurn = other.forkTurn;
    totalPromptTokens = other.totalPromptTokens;
    totalCompletionTokens = other.totalCompletionTokens;
    totalCacheHitTokens = other.totalCacheHitTokens;
    totalCacheMissTokens = other.totalCacheMissTokens;
    lastUsage = other.lastUsage;
    _roots
      ..clear()
      ..addAll(other._roots.map((r) => r.clone()));
    _activeRoot = other._activeRoot;
    _rebuildActivePath();
    _rebuildMessages();
  }

  /// 清空对话内容（新建会话用）：清空消息、树与活动路径。
  void clearMessages() {
    messages.clear();
    _roots.clear();
    _activePath.clear();
    _activeRoot = 0;
    updatedAt = DateTime.now();
  }

  /// 压实（compact）后重建单路径树：压实把活动路径中间段替换为摘要，
  /// 旧树结构（含侧枝）不再有意义，重建为与压实后 messages 一致的单路径树。
  void rebuildTreeFromMessages() {
    _roots.clear();
    _activePath.clear();
    _activeRoot = 0;
    _deriveTreeFromMessages();
    _rebuildActivePath();
  }

  /// 创建快照（用于序列化/持久化）。
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (parentId != null) 'parent_id': parentId,
        if (forkTurn != null) 'fork_turn': forkTurn,
        'messages': messages.map((m) => m.toJson()).toList(),
        if (_roots.isNotEmpty) 'tree': _roots.map((r) => r.toJson()).toList(),
        if (_activeRoot != 0) 'active_root': _activeRoot,
        'total_prompt_tokens': totalPromptTokens,
        'total_completion_tokens': totalCompletionTokens,
        'total_cache_hit_tokens': totalCacheHitTokens,
        'total_cache_miss_tokens': totalCacheMissTokens,
      };

  /// 从快照恢复。
  ///
  /// `tree` 缺失（旧直线数据）→ 由 `messages` 按 user 消息边界推导单路径树，
  /// 行为等同旧直线；树存在时以树权威重建活动路径与消息（双写一致性）。
  /// 未知字段静默忽略。
  factory Session.fromJson(Map<String, dynamic> json) {
    final session = Session(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      parentId: json['parent_id']?.toString(),
      forkTurn: (json['fork_turn'] as num?)?.toInt(),
    );
    final msgs = json['messages'] as List? ?? [];
    for (final m in msgs) {
      if (m is Map<String, dynamic>) {
        session.messages.add(_messageFromJson(m));
      }
    }
    final tree = json['tree'];
    if (tree is List) {
      for (final r in tree) {
        if (r is Map<String, dynamic>) {
          session._roots.add(Round.fromJson(r));
        }
      }
      session._activeRoot = (json['active_root'] as num?)?.toInt() ?? 0;
    }
    if (session._roots.isEmpty) {
      // 旧数据：由 messages 推导单路径树（缺省零行为变化）。
      session._deriveTreeFromMessages();
    }
    session._rebuildActivePath();
    if (session._roots.isNotEmpty) {
      // 树权威：以树重建 messages（与活动路径一致）。
      session._rebuildMessages();
    }
    session.totalPromptTokens = json['total_prompt_tokens'] ?? 0;
    session.totalCompletionTokens = json['total_completion_tokens'] ?? 0;
    session.totalCacheHitTokens = json['total_cache_hit_tokens'] ?? 0;
    session.totalCacheMissTokens = json['total_cache_miss_tokens'] ?? 0;
    return session;
  }

  // ═══════ 树内部 ═══════

  /// 树缺失但 messages 有内容（旧直线数据 / 直接改 messages 的调用方）时，
  /// 先由 messages 推导单路径树，保证树与消息双写一致（懒采纳）。
  void _ensureTree() {
    if (_roots.isEmpty && messages.isNotEmpty) {
      _deriveTreeFromMessages();
      _rebuildActivePath();
    }
  }

  /// 由平铺 messages 按 user 消息边界推导单路径树。
  void _deriveTreeFromMessages() {
    if (messages.isEmpty) return;
    final root = Round(loopId: 0);
    _roots.add(root);
    var current = root;
    for (final m in messages) {
      if (m.isUser && current.messages.any((x) => x.isUser)) {
        final next = Round(loopId: current.loopId + 1);
        current.children.add(next);
        current = next;
      }
      current.messages.add(m);
    }
  }

  /// 从根轮沿各轮 [Round.activeChild] 重建活动路径（到叶子）。
  void _rebuildActivePath() {
    _activePath.clear();
    if (_roots.isEmpty) return;
    final rootIdx = _activeRoot.clamp(0, _roots.length - 1);
    _activeRoot = rootIdx;
    var current = _roots[rootIdx];
    _activePath.add(current);
    while (current.children.isNotEmpty) {
      final ci = current.activeChild.clamp(0, current.children.length - 1);
      current.activeChild = ci;
      current = current.children[ci];
      _activePath.add(current);
    }
  }

  /// 以活动路径重建平铺 messages（树权威、messages 派生）。
  void _rebuildMessages() {
    messages
      ..clear()
      ..addAll(_activePath.expand((r) => r.messages));
  }

  /// 平铺 messages 中 [index] 所在轮在活动路径中的下标。
  int _roundIndexAtMessageIndex(int index) {
    var offset = 0;
    for (var i = 0; i < _activePath.length; i++) {
      final len = _activePath[i].messages.length;
      if (index < offset + len) return i;
      offset += len;
    }
    return -1;
  }

  /// 移除活动路径第 [idx] 轮及其全部子树分支，并截断活动路径。
  void _removeRoundAt(int idx) {
    if (idx == 0) {
      if (_activeRoot >= 0 && _activeRoot < _roots.length) {
        _roots.removeAt(_activeRoot);
        if (_roots.isEmpty) {
          _activeRoot = 0;
        } else {
          _activeRoot = _activeRoot.clamp(0, _roots.length - 1);
        }
      }
    } else {
      final parent = _activePath[idx - 1];
      final ci = parent.activeChild.clamp(0, parent.children.length - 1);
      parent.children.removeAt(ci);
      parent.activeChild = parent.children.isEmpty
          ? 0
          : ci.clamp(0, parent.children.length - 1);
    }
    _activePath.removeRange(idx, _activePath.length);
    _rebuildMessages();
  }

  static final _uuid = Uuid();

  static String _generateId() {
    return 'session_${_uuid.v4()}';
  }
}

// ═══════ 消息解析 ═══════

/// 从 JSON 解析单条消息（Session/Round 共用；未知字段静默忽略）。
Message _messageFromJson(Map<String, dynamic> json) {
  final role = Role.values.firstWhere(
      (r) => r.value == json['role'],
      orElse: () => Role.user);
  return Message(
    role: role,
    content: json['content']?.toString() ?? '',
    reasoningContent: json['reasoning_content']?.toString() ?? '',
    toolCalls: (json['tool_calls'] as List?)
            ?.map((tc) => ToolCall.fromJson(tc as Map<String, dynamic>))
            .toList() ??
        [],
    toolCallId: json['tool_call_id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
  );
}
