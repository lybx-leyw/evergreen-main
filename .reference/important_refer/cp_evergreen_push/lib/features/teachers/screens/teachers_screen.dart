import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/teachers_provider.dart';
import '../services/chalaoshi_service.dart';
import '../../../core/config/theme.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/error_card.dart';

class TeachersScreen extends ConsumerStatefulWidget {
  const TeachersScreen({super.key});

  @override
  ConsumerState<TeachersScreen> createState() => _TeachersScreenState();
}

class _TeachersScreenState extends ConsumerState<TeachersScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('查老师')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜索教师姓名...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                helperText: '数据来自 chalaoshi.top（第三方平台），仅供参考',
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  if (v.trim().isNotEmpty) {
                    setState(() => _query = v.trim());
                  }
                });
              },
            ),
          ),
          Expanded(
            child: Consumer(
              builder: (context, ref, _) {
                final query = _query;
                if (query.isEmpty) {
                  return const EmptyState(icon: Icons.person_search, title: '输入教师姓名搜索');
                }
                final result = ref.watch(teacherSearchProvider(query));
                return result.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => ErrorCard(
                    message: '搜索失败',
                    detail: e.toString(),
                    onRetry: () => ref.invalidate(teacherSearchProvider(query)),
                  ),
                  data: (teachers) {
                    if (teachers.isEmpty) {
                      return const EmptyState(icon: Icons.person_off, title: '未找到相关教师');
                    }
                    return ListView.builder(
                      itemCount: teachers.length,
                      itemBuilder: (_, i) {
                        final t = teachers[i];
                        final color = AppTheme.scoreColor(t.score);
                        return Card(
                          child: ListTile(
                            title: Row(
                              children: [
                                Flexible(child: Text(t.name, overflow: TextOverflow.ellipsis)),
                                const SizedBox(width: 6),
                                // 数据来源标识
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: t.dataSource == 'online'
                                        ? Colors.green.shade50
                                        : Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: t.dataSource == 'online'
                                          ? Colors.green.shade300
                                          : Colors.orange.shade300,
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    t.dataSource == 'online' ? '实时' : '缓存',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: t.dataSource == 'online'
                                          ? Colors.green.shade700
                                          : Colors.orange.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            trailing: t.score != null
                                ? Text(t.score!.toStringAsFixed(1), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18))
                                : const Text('-'),
                            onTap: () => _showDetail(ref, t),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(WidgetRef ref, TeacherResult teacher) {
    final detailAsync = ref.read(teacherDetailProvider((id: teacher.id, name: teacher.name)));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('教师详情'),
        content: detailAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('加载失败: $e'),
          data: (detail) {
            if (detail == null) return const Text('无数据');
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${detail.name} 老师', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (detail.score != null) Text('评分: ${detail.score!.toStringAsFixed(1)} ($detail.raters 人打分)'),
                if (detail.college != null) Text('学院: ${detail.college}'),
              ],
            );
          },
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭'))],
      ),
    );
  }
}
