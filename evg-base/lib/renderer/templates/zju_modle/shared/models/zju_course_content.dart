/// ZjuCourseContent — 智云课堂单条录播的聚合内容（PPT + 字幕）。
///
/// B3-classroom（2026-08-12）自参考工程 `cp_evergreen_push/lib/features/
/// classroom/models/course_content.dart` 前缀 `Zju`（规划 §5.6 防符号冲突）。
/// 保留 fromJson/toJson 双向桥接（数据中枢缓存契约）。
library;

import 'zju_ppt_slide.dart';
import 'zju_subtitle.dart';

/// 一节录播的完整内容：PPT 幻灯片列表 + ASR 字幕列表。
class ZjuCourseContent {
  final List<ZjuPptSlide> slides;
  final List<ZjuSubtitle> subtitles;

  const ZjuCourseContent({required this.slides, required this.subtitles});

  factory ZjuCourseContent.fromJson(Map<String, dynamic> json) {
    return ZjuCourseContent(
      slides: (json['slides'] as List<dynamic>? ?? [])
          .map((e) => ZjuPptSlide.fromJson(e as Map<String, dynamic>))
          .toList(),
      subtitles: (json['subtitles'] as List<dynamic>? ?? [])
          .map((e) => ZjuSubtitle.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 序列化（数据中枢缓存契约）。
  Map<String, dynamic> toJson() => {
        'slides': slides.map((s) => s.toJson()).toList(),
        'subtitles': subtitles.map((s) => s.toJson()).toList(),
      };

  /// 聚合为纯文本（PPT 分页文本 + 带时间戳字幕，供 AI 笔记等消费）。
  String get aiContent {
    final buf = StringBuffer();
    buf.writeln('## PPT 内容\n');
    for (final s in slides) {
      if (s.text != null && s.text!.isNotEmpty) {
        buf.writeln('### 第${s.page}页\n${s.text}\n');
      }
    }
    if (subtitles.isNotEmpty) {
      buf.writeln('## 语音转录字幕\n');
      for (final s in subtitles) {
        final min = (s.startMs / 60000).floor();
        final sec = ((s.startMs % 60000) / 1000).floor();
        buf.writeln('[$min:${sec.toString().padLeft(2, '0')}] ${s.text}');
      }
    }
    return buf.toString();
  }
}
