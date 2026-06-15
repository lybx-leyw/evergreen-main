import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/config/app_config.dart';
import '../../tutor/services/deepseek_client.dart';
import '../services/fsrs_service.dart';
import '../services/dictionary_service.dart';
import '../services/etymology_service.dart';
import '../models/word_entry.dart';
import '../models/fsrs_card.dart';

/// WordPecker state — FSRS-5 spaced repetition vocabulary learning.
class WordPeckerState {
  final FsrsStats fsrsStats;
  final String currentStrategy;
  final String currentMode;
  final int batchSize;
  final bool autoEtymology;
  final bool isPracticing;
  final List<String> wordBasket;
  final String? currentWord;
  final String? etymologyResult;

  const WordPeckerState({
    this.fsrsStats = const FsrsStats(),
    this.currentStrategy = 'chew',
    this.currentMode = 'copy',
    this.batchSize = 10,
    this.autoEtymology = true,
    this.isPracticing = false,
    this.wordBasket = const [],
    this.currentWord,
    this.etymologyResult,
  });

  WordPeckerState copyWith({
    FsrsStats? fsrsStats,
    String? currentStrategy,
    String? currentMode,
    int? batchSize,
    bool? autoEtymology,
    bool? isPracticing,
    List<String>? wordBasket,
    String? currentWord,
    String? etymologyResult,
  }) {
    return WordPeckerState(
      fsrsStats: fsrsStats ?? this.fsrsStats,
      currentStrategy: currentStrategy ?? this.currentStrategy,
      currentMode: currentMode ?? this.currentMode,
      batchSize: batchSize ?? this.batchSize,
      autoEtymology: autoEtymology ?? this.autoEtymology,
      isPracticing: isPracticing ?? this.isPracticing,
      wordBasket: wordBasket ?? this.wordBasket,
      currentWord: currentWord,
      etymologyResult: etymologyResult,
    );
  }
}

class WordPeckerNotifier extends StateNotifier<WordPeckerState> {
  final FsrsService _fsrs;
  final DictionaryService _dict;
  final EtymologyService? _etymology;

  WordPeckerNotifier(this._fsrs, this._dict, this._etymology)
      : super(WordPeckerState(fsrsStats: _fsrs.getStats())) {
    _refreshStats();
  }

  void _refreshStats() {
    state = state.copyWith(fsrsStats: _fsrs.getStats());
  }

  void setStrategy(String s) => state = state.copyWith(currentStrategy: s);
  void setMode(String m) => state = state.copyWith(currentMode: m);
  void setBatchSize(int n) => state = state.copyWith(batchSize: n);
  void toggleAutoEtymology() => state = state.copyWith(autoEtymology: !state.autoEtymology);

  void addToBasket(String word) {
    final basket = List<String>.from(state.wordBasket);
    if (!basket.contains(word)) {
      basket.add(word);
      state = state.copyWith(wordBasket: basket);
    }
  }

  void removeFromBasket(String word) {
    final basket = List<String>.from(state.wordBasket);
    basket.remove(word);
    state = state.copyWith(wordBasket: basket);
  }

  void clearBasket() {
    state = state.copyWith(wordBasket: []);
  }

  /// Grade the current word with an FSRS rating and advance.
  void gradeWord(int rating) {
    if (state.currentWord == null) return;
    _fsrs.gradeWord(state.currentWord!, rating);
    _refreshStats();
  }

  /// Import words from basket into FSRS.
  void importFromBasket() {
    if (state.wordBasket.isEmpty) return;
    for (final word in state.wordBasket) {
      _fsrs.getOrCreateCard(word);
    }
    _refreshStats();
    state = state.copyWith(wordBasket: []);
  }

  /// Fetch etymology for a word.
  Future<void> lookupEtymology(String word) async {
    if (_etymology == null) return;
    final result = await _etymology!.analyze(word);
    if (result != null) {
      state = state.copyWith(etymologyResult: result.format());
    }
  }

  /// Get the next due word for practice.
  String? getNextDueWord() {
    final dueCards = _fsrs.getDueCards();
    if (dueCards.isEmpty) return null;
    return dueCards.first.wordId;
  }

  /// Start a practice session.
  void startPractice() {
    final word = getNextDueWord();
    if (word != null || state.wordBasket.isNotEmpty) {
      importFromBasket();
      final due = getNextDueWord() ?? state.wordBasket.firstOrNull;
      state = state.copyWith(isPracticing: true, currentWord: due);
      if (due != null && state.autoEtymology) {
        lookupEtymology(due);
      }
    }
  }

  /// Load FSRS data from disk.
  Future<void> load() async {
    await _fsrs.load();
    _refreshStats();
  }
}

/// Provider for WordPecker state.
/// Creates EtymologyService on-demand using the DeepSeekClient if an API key is configured.
final wordpeckerProvider =
    StateNotifierProvider<WordPeckerNotifier, WordPeckerState>((ref) {
  final fsrs = FsrsService();
  final dict = DictionaryService();
  // Try to wire DeepSeekClient if available; etymology gracefully degrades to local + cache only
  EtymologyService? etymology;
  try {
    final dio = ref.read(dioClientProvider);
    final client = DeepSeekClient(dio);
    if (AppConfig.hasDeepSeekApiKey) {
      etymology = EtymologyService(aiClient: client);
    }
  } catch (_) {
    // DeepSeekClient creation failed — etymology will be null, AI lookups disabled
  }
  final notifier = WordPeckerNotifier(fsrs, dict, etymology);
  // Schedule async load after provider creation — state starts with zeros, then
  // updates when load completes. The UI handles this via the loading -> data transition.
  unawaited(notifier.load());
  return notifier;
});
