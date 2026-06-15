/// Memory 系统 — 四类记忆存储 + MEMORY.md 索引。
///
/// 对应 reasonix/internal/memory/。
/// 记忆是文件系统中的一等公民——每个事实一个文件，通过 MEMORY.md 索引加载到 system prompt 前缀中。
library;

import 'dart:io';

/// 记忆类型，对应 Go 的 memory.Type。
enum MemoryType {
  /// 用户身份：角色、偏好、专长。
  user,

  /// 反馈：工作方式指导（含 why + how-to-apply）。
  feedback,

  /// 项目：当前工作、目标、约束。
  project,

  /// 引用：外部资源指针（URL、工单）。
  reference;

  String get value => name;

  static MemoryType fromString(String s) {
    return MemoryType.values.firstWhere(
      (t) => t.value == s.toLowerCase().trim(),
      orElse: () => MemoryType.project,
    );
  }
}

/// 一条记忆事实，对应 Go 的 memory.Memory。
class Memory {
  /// 短横线分隔的标识，也是文件名（<name>.md）。
  final String name;

  /// 人类可读的标题（索引显示用）。
  String title;

  /// 一行摘要，用于索引和召回。
  String description;

  /// 记忆类型。
  MemoryType type;

  /// 正文（Markdown）。
  String body;

  /// 优先级（高优先级记忆会注入到 HIGH PRIORITY 块）。
  String priority;

  Memory({
    required this.name,
    this.title = '',
    this.description = '',
    this.type = MemoryType.project,
    this.body = '',
    this.priority = 'medium',
  }) {
    if (title.isEmpty) title = _deKebab(name);
  }

  /// 文件名（含扩展名）。
  String get filename => '$name.md';

  Map<String, dynamic> toYamlFrontmatter() => {
        'name': name,
        'title': title,
        'description': description,
        'type': type.value,
        'priority': priority,
      };

  @override
  String toString() => 'Memory($name: $description)';
}

/// 将短横线分隔的标识转为标题（如 "my-fact" → "My Fact"）。
String _deKebab(String s) {
  return s.split(RegExp(r'[-_]')).map((w) {
    if (w.isEmpty) return w;
    return w[0].toUpperCase() + w.substring(1);
  }).join(' ');
}

// ─── Store ─────────────────────────────────────────────────

/// 记忆存储——管理记忆文件的目录 + MEMORY.md 索引。
///
/// 对应 Go 的 memory.Store。
class MemoryStore {
  final String dir;
  bool _loaded = false;
  final List<Memory> _memories = [];

  MemoryStore(this.dir);

  /// 目录是否存在。
  bool get exists => Directory(dir).existsSync();

  /// 确保目录存在。
  void ensureDir() {
    Directory(dir).createSync(recursive: true);
  }

  /// 从目录加载所有记忆。
  void load() {
    if (_loaded) return;
    _memories.clear();

    if (!exists) {
      _loaded = true;
      return;
    }

    final dirObj = Directory(dir);
    final files = dirObj.listSync().whereType<File>().toList();

    for (final file in files) {
      if (!file.path.endsWith('.md')) continue;
      if (file.path.endsWith('MEMORY.md')) continue;

      try {
        final content = file.readAsStringSync();
        final memory = _parseMemory(content, file.path);
        if (memory != null) {
          _memories.add(memory);
        }
      } catch (_) {
        // 跳过无法解析的文件
      }
    }

    _memories.sort((a, b) => a.name.compareTo(b.name));
    _loaded = true;
  }

