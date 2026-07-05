/// PDF 翻译状态与语言选项枚举。
enum TranslationStatus {
  idle,
  preparing,
  translating,
  done,
  error;

  bool get isActive => this == preparing || this == translating;
  bool get isTerminal => this == done || this == error;
}

/// 支持的语言选项。
enum LanguageOption {
  chinese('Chinese', 'zh', '中文'),
  english('English', 'en', 'English'),
  japanese('Japanese', 'ja', '日本語'),
  korean('Korean', 'ko', '한국어'),
  french('French', 'fr', 'Français'),
  german('German', 'de', 'Deutsch'),
  spanish('Spanish', 'es', 'Español');

  const LanguageOption(this.displayName, this.code, this.nativeName);
  final String displayName;
  final String code;
  final String nativeName;
}
