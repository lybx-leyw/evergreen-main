/// ZjuClassroomCourse — 智云课堂课程元数据模型。
///
/// B3-classroom（2026-08-12）自参考工程 `cp_evergreen_push/lib/features/
/// classroom/services/classroom_crawler.dart` 的 `ClassroomCourse` 独立成文件
/// 并前缀 `Zju`（规划 §5.6 防符号冲突）。保留 fromJson/toJson 双向桥接——
/// fetcher 产出 JSON（数据中枢 jsonEncode 缓存），renderer 侧 fromJson 还原。
library;

/// 一门智云课堂课程。
class ZjuClassroomCourse {
  /// 课程 id（智云课堂内部 Id，视频目录查询参数）。
  final int id;

  /// 课程标题。
  final String title;

  /// 授课教师（可能缺失）。
  final String? teacher;

  const ZjuClassroomCourse({
    required this.id,
    required this.title,
    this.teacher,
  });

  factory ZjuClassroomCourse.fromJson(Map<String, dynamic> json) {
    return ZjuClassroomCourse(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      title: json['title']?.toString() ?? '',
      teacher: json['teacher']?.toString(),
    );
  }

  /// 序列化（数据中枢缓存契约，字段名与原始 API 一致可还原）。
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (teacher != null) 'teacher': teacher,
      };

  /// 值相等：id 是课程唯一标识，两个实例 id 相同即视为同一门课。
  ///
  /// 必须重写——`DropdownButtonFormField.value` 与 items 的比较依赖 `==`。
  /// 不重写时按引用比较，而每次 build 从 JSON 重新 fromJson 都会产生新实例，
  /// 选中项（旧实例）与新 items（新实例）引用不等 → Flutter 断言
  /// 「There should be exactly one item with [DropdownButton]'s value」崩溃。
  @override
  bool operator ==(Object other) {
    return other is ZjuClassroomCourse && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
