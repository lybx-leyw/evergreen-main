/// 单场考试卡片——倒计时 + 紧急度配色。
///
/// B3-exams（2026-08-12）自参考工程
/// `cp_evergreen_push/lib/features/exams/widgets/exam_card.dart` 移植，
/// 仅替换 `AppTheme.*` → `ZjuScoreColors.*`（前缀防冲突）。
library;

import 'package:flutter/material.dart';

import '../../shared/models/zju_exam.dart';
import '../../shared/utils/zju_theme_colors.dart';

/// 展示单场考试（课程名 / 考场 / 时间 / 倒计时，左侧紧急度色条）。
class ExamCard extends StatelessWidget {
  final ZjuExam exam;

  const ExamCard({super.key, required this.exam});

  @override
  Widget build(BuildContext context) {
    final urgencyColors = {
      ZjuExamUrgency.past: Colors.grey,
      ZjuExamUrgency.critical: ZjuScoreColors.dangerRed,
      ZjuExamUrgency.soon: ZjuScoreColors.warningOrange,
      ZjuExamUrgency.future: ZjuScoreColors.zjuBlue,
    };

    final color = urgencyColors[exam.urgency]!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exam.name, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  if (exam.location != null)
                    Text(
                      '📍 ${exam.location}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (exam.startTime != null)
                    Text(
                      '🕐 ${exam.startTime!.month}/${exam.startTime!.day} '
                      '${exam.startTime!.hour}:'
                      '${exam.startTime!.minute.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            Text(
              _countdownText,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  String get _countdownText {
    if (exam.startTime == null) return '';
    final diff = exam.startTime!.difference(DateTime.now());
    if (diff.isNegative) return '已结束';

    final parts = <String>[];
    if (diff.inDays > 0) parts.add('${diff.inDays}天');
    final hours = diff.inHours % 24;
    if (hours > 0 || diff.inDays > 0) parts.add('${hours}时');
    parts.add('${diff.inMinutes % 60}分');

    return parts.join('');
  }
}
