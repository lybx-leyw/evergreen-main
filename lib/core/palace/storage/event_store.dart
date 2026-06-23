/// Palace 事件存储——文件系统 CRUD + 三重索引。
///
/// 每个事件存储为一个独立的 Markdown 文件（YAML frontmatter + body），
/// 按年月分目录。三重索引为：
///   - `EVENTS_BY_DATE.md` — 按日期倒序
///   - `EVENTS_BY_TYPE.md` — 按类型分组
///   - `EVENTS_BY_TAG.md`  — 按标签分组
///
/// 索引在每次写操作（save/delete）后自动重建。搜索走关键词匹配。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/consciousness_event.dart';

/// 事件索引条目——存在内存中，用于快速查找而无需扫描全部文件。
class _EventIndexEntry {
  final String id;
  final EventType type;
  final DateTime capturedAt;
  final String title;
  final List<String> tagIds;

  const _EventIndexEntry({
    required this.id,
    required this.type,
    required this.capturedAt,
    required this.title,
    required this.tagIds,
  });
}

/// 事件文件存储 + 三重索引。
class EventStore {
  final String _eventsDir;

  /// 索引文件路径（存储在同目录下）。
  String get _dateIndexPath => p.join(_eventsDir, 'EVENTS_BY_DATE.md');
  String get _typeIndexPath => p.join(_eventsDir, 'EVENTS_BY_TYPE.md');
  String get _tagIndexPath => p.join(_eventsDir, 'EVENTS_BY_TAG.md');

  /// 内存索引（启动时加载索引文件 → 重建，写操作时增量更新）。
  final Map<String, _EventIndexEntry> _index = {};

  EventStore(this._eventsDir) {
    _ensureDir();
    _loadIndexes();
  }

  // ── 公开 CRUD ──────────────────────────────────────────────

  /// 保存一条事件——写入文件 + 重建索引。
  Future<void> save(ConsciousnessEvent event) async {
    final filePath = _eventFilePath(event.id, event.capturedAt);
    // 确保年月目录存在
    final dir = p.dirname(filePath);
    Directory(dir).createSync(recursive: true);

    final file = File(filePath);
    await file.writeAsString(event.toFileContent());

    // 更新内存索引
    _index[event.id] = _EventIndexEntry(
      id: event.id,
      type: event.type,
      capturedAt: event.capturedAt,
      title: event.title,
      tagIds: event.tagIds,
    );

    // 重建磁盘索引
    _rebuildIndexes();
  }

  /// 按 ID 获取事件（读文件 → 解析）。
  ConsciousnessEvent? get(String id) {
    final entry = _index[id];
    if (entry == null) return null;

    // 从索引找文件路径
    final filePath = _eventFilePath(id, entry.capturedAt);
    final file = File(filePath);
    if (!file.existsSync()) return null;

    try {
      final content = file.readAsStringSync();
      return ConsciousnessEvent.fromFileContent(content);
    } catch (_) {
      return null;
    }
  }

  /// 列出所有事件（按捕获时间倒序）。
  List<ConsciousnessEvent> all({int? limit, int offset = 0}) {
    final sorted = _index.values.toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    var ids = sorted.map((e) => e.id).toList();
    if (offset > 0) ids = ids.skip(offset).toList();
    if (limit != null) ids = ids.take(limit).toList();
    return ids.map((id) => get(id)).whereType<ConsciousnessEvent>().toList();
  }

  /// 删除事件——删除文件 + 重建索引。
  Future<void> delete(String id) async {
    final entry = _index[id];
    if (entry == null) return;

    final filePath = _eventFilePath(id, entry.capturedAt);
    final file = File(filePath);
    if (file.existsSync()) await file.delete();

    _index.remove(id);
    _rebuildIndexes();
  }

  /// 更新事件——覆盖写入文件 + 重建索引。
  Future<void> update(ConsciousnessEvent event) async {
    // 删除旧文件（如果捕获时间变了，路径也变了）
    final oldEntry = _index[event.id];
    if (oldEntry != null) {
      final oldPath = _eventFilePath(event.id, oldEntry.capturedAt);
      final oldFile = File(oldPath);
      if (oldFile.existsSync()) await oldFile.delete();
    }
    await save(event);
  }

