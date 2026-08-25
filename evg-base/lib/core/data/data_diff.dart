/// 数据差异引擎 —— 后台循环刷新覆写缓存时计算「变化摘要」，驱动变更通知。
///
/// 纯 Dart，无 Flutter 依赖，可在 data 子包独立 `dart test`。
/// 与缓存优先策略配合：只对「成功拉取的非空新数据」与「被覆写的旧缓存」
/// 做对比，输出用户可读的中文变更摘要（新增/移除/更新条目数 + 示例）。
library;

import 'dart:convert';

/// 易变字段黑名单：比较时忽略（时间戳类字段每次刷新都会变，会造成假变更）。
///
/// 递归生效：Map 任意层级的这些 key 均跳过；列表元素做身份比较前也会先
/// 剥除这些字段，避免「同一元素因时间戳不同被判为新增+移除」。
const Set<String> kVolatileDiffKeys = {
  'ts',
  'timestamp',
  'updatedAt',
  'updated_at',
  'lastFetchedAt',
  'cachedAt',
  'fetchedAt',
  'fetched_at',
  'at',
  'time',
  'refreshAt',
};

/// 结构差异摘要（与具体数据源解耦，纯数据模型）。
class DataDiff {
  const DataDiff({
    required this.added,
    required this.removed,
    required this.changed,
    required this.addedItems,
    required this.removedItems,
    required this.changedItems,
  });

  /// 新增条目数（Map 新增 key / List 新增元素）。
  final int added;

  /// 移除条目数。
  final int removed;

  /// 值变化条目数（标量变化、嵌套结构变化）。
  final int changed;

  /// 新增条目示例（最多 [kMaxDiffDetailItems] 条）。
  final List<String> addedItems;

  /// 移除条目示例。
  final List<String> removedItems;

  /// 变化条目示例（`key: 旧 → 新`）。
  final List<String> changedItems;

  /// 是否有实质变化（忽略易变字段后）。
  bool get hasChanges => added + removed + changed > 0;

  /// 序列化为 JSON（供 SSE 变更事件帧 / 跨进程传输）。
  Map<String, dynamic> toJson() => {
        'added': added,
        'removed': removed,
        'changed': changed,
        'addedItems': addedItems,
        'removedItems': removedItems,
        'changedItems': changedItems,
      };

  static const kMaxDiffDetailItems = 5;

  /// 人类可读摘要，如「新增 2 项、移除 1 项 · 线性代数；高等数学」。
  String summarize({int maxExamples = 3}) {
    if (!hasChanges) return '无变化';
    final parts = <String>[];
    if (added > 0) parts.add('新增 $added 项');
    if (removed > 0) parts.add('移除 $removed 项');
    if (changed > 0) parts.add('更新 $changed 项');
    final examples = <String>[
      ...addedItems.take(maxExamples),
      ...removedItems.take(maxExamples),
      ...changedItems.take(maxExamples),
    ];
    final head = parts.join('、');
    if (examples.isEmpty) return head;
    return '$head · ${examples.join('；')}';
  }
}

/// 数据变更事件（后台循环刷新成功覆写缓存且内容变化时由 Orchestrator 发出）。
class DataChangeEvent {
  const DataChangeEvent({
    required this.sourceName,
    required this.displayName,
    required this.diff,
    required this.at,
  });

  /// 数据源 name（如 `zju_scores`）。
  final String sourceName;

  /// 数据源展示名（如 `成绩单`）。
  final String displayName;

  final DataDiff diff;

  final DateTime at;

  /// 序列化为 JSON（供 SSE 变更事件帧 / 跨进程传输）。
  Map<String, dynamic> toJson() => {
        'sourceName': sourceName,
        'displayName': displayName,
        'diff': diff.toJson(),
        'at': at.toIso8601String(),
      };
}

/// 计算 before → after 的结构差异。
DataDiff computeDataDiff(dynamic before, dynamic after) {
  final b = _DiffBuilder();
  final nb = _normalize(before);
  final na = _normalize(after);
  _diff(nb, na, b);
  return b.build();
}

