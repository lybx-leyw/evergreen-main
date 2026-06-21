import 'ppt_slide.dart';
import 'subtitle.dart';

class CourseContent {
  final List<PptSlide> slides;
  final List<Subtitle> subtitles;

  const CourseContent({required this.slides, required this.subtitles});

  factory CourseContent.fromJson(Map<String, dynamic> json) => CourseContent(
        slides: (json['slides'] as List<dynamic>? ?? [])
            .map((e) => PptSlide.fromJson(e as Map<String, dynamic>))
            .toList(),
        subtitles: (json['subtitles'] as List<dynamic>? ?? [])
            .map((e) => Subtitle.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'slides': slides.map((s) => s.toJson()).toList(),
        'subtitles': subtitles.map((s) => s.toJson()).toList(),
      };

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
