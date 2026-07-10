/// 差异对比器槽位——从 [ComponentDescriptor.config] 读取双栏 diff 行。
///
/// 支持两种输入：
/// - `config.lines[]`：每行 `{type: same|add|del, text}`
/// - `config.left` / `config.right`：两段文本，按行做简单对比
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 差异对比器——`diff-viewer` 组件。
class DiffViewerSlot extends StatelessWidget {
  final ComponentDescriptor config;

  const DiffViewerSlot({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final leftLabel = cfg['leftLabel'] as String? ?? '原文件';
    final rightLabel = cfg['rightLabel'] as String? ?? '新文件';
    final theme = Theme.of(context);

    final lines = _parseLines(cfg);
    if (lines.isEmpty) {
      return _emptyState(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(leftLabel,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: Text(rightLabel,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: lines.map((l) {
                final color = switch (l.type) {
                  'add' => Colors.green,
                  'del' => Colors.red,
                  _ => theme.colorScheme.onSurface,
                };
                final bg = switch (l.type) {
                  'add' => Colors.green.withValues(alpha: 0.12),
                  'del' => Colors.red.withValues(alpha: 0.12),
                  _ => Colors.transparent,
                };
                final prefix = switch (l.type) {
                  'add' => '+ ',
                  'del' => '- ',
                  _ => '  ',
                };
                return Container(
                  color: bg,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        child: Text(prefix,
                            style: TextStyle(color: color, fontFamily: 'monospace')),
                      ),
                      Expanded(
                        child: SelectableText(
                          l.text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  List<_DiffLine> _parseLines(Map<String, dynamic> cfg) {
    final raw = cfg['lines'];
    if (raw is List && raw.isNotEmpty) {
      return raw.whereType<Map<String, dynamic>>().map((m) {
        return _DiffLine(
          type: m['type'] as String? ?? 'same',
          text: m['text'] as String? ?? '',
        );
      }).toList();
    }
    // 退化：left/right 两段文本按行对比
    final left = cfg['left'] as String? ?? '';
    final right = cfg['right'] as String? ?? '';
    if (left.isEmpty && right.isEmpty) return [];
    final lLines = left.split('\n');
    final rLines = right.split('\n');
    final max = lLines.length > rLines.length ? lLines.length : rLines.length;
    final out = <_DiffLine>[];
    for (var i = 0; i < max; i++) {
      final l = i < lLines.length ? lLines[i] : '';
      final r = i < rLines.length ? rLines[i] : '';
      if (l == r) {
        out.add(_DiffLine(type: 'same', text: l));
      } else {
        if (l.isNotEmpty) out.add(_DiffLine(type: 'del', text: l));
        if (r.isNotEmpty) out.add(_DiffLine(type: 'add', text: r));
      }
    }
    return out;
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.compare, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('未配置 diff 内容 (config.lines / left / right)',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _DiffLine {
  final String type;
  final String text;
  const _DiffLine({required this.type, required this.text});
}
