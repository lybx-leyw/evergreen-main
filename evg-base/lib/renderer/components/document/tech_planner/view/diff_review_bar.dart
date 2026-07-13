/// AI 改写提案 → Diff 对比栏。
///
/// 接收原文和 AI 改写稿，使用 diff_match_patch 做 Myers diff，
/// 逐条展示 Keep/Discard 选项。
library;

import 'package:flutter/material.dart';
import 'package:diff_match_patch/diff_match_patch.dart';

/// Diff 结果条目。
class DiffChunk {
  final String text;
  final int operation; // DIFF_EQUAL=0, DIFF_DELETE=-1, DIFF_INSERT=1

  const DiffChunk({required this.text, required this.operation});

  bool get isEqual => operation == 0;
  bool get isDelete => operation == -1;
  bool get isInsert => operation == 1;

  Color? get backgroundColor {
    if (isEqual) return null;
    if (isDelete) return Colors.red.withValues(alpha: 0.08);
    return Colors.green.withValues(alpha: 0.08);
  }

  Color? get textColor {
    if (isEqual) return null;
    if (isDelete) return Colors.red.shade400;
    return Colors.green.shade400;
  }
}

/// Diff 对比栏——左右分栏显示原文与 AI 改写。
///
/// 提供逐条 Keep/Discard 操作，确认后合并结果。
class DiffReviewBar extends StatefulWidget {
  final String original;
  final String proposed;
  final ValueChanged<String> onApply;

  const DiffReviewBar({
    super.key,
    required this.original,
    required this.proposed,
    required this.onApply,
  });

  @override
  State<DiffReviewBar> createState() => _DiffReviewBarState();
}

class _DiffReviewBarState extends State<DiffReviewBar> {
  late List<Diff> _diffs;
  final Set<int> _discardIndices = {};

  @override
  void initState() {
    super.initState();
    _computeDiffs();
  }

  @override
  void didUpdateWidget(DiffReviewBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.original != widget.original ||
        oldWidget.proposed != widget.proposed) {
      _computeDiffs();
    }
  }

  void _computeDiffs() {
    final dmp = DiffMatchPatch();
    _diffs = dmp.diff(widget.original, widget.proposed);
    _discardIndices.clear();
  }

  String _mergedText() {
    final buf = StringBuffer();
    for (int i = 0; i < _diffs.length; i++) {
      if (_discardIndices.contains(i)) continue;
      final diff = _diffs[i];
      if (diff.operation == DIFF_INSERT) {
        buf.write(diff.text);
      } else if (diff.operation == DIFF_DELETE) {
        // 删除块——保留则写入，丢弃则跳过
        // 这里的逻辑：Keep = 保留删除块（即保留原文），Discard = 采纳插入块（即删除原文）
        // 实际逻辑由按钮控制，这里简化处理
        // Keep 表示保留当前状态（不改变），Discard 表示反向操作
      }
    }

    // 重新计算合并结果
    final result = StringBuffer();
    for (int i = 0; i < _diffs.length; i++) {
      if (_discardIndices.contains(i)) continue;
      final diff = _diffs[i];
      if (diff.operation == DIFF_INSERT) {
        result.write(diff.text);
      } else if (diff.operation == DIFF_EQUAL) {
        result.write(diff.text);
      } else {
        // DIFF_DELETE — Keep 保留（即保留原文中的删除部分）
        // 对于 diff 算法来说 DELETE 是原文有、新文没有的，
        // 所以 Keep 会保留它，Discard 则丢弃
        result.write(diff.text);
      }
    }
    return result.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 标题栏 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.compare_arrows, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('AI 改写对比',
                    style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.primary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => widget.onApply(_mergedText()),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('确认应用'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => widget.onApply(widget.original),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('全部丢弃'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
          ),

          // ── 差异内容 ──
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 文本对比区域
                  _buildDiffView(theme, colorScheme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffView(ThemeData theme, ColorScheme colorScheme) {
    // 按行重新组织 diff
    final chunks = _buildLineChunks();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 图例
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              _legendDot(Colors.green.shade400, '新增'),
              const SizedBox(width: 12),
              _legendDot(Colors.red.shade400, '删除'),
              const SizedBox(width: 12),
              _legendDot(colorScheme.onSurfaceVariant, '未变'),
            ],
          ),
        ),

        // 差异行
        ...chunks.asMap().entries.map((entry) {
          final i = entry.key;
          final chunk = entry.value;
          final isDiscarded = _discardIndices.contains(i);

          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 操作图标 ──
                SizedBox(
                  width: 36,
                  height: 28,
                  child: chunk.isDelete
                      ? _actionButton(
                          i,
                          isDiscarded,
                          Icons.undo,
                          Icons.delete_outline,
                          Colors.red,
                          'Keep = 保留原文',
                          'Discard = 采纳删除',
                        )
                      : chunk.isInsert
                          ? _actionButton(
                              i,
                              isDiscarded,
                              Icons.add_circle_outline,
                              Icons.remove_circle_outline,
                              Colors.green,
                              'Keep = 采纳新增',
                              'Discard = 拒绝新增',
                            )
                          : const SizedBox.shrink(),
                ),

                // ── 文本内容 ──
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDiscarded
                          ? Colors.transparent
                          : chunk.backgroundColor,
                      borderRadius: BorderRadius.circular(3),
                      border: isDiscarded
                          ? Border.all(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.3))
                          : null,
                    ),
                    child: Text(
                      chunk.text.isEmpty ? ' ' : chunk.text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: isDiscarded
                            ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                            : chunk.textColor ?? colorScheme.onSurface,
                        decoration: isDiscarded ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _actionButton(
    int index,
    bool isDiscarded,
    IconData keepIcon,
    IconData discardIcon,
    MaterialColor color,
    String keepTooltip,
    String discardTooltip,
  ) {
    return Tooltip(
      message: isDiscarded ? discardTooltip : keepTooltip,
      child: InkWell(
        onTap: () {
          setState(() {
            if (isDiscarded) {
              _discardIndices.remove(index);
            } else {
              _discardIndices.add(index);
            }
          });
        },
        borderRadius: BorderRadius.circular(4),
        child: Icon(
          isDiscarded ? discardIcon : keepIcon,
          size: 18,
          color: isDiscarded
              ? color.shade100.withValues(alpha: 0.3)
              : color.shade400,
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  /// 将逐字符 diff 重组为逐行 diff 块。
  List<DiffChunk> _buildLineChunks() {
    // 将 diffs 按 newline 拆分，合并连续的同类块
    final chunks = <DiffChunk>[];
    final currentBuf = StringBuffer();
    int currentOp = DIFF_EQUAL;

    for (final diff in _diffs) {
      final lines = diff.text.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final isLast = i == lines.length - 1;

        if (currentOp == diff.operation) {
          currentBuf.write(line);
        } else {
          if (currentBuf.isNotEmpty) {
            chunks.add(DiffChunk(text: currentBuf.toString(), operation: currentOp));
          }
          currentBuf.clear();
          currentBuf.write(line);
          currentOp = diff.operation;
        }

        if (!isLast) {
          currentBuf.write('\n');
        }
      }
    }

    if (currentBuf.isNotEmpty) {
      chunks.add(DiffChunk(text: currentBuf.toString(), operation: currentOp));
    }

    return chunks;
  }
}
