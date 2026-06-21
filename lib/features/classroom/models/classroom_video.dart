class ClassroomVideo {
  final String id;
  final int courseId;
  final int subId;
  final String title;
  final String? startAt;
  final String? videoUrl;

  const ClassroomVideo({
    required this.id,
    required this.courseId,
    required this.subId,
    required this.title,
    this.startAt,
    this.videoUrl,
  });

  factory ClassroomVideo.fromJson(Map<String, dynamic> json) => ClassroomVideo(
        id: json['id'] as String? ?? '',
        courseId: json['courseId'] as int? ?? 0,
        subId: json['subId'] as int? ?? 0,
        title: json['title'] as String? ?? '',
        startAt: json['startAt'] as String?,
        videoUrl: json['videoUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'subId': subId,
        'title': title,
        if (startAt != null) 'startAt': startAt,
        if (videoUrl != null) 'videoUrl': videoUrl,
      };
}
