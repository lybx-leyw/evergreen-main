import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/flow_scheduler.dart';
import '../../zdbk/providers/zdbk_provider.dart';
import '../../../core/result.dart';
import '../../../core/models/timetable_session.dart';

/// ZJU class period start times (0-indexed: period 1 = 08:00).
/// Mirrors the mapping in ICalExporter._periodStartTimes.
const List<String> _periodStartTimes = [
  '08:00', '08:50', '09:50', '10:40', '11:30',
  '13:15', '14:05', '15:05', '15:55', '16:45',
  '18:30', '19:20', '20:10', '21:00',
];

/// Each period is 45 minutes.
const int _periodDurationMinutes = 45;

/// Parse "HH:MM" string into (hour, minute).
(int hour, int minute) _parseTime(String t) {
  final parts = t.split(':');
  return (int.parse(parts[0]), int.parse(parts[1]));
}

/// Convert a period number (1-based) to a (startMinutes, endMinutes) pair
/// measured from midnight.
(int startMinutes, int endMinutes) _periodToMinutes(int period) {
  final idx = (period - 1).clamp(0, _periodStartTimes.length - 1);
  final (sh, sm) = _parseTime(_periodStartTimes[idx]);
  final start = sh * 60 + sm;
  return (start, start + _periodDurationMinutes);
}

/// Build available [TimeSlot]s for [date] by subtracting busy periods
/// (course sessions) from the default daily ranges.
///
/// Default ranges (if no ZDBK data is available or on weekends):
///   morning:   08:00 - 12:00
///   afternoon: 13:00 - 18:00
///   evening:   19:00 - 22:00
///
/// When a course occupies time within one of these ranges, that occupied
/// sub-range is removed. If the course fully covers a range, the range is
/// omitted entirely.
List<TimeSlot> _buildSlotsForDay(DateTime date, List<TimetableSession> sessions) {
  const defaultRanges = <(int, int)>[
    (8 * 60, 12 * 60),   // 08:00 - 12:00
    (13 * 60, 18 * 60),  // 13:00 - 18:00
    (19 * 60, 22 * 60),  // 19:00 - 22:00
  ];

  final dayOfWeek = date.weekday; // DateTime.monday = 1

  // Collect busy intervals for this day of week from the timetable.
  final busyIntervals = sessions
      .where((s) => s.dayOfWeek == dayOfWeek)
      .expand((s) => s.periods.map((p) {
            final (start, _) = _periodToMinutes(p);
            return (start, start + _periodDurationMinutes);
          }))
      .fold(<(int, int)>[], (list, interval) => _mergeInterval(list, interval));

  final slots = <TimeSlot>[];
  for (final (rangeStart, rangeEnd) in defaultRanges) {
    final free = _subtractIntervals((rangeStart, rangeEnd), busyIntervals);
    for (final (freeStart, freeEnd) in free) {
      if (freeEnd - freeStart < 25) continue; // skip gaps too small for one work block
      slots.add(TimeSlot(
        start: DateTime(date.year, date.month, date.day)
            .add(Duration(minutes: freeStart)),
        end: DateTime(date.year, date.month, date.day)
            .add(Duration(minutes: freeEnd)),
      ));
    }
  }

  return slots;
}

/// Merge a new (start, end) interval into a sorted list of non-overlapping
/// intervals, producing a new sorted list.
List<(int, int)> _mergeInterval(List<(int, int)> intervals, (int, int) next) {
  if (intervals.isEmpty) return [next];
  final result = <(int, int)>[];
  var (ns, ne) = next;
  for (final (s, e) in intervals) {
    if (e < ns) {
      result.add((s, e));
    } else if (s > ne) {
      result.add((ns, ne));
      ns = s;
      ne = e;
    } else {
      ns = ns < s ? ns : s;
      ne = ne > e ? ne : e;
    }
  }
  result.add((ns, ne));
  return result;
}

