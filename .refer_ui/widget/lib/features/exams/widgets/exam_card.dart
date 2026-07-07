import 'package:flutter/material.dart';
import '../../../core/models/exam.dart';
import '../../../core/config/theme.dart';

/// Displays a single exam with countdown and urgency color.
class ExamCard extends StatelessWidget {
  final Exam exam;

  const ExamCard({super.key, required this.exam});

  @override
  Widget build(BuildContext context) {
    final urgencyColors = {
      ExamUrgency.past: Colors.grey,
      ExamUrgency.critical: AppTheme.dangerRed,
      ExamUrgency.soon: AppTheme.warningOrange,
      ExamUrgency.future: AppTheme.zjuBlue,
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
                      '🕐 ${exam.startTime!.month}/${exam.startTime!.day} ${exam.startTime!.hour}:${exam.startTime!.minute.toString().padLeft(2, '0')}',
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
