/// Flow Scheduler — greedy time block assignment with binary search.
///
/// Ports the algorithm from electron/services/flow-scheduler.js
/// and Celechron's algorithm/arrange.dart.
class FlowScheduler {
  /// Schedule tasks into available time blocks.
  ///
  /// Uses greedy deadline-first algorithm with binary-search optimized rest intervals.
  static ScheduleResult schedule({
    required int workTimeMinutes,
    required int maxRestMinutes,
    required List<FlowTask> tasks,
    required List<TimeSlot> availableSlots,
  }) {
    if (tasks.isEmpty || availableSlots.isEmpty) {
      return ScheduleResult(isValid: false, blocks: [], restTimeMinutes: 0);
    }

    // Sort tasks by deadline (earliest first)
    final sorted = List<FlowTask>.from(tasks)
      ..sort((a, b) => (a.deadline ?? DateTime(2100)).compareTo(b.deadline ?? DateTime(2100)));

    // Sort slots by start time
    final slots = List<TimeSlot>.from(availableSlots)
      ..sort((a, b) => a.start.compareTo(b.start));

    final blocks = <ScheduledBlock>[];
    final remaining = sorted.map((t) => t.timeNeededMinutes).toList();

    // Greedy assignment — slot-by-slot packing with per-slot work accounting
    for (final slot in slots) {
      var slotStart = slot.start;
      final slotEnd = slot.end;
      final slotDuration = slotEnd.difference(slotStart).inMinutes;
      var workSinceLastRest = 0;

      if (slotDuration < workTimeMinutes) continue;

      var slotRemaining = slotDuration;

      for (var i = 0; i < sorted.length; i++) {
        if (remaining[i] <= 0) continue;

        final task = sorted[i];

        // Skip tasks whose deadline is before this slot's cursor — they can't
        // be assigned here and still meet their deadline.
        if (task.deadline != null && slotStart.isAfter(task.deadline!)) continue;

        final duration = [remaining[i], slotRemaining].reduce((a, b) => a < b ? a : b);
        if (duration < workTimeMinutes && remaining[i] > slotRemaining) continue;

        final blockEnd = slotStart.add(Duration(minutes: duration));
        if (blockEnd.isAfter(slotEnd)) continue;

        blocks.add(ScheduledBlock(
          taskId: task.id,
          description: task.description,
          startTime: slotStart,
          endTime: blockEnd,
          location: task.location,
        ));

        remaining[i] -= duration;
        slotStart = blockEnd;
        slotRemaining -= duration;
        workSinceLastRest += duration;

        // Insert rest only when we've accumulated enough work AND there is
        // still slot time remaining for a rest block + at least one more
        // work block.
        if (workSinceLastRest >= workTimeMinutes &&
            slotRemaining >= maxRestMinutes + workTimeMinutes &&
            remaining.any((r) => r > 0)) {
          final restDuration = [maxRestMinutes, slotRemaining ~/ 2].reduce((a, b) => a < b ? a : b);
          final restBlock = ScheduledBlock(
            taskId: 'rest_${blocks.length}',
            description: '休息',
            startTime: slotStart,
            endTime: slotStart.add(Duration(minutes: restDuration)),
            isRest: true,
          );
          blocks.add(restBlock);
          slotStart = slotStart.add(Duration(minutes: restDuration));
          slotRemaining -= restDuration;
          workSinceLastRest = 0;
        }

        if (slotRemaining < workTimeMinutes) break;
      }
    }

    // Binary search for minimum feasible rest time
    final restTimeMinutes = _binarySearchRestTime(workTimeMinutes, maxRestMinutes, sorted, availableSlots);
    final allDone = remaining.every((r) => r <= 0);

    return ScheduleResult(
      isValid: allDone,
      blocks: blocks,
      restTimeMinutes: restTimeMinutes,
    );
  }

