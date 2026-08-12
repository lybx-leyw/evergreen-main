/// ZjuPptSlide — 智云课堂 PPT 单页模型。
///
/// B3-classroom（2026-08-12）自参考工程 `cp_evergreen_push/lib/features/
/// classroom/models/ppt_slide.dart` 前缀 `Zju`（规划 §5.6 防符号冲突）。
/// 保留 fromJson/toJson 双向桥接（数据中枢缓存契约）。
library;

/// 一页 PPT 幻灯片（图片 URL + 识别文本）。
class ZjuPptSlide {
  /// 页码（从 1 起，按抓取顺序编号）。
  final int page;

  /// 幻灯片图片直链（二进制流，UI 侧 dio 直连下载，不进中枢缓存）。
  final String imageUrl;

  /// OCR/PPT 内嵌文本（可能缺失）。
  final String? text;

  const ZjuPptSlide({
    required this.page,
    required this.imageUrl,
    this.text,
  });

  factory ZjuPptSlide.fromJson(Map<String, dynamic> json) {
    return ZjuPptSlide(
      page: int.tryParse(json['page']?.toString() ?? '') ?? 0,
      imageUrl: json['imageUrl']?.toString() ?? '',
      text: json['text']?.toString(),
    );
  }

  /// 序列化（数据中枢缓存契约）。
  Map<String, dynamic> toJson() => {
        'page': page,
        'imageUrl': imageUrl,
        if (text != null) 'text': text,
      };
}
