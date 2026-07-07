/// Palace 快速捕捉弹窗。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/palace/capture/quick_capture_service.dart' show CaptureResult;
import '../../../core/palace/models/consciousness_event.dart' show EventType;
import '../providers/palace_capture_provider.dart';
import '../widgets/emotion_selector.dart';

/// 快速捕捉弹窗——由 `showDialog` 调用。
class CaptureDialog extends ConsumerStatefulWidget {
  const CaptureDialog({super.key});

  /// 显示捕捉弹窗。
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const CaptureDialog(),
    );
  }

  @override
  ConsumerState<CaptureDialog> createState() => _CaptureDialogState();
}

class _CaptureDialogState extends ConsumerState<CaptureDialog> {
  final _controller = TextEditingController();
  final _tagController = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final captureState = ref.watch(palaceCaptureProvider);
    final notifier = ref.read(palaceCaptureProvider.notifier);
    final theme = Theme.of(context);

    // 同步 TextEditingController 与 state
    if (_controller.text != captureState.content &&
        !captureState.isLoading) {
      _controller.text = captureState.content;
    }

    return AlertDialog(
      title: const Row(
        children: [
          Text('捕捉到 Palace'),
        ],
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 加载状态
              if (captureState.isLoading)
                _buildLoading(theme, captureState.loadingStage),

              // 捕捉结果
              if (captureState.lastResult != null && !captureState.isLoading)
                _buildResult(theme, captureState.lastResult!, notifier),

              // 输入区域（结果展示时隐藏）
              if (captureState.lastResult == null && !captureState.isLoading) ...[
                // 类型选择
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '类型',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<EventType>(
                      value: captureState.selectedType,
                      isDense: true,
                      isExpanded: true,
                      items: EventType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(_typeName(type)),
                        );
                      }).toList(),
                      onChanged: (t) => notifier.updateType(t!),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 内容输入
                TextField(
                  controller: _controller,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: '输入你想记住的内容...',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: notifier.updateContent,
                ),
                const SizedBox(height: 12),

                // 情绪
                Row(
                  children: [
                    const Text('情绪：', style: TextStyle(fontSize: 13)),
                    EmotionSelector(
                      selected: captureState.emotionalValence,
                      onChanged: notifier.updateEmotion,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 标签
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tagController,
                        decoration: const InputDecoration(
                          hintText: '添加标签...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (tag) {
                          notifier.addTag(tag.trim());
                          _tagController.clear();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        notifier.addTag(_tagController.text.trim());
                        _tagController.clear();
                      },
                    ),
                  ],
                ),
                if (captureState.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: captureState.tags.map((t) => Chip(
                      label: Text(t, style: const TextStyle(fontSize: 12)),
                      onDeleted: () => notifier.removeTag(t),
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                ],
                const SizedBox(height: 8),

                // 错误信息
                if (captureState.errorMessage != null)
                  Text(captureState.errorMessage!,
                      style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (captureState.lastResult != null && !captureState.isLoading)
          TextButton(
            onPressed: () {
              notifier.finish();
              Navigator.of(context).pop();
            },
            child: const Text('完成'),
          )
        else ...[
          TextButton(
            onPressed: captureState.isLoading ? null : () {
              notifier.close();
              Navigator.of(context).pop();
            },
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: captureState.isLoading ? null : notifier.submit,
            child: const Text('💎 存入宫殿'),
          ),
        ],
      ],
    );
  }

  Widget _buildLoading(ThemeData theme, String? stage) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(stage ?? '正在处理...',
              style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildResult(ThemeData theme, CaptureResult result,
      PalaceCaptureNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600),
            const SizedBox(width: 8),
            const Text('已存入 Palace', style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        if (result.event.aiSummary != null && result.event.aiSummary!.isNotEmpty)
          Text(result.event.aiSummary!,
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic)),
        if (result.lesson != null) ...[
          const SizedBox(height: 16),
          const Text('AI 初步提炼的教训：',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.lesson!.corePrinciple,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (result.lesson!.elaboration.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(result.lesson!.elaboration,
                      style: const TextStyle(fontSize: 13)),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: notifier.dismissLesson,
                      child: const Text('忽略', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: notifier.confirmLesson,
                      child: const Text('确认教训', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (result.followUpQuestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('追问：', style: TextStyle(fontSize: 12, color: Colors.grey)),
          for (final q in result.followUpQuestions)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(fontSize: 13)),
                  Expanded(child: Text(q, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
        ],
      ],
    );
  }

  String _typeName(EventType type) => switch (type) {
    EventType.thought => '💡 想法',
    EventType.lesson => '📖 教训',
    EventType.decision => '🎯 决策',
    EventType.reflection => '🪞 反思',
    EventType.connection => '🔗 连接',
    EventType.milestone => '🏔️ 节点',
  };
}
