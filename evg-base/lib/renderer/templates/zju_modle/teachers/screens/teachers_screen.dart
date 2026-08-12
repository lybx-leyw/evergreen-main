/// 查老师视图（zju / teachers）——教师评分搜索。
///
/// B3-teachers（2026-08-13）自参考工程
/// `cp_evergreen_push/lib/features/teachers/screens/teachers_screen.dart`
/// 移植，改造点：
/// - 去 Scaffold/AppBar（evg-base 桌面规范：无 per-module AppBar，页面自绘标题头）；
/// - provider 换 `zjuTeacherSearchProvider` / `zjuTeacherDetailProvider`；
/// - `AppTheme.scoreColor` → `ZjuScoreColors.scoreColor`；EmptyState/ErrorCard
///   按 evg-base 各页惯例内联（参考 exams_screen）；
/// - 搜索框防抖 400ms + 结果列表 + 详情对话框，交互逻辑照抄参考。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/zju_teacher.dart';
import '../../shared/utils/zju_theme_colors.dart';
import '../providers/teachers_provider.dart';

class TeachersView extends ConsumerStatefulWidget {
  const TeachersView({super.key});

  @override
  ConsumerState<TeachersView> createState() => _TeachersViewState();
}

class _TeachersViewState extends ConsumerState<TeachersView> {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        Expanded(
          child: _query.isEmpty ? _buildIdle() : _buildResults(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('查老师', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '清空搜索',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: '搜索教师姓名 / 拼音 / 缩写...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
              helperText: '数据来自 chalaoshi.top（第三方平台），仅供参考',
              helperMaxLines: 1,
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () {
                if (mounted) {
                  setState(() => _query = v.trim());
                }
              });
            },
            onSubmitted: (v) {
              _debounce?.cancel();
              if (mounted) setState(() => _query = v.trim());
            },
          ),
        ],
      ),
    );
  }

  /// 未输入搜索词的空态。
  Widget _buildIdle() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_search, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          const Text('输入教师姓名搜索', style: TextStyle(fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            '本地完整数据集毫秒级匹配，在线评分后台刷新',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final result = ref.watch(zjuTeacherSearchProvider(_query));
    return result.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildError(e.toString()),
      data: (teachers) {
        if (teachers.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_off, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                const Text('未找到相关教师', style: TextStyle(fontSize: 15)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: teachers.length,
          itemBuilder: (_, i) => _buildTile(teachers[i]),
        );
      },
    );
  }

  Widget _buildTile(ZjuTeacherResult t) {
    final color = ZjuScoreColors.scoreColor(t.score);
    final isOnline = t.dataSource == 'online';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        title: Row(
          children: [
            Flexible(
              child: Text(t.name, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            // 数据来源标识
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isOnline ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isOnline ? Colors.green.shade300 : Colors.orange.shade300,
                  width: 0.5,
                ),
              ),
              child: Text(
                isOnline ? '实时' : '缓存',
                style: TextStyle(
                  fontSize: 10,
                  color: isOnline ? Colors.green.shade700 : Colors.orange.shade700,
                ),
              ),
            ),
          ],
        ),
        subtitle: t.college != null ? Text(t.college!) : null,
        trailing: t.score != null
            ? Text(
                t.score!.toStringAsFixed(1),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              )
            : const Text('-'),
        onTap: () => _showDetail(ref, t),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            const Text('搜索失败', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () =>
                  ref.invalidate(zjuTeacherSearchProvider(_query)),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(WidgetRef ref, ZjuTeacherResult teacher) {
    final detailAsync = ref
        .read(zjuTeacherDetailProvider((id: teacher.id, name: teacher.name)));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('教师详情'),
        content: SizedBox(
          width: 320,
          child: detailAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('加载失败: $e'),
            data: (detail) {
              if (detail == null) return const Text('无数据');
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${detail.name} 老师',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (detail.score != null)
                    Text('评分: ${detail.score!.toStringAsFixed(1)}'
                        '（${detail.raters} 人打分）'),
                  if (detail.college != null) Text('学院: ${detail.college}'),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
