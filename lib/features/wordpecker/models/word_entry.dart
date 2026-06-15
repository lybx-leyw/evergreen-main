/// Word entry model for vocabulary learning.
///
/// Maps to the word data structure from app/js/components/wordpecker.js.
class WordEntry {
  final String word;
  final String? phonetic;
  final String? translation;
  final String? definition;
  final String? etymology;
  final Map<String, String>? dictDefinitions; // dict_name → definition
  final WordSource source;

  const WordEntry({
    required this.word,
    this.phonetic,
    this.translation,
    this.definition,
    this.etymology,
    this.dictDefinitions,
    this.source = WordSource.manual,
  });

  factory WordEntry.fromJson(Map<String, dynamic> json) {
    return WordEntry(
      word: json['word']?.toString() ?? '',
      phonetic: json['phonetic']?.toString(),
      translation: json['translation']?.toString(),
      definition: json['definition']?.toString(),
      etymology: json['etymology']?.toString(),
      dictDefinitions: json['dictDefinitions'] is Map
          ? (json['dictDefinitions'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
          : null,
      source: WordSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => WordSource.manual,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'word': word,
        'phonetic': phonetic,
        'translation': translation,
        'definition': definition,
        'etymology': etymology,
        'dictDefinitions': dictDefinitions,
        'source': source.name,
      };

  /// Get the best available definition across dictionaries.
  String get bestDefinition {
    if (definition != null && definition!.isNotEmpty) return definition!;
    if (translation != null && translation!.isNotEmpty) return translation!;
    if (dictDefinitions != null && dictDefinitions!.isNotEmpty) {
      return dictDefinitions!.values.first;
    }
    return word;
  }
}

enum WordSource { manual, dictionary, ai, import_file }
