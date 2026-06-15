import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/quiz_provider.dart';
import '../../../features/courses/providers/courses_provider.dart';
import '../../../widgets/loading_indicator.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/empty_state.dart';
import '../../../core/config/theme.dart';

/// Quiz screen — classroom quiz answer viewer.
///
/// Ports the functionality from app/js/components/quiz.js.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  int? _selectedCourseId;
  Map<String, dynamic>? _selectedClassroom;

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('答题查看')),
      body: Column(
        children: [
          // Course selector
          Padding(
            padding: const EdgeInsets.all(16),
            child: coursesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => ErrorCard(message: '加载课程失败: $e'),
              data: (result) => result.fold(
                (courses) => DropdownButtonFormField<int>(
                  value: _selectedCourseId,
                  decoration: const InputDecoration(labelText: '选择课程', border: OutlineInputBorder()),
                  items: courses.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (id) => setState(() { _selectedCourseId = id; _selectedClassroom = null; }),
                ),
                (error) => ErrorCard(message: error.userMessage),
              ),
            ),
          ),
          // Classroom selector
          if (_selectedCourseId != null) ...[
            _buildClassroomSelector(),
            if (_selectedClassroom != null) _buildQuestions(),
          ],
        ],
      ),
    );
  }

  Widget _buildClassroomSelector() {
    final classrooms = ref.watch(quizClassroomsProvider(_selectedCourseId!));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: classrooms.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => ErrorCard(
            message: '加载课堂失败',
            detail: e.toString(),
            onRetry: () => ref.invalidate(quizClassroomsProvider(_selectedCourseId!)),
          ),
        data: (result) => result.fold(
          (list) => DropdownButtonFormField<Map<String, dynamic>>(
            value: _selectedClassroom,
            decoration: const InputDecoration(labelText: '选择课堂互动', border: OutlineInputBorder()),
            items: list.map((c) => DropdownMenuItem(
              value: c,
              child: Text(c['title']?.toString() ?? '课堂互动 ${c['id']}'),
            )).toList(),
            onChanged: (v) => setState(() => _selectedClassroom = v),
          ),
          (error) => ErrorCard(message: error.userMessage),
        ),
      ),
    );
  }

  Widget _buildQuestions() {
    final classroomId = _selectedClassroom!['id'] as int;
    final subjects = ref.watch(quizSubjectsProvider(classroomId));

    return Expanded(
      child: subjects.when(
        loading: () => const LoadingWidget(message: '加载题目...'),
        error: (e, _) => ErrorCard(message: '加载题目失败: $e'),
        data: (result) => result.fold(
          (questions) {
            if (questions.isEmpty) {
              return const EmptyState(
                  icon: Icons.quiz_outlined, title: '暂无题目');
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: questions.length,
              itemBuilder: (_, i) {
                final q = questions[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${i + 1}. ${q['title'] ?? q['question'] ?? ''}',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        if (q['options'] is List)
                          ...(q['options'] as List).map((opt) {
                            final isAnswer = opt['is_answer'] == true;
                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isAnswer
                                    ? AppTheme.successGreen
                                        .withValues(alpha: 0.1)
                                    : null,
                                border: Border.all(
                                    color: isAnswer
                                        ? AppTheme.successGreen
                                        : Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  if (isAnswer)
                                    const Icon(Icons.check_circle,
                                        color: AppTheme.successGreen,
                                        size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(
                                          opt['content']?.toString() ?? '')),
                                ],
                              ),
                            );
                          }),
                        if (q['correct_answers'] is List)
                          Text(
                              '正确答案: ${(q['correct_answers'] as List).join(", ")}',
                              style: const TextStyle(
                                  color: AppTheme.successGreen)),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          (error) => ErrorCard(message: error.userMessage),
        ),
      ),
    );
  }
}