// ═══════════════════════════════════════════════════════════════════════
// 内部实现
// ═══════════════════════════════════════════════════════════════════════

/// 递归剥除易变字段，使比较/身份判定不受时间戳等字段干扰。
dynamic _normalize(dynamic v) {
  if (v is Map) {
    final m = <String, dynamic>{};
    for (final entry in v.entries) {
      if (kVolatileDiffKeys.contains(entry.key)) continue;
      m[entry.key] = _normalize(entry.value);
    }
    return m;
  }
  if (v is List) return v.map(_normalize).toList();
  return v;
}

bool _deepEqual(dynamic a, dynamic b) => jsonEncode(a) == jsonEncode(b);

String _brief(dynamic v, [int maxLen = 24]) {
  if (v == null) return 'null';
  final s = v is String ? v : jsonEncode(v);
  return s.length > maxLen ? '${s.substring(0, maxLen - 1)}…' : s;
}

void _diff(dynamic before, dynamic after, _DiffBuilder b) {
  if (identical(before, after) || _deepEqual(before, after)) return;
  if (before is Map && after is Map) return _diffMap(before, after, b);
  if (before is List && after is List) return _diffList(before, after, b);
  b.changed(1, '${_brief(before)} → ${_brief(after)}');
}

void _diffMap(Map before, Map after, _DiffBuilder b) {
  final keys = <String>{...before.keys.cast<String>(), ...after.keys.cast<String>()};
  for (final k in keys) {
    final hasBefore = before.containsKey(k);
    final hasAfter = after.containsKey(k);
    if (hasBefore && !hasAfter) {
      b.removed(1, k);
      continue;
    }
    if (!hasBefore && hasAfter) {
      b.added(1, k);
      continue;
    }
    final bv = before[k];
    final av = after[k];
    if (_deepEqual(bv, av)) continue;
    if (bv is Map && av is Map) {
      _diffMap(bv, av, b);
      continue;
    }
    if (bv is List && av is List) {
      _diffList(bv, av, b);
      continue;
    }
    b.changed(1, '$k: ${_brief(bv)} → ${_brief(av)}');
  }
}

void _diffList(List before, List after, _DiffBuilder b) {
  final bSet = {for (final e in before) jsonEncode(e)};
  final aSet = {for (final e in after) jsonEncode(e)};
  for (final e in after) {
    if (!bSet.contains(jsonEncode(e))) b.added(1, _elementLabel(e));
  }
  for (final e in before) {
    if (!aSet.contains(jsonEncode(e))) b.removed(1, _elementLabel(e));
  }
}

/// 列表元素展示标签：Map 优先取常见标题字段（课程名/标题/名称/id），
/// 否则退化为截断 JSON。
String _elementLabel(dynamic e) {
  if (e is Map) {
    for (final k in const ['name', 'title', 'kcmc', 'courseName', 'id']) {
      final v = e[k];
      if (v is String && v.isNotEmpty && v.length <= 24) return v;
    }
  }
  return _brief(e, 16);
}

class _DiffBuilder {
  int _added = 0;
  int _removed = 0;
  int _changed = 0;
  final List<String> _addedItems = [];
  final List<String> _removedItems = [];
  final List<String> _changedItems = [];

  void added(int count, String label) {
    _added += count;
    if (_addedItems.length < DataDiff.kMaxDiffDetailItems) {
      _addedItems.add(label);
    }
  }

  void removed(int count, String label) {
    _removed += count;
    if (_removedItems.length < DataDiff.kMaxDiffDetailItems) {
      _removedItems.add(label);
    }
  }

  void changed(int count, String label) {
    _changed += count;
    if (_changedItems.length < DataDiff.kMaxDiffDetailItems) {
      _changedItems.add(label);
    }
  }

  DataDiff build() => DataDiff(
        added: _added,
        removed: _removed,
        changed: _changed,
        addedItems: List.unmodifiable(_addedItems),
        removedItems: List.unmodifiable(_removedItems),
        changedItems: List.unmodifiable(_changedItems),
      );
}
