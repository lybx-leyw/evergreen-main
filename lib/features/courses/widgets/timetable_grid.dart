import 'package:flutter/material.dart';
import '../../../core/models/timetable_session.dart';

/// 课表周视图网格 — 自适应尺寸 + 深色模式兼容。
class TimetableGrid extends StatelessWidget {
  final List<TimetableSession> sessions;

  const TimetableGrid({super.key, required this.sessions});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final labelW = 28.0;
        final colW = ((constraints.maxWidth - labelW) / 7).clamp(56.0, 140.0);
        // 行高：宽度缩放 + 高度上限防止 bottom overflow
        final rowH = (colW * 0.45).clamp(0.0, (constraints.maxHeight - 24) / 13);
        final totalH = 13 * rowH;

        // 构建格子数据
        final grid = List.generate(
            13, (_) => List.generate(7, (_) => <TimetableSession>[]));
        for (final s in sessions) {
          for (final p in s.periods) {
            if (p >= 1 && p <= 13) {
              grid[p - 1][s.dayOfWeek - 1].add(s);
            }
          }
        }

        // 合并连续同课为一个卡片
        final cards = <Widget>[];
        for (var col = 0; col < 7; col++) {
          var row = 0;
          while (row < 13) {
            if (grid[row][col].isEmpty) {
              row++;
              continue;
            }
            final name = grid[row][col].first.courseName;
            var span = 1;
            for (var r = row + 1; r < 13; r++) {
              if (grid[r][col].isEmpty) break;
              if (grid[r][col].first.courseName != name) break;
              span++;
            }
            final sessionsInCell = grid[row][col];
            cards.add(Positioned(
              top: row * rowH,
              left: labelW + col * colW + 1,
              width: colW - 2,
              height: span * rowH - 1,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                      width: 1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: sessionsInCell
                      .take(2)
                      .map((s) => Text(
                            s.courseName,
                            style: TextStyle(
                              fontSize: (colW * 0.10).clamp(9.0, 13.0),
                              height: 1.2,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ))
                      .toList(),
                ),
              ),
            ));
            row += span;
          }
        }

        return SingleChildScrollView(
          child: SizedBox(
            width: labelW + 7 * colW,
            child: Column(
              children: [
                // Header
                Row(children: [
                  SizedBox(width: labelW, height: 24),
                  ...'一二三四五六日'.split('').map((d) => Container(
                        width: colW,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                              width: 0.5),
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                        child: Text('周$d',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface)),
                      )),
                ]),
                // Grid
                SizedBox(
                  height: totalH,
                  child: Stack(
                    children: [
                      // 网格线
                      ...List.generate(13, (p) => Positioned(
                            top: p * rowH,
                            left: 0,
                            child: Row(children: [
                              Container(
                                width: labelW,
                                height: rowH,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: theme.colorScheme.outlineVariant,
                                      width: 0.5),
                                ),
                                child: Text('${p + 1}',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: theme
                                            .colorScheme.onSurfaceVariant)),
                              ),
                              ...List.generate(7, (d) => Container(
                                    width: colW,
                                    height: rowH,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: theme
                                              .colorScheme.outlineVariant,
                                          width: 0.5),
                                    ),
                                  )),
                            ]),
                          )),
                      // 课程卡片
                      ...cards,
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
