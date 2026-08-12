/// ZjuSubtitle — 智云课堂语音识别字幕条目模型。
///
/// B3-classroom（2026-08-12）自参考工程 `cp_evergreen_push/lib/features/
/// classroom/models/subtitle.dart` 前缀 `Zju`（规划 §5.6 防符号冲突）。
/// 保留 fromJson/toJson 双向桥接（数据中枢缓存契约）。
library;

/// 一条 ASR 字幕。
class ZjuSubtitle {
  /// 开始时间（毫秒）。
  final int startMs;

  /// 结束时间（毫秒；智云 ASR 接口不返回结束时间，保持 0）。
  final int endMs;

  /// 字幕文本。
  final String text;

  const ZjuSubtitle({
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  factory ZjuSubtitle.fromJson(Map<String, dynamic> json) {
    return ZjuSubtitle(
      startMs: int.tryParse(json['startMs']?.toString() ?? '') ?? 0,
      endMs: int.tryParse(json['endMs']?.toString() ?? '') ?? 0,
      text: json['text']?.toString() ?? '',
    );
  }

  /// 序列化（数据中枢缓存契约）。
  Map<String, dynamic> toJson() => {
        'startMs': startMs,
        'endMs': endMs,
        'text': text,
      };
}
