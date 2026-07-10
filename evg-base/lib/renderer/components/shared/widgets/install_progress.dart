/// 安装进度组件——进度条 + 状态文本 + 完成动画。
///
/// 用于插件详情页、市场卡片等的安装进度展示。
import 'package:flutter/material.dart';
import 'models.dart';

/// 安装进度条 + 状态文本。
class InstallProgressWidget extends StatelessWidget {
  final InstallProgress progress;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  const InstallProgressWidget({
    super.key,
    required this.progress,
    this.onRetry,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCompleted = progress.status == InstallStatus.completed;
    final isFailed = progress.status == InstallStatus.failed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isCompleted && !isFailed) ...[
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress.progress,
              minHeight: 6,
              backgroundColor: scheme.outline.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
            ),
          ),
          const SizedBox(height: 6),
        ],
        // 状态文本
        Row(
          children: [
            if (isCompleted)
              Icon(Icons.check_circle, size: 14, color: Colors.green)
            else if (isFailed)
              Icon(Icons.error, size: 14, color: scheme.error)
            else
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                ),
              ),
            const SizedBox(width: 6),
            Text(
              progress.message ?? progress.status.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isFailed
                    ? scheme.error
                    : isCompleted
                        ? Colors.green
                        : scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (!isCompleted && !isFailed)
              Text(
                ' ${(progress.progress * 100).toInt()}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            const Spacer(),
            // 操作按钮
            if (isFailed && onRetry != null)
              _MiniButton(
                label: '重试',
                icon: Icons.refresh,
                onTap: onRetry,
              ),
            if (!isCompleted && !isFailed && onCancel != null)
              _MiniButton(
                label: '取消',
                icon: Icons.close,
                onTap: onCancel,
              ),
          ],
        ),
      ],
    );
  }
}

/// 安装状态徽章——用于卡片角标。
class InstallBadge extends StatelessWidget {
  final bool installed;
  final bool hasUpdate;

  const InstallBadge({
    super.key,
    this.installed = false,
    this.hasUpdate = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!installed) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: hasUpdate ? const Color(0xFFFA8C16) : const Color(0xFF2DA44E),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        hasUpdate ? '更新' : '已安装',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _MiniButton({
    required this.label,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
