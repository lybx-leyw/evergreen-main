import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/fsrs_card.dart';
import '../models/word_entry.dart';

/// FSRS-5 scheduling service — manages spaced repetition cards.
///
/// Ports the fsrs scheduling from app/js/components/wordpecker-fsrs.js.
class FsrsService {
  final Map<String, FsrsCard> _cards = {};
  bool _loaded = false;

  /// Load cards from persistent storage.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'wordpecker_fsrs.json'));
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> data = jsonDecode(content);
        for (final entry in data) {
          final card = FsrsCard.fromJson(entry as Map<String, dynamic>);
          _cards[card.wordId] = card;
        }
      }
    } catch (_) {
      // File doesn't exist or is corrupted — start fresh
    }
    _loaded = true;
  }

  /// Save cards to persistent storage.
  Future<void> _save() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'wordpecker_fsrs.json'));
      final data = _cards.values.map((c) => c.toJson()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (_) {
      // Best-effort persistence
    }
  }

  /// Get or create an FSRS card for a word.
  FsrsCard getOrCreateCard(String wordId) {
    if (_cards.containsKey(wordId)) return _cards[wordId]!;
    final card = FsrsCard(wordId: wordId);
    _cards[wordId] = card;
    return card;
  }

  /// Grade a word after review and schedule next review.
  void gradeWord(String wordId, int rating, {DateTime? now}) {
    final card = getOrCreateCard(wordId);
    card.schedule(rating, now: now);
    _save();
  }

  /// Get all cards due for review.
  List<FsrsCard> getDueCards() {
    return _cards.values.where((c) => c.isDue).toList();
  }

  /// Get the number of cards due for review.
  int get dueCount => getDueCards().length;

  /// Get total number of cards.
  int get totalCount => _cards.length;

  /// Calculate streak (consecutive days with at least one review).
  int calculateStreak() {
    final reviews = _cards.values
        .map((c) => c.lastReview)
        .where((d) => d.isBefore(DateTime.now()))
        .toList();
    if (reviews.isEmpty) return 0;

    reviews.sort((a, b) => b.compareTo(a));
    var streak = 0;
    var checkDate = DateTime.now().subtract(const Duration(days: 1));
    for (final reviewDate in reviews) {
      if (_isSameDay(reviewDate, checkDate)) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else if (reviewDate.isBefore(checkDate)) {
        break;
      }
    }
    // Check if today has reviews too
    final todayReviews = _cards.values
        .where((c) => _isSameDay(c.lastReview, DateTime.now()))
        .length;
    if (todayReviews > 0 && streak == 0) streak = 1;

    return streak;
  }

  /// Get statistics for the stats screen.
  FsrsStats getStats() {
    final today = getDueCards();
    final total = _cards.length;
    final mastered = _cards.values.where((c) => c.stability > 21).length;
    final learning = _cards.values.where((c) => c.state == FsrsState.learning || c.state == FsrsState.relearning).length;

    return FsrsStats(
      dueCount: today.length,
      totalCards: total,
      masteredCount: mastered,
      learningCount: learning,
    );
  }

  /// Import cards from a list of words.
  void importCards(List<WordEntry> words) {
    for (final word in words) {
      getOrCreateCard(word.word);
    }
    _save();
  }

  /// Clear all data.
  Future<void> clearAll() async {
    _cards.clear();
    await _save();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class FsrsStats {
  final int dueCount;
  final int totalCards;
  final int masteredCount;
  final int learningCount;

  const FsrsStats({
    this.dueCount = 0,
    this.totalCards = 0,
    this.masteredCount = 0,
    this.learningCount = 0,
  });
}
