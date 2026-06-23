/// Palace 情绪选择器 —— 表情符号 + 可选滑块。
library;

import 'package:flutter/material.dart';

/// 情绪选项。
class EmotionOption {
  final double value;
  final String emoji;
  final String label;

  const EmotionOption({
    required this.value,
    required this.emoji,
    required this.label,
  });
}

/// 预设情绪选项。
const emotionOptions = [
  EmotionOption(value: 1.0, emoji: '😄', label: '非常正面'),
  EmotionOption(value: 0.5, emoji: '🙂', label: '正面'),
  EmotionOption(value: 0.0, emoji: '😐', label: '中性'),
  EmotionOption(value: -0.5, emoji: '😟', label: '负面'),
  EmotionOption(value: -1.0, emoji: '😡', label: '非常负面'),
];

/// 情绪选择器——点击 emoji 选择情绪效价。
class EmotionSelector extends StatelessWidget {
  final double? selected;
  final ValueChanged<double?> onChanged;

  const EmotionSelector({
    super.key,
    this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: emotionOptions.map((option) {
        final isSelected = selected == option.value;
        return Tooltip(
          message: option.label,
          child: GestureDetector(
            onTap: () {
              if (isSelected) {
                onChanged(null); // 取消选择
              } else {
                onChanged(option.value);
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(color: Theme.of(context).colorScheme.primary)
                    : null,
              ),
              child: Text(option.emoji, style: const TextStyle(fontSize: 24)),
            ),
          ),
        );
      }).toList(),
    );
  }
}
