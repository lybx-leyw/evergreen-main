/// 抽奖转盘 slot——自绘交互式转盘，数据从 manifest config 读取。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/lottery_wheel.dart';

/// 从 hex 字符串（如 "#2ECC71"）解析 [Color]，失败返回 fallback。
Color _parseHex(String hex, Color fallback) {
  try {
    final s = hex.replaceFirst('#', '');
    if (s.length == 6) {
      return Color(int.parse('FF$s', radix: 16));
    }
  } catch (_) {}
  return fallback;
}

class LotteryWheelSlot extends StatelessWidget {
  final ComponentDescriptor config;
  const LotteryWheelSlot({required this.config});

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final lottery = cfg['lottery'] as Map<String, dynamic>? ?? const {};
    final title = lottery['title'] as String? ?? '抽奖转盘';
    final subtitle = lottery['subtitle'] as String? ?? '';
    final buttonText = lottery['buttonText'] as String? ?? '开始';
    final rawSegments =
        (lottery['segments'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final segments = rawSegments.map((s) {
      final label = s['label'] as String? ?? '?';
      final colorHex = s['color'] as String? ?? '#3498DB';
      return WheelSegment(
        label: label,
        color: _parseHex(colorHex, Colors.blue),
      );
    }).toList();

    if (segments.length < 2) {
      // 至少要有 2 个分区
      return Center(
        child: Text(
          '配置的分区 < 2，至少需要 2 个奖项',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final theme = Theme.of(context);
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          LotteryWheel(
            segments: segments,
            spinLabel: buttonText,
          ),
        ],
      ),
    );
  }
}
