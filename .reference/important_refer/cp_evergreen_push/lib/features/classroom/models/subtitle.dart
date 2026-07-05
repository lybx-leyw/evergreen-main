class Subtitle {
  final int startMs;
  final int endMs;
  final String text;

  const Subtitle({required this.startMs, required this.endMs, required this.text});

  factory Subtitle.fromJson(Map<String, dynamic> json) => Subtitle(
        startMs: json['startMs'] as int? ?? 0,
        endMs: json['endMs'] as int? ?? 0,
        text: json['text'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'startMs': startMs,
        'endMs': endMs,
        'text': text,
      };
}