  /// 解析记忆文件（frontmatter + body）。
  Memory? _parseMemory(String content, String path) {
    // 简单 frontmatter 解析（YAML frontmatter between ---）
    final frontmatterMatch = RegExp(r'^---\n([\s\S]*?)\n---\n([\s\S]*)').firstMatch(content);

    String body;
    String name = '';
    String title = '';
    String description = '';
    String typeStr = '';
    String priority = 'medium';

    if (frontmatterMatch != null) {
      final fm = frontmatterMatch.group(1)!;
      body = frontmatterMatch.group(2) ?? '';

      // 解析键值对
      for (final line in fm.split('\n')) {
        final colon = line.indexOf(':');
        if (colon <= 0) continue;
        final key = line.substring(0, colon).trim();
        final value = line.substring(colon + 1).trim().replaceAll(RegExp(r'^"|"$'), '');
        switch (key) {
          case 'name':
            name = value;
          case 'title':
            title = value;
          case 'description':
            description = value;
          case 'type':
            typeStr = value;
          case 'priority':
            priority = value;
        }
      }
    } else {
      body = content;
    }

    // 从文件名推导 name
    if (name.isEmpty) {
      name = path.split(RegExp(r'[/\\]')).last.replaceAll('.md', '');
    }

    return Memory(
      name: name,
      title: title,
      description: description,
      type: MemoryType.fromString(typeStr),
      body: body.trim(),
      priority: priority,
    );
  }

  /// 保存一条记忆。
  void save(Memory memory) {
    ensureDir();
    final file = File('${dir}${Platform.pathSeparator}${memory.filename}');

    final frontmatter = memory.toYamlFrontmatter();
    final yamlLines = frontmatter.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    final content = '---\n$yamlLines\n---\n\n${memory.body}';

    file.writeAsStringSync(content);

    // 更新内存索引
    _memories.removeWhere((m) => m.name == memory.name);
    _memories.add(memory);
    _memories.sort((a, b) => a.name.compareTo(b.name));

    // 重写索引
    _writeIndex();
  }

  /// 删除一条记忆。
  void delete(String name) {
    final file = File('${dir}${Platform.pathSeparator}$name.md');
    if (file.existsSync()) file.deleteSync();
    _memories.removeWhere((m) => m.name == name);
    _writeIndex();
  }

  /// 按名称获取记忆。
  Memory? get(String name) {
    load();
    try {
      return _memories.firstWhere((m) => m.name == name);
    } catch (_) {
      return null;
    }
  }

  /// 所有记忆。
  List<Memory> all() {
    load();
    return List.unmodifiable(_memories);
  }

  /// 按类型筛选。
  List<Memory> byType(MemoryType type) {
    load();
    return _memories.where((m) => m.type == type).toList();
  }

  /// 生成 MEMORY.md 索引内容。
  String buildIndex() {
    load();
    if (_memories.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('## Project memory (MEMORY.md)');
    buf.writeln();
    buf.writeln('The user pinned these notes about this project — treat them as authoritative context for every turn.');
    buf.writeln();

    for (final mem in _memories) {
      final priority = mem.priority == 'high' ? ' 🔴' : '';
      buf.writeln('- [${mem.name}](${mem.filename}) — ${mem.description}$priority');
    }

    return buf.toString();
  }

  /// 重写 MEMORY.md 索引文件。
  void _writeIndex() {
    ensureDir();
    final indexFile = File('${dir}${Platform.pathSeparator}MEMORY.md');
    indexFile.writeAsStringSync(buildIndex());
  }

  /// 读取 MEMORY.md 内容。
  String readIndex() {
    final indexFile = File('${dir}${Platform.pathSeparator}MEMORY.md');
    if (!indexFile.existsSync()) return '';
    return indexFile.readAsStringSync();
  }
}

// ─── MemorySet ─────────────────────────────────────────────

/// 一次会话中加载的所有记忆。
///
/// 对应 Go 的 memory.Set。
class MemorySet {
  /// 记忆存储。
  final MemoryStore store;

  /// MEMORY.md 索引内容（加载时捕获）。
  final String index;

  MemorySet({required this.store, String? index})
      : index = index ?? store.readIndex();

  /// 是否为空（无记忆可注入）。
  bool get isEmpty => index.trim().isEmpty && store.all().isEmpty;

  /// 将记忆注入到 system prompt 中的文本。
  String toContextString() {
    if (isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('\n## 项目记忆');
    buf.writeln('以下是与当前项目相关的记忆，作为每轮对话的上线文。');
    buf.writeln();
    buf.writeln(index);
    return buf.toString();
  }
}
