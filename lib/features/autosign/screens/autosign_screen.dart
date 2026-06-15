import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/autosign_provider.dart';
import '../services/autosign_service.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/theme.dart';

class AutosignScreen extends ConsumerWidget {
  const AutosignScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRunning = ref.watch(autosignRunningProvider);
    final logs = ref.watch(autosignLogProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('自动签到')),
      body: Column(
        children: [
          // Control section
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isRunning ? AppTheme.successGreen : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(isRunning ? '运行中' : '已停止'),
                    ],
                  ),
                  const SizedBox(width: 32),
                  FilledButton.icon(
                    onPressed: () {
                      if (isRunning) {
                        ref.read(autosignLogProvider.notifier).stop();
                        ref.read(autosignRunningProvider.notifier).state = false;
                      } else {
                        ref.read(autosignLogProvider.notifier).start();
                        ref.read(autosignRunningProvider.notifier).state = true;
                      }
                    },
                    icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
                    label: Text(isRunning ? '停止' : '启动'),
                    style: FilledButton.styleFrom(
                      backgroundColor: isRunning ? AppTheme.dangerRed : AppTheme.zjuBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Log area
          Expanded(
            child: logs.isEmpty
                ? const Center(child: Text('启动自动签到后，日志将显示在这里', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (_, i) {
                      final entry = logs[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        child: Row(
                          children: [
                            Text('${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')} ',
                                style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'monospace')),
                            Expanded(child: Text(entry.message, style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
