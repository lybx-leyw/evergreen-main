import 'dart:math';

/// FSRS-5 card state — port of ts-fsrs Card type.
///
/// The Free Spaced Repetition Scheduler (FSRS) is a modern alternative to
/// Anki's SM-2 algorithm. This is a Dart port of the ts-fsrs TypeScript library.
///
/// Reference: https://github.com/open-spaced-repetition/ts-fsrs
class FsrsCard {
  final String wordId;
  DateTime due;
  double stability;
  double difficulty;
  int elapsedDays;
  int scheduledDays;
  int reps;
  int lapses;
  FsrsState state;
  DateTime lastReview;

  FsrsCard({
    required this.wordId,
    DateTime? due,
    this.stability = 0.0,
    this.difficulty = 0.0,
    this.elapsedDays = 0,
    this.scheduledDays = 0,
    this.reps = 0,
    this.lapses = 0,
    this.state = FsrsState.new_,
    DateTime? lastReview,
  })  : due = due ?? DateTime.now(),
        lastReview = lastReview ?? DateTime.now();

  /// FSRS default parameters (from ts-fsrs generator defaults).
  static const defaultW = [
    0.4, 0.6, 2.4, 5.8, 4.93, 0.94, 0.86, 0.01,
    1.49, 0.14, 0.94, 2.18, 0.05, 0.34, 1.26, 0.29, 2.61,
  ];

  /// Rating options for FSRS.
  static const ratingAgain = 1;
  static const ratingHard = 2;
  static const ratingGood = 3;
  static const ratingEasy = 4;

  /// Schedule next review based on FSRS algorithm.
  /// [rating] — 1=Again, 2=Hard, 3=Good, 4=Easy
  /// [now] — current time (for test determinism)
  void schedule(int rating, {DateTime? now, List<double>? w}) {
    final weights = w ?? defaultW;
    final currentTime = now ?? DateTime.now();

    final daysSinceLastReview = max(0, currentTime.difference(lastReview).inDays);
    elapsedDays = daysSinceLastReview;

    // Compute retrievability
    final retrievability = exp(
      log(0.9) * daysSinceLastReview / max(stability, 0.01),
    );

    // Update difficulty
    final newDifficulty = (difficulty +
            weights[4] * (rating - 3) -
            weights[5] * (rating - 3))
        .clamp(1.0, 10.0);
    difficulty = newDifficulty;

    double newStability;
    if (rating == ratingAgain) {
      // Forgot: reset
      newStability = weights[6] *
          exp(weights[7] * (11 - difficulty)) *
          pow(stability, weights[8]) *
          exp(weights[9] * (1 - retrievability));
      lapses++;
      state = FsrsState.learning;
    } else {
      // Remembered
      double stabilityIncrease;
      if (rating == ratingHard) {
        stabilityIncrease = weights[10];
      } else if (rating == ratingEasy) {
        stabilityIncrease = weights[12];
      } else {
        stabilityIncrease = weights[11];
      }

      newStability = stability *
          (1 +
              stabilityIncrease *
                  11 *
                  exp(weights[13] * (11 - difficulty)) *
                  pow(stability, weights[14]) *
                  exp(weights[15] * (1 - retrievability)));

      reps++;
      if (state == FsrsState.new_ || state == FsrsState.learning) {
        state = FsrsState.review;
      }
    }

    stability = newStability.clamp(0.01, 36500.0);
    scheduledDays = (stability * weights[16]).round().clamp(1, 36500);
    due = currentTime.add(Duration(days: scheduledDays));
    lastReview = currentTime;
  }

  /// Whether the card is due for review.
  bool get isDue => due.isBefore(DateTime.now()) || due.isAtSameMomentAs(DateTime.now());

  /// Days until next review.
  int get daysUntilDue => max(0, due.difference(DateTime.now()).inDays);

  Map<String, dynamic> toJson() => {
        'wordId': wordId,
        'due': due.toIso8601String(),
        'stability': stability,
        'difficulty': difficulty,
        'elapsedDays': elapsedDays,
        'scheduledDays': scheduledDays,
        'reps': reps,
        'lapses': lapses,
        'state': state.index,
        'lastReview': lastReview.toIso8601String(),
      };

  factory FsrsCard.fromJson(Map<String, dynamic> json) {
    return FsrsCard(
      wordId: json['wordId']?.toString() ?? '',
      due: DateTime.tryParse(json['due']?.toString() ?? '') ?? DateTime.now(),
      stability: (json['stability'] as num?)?.toDouble() ?? 0.0,
      difficulty: (json['difficulty'] as num?)?.toDouble() ?? 0.0,
      elapsedDays: (json['elapsedDays'] as num?)?.toInt() ?? 0,
      scheduledDays: (json['scheduledDays'] as num?)?.toInt() ?? 0,
      reps: (json['reps'] as num?)?.toInt() ?? 0,
      lapses: (json['lapses'] as num?)?.toInt() ?? 0,
      state: FsrsState.values[(json['state'] as num?)?.toInt() ?? 0],
      lastReview: DateTime.tryParse(json['lastReview']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

enum FsrsState { new_, learning, review, relearning }