  /// 事件总数。
  int get count => _index.length;

  // ── 查询方法 ───────────────────────────────────────────────

  /// 按类型筛选（返回事件 ID 列表，按时间倒序）。
  List<String> listByType(EventType type) {
    return _index.values
        .where((e) => e.type == type)
        .map((e) => e.id)
        .toList()
      ..sort((a, b) {
        final ea = _index[a]!;
        final eb = _index[b]!;
        return eb.capturedAt.compareTo(ea.capturedAt);
      });
  }

  /// 按标签筛选（返回事件 ID 列表，按时间倒序）。
  List<String> listByTag(String tag) {
    return _index.values
        .where((e) => e.tagIds.contains(tag))
        .map((e) => e.id)
        .toList()
      ..sort((a, b) {
        final ea = _index[a]!;
        final eb = _index[b]!;
        return eb.capturedAt.compareTo(ea.capturedAt);
      });
  }

  /// 按日期范围筛选（返回事件 ID 列表，按时间倒序）。
  List<String> listByDateRange(DateTime from, DateTime to) {
    return _index.values
        .where((e) =>
            e.capturedAt.isAfter(from) && e.capturedAt.isBefore(to))
        .map((e) => e.id)
        .toList()
      ..sort((a, b) {
        final ea = _index[a]!;
        final eb = _index[b]!;
        return eb.capturedAt.compareTo(ea.capturedAt);
      });
  }

  /// 关键词搜索（匹配 title + rawContent）。
  List<String> search(String query) {
    final q = query.toLowerCase();
    final results = <String>[];
    for (final entry in _index.values) {
      if (entry.title.toLowerCase().contains(q)) {
        results.add(entry.id);
        continue;
      }
      // 如果标题没命中，读文件检查正文（成本较高，仅搜索时）
      final event = get(entry.id);
      if (event != null && event.rawContent.toLowerCase().contains(q)) {
        results.add(entry.id);
      }
    }
    return results;
  }

  /// 获取所有标签（去重、排序）。
  List<String> allTags() {
    final tags = <String>{};
    for (final entry in _index.values) {
      tags.addAll(entry.tagIds);
    }
    final sorted = tags.toList()..sort();
    return sorted;
  }

  // ── 索引持久化 ─────────────────────────────────────────────

  /// 从磁盘索引文件加载到内存。如果索引损坏或缺失，回退到扫描事件文件。
  void _loadIndexes() {
    _index.clear();
    // 优先从日期索引加载（格式最完整）
    final dateIndex = File(_dateIndexPath);
    if (dateIndex.existsSync()) {
      try {
        final lines = dateIndex.readAsLinesSync();
        for (final line in lines) {
          // 格式：- YYYY-MM-DD | event_type | <id> | <标题前 60 字>
          if (!line.startsWith('- ')) continue;
          final parts = line.substring(2).split(' | ');
          if (parts.length < 3) continue;
          // 剥离 📌 等标记符号（今天的事件带此标记）
          final dateStr = parts[0].trim().replaceAll(RegExp(r'[📌]'), '').trim();
          final date = DateTime.tryParse(dateStr);
          final type = _parseType(parts[1].trim());
          final id = parts[2].trim();
          if (date == null || id.isEmpty) continue;

          _index[id] = _EventIndexEntry(
            id: id,
            type: type,
            capturedAt: date,
            title: parts.length >= 4 ? parts[3].trim() : '',
            tagIds: [],
          );
        }
        // 补全标签
        _loadTagIndexes();
        return;
      } catch (_) {
        // 索引损坏 → 回退到扫描文件
        _index.clear();
      }
    }

    // 索引缺失或损坏 → 扫描事件文件目录重建
    _scanEventsDir();
    _rebuildIndexes();
  }

