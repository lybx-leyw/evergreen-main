/// 技术规划编辑器 —— 数据模型。
library;

/// 技术规划文档。
class TechDocument {
  final String id;
  String title;
  String content;
  final DateTime createdAt;
  DateTime updatedAt;

  TechDocument({
    required this.id,
    this.title = '未命名技术规划',
    this.content = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 从 JSON 反序列化。
  factory TechDocument.fromJson(Map<String, dynamic> json) => TechDocument(
        id: json['id'] as String,
        title: json['title'] as String? ?? '未命名技术规划',
        content: json['content'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
      );

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// AI 技术调研分析报告。
class TechAnalysisReport {
  final String understanding;
  final List<TechEvidence> evidence;
  final List<String> blindSpots;
  final List<String> newIdeas;
  final List<String> risks;
  final String rawResponse;

  const TechAnalysisReport({
    required this.understanding,
    this.evidence = const [],
    this.blindSpots = const [],
    this.newIdeas = const [],
    this.risks = const [],
    this.rawResponse = '',
  });

  bool get isEmpty => understanding.isEmpty && evidence.isEmpty;

  factory TechAnalysisReport.empty() => const TechAnalysisReport(understanding: '');

  /// 从 AI 返回的 JSON 字符串解析。
  factory TechAnalysisReport.fromJsonString(String jsonStr) {
    try {
      final Map<String, dynamic> m = _safeParse(jsonStr);
      // 如果解析结果为空且原始输入非空，且输入不是合法的 JSON 对象/数组，
      // 则视为纯文本降级（将全文作为 understanding）
      if (m.isEmpty && jsonStr.trim().isNotEmpty) {
        final directParse = _simpleJson(jsonStr);
        if (directParse is! Map && directParse is! List) {
          return TechAnalysisReport(
            understanding: jsonStr,
            rawResponse: jsonStr,
          );
        }
      }
      return TechAnalysisReport(
        understanding: _asString(m['understanding']),
        evidence: _parseEvidence(m['evidence']),
        blindSpots: _asStringList(m['blindSpots']),
        newIdeas: _asStringList(m['newIdeas']),
        risks: _asStringList(m['risks']),
        rawResponse: jsonStr,
      );
    } catch (e) {
      // JSON 解析失败 → 将全文作为 understanding 降级
      return TechAnalysisReport(
        understanding: jsonStr,
        rawResponse: jsonStr,
      );
    }
  }

  /// 将 evidence 字段解析为 [TechEvidence] 列表。
  ///
  /// 输入可能是 List、JSON 数组字符串、或 null。
  /// 每个元素可能是 Map 或 JSON 对象字符串。
  static List<TechEvidence> _parseEvidence(dynamic v) {
    if (v == null) return [];
    List<dynamic> items;
    if (v is List) {
      items = v;
    } else if (v is String) {
      final parsed = _simpleJson(v);
      items = parsed is List ? parsed : [];
    } else {
      return [];
    }

    return items.map((item) {
      if (item is Map) {
        return TechEvidence(
          source: _asString(item['source']),
          content: _asString(item['content']),
          url: item['url'] is String ? item['url'] as String : null,
        );
      }
      if (item is String) {
        // 递归解析 JSON 对象字符串
        final inner = _simpleJson(item);
        if (inner is Map) {
          return TechEvidence(
            source: _asString(inner['source']),
            content: _asString(inner['content']),
            url: inner['url'] is String ? inner['url'] as String : null,
          );
        }
      }
      return null;
    }).whereType<TechEvidence>().toList();
  }

  static Map<String, dynamic> _safeParse(String s) {
    try {
      final decoded = _tryJsonDecode(s);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {};
  }

  static dynamic _tryJsonDecode(String s) {
    // 使用 dart:convert 的 jsonDecode（调用方提供 import）
    // 这里用简单实现避免循环依赖
    return _simpleJson(s);
  }

  static String _asString(dynamic v) => (v is String) ? v : (v?.toString() ?? '');

  static List<String> _asStringList(dynamic v, [String? nestedKey]) {
    List<dynamic> items;
    if (v is List) {
      items = v;
    } else if (v is String) {
      // 可能是 JSON 数组字符串（如 '["a", "b"]'），
      // 先尝试用 _simpleJson 解析
      final parsed = _simpleJson(v);
      items = parsed is List ? parsed : [];
    } else {
      return [];
    }
    return items.map((e) {
      if (nestedKey != null && e is Map) {
        return _asString(e[nestedKey]);
      }
      return _asString(e);
    }).where((s) => s.isNotEmpty).toList();
  }

  /// 极简 JSON 解析器（避免对 core 的循环依赖）。
  static dynamic _simpleJson(String source) {
    final s = source.trim();
    if (s.startsWith('{')) {
      final map = <String, dynamic>{};
      final content = s.substring(1, s.lastIndexOf('}')).trim();
      if (content.isEmpty) return map;

      // 简易键值对提取（不处理嵌套）
      final parts = _splitTopLevel(content, ',');
      for (final part in parts) {
        final colon = part.indexOf(':');
        if (colon < 0) continue;
        final key = part.substring(0, colon).trim().replaceAll('"', '');
        final value = part.substring(colon + 1).trim();
        map[key] = _parseSimpleValue(value);
      }
      return map;
    }
    if (s.startsWith('[')) {
      final content = s.substring(1, s.lastIndexOf(']')).trim();
      if (content.isEmpty) return [];
      return _splitTopLevel(content, ',').map(_parseSimpleValue).toList();
    }
    return s;
  }

  static List<String> _splitTopLevel(String s, String sep) {
    final parts = <String>[];
    int depth = 0;
    int start = 0;
    for (int i = 0; i < s.length; i++) {
      if (s[i] == '{' || s[i] == '[') depth++;
      if (s[i] == '}' || s[i] == ']') depth--;
      if (s[i] == sep && depth == 0) {
        parts.add(s.substring(start, i).trim());
        start = i + 1;
      }
    }
    if (start < s.length) parts.add(s.substring(start).trim());
    return parts;
  }

  static dynamic _parseSimpleValue(String v) {
    v = v.trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      return v.substring(1, v.length - 1);
    }
    if (v == 'true') return true;
    if (v == 'false') return false;
    if (v == 'null') return null;
    final n = num.tryParse(v);
    if (n != null) return n;
    return v;
  }
}

/// 调研证据项。
class TechEvidence {
  final String source;
  final String content;
  final String? url;

  const TechEvidence({required this.source, required this.content, this.url});
}
