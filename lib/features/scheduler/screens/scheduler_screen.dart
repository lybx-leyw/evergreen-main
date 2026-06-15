import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/scheduler_provider.dart';
import '../services/flow_scheduler.dart';

/// Flow scheduler screen — time block scheduling.
///
/// Uses Riverpod SchedulerNotifier for state management.
class SchedulerScreen extends ConsumerStatefulWidget {
  const SchedulerScreen({super.key});
  @override
  ConsumerState<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends ConsumerState<SchedulerScreen> {
  final _descController = TextEditingController();
  final _minutesController = TextEditingController();

  @override
  void dispose() {
    _descController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(schedulerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('智能调度'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            tooltip: '自动调度',
            onPressed:
                state.tasks.isNotEmpty ? () => ref.read(schedulerProvider.notifier).schedule() : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // Task input
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _descController,
                      decoration: const InputDecoration(
                        hintText: '任务描述',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _minutesController,
                      decoration: const InputDecoration(
                        hintText: '分钟',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle),
                    onPressed: _addTask,
                  ),
                ],
              ),
            ),
          ),
          // Task list
          if (state.tasks.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: state.tasks.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(state.tasks[i].description),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${state.tasks[i].timeNeededMinutes} 分钟'),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 18),
                        onPressed: () =>
                            ref.read(schedulerProvider.notifier).removeTask(i),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Result
          if (state.result != null) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                state.result!.isValid
                    ? '✅ 调度完成 (休息: ${state.result!.restTimeMinutes} 分钟)'
                    : '❌ 时间不足以完成所有任务',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (state.result!.blocks.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: state.result!.blocks.length,
                  itemBuilder: (_, i) {
                    final b = state.result!.blocks[i];
                    return ListTile(
                      leading: Icon(
                        b.isRest ? Icons.coffee : Icons.task,
                        color: b.isRest ? Colors.orange : Colors.blue,
                      ),
                      title: Text(b.description),
                      subtitle: Text(
                        '${b.startTime.hour}:${b.startTime.minute.toString().padLeft(2, '0')} - '
                        '${b.endTime.hour}:${b.endTime.minute.toString().padLeft(2, '0')}',
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _addTask() {
    final desc = _descController.text.trim();
    final minutes = int.tryParse(_minutesController.text.trim());
    if (desc.isEmpty || minutes == null || minutes <= 0) return;
    ref.read(schedulerProvider.notifier).addTask(desc, minutes);
    _descController.clear();
    _minutesController.clear();
  }
}
