import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/flow_scheduler.dart';

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
  SchedulerNotifier() : super(const SchedulerState());

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
  void schedule() {
    if (state.tasks.isEmpty) return;
    final now = DateTime.now();
    final slots = [
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
  return SchedulerNotifier();
});
