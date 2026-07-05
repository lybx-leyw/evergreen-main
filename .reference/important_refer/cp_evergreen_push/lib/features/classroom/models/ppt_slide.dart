class PptSlide {
  final int page;
  final String imageUrl;
  final String? text;

  const PptSlide({required this.page, required this.imageUrl, this.text});

  factory PptSlide.fromJson(Map<String, dynamic> json) => PptSlide(
        page: json['page'] as int? ?? 0,
        imageUrl: json['imageUrl'] as String? ?? '',
        text: json['text'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'page': page,
        'imageUrl': imageUrl,
        if (text != null) 'text': text,
      };
}
