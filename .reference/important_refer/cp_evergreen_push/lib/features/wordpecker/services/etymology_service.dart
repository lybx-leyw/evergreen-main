import 'dart:convert';
import '../../../core/result.dart';
import '../../tutor/services/deepseek_client.dart';

/// AI-powered etymology analysis service.
///
/// Ports the etymology pipeline from app/js/components/wordpecker.js:
/// 1. Local JSON cache (pre-generated)
/// 2. localStorage cache (session persistence)
/// 3. DeepSeek API call (on-demand)
class EtymologyService {
  final DeepSeekClient? _aiClient;

  EtymologyService({DeepSeekClient? aiClient}) : _aiClient = aiClient;

  /// Analyze a word's etymology including:
  /// - Root/affix breakdown
  /// - Historical origin
  /// - Cognates in other languages
  /// - Memory aids (mnemonics)
  Future<EtymologyResult?> analyze(String word) async {
    // Tier 1: Check local pre-generated cache
    final localResult = await _checkLocalCache(word);
    if (localResult != null) return localResult;

    // Tier 2: Check session cache
    // (session cache would be implemented with in-memory Map)

    // Tier 3: AI analysis via DeepSeek
    if (_aiClient != null) {
      return await _aiAnalysis(word);
    }

    return null;
  }

  Future<EtymologyResult?> _checkLocalCache(String word) async {
    // In a full implementation, this would check:
    // vendor/dicts/etymology/{first_letter}/{word}.json
    // These are pre-generated with DeepSeek batch analysis.
    return null;
  }

  Future<EtymologyResult?> _aiAnalysis(String word) async {
    if (_aiClient == null) return null;

    final messages = [
      {
        'role': 'system',
        'content': '''你是一位词源学家。请分析以下单词的词源，严格按以下JSON格式输出：
{
  "word": "单词",
  "root": "词根",
  "rootMeaning": "词根含义",
  "prefix": "前缀（如无则为null）",
  "prefixMeaning": "前缀含义",
  "suffix": "后缀（如无则为null）",
  "suffixMeaning": "后缀含义",
  "origin": "词源语言（如拉丁语/希腊语/古英语）",
  "cognates": ["同源词1", "同源词2"],
  "mnemonic": "一句话记忆法（中文）",
  "evolution": "词义演变简述"
}'''
      },
      {'role': 'user', 'content': '请分析: $word'},
    ];

    final result = await _aiClient!.chat(messages);
    return result.fold(
      (text) => EtymologyResult.fromJson(text),
      (_) => null,
    );
  }
}

class EtymologyResult {
  final String word;
  final String? root;
  final String? rootMeaning;
  final String? prefix;
  final String? prefixMeaning;
  final String? suffix;
  final String? suffixMeaning;
  final String? origin;
  final List<String>? cognates;
  final String? mnemonic;
  final String? evolution;

  const EtymologyResult({
    required this.word,
    this.root,
    this.rootMeaning,
    this.prefix,
    this.prefixMeaning,
    this.suffix,
    this.suffixMeaning,
    this.origin,
    this.cognates,
    this.mnemonic,
    this.evolution,
  });

  factory EtymologyResult.fromJson(dynamic data) {
    Map<String, dynamic> json;
    if (data is String) {
      // Parse JSON from AI response
      try {
        final start = data.indexOf('{');
        final end = data.lastIndexOf('}');
        if (start >= 0 && end > start) {
          json = _parseJson(data.substring(start, end + 1));
        } else {
          return EtymologyResult(word: '');
        }
      } catch (_) {
        return EtymologyResult(word: '');
      }
    } else if (data is Map<String, dynamic>) {
      json = data;
    } else {
      return EtymologyResult(word: '');
    }

    return EtymologyResult(
      word: json['word']?.toString() ?? '',
      root: json['root']?.toString(),
      rootMeaning: json['rootMeaning']?.toString(),
      prefix: json['prefix']?.toString(),
      prefixMeaning: json['prefixMeaning']?.toString(),
      suffix: json['suffix']?.toString(),
      suffixMeaning: json['suffixMeaning']?.toString(),
      origin: json['origin']?.toString(),
      cognates: (json['cognates'] as List?)?.map((e) => e.toString()).toList(),
      mnemonic: json['mnemonic']?.toString(),
      evolution: json['evolution']?.toString(),
    );
  }

  static Map<String, dynamic> _parseJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      // AI output may be malformed JSON — return empty map as graceful degradation
      return {};
    }
  }

  /// Format as a human-readable string for display in the etymology panel.
  String format() {
    final buf = StringBuffer();
    buf.writeln('## $word — 词源分析\n');
    if (root != null && rootMeaning != null) {
      buf.writeln('**词根**: $root ($rootMeaning)');
    }
    if (prefix != null) {
      buf.writeln('**前缀**: $prefix ($prefixMeaning)');
    }
    if (suffix != null) {
      buf.writeln('**后缀**: $suffix ($suffixMeaning)');
    }
    if (origin != null) {
      buf.writeln('**来源**: $origin');
    }
    if (cognates != null && cognates!.isNotEmpty) {
      buf.writeln('**同源词**: ${cognates!.join(", ")}');
    }
    if (mnemonic != null) {
      buf.writeln('\n**记忆法**: $mnemonic');
    }
    if (evolution != null) {
      buf.writeln('\n**词义演变**: $evolution');
    }
    return buf.toString();
  }
}
