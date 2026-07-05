/// Course model — represents an enrolled course on courses.zju.edu.cn.
class Course {
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

  const Course({
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

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
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

  /// Status label in Chinese.
  String get statusLabel {
    if (!isStarted) return '未开始';
    if (isClosed) return '已结束';
    return '进行中';
  }

  /// Status code (1 = active, for backward compatibility with frontend).
  int get status => isStarted ? 1 : 0;
}