/// Subtract a list of busy intervals from a single outer interval.
/// Returns the resulting free intervals (gaps).
List<(int, int)> _subtractIntervals((int, int) outer, List<(int, int)> inners) {
  var (os, oe) = outer;
  final result = <(int, int)>[];
  for (final (ins, ine) in inners) {
    if (ine <= os || ins >= oe) continue; // no overlap
    if (ins > os) {
      result.add((os, ins)); // free before busy
    }
    os = os > ine ? os : ine; // advance start past this busy block
    if (os >= oe) break;
  }
  if (os < oe) {
    result.add((os, oe)); // remaining free after last busy
  }
  return result;
}

/// Scheduler state.
class SchedulerState {
  final List<FlowTask> tasks;
  final ScheduleResult? result;

  const SchedulerState({this.tasks = const [], this.result});

  SchedulerState copyWith({List<FlowTask>? tasks, ScheduleResult? result}) {
    return SchedulerState(
      tasks: tasks ?? this.tasks,
      result: result,
    );
  }
}

class SchedulerNotifier extends StateNotifier<SchedulerState> {
  final Ref _ref;

  SchedulerNotifier(this._ref) : super(const SchedulerState());

  void addTask(String description, int minutes) {
    final task = FlowTask(
      id: 'task_${state.tasks.length}',
      description: description,
      timeNeededMinutes: minutes,
    );
    state = state.copyWith(
      tasks: [...state.tasks, task],
      result: null, // Clear previous result when tasks change
    );
  }

  void removeTask(int index) {
    final updated = List<FlowTask>.from(state.tasks);
    if (index >= 0 && index < updated.length) {
      updated.removeAt(index);
      state = state.copyWith(tasks: updated, result: null);
    }
  }

  /// Run the scheduler against the current task list.
  ///
  /// Dynamically generates available time slots by reading the ZDBK course
  /// timetable and subtracting course-occupied periods from the default
  /// 08:00-12:00, 13:00-18:00, 19:00-22:00 daily ranges.
  /// Falls back to hardcoded slots when ZDBK timetable is unavailable.
  void schedule() {
    if (state.tasks.isEmpty) return;

    final now = DateTime.now();

    // Attempt to read ZDBK timetable data. If not yet loaded, fall back to
    // the hardcoded default slots (backward compatible).
    List<TimetableSession> sessions = [];
    try {
      final timetableResult = _ref.read(zdbkTimetableProvider).valueOrNull;
      if (timetableResult != null && timetableResult.isOk) {
        sessions = (timetableResult as Ok<List<TimetableSession>>).value;
      }
    } catch (_) {
      sessions = [];
    }

    List<TimeSlot> slots;
    if (sessions.isEmpty) {
      // Fallback: hardcoded default slots (original behavior)
      slots = [
        TimeSlot(
          start: DateTime(now.year, now.month, now.day, 8, 0),
          end: DateTime(now.year, now.month, now.day, 12, 0),
        ),
        TimeSlot(
          start: DateTime(now.year, now.month, now.day, 13, 0),
          end: DateTime(now.year, now.month, now.day, 18, 0),
        ),
        TimeSlot(
          start: DateTime(now.year, now.month, now.day, 19, 0),
          end: DateTime(now.year, now.month, now.day, 22, 0),
        ),
      ];
    } else {
      slots = _buildSlotsForDay(now, sessions);
      // If all slots were consumed by courses (heavy day), fall back to defaults
      // so the user still has something to work with.
      if (slots.isEmpty) {
        slots = [
          TimeSlot(
            start: DateTime(now.year, now.month, now.day, 8, 0),
            end: DateTime(now.year, now.month, now.day, 12, 0),
          ),
          TimeSlot(
            start: DateTime(now.year, now.month, now.day, 13, 0),
            end: DateTime(now.year, now.month, now.day, 18, 0),
          ),
          TimeSlot(
            start: DateTime(now.year, now.month, now.day, 19, 0),
            end: DateTime(now.year, now.month, now.day, 22, 0),
          ),
        ];
      }
    }

    final result = FlowScheduler.schedule(
      workTimeMinutes: 25,
      maxRestMinutes: 10,
      tasks: state.tasks,
      availableSlots: slots,
    );
    state = state.copyWith(result: result);
  }
}

final schedulerProvider =
    StateNotifierProvider<SchedulerNotifier, SchedulerState>((ref) {
  return SchedulerNotifier(ref);
});
