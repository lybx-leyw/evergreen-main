import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/result.dart';
import '../../../core/utils/auto_refresh.dart';
import '../../../features/zdbk/providers/zdbk_provider.dart';
import '../providers/courses_provider.dart';
import '../models/course.dart';
import '../widgets/timetable_grid.dart';
import '../../../widgets/loading_indicator.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/freshness_badge.dart';

/// Courses screen — displays enrolled courses list and weekly timetable.
class CoursesScreen extends ConsumerStatefulWidget {
  const CoursesScreen({super.key});

  @override
  ConsumerState<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends ConsumerState<CoursesScreen> {
  String _searchQuery = '';
  bool _showTimetable = false;
  int _timetableYear = 0;
  int _timetableSeason = 1; // 按位: 春=1, 夏=2, 秋=4, 冬=8

  String get _currentTimetableCacheKey {
    final now = DateTime.now();
    final isAW = now.month >= 9 || now.month <= 2;
    return 'zdbk_Timetable${isAW ? now.year : now.year - 1}_${isAW ? 3 : 12}';
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      // 不再自动刷新：前端永远读缓存
    });
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_showTimetable ? '课表' : '课程列表'),
        actions: [
          FreshnessBadge(cacheKey: _currentTimetableCacheKey),
          IconButton(
            icon: Icon(_showTimetable ? Icons.list : Icons.calendar_view_week),
            tooltip: _showTimetable ? '列表视图' : '课表视图',
            onPressed: () {
              setState(() {
                _showTimetable = !_showTimetable;
                if (_showTimetable && _timetableYear == 0) {
                  final now = DateTime.now();
                  _timetableYear = now.month >= 9 ? now.year : now.year - 1;
                  _timetableSeason = 1; // 默认春
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(coursesListProvider),
          ),
        ],
      ),
      body: _showTimetable ? _buildTimetable() : _buildCourseList(coursesAsync),
    );
  }

  Widget _buildCourseList(AsyncValue<Result<List<Course>>> coursesAsync) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              hintText: '搜索课程名称或教师...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _searchQuery = value.trim()),
          ),
        ),
        Expanded(
          child: coursesAsync.when(
            loading: () => const LoadingWidget(message: '加载课程列表...'),
            error: (err, _) => ErrorCard(
              message: '加载课程失败', detail: err.toString(),
              onRetry: () => ref.invalidate(coursesListProvider),
            ),
            data: (result) => result.fold(
              (courses) {
                final filtered = _searchQuery.isEmpty
                    ? courses
                    : courses.where((c) {
                        final q = _searchQuery.toLowerCase();
                        return c.name.toLowerCase().contains(q) ||
                            (c.teacherName?.toLowerCase().contains(q) ?? false) ||
                            (c.courseCode?.toLowerCase().contains(q) ?? false);
                      }).toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.school_outlined,
                    title: _searchQuery.isNotEmpty ? '未找到匹配的课程' : '暂无课程',
                    subtitle: _searchQuery.isNotEmpty ? '尝试其他搜索词' : '请检查是否已登录',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _CourseTile(course: filtered[i]),
                );
              },
              (error) => ErrorCard(
                message: error.userMessage, hint: error.recoveryHint,
                onRetry: () => ref.invalidate(coursesListProvider),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimetable() {
    final semKey = '$_timetableYear-$_timetableSeason';
    final timetableAsync = ref.watch(zdbkTimetableBySemesterProvider(semKey));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('学年', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _timetableYear,
                items: [2023, 2024, 2025, 2026, 2027].map((y) => DropdownMenuItem(
                  value: y, child: Text('$y-${y+1}', style: const TextStyle(fontSize: 13)),
                )).toList(),
                onChanged: (v) => setState(() => _timetableYear = v ?? _timetableYear),
              ),
              const SizedBox(width: 16),
              const Text('学期', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _timetableSeason,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('春', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 2, child: Text('夏', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 4, child: Text('短①', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 8, child: Text('秋', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 16, child: Text('冬', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 32, child: Text('短②', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 64, child: Text('暑', style: TextStyle(fontSize: 13))),
                ],
                onChanged: (v) => setState(() => _timetableSeason = v ?? _timetableSeason),
              ),
            ],
          ),
        ),
        Expanded(
          child: timetableAsync.when(
            loading: () => const LoadingWidget(message: '加载课表...'),
            error: (err, _) => ErrorCard(
              message: '加载课表失败', detail: err.toString(),
              onRetry: () => ref.invalidate(zdbkTimetableBySemesterProvider(semKey)),
            ),
            data: (result) => result.fold(
              (sessions) {
                // 按学期过滤：ZDBK 忽略 xqm 参数，返回整个学年的课
                // semester 按位标记：春=1, 夏=2, 秋=4, 冬=8
                final year = _timetableYear;
                final mask = _timetableSeason;
                final filtered = sessions.where((s) =>
                    (s.courseYear == null || s.courseYear == year) &&
                    ((s.semester ?? 0) & mask) != 0).toList();
                if (filtered.isEmpty) {
                  return const EmptyState(icon: Icons.calendar_view_week, title: '暂未获取到课表数据');
                }
                return TimetableGrid(sessions: filtered);
              },
              (error) => ErrorCard(message: error.userMessage, hint: error.recoveryHint,
                  onRetry: () => ref.invalidate(zdbkTimetableBySemesterProvider(semKey))),
            ),
          ),
        ),
      ],
    );
  }
}

class _CourseTile extends ConsumerWidget {
  final Course course;
  const _CourseTile({required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(course.name),
      subtitle: Text(
        [if (course.teacherName != null) course.teacherName!,
          if (course.courseTypeName != null) course.courseTypeName!,
          course.statusLabel,
        ].join(' · '),
      ),
      trailing: Wrap(spacing: 8, children: [
        IconButton(icon: const Icon(Icons.person_search), tooltip: '查老师评分',
          onPressed: () => context.go('/teachers')),
        IconButton(icon: const Icon(Icons.download), tooltip: '下载资料',
          onPressed: () {
            ref.read(selectedCourseIdProvider.notifier).state = course.id;
            context.go('/downloads');
          }),
        IconButton(icon: const Icon(Icons.grade), tooltip: '查看成绩',
          onPressed: () => context.go('/scores')),
      ]),
    );
  }
}

