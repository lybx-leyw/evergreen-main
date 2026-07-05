/// 奥尔波特特质层级。
enum TraitLevel {
  /// 首要特质——最能定义一个用户的支配性形容词。
  cardinal,

  /// 中心特质——5-10个核心特质形容词。
  central,

  /// 次要特质——情境性偏好/风格。
  secondary,

  /// 关键事实——客观不变的硬事实。
  keyFact;
}

/// 一条带时间锚定的记忆事实。
class MemoryFact {
  /// 事实陈述（如"用户主修计算机科学"）。
  final String fact;

  /// 事实成立的时间点（如"2026年6月"）。
  final String timeAnchor;

  /// 置信度 0.0~1.0。
  final double confidence;

  /// 是否为风格类事实（vs 客观事实）。
  final bool isStyleFact;

  /// 记录时间。
  final DateTime recordedAt;

  /// 来源证据（对话片段）。
  final String? source;

  const MemoryFact({
    required this.fact,
    required this.timeAnchor,
    required this.confidence,
    this.isStyleFact = false,
    required this.recordedAt,
    this.source,
  });

  /// 格式化注入 system prompt 的形式。
  String toPrompt() => '[$timeAnchor] $fact';

  Map<String, dynamic> toJson() => {
        'fact': fact,
        'time_anchor': timeAnchor,
        'confidence': confidence,
        'is_style': isStyleFact,
        'recorded_at': recordedAt.toIso8601String(),
        'source': source,
      };

  factory MemoryFact.fromJson(Map<String, dynamic> json) {
    String _str(dynamic v) => (v is String) ? v : (v?.toString() ?? '');
    double _num(dynamic v) => (v is num) ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0.5);
    bool _bool(dynamic v) => v is bool ? v : (v?.toString() == 'true');
    return MemoryFact(
      fact: _str(json['fact']),
      timeAnchor: _str(json['time_anchor']),
      confidence: _num(json['confidence']),
      isStyleFact: _bool(json['is_style']),
      recordedAt:
          DateTime.tryParse(_str(json['recorded_at'])) ?? DateTime(2024),
      source: json['source'] is String ? json['source'] as String : null,
    );
  }

  /// 是否与另一条事实矛盾（语义上冲突）。
  bool contradicts(MemoryFact other) {
    // 简陋的冲突检测：关键词替换
    final f = fact.toLowerCase();
    final o = other.fact.toLowerCase();
    // 年级变化
    final grades = ['大一', '大二', '大三', '大四', '研一', '研二', '研三', '博一', '博二', '博三', '博四', '博五'];
    for (var i = 0; i < grades.length; i++) {
      for (var j = i + 1; j < grades.length; j++) {
        if ((f.contains(grades[i]) && o.contains(grades[j])) ||
            (f.contains(grades[j]) && o.contains(grades[i]))) {
          return true;
        }
      }
    }
    if ((f.contains('本科生') && o.contains('研究生')) ||
        (f.contains('硕士') && o.contains('博士'))) return true;
    // 专业变化
    if (f.contains('主修') && o.contains('主修') && !f.split('主修').last
        .trim()
        .contains(o.split('主修').last.trim())) return true;
    return false;
  }
}
