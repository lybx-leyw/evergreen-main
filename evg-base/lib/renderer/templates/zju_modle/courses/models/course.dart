/// ZjuCourse — courses.zju.edu.cn（学在浙大）选课记录模型。
///
/// B3（2026-08-12）自参考工程 `cp_evergreen_push/lib/features/courses/models/course.dart`
/// 拷入并前缀 `Zju`（规划 §5.6：避免与 evg-base 现有符号冲突）。
/// 保留 fromJson/toJson 双向桥接——fetcher 产出 JSON（数据中枢 jsonEncode 缓存），
/// renderer 侧 fromJson 还原。
library;

/// 一门已选课程。
class ZjuCourse {
  final int id;
  final String name;
  final String? courseCode;
  final String? className;
  final String? teacherName;
  final String? teachingPlace;
  final String? courseTypeName;
  final bool isStarted;
  final bool isClosed;
  final double credits;

  const ZjuCourse({
    required this.id,
    required this.name,
    this.courseCode,
    this.className,
    this.teacherName,
    this.teachingPlace,
    this.courseTypeName,
    this.isStarted = false,
    this.isClosed = false,
    this.credits = 0.0,
  });

  factory ZjuCourse.fromJson(Map<String, dynamic> json) {
    return ZjuCourse(
      id: json['id'] ?? json['course_id'] ?? 0,
      name: json['name']?.toString() ?? json['course_name']?.toString() ?? '',
      courseCode: json['course_code']?.toString(),
      className: json['class_name']?.toString(),
      teacherName: json['teacher_name']?.toString() ??
          (json['instructors'] is List && (json['instructors'] as List).isNotEmpty
              ? (json['instructors'] as List).first['name']?.toString()
              : null),
      teachingPlace: json['teaching_place']?.toString(),
      courseTypeName:
          json['course_type_name']?.toString() ?? json['course_type']?.toString(),
      isStarted: json['is_started'] == true || json['is_started'] == 1,
      isClosed: json['is_closed'] == true || json['is_closed'] == 1,
      credits: (json['credits'] is num) ? (json['credits'] as num).toDouble() : 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'course_code': courseCode,
        'class_name': className,
        'teacher_name': teacherName,
        'teaching_place': teachingPlace,
        'course_type_name': courseTypeName,
        'is_started': isStarted,
        'is_closed': isClosed,
        'credits': credits,
      };

  /// 状态中文标签。
  String get statusLabel {
    if (!isStarted) return '未开始';
    if (isClosed) return '已结束';
    return '进行中';
  }

  /// 状态码（1 = 进行中，兼容旧前端）。
  int get status => isStarted ? 1 : 0;
}