  /// 扫描 events 目录下所有 .md 文件，从文件 frontmatter 重建索引。
  void _scanEventsDir() {
    final eventsRoot = Directory(_eventsDir);
    if (!eventsRoot.existsSync()) return;

    try {
      final entries = eventsRoot.listSync(recursive: true);
      for (final entity in entries) {
        if (entity is! File || !entity.path.endsWith('.md')) continue;
        // 跳过索引文件自身
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('EVENTS_BY_')) continue;

        try {
          final content = entity.readAsStringSync();
          final event = ConsciousnessEvent.fromFileContent(content);
          _index[event.id] = _EventIndexEntry(
            id: event.id,
            type: event.type,
            capturedAt: event.capturedAt,
            title: event.title,
            tagIds: event.tagIds,
          );
        } catch (_) {
          // 跳过损坏的事件文件
        }
      }
    } catch (_) {
      // 扫描失败不阻塞启动
    }
  }

  void _loadTagIndexes() {
    final tagIndex = File(_tagIndexPath);
    if (!tagIndex.existsSync()) return;

    try {
      final lines = tagIndex.readAsLinesSync();
      String? currentTag;
      for (final line in lines) {
        if (line.startsWith('## ')) {
          currentTag = line.substring(3).trim();
          continue;
        }
        if (line.startsWith('- ') && currentTag != null) {
          // 格式：- YYYY-MM-DD | <id> | <标题>
          final parts = line.substring(2).split(' | ');
          if (parts.length >= 2) {
            final id = parts[1].trim();
            if (_index.containsKey(id)) {
              _index[id]!.tagIds.add(currentTag);
            }
          }
        }
      }
    } catch (_) {
      // ignore — 标签加载失败不影响核心功能
    }
  }

  /// 重建三个磁盘索引文件。
  void _rebuildIndexes() {
    _writeDateIndex();
    _writeTypeIndex();
    _writeTagIndex();
  }

  void _writeDateIndex() {
    final file = File(_dateIndexPath);
    final buf = StringBuffer();
    buf.writeln('# Palace 事件索引 — 按日期');
    buf.writeln();
    final sorted = _index.values.toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    final now = DateTime.now();
    for (final entry in sorted) {
      final date = entry.capturedAt;
      final isToday = date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
      final dateStr = isToday
          ? '${date.toIso8601String().substring(0, 10)} 📌'
          : date.toIso8601String().substring(0, 10);
      buf.writeln('- $dateStr | ${entry.type.name} | ${entry.id} | ${entry.title}');
    }
    file.writeAsStringSync(buf.toString());
  }

  void _writeTypeIndex() {
    final file = File(_typeIndexPath);
    final buf = StringBuffer();
    buf.writeln('# Palace 事件索引 — 按类型');
    buf.writeln();

    for (final type in EventType.values) {
      final entries = _index.values
          .where((e) => e.type == type)
          .toList()
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      if (entries.isEmpty) continue;

      buf.writeln('## ${type.name} (${entries.length})');
      buf.writeln();
      for (final entry in entries) {
        final dateStr = entry.capturedAt.toIso8601String().substring(0, 10);
        buf.writeln('- $dateStr | ${entry.id} | ${entry.title}');
      }
      buf.writeln();
    }
    file.writeAsStringSync(buf.toString());
  }

  void _writeTagIndex() {
    final file = File(_tagIndexPath);
    final buf = StringBuffer();
    buf.writeln('# Palace 事件索引 — 按标签');
    buf.writeln();

    final tags = allTags(); // 已排序去重
    for (final tag in tags) {
      final entries = _index.values
          .where((e) => e.tagIds.contains(tag))
          .toList()
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      if (entries.isEmpty) continue;

      buf.writeln('## $tag (${entries.length})');
      buf.writeln();
      for (final entry in entries) {
        final dateStr = entry.capturedAt.toIso8601String().substring(0, 10);
        buf.writeln('- $dateStr | ${entry.id} | ${entry.title}');
      }
      buf.writeln();
    }
    file.writeAsStringSync(buf.toString());
  }

  // ── 内部 ───────────────────────────────────────────────────

  void _ensureDir() {
    Directory(_eventsDir).createSync(recursive: true);
  }

  static EventType _parseType(String s) {
    try {
      return EventType.values.firstWhere((t) => t.name == s);
    } catch (_) {
      return EventType.thought;
    }
  }

  /// 给定事件 ID 和时间，返回事件文件路径。
  /// 格式：`{eventsDir}/{YYYY}/{MM}/{id}.md`
  String _eventFilePath(String id, DateTime capturedAt) {
    final year = capturedAt.year.toString();
    final month = capturedAt.month.toString().padLeft(2, '0');
    return p.join(_eventsDir, year, month, '$id.md');
  }
}
