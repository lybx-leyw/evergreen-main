/// ZjuClassroomVideo — 智云课堂录播视频元数据模型。
///
/// B3-classroom（2026-08-12）自参考工程 `cp_evergreen_push/lib/features/
/// classroom/models/classroom_video.dart` 前缀 `Zju`（规划 §5.6 防符号冲突）。
/// 保留 fromJson/toJson 双向桥接（数据中枢缓存契约）。
library;

/// 一条智云课堂录播视频。
class ZjuClassroomVideo {
  /// 组合 id（`courseId_subId`，唯一标识）。
  final String id;

  /// 课程 id。
  final int courseId;

  /// 视频子 id（目录项 id，PPT/字幕/播放地址查询参数）。
  final int subId;

  /// 视频标题。
  final String title;

  /// 开播时间（原始字符串，如 `2025-09-01 08:00`）。
  final String? startAt;

  /// 直链播放地址（从 content JSON 解析，可能缺失）。
  final String? videoUrl;

  const ZjuClassroomVideo({
    required this.id,
    required this.courseId,
    required this.subId,
    required this.title,
    this.startAt,
    this.videoUrl,
  });

  factory ZjuClassroomVideo.fromJson(Map<String, dynamic> json) {
    return ZjuClassroomVideo(
      id: json['id']?.toString() ?? '',
      courseId: int.tryParse(json['courseId']?.toString() ?? '') ?? 0,
      subId: int.tryParse(json['subId']?.toString() ?? '') ?? 0,
      title: json['title']?.toString() ?? '',
      startAt: json['startAt']?.toString(),
      videoUrl: json['videoUrl']?.toString(),
    );
  }

  /// 序列化（数据中枢缓存契约）。
  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'subId': subId,
        'title': title,
        if (startAt != null) 'startAt': startAt,
        if (videoUrl != null) 'videoUrl': videoUrl,
      };
}
