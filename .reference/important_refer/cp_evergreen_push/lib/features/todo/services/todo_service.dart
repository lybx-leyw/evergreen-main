/// Todo item model — represents an upcoming assignment or exam.
class TodoItem {
  final String id;
  final String title;
  final String courseName;
  final String type; // 'homework', 'exam', 'interactive', 'classroom'
  final String? deadline;
  final bool isSubmitted;

  /// 数据来源平台。
  final String source; // 'courses' | 'pintia'

  const TodoItem({
    required this.id,
    required this.title,
    required this.courseName,
    required this.type,
    this.deadline,
    this.isSubmitted = false,
    this.source = 'courses',
  });

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        courseName: json['courseName'] as String? ?? '',
        type: json['type'] as String? ?? '',
        deadline: json['deadline'] as String?,
        isSubmitted: json['isSubmitted'] as bool? ?? false,
        source: json['source'] as String? ?? 'courses',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'courseName': courseName,
        'type': type,
        if (deadline != null) 'deadline': deadline,
        'isSubmitted': isSubmitted,
        'source': source,
      };

  DateTime? get deadlineDate {
    if (deadline == null || deadline!.isEmpty) return null;
    return DateTime.tryParse(deadline!);
  }

  int get daysUntil {
    final d = deadlineDate;
    if (d == null) return 999;
    return d.difference(DateTime.now()).inDays;
  }

  bool get isExpired => daysUntil < 0;

  int get priority {
    if (isSubmitted) return 0;
    if (daysUntil < 0) return 4;
    if (daysUntil <= 1) return 3;
    if (daysUntil <= 3) return 2;
    return 1;
  }

  String get typeLabel {
    switch (type) {
      case 'homework': return '作业';
      case 'exam': return '考试';
      case 'interactive': return '课堂互动';
      case 'classroom': return '课堂';
      default: return type;
    }
  }

  String get sourceLabel => source == 'pintia' ? 'PTA' : '学在浙大';

  String get statusLabel {
    if (isSubmitted) return '已提交';
    if (daysUntil < 0) return '已过期';
    if (daysUntil == 0) return '今天截止';
    if (daysUntil == 1) return '明天截止';
    return '剩余 $daysUntil 天';
  }
}
