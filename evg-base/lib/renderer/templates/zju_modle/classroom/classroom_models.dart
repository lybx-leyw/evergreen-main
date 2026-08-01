/// 教室 slot 内部数据模型。
///
/// 对应目标数据 schema（由 DataOrchestrator 提供或嵌入 static config）：
/// ```json
/// { "courses": [{
///   "id": 1, "title": "...", "teachers": ["..."],
///   "videos": [{
///     "subId": 1, "title": "...", "startAt": "...", "videoUrl": "...",
///     "slides": [{"page": 1, "imageUrl": "...", "text": "..."}],
///     "subtitles": [{"startMs": 0, "endMs": 0, "text": "..."}]
///   }]
/// }]}
/// ```
library;

/// PPT 幻灯片。
class PptSlide {
  final int page;
  final String imageUrl;
  final String? text;

  const PptSlide({required this.page, required this.imageUrl, this.text});

  factory PptSlide.fromJson(Map<String, dynamic> json) => PptSlide(
        page: (json['page'] as num?)?.toInt() ?? 0,
        imageUrl: json['imageUrl'] as String? ?? '',
        text: json['text'] as String?,
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'page': page,
      'imageUrl': imageUrl,
    };
    if (text != null) m['text'] = text;
    return m;
  }
}

/// 语音转录字幕。
class Subtitle {
  final int startMs;
  final int endMs;
  final String text;

  const Subtitle({required this.startMs, this.endMs = 0, required this.text});

  factory Subtitle.fromJson(Map<String, dynamic> json) => Subtitle(
        startMs: (json['startMs'] as num?)?.toInt() ?? 0,
        endMs: (json['endMs'] as num?)?.toInt() ?? 0,
        text: json['text'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'startMs': startMs,
        'endMs': endMs,
        'text': text,
      };
}

/// 课堂录播视频（包含 PPT 与字幕）。
class ClassroomVideo {
  final int subId;
  final String title;
  final String? startAt;
  final String? videoUrl;
  final List<PptSlide> slides;
  final List<Subtitle> subtitles;

  const ClassroomVideo({
    required this.subId,
    required this.title,
    this.startAt,
    this.videoUrl,
    this.slides = const [],
    this.subtitles = const [],
  });

  factory ClassroomVideo.fromJson(Map<String, dynamic> json) {
    final slidesRaw = json['slides'] as List<dynamic>? ?? [];
    final subsRaw = json['subtitles'] as List<dynamic>? ?? [];
    return ClassroomVideo(
      subId: (json['subId'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      startAt: json['startAt'] as String?,
      videoUrl: json['videoUrl'] as String?,
      slides: slidesRaw
          .map((s) => PptSlide.fromJson(s as Map<String, dynamic>))
          .toList(),
      subtitles: subsRaw
          .map((s) => Subtitle.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'subId': subId,
        'title': title,
        if (startAt != null) 'startAt': startAt,
        if (videoUrl != null) 'videoUrl': videoUrl,
        'slides': slides.map((s) => s.toJson()).toList(),
        'subtitles': subtitles.map((s) => s.toJson()).toList(),
      };
}

/// 课程。
class ClassroomCourse {
  final String id;
  final String title;
  final List<String> teachers;
  final List<ClassroomVideo> videos;

  const ClassroomCourse({
    required this.id,
    this.title = '',
    this.teachers = const [],
    this.videos = const [],
  });

  factory ClassroomCourse.fromJson(Map<String, dynamic> json) {
    final vidsRaw = json['videos'] as List<dynamic>? ?? [];
    final tRaw = json['teachers'] as List<dynamic>? ?? [];
    return ClassroomCourse(
      id: '${json['id'] ?? ''}',
      title: json['title'] as String? ?? '',
      teachers: tRaw.map((t) => t.toString()).toList(),
      videos: vidsRaw
          .map((v) => ClassroomVideo.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'teachers': teachers,
        'videos': videos.map((v) => v.toJson()).toList(),
      };
}

/// 课程内容聚合（供 AI 笔记使用）。
class CourseContent {
  final List<PptSlide> slides;
  final List<Subtitle> subtitles;

  const CourseContent({this.slides = const [], this.subtitles = const []});

  /// 拼接 PPT 文本 + 字幕为 AI 可读的 Markdown 文本。
  String get aiContent {
    final buf = StringBuffer();
    if (slides.isNotEmpty) {
      buf.writeln('## PPT 内容');
      for (final s in slides) {
        if (s.text != null && s.text!.isNotEmpty) {
          buf.writeln('- 第${s.page}页: ${s.text}');
        }
      }
    }
    if (subtitles.isNotEmpty) {
      buf.writeln('## 语音字幕');
      for (final s in subtitles) {
        buf.writeln(
            '- [${_formatMs(s.startMs)}] ${s.text}');
      }
    }
    return buf.toString().trim();
  }

  bool get isEmpty => slides.isEmpty && subtitles.isEmpty;

  static String _formatMs(int ms) {
    final m = (ms / 60000).floor();
    final s = ((ms % 60000) / 1000).floor();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
