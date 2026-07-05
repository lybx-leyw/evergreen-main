import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../providers/classroom_provider.dart';
import '../services/classroom_crawler.dart';
import '../screens/classroom_viewer_screen.dart';
import '../../../widgets/loading_indicator.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/freshness_badge.dart';

class ClassroomScreen extends ConsumerStatefulWidget {
  const ClassroomScreen({super.key});
  @override
  ConsumerState<ClassroomScreen> createState() => _ClassroomScreenState();
}

class _ClassroomScreenState extends ConsumerState<ClassroomScreen> {
  ClassroomCourse? _selectedCourse;

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(classroomCoursesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('智云课堂'),
        actions: const [FreshnessBadge(cacheKey: 'classroom_courses')],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: coursesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => ErrorCard(message: '加载课程失败: $e'),
              data: (result) => result.fold(
                (courses) => DropdownButtonFormField<ClassroomCourse>(
                  value: _selectedCourse,
                  decoration: const InputDecoration(
                      labelText: '选择课程',
                      border: OutlineInputBorder()),
                  items: courses
                      .map((c) => DropdownMenuItem(
                          value: c, child: Text(c.title)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedCourse = v),
                ),
                (error) => ErrorCard(
                    message: error.userMessage,
                    hint: error.recoveryHint),
              ),
            ),
          ),
          if (_selectedCourse != null)
            Expanded(child: _buildVideos(_selectedCourse!.id)),
        ],
      ),
    );
  }

  Widget _buildVideos(int courseId) {
    final videosAsync = ref.watch(classroomVideosProvider(courseId));
    return videosAsync.when(
      loading: () => const LoadingWidget(message: '加载视频列表...'),
      error: (e, _) => ErrorCard(message: '加载视频失败: $e'),
      data: (result) => result.fold(
        (videos) {
          if (videos.isEmpty)
            return const EmptyState(
                icon: Icons.video_library, title: '暂无视频');
          return ListView.builder(
            itemCount: videos.length,
            itemBuilder: (_, i) {
              final v = videos[i];
              return Card(
                child: ListTile(
                  title: Text(v.title),
                  subtitle: Text(v.startAt ?? ''),
                  trailing: TextButton(
                    onPressed: () =>
                        _openViewer(v.courseId, v.subId, v.title),
                    child: const Text('查看内容'),
                  ),
                ),
              );
            },
          );
        },
        (error) => ErrorCard(
            message: error.userMessage, hint: error.recoveryHint),
      ),
    );
  }

  void _openViewer(int courseId, int subId, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClassroomViewerScreen(
          courseId: courseId,
          subId: subId,
          title: title,
        ),
      ),
    );
  }
}
