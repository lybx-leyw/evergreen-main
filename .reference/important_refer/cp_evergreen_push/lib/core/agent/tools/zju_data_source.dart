/// ZJU 数据源接口——Agent 工具与 Flutter Provider 之间的桥梁。
///
/// Flutter 层实现此接口，将 Provider 数据注入 Agent 工具。
/// 这样工具层不依赖 Riverpod，可测试、可复用。
library;

/// ZJU 数据源——Agent 工具读取用户数据的统一入口。
abstract class ZjuDataSource {
  /// 获取课程列表。
  Future<List<ZjuCourse>> getCourses();

  /// 获取成绩/GPA。
  Future<ZjuScoreResult?> getScores();

  /// 获取智云课堂课程列表。
  Future<List<ZjuClassroomCourse>> getClassroomCourses();

  /// 获取一卡通余额。
  Future<ZjuEcardResult?> getEcardBalance();

  /// 获取待办列表。
  Future<List<ZjuTodo>> getTodos();

  /// 获取考试列表。
  Future<List<ZjuExam>> getExams();

  /// 获取当前课表。
  Future<List<ZjuTimetableEntry>> getTimetable();

  /// 获取教务通知列表。
  Future<List<ZjuNotification>> getNotifications();
}

// ── 数据模型 ──────────────────────────────────────────────

class ZjuCourse {
  final int id;
  final String name;
  final String? teacher;
  final bool isActive;

  const ZjuCourse({
    required this.id,
    required this.name,
    this.teacher,
    this.isActive = true,
  });
}

class ZjuScoreResult {
  /// 五分制 GPA（ZDBK 权威值，0-5.0）。
  final double fivePointGpa;

  /// 四分制 GPA（4.3 标准，出国用）。
  final double fourPointThreeGpa;

  /// 四分制 GPA（4.0 旧标准）。
  final double fourPointGpa;

  /// 百分制。
  final double hundredPointGpa;

  /// 已获总学分。
  final double totalCredits;

  /// 课程总数。
  final int courseCount;

  const ZjuScoreResult({
    required this.fivePointGpa,
    required this.fourPointThreeGpa,
    required this.fourPointGpa,
    required this.hundredPointGpa,
    required this.totalCredits,
    required this.courseCount,
  });
}

class ZjuClassroomCourse {
  final int id;
  final String title;
  final int videoCount;

  const ZjuClassroomCourse({
    required this.id,
    required this.title,
    this.videoCount = 0,
  });
}

class ZjuEcardResult {
  final double balance;
  final String? cardNumber;

  const ZjuEcardResult({required this.balance, this.cardNumber});
}

class ZjuTodo {
  final String id;
  final String title;
  final String? deadline;
  final String type;

  const ZjuTodo({
    required this.id,
    required this.title,
    this.deadline,
    this.type = 'homework',
  });
}

class ZjuExam {
  final String name;
  final DateTime? startTime;
  final String? location;

  const ZjuExam({required this.name, this.startTime, this.location});
}

class ZjuNotification {
  final String id;
  final String title;
  final String? publisher;
  final String? publishDate;
  final String? content;

  const ZjuNotification({
    required this.id,
    required this.title,
    this.publisher,
    this.publishDate,
    this.content,
  });
}

class ZjuTimetableEntry {
  final String courseName;
  final String? teacher;
  final String? location;
  final int dayOfWeek;
  final List<int> periods;
  final String? weekRange;

  /// 学期标签，如 "2025-2026 秋冬".
  final String? semesterLabel;

  const ZjuTimetableEntry({
    required this.courseName,
    this.teacher,
    this.location,
    required this.dayOfWeek,
    required this.periods,
    this.weekRange,
    this.semesterLabel,
  });
}

/// 将 ZDBK 的学期位掩码转换为中文字符串（如 "秋冬"）。
///
/// 位编码: 1=春, 2=夏, 4=短①, 8=秋, 16=冬, 32=短②, 64=暑
/// ZDBK 课表 kcb 文本不区分短①/短②，两位置同时设时输出 "短"。
String semesterBitsToLabel(int? bits, int? courseYear) {
  if (bits == null) return '';
  final parts = <String>[];
  if (bits & 1 != 0) parts.add('春');
  if (bits & 2 != 0) parts.add('夏');
  // 短①(4) 和 短②(32)
  if ((bits & 4) != 0 && (bits & 32) != 0) {
    parts.add('短'); // ZDBK 不分短①短②，同时设说明是短学期
  } else {
    if (bits & 4 != 0) parts.add('短①');
    if (bits & 32 != 0) parts.add('短②');
  }
  if (bits & 8 != 0) parts.add('秋');
  if (bits & 16 != 0) parts.add('冬');
  if (bits & 64 != 0) parts.add('暑');
  if (parts.isEmpty) return '';
  final yearLabel = courseYear != null ? '$courseYear-${courseYear + 1} ' : '';
  return '$yearLabel${parts.join('')}';
}
