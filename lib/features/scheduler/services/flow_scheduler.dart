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

    // Greedy assignment
    for (final slot in slots) {
      var slotStart = slot.start;
      final slotEnd = slot.end;
      final slotDuration = slotEnd.difference(slotStart).inMinutes;

      if (slotDuration < workTimeMinutes) continue;

      var slotRemaining = slotDuration;

      for (var i = 0; i < sorted.length; i++) {
        if (remaining[i] <= 0) continue;

        final task = sorted[i];
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

        // Add rest period
        if (slotRemaining >= maxRestMinutes && remaining.any((r) => r > 0)) {
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
    // Simplified: return maxRest if schedule is feasible, otherwise binary search
    var low = 0, high = maxRest, best = 0;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      // Check feasibility with `mid` minute rest intervals (simplified check)
      if (_isFeasible(workTime, mid, tasks, slots)) {
        best = mid;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    return best;
  }

  static bool _isFeasible(int workTime, int restTime, List<FlowTask> tasks, List<TimeSlot> slots) {
    final totalNeeded = tasks.fold<int>(0, (sum, t) => sum + t.timeNeededMinutes);
    final totalAvailable = slots.fold<int>(0, (sum, s) => sum + s.end.difference(s.start).inMinutes);
    final restNeeded = tasks.length * restTime;
    return totalAvailable >= totalNeeded + restNeeded;
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