  static int _binarySearchRestTime(int workTime, int maxRest, List<FlowTask> tasks, List<TimeSlot> slots) {
    var low = 0, high = maxRest, best = 0;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (_isFeasible(workTime, mid, tasks, slots)) {
        best = mid;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    return best;
  }

  /// Check whether all tasks can be assigned to the given slots when each
  /// work block is followed by at most [restTime] minutes of rest within the
  /// same slot (rest is NOT carried between slots).
  ///
  /// Simulates slot-by-slot packing:
  ///   1. Sort tasks by deadline (earliest first).
  ///   2. For each slot, track accumulated work time and insert rest when
  ///      the accumulated work reaches [workTime] minutes (and there is
  ///      enough remaining slot time for both rest and more work).
  ///   3. If all tasks are exhausted (remaining <= 0), the schedule is feasible.
  static bool _isFeasible(int workTime, int restTime, List<FlowTask> tasks, List<TimeSlot> slots) {
    if (tasks.isEmpty) return true;
    if (slots.isEmpty) return false;

    // Sort tasks by deadline
    final sorted = List<FlowTask>.from(tasks)
      ..sort((a, b) => (a.deadline ?? DateTime(2100)).compareTo(b.deadline ?? DateTime(2100)));

    // Sort slots by start time
    final sortedSlots = List<TimeSlot>.from(slots)
      ..sort((a, b) => a.start.compareTo(b.start));

    // remaining[i] > 0 means task i still needs time
    final remaining = sorted.map((t) => t.timeNeededMinutes).toList();

    // Simulate packing through each slot
    for (final slot in sortedSlots) {
      var slotCursor = slot.start;
      final slotEnd = slot.end;
      var workSinceLastRest = 0;

      for (var i = 0; i < sorted.length; i++) {
        if (remaining[i] <= 0) continue;

        final task = sorted[i];

        // Skip tasks whose deadline is before this slot's cursor — they
        // cannot be assigned here and still meet their deadline.
        if (task.deadline != null && slotCursor.isAfter(task.deadline!)) continue;

        final slotRemaining = slotEnd.difference(slotCursor).inMinutes;
        if (slotRemaining < workTime) break; // not enough room in this slot

        // How much of this task can we fit in this slot?
        final chunk = remaining[i] < slotRemaining ? remaining[i] : slotRemaining;
        if (chunk < workTime && remaining[i] > slotRemaining) continue;

        remaining[i] -= chunk;
        slotCursor = slotCursor.add(Duration(minutes: chunk));
        workSinceLastRest += chunk;

        // Insert rest only if:
        //   - we have accumulated at least [workTime] minutes of work, AND
        //   - there is enough remaining slot time for a rest block + at least
        //     one more work block, AND
        //   - there are still unassigned tasks
        if (workSinceLastRest >= workTime &&
            slotEnd.difference(slotCursor).inMinutes >= restTime + workTime &&
            remaining.any((r) => r > 0)) {
          slotCursor = slotCursor.add(Duration(minutes: restTime));
          workSinceLastRest = 0;
        }
      }

      // If all tasks are done, we are feasible
      if (remaining.every((r) => r <= 0)) return true;
    }

    // If we exit the loop without finishing all tasks, the schedule is not feasible
    return remaining.every((r) => r <= 0);
  }
}

class FlowTask {
  final String id;
  final String description;
  final int timeNeededMinutes;
  final DateTime? deadline;
  final String? location;
  final bool isBreakable;

  const FlowTask({
    required this.id,
    required this.description,
    required this.timeNeededMinutes,
    this.deadline,
    this.location,
    this.isBreakable = true,
  });
}

class TimeSlot {
  final DateTime start;
  final DateTime end;

  const TimeSlot({required this.start, required this.end});
}

class ScheduledBlock {
  final String taskId;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final String? location;
  final bool isRest;

  const ScheduledBlock({
    required this.taskId,
    required this.description,
    required this.startTime,
    required this.endTime,
    this.location,
    this.isRest = false,
  });
}

class ScheduleResult {
  final bool isValid;
  final List<ScheduledBlock> blocks;
  final int restTimeMinutes;

  const ScheduleResult({
    required this.isValid,
    required this.blocks,
    required this.restTimeMinutes,
  });
}
