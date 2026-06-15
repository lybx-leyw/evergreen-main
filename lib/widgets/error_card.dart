import 'package:flutter/material.dart';

/// Error display widget — used when API calls fail.
/// Shows an error icon, message, optional detail, recovery hint, and retry button.
class ErrorCard extends StatelessWidget {
  final String message;
  final String? detail;
  final String? hint;
  final VoidCallback? onRetry;
  final String? semanticLabel;

  const ErrorCard({
    super.key,
    required this.message,
    this.detail,
    this.hint,
    this.onRetry,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final label = semanticLabel ?? message;
    return Center(
      child: Semantics(
        label: label,
        button: onRetry != null,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (detail != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    detail!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                if (hint != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withAlpha(80),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lightbulb_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            hint!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
