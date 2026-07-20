import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/components/shared/slot_scale.dart';

/// Empty state widget — shown when there's no data to display.
///
/// 三级自适应：
/// - 高度 < 60px：超紧凑（纯文本单行，无图标，min padding）
/// - 高度 < 150px：紧凑（小图标 + 文字）
/// - 正常：完整布局，SlotScale 等比缩放
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? semanticLabel;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.subtitle,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = SlotScale.of(context).scale;

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;

        // ── 超紧凑：仅有单行文字 ──
        if (h.isFinite && h < 60) {
          return Semantics(
            label: semanticLabel ?? title,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11 * s,
                  ),
                ),
              ),
            ),
          );
        }

        // ── 紧凑：小图标 + 标题 ──
        if (h.isFinite && h < 150) {
          return Semantics(
            label: semanticLabel ?? title,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(12 * s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 24 * s,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4)),
                    SizedBox(height: 6 * s),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12 * s,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // ── 正常：完整布局 ──
        return Semantics(
          label: semanticLabel ?? title,
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(48 * s),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 64 * s,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                  ),
                  SizedBox(height: 16 * s),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: (theme.textTheme.titleMedium?.fontSize ?? 16) * s,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 8 * s),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                        fontSize: (theme.textTheme.bodySmall?.fontSize ?? 12) * s,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
