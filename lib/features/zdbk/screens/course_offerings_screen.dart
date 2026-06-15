/// 开课情况页面 — 显示当前学期的课程安排，支持搜索筛选。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/models/course_offering.dart';
import '../../../widgets/loading_indicator.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/empty_state.dart';
import '../providers/zdbk_provider.dart';

class CourseOfferingsScreen extends ConsumerStatefulWidget {
  const CourseOfferingsScreen({super.key});

  @override
  ConsumerState<CourseOfferingsScreen> createState() =>
      _CourseOfferingsScreenState();
}

class _CourseOfferingsScreenState
    extends ConsumerState<CourseOfferingsScreen> {
  int _year = DateTime.now().month >= 9
      ? DateTime.now().year
      : DateTime.now().year - 1;
  int _semester = DateTime.now().month >= 9 || DateTime.now().month <= 2
      ? 3
      : 12;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  String get _semesterLabel => _semester == 3 ? '秋冬' : '春夏';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[KkqkUI:D] build() year=$_year semester=$_semester search="$_searchQuery"');
    final async =
        ref.watch(courseOfferingsProvider((year: _year, semester: _semester)));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('开课情况'),
            Text('${_year}-${_year + 1}学年 · ${_semesterLabel}学期',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          // 学年选择
          PopupMenuButton<int>(
            tooltip: '选择学年',
            icon: const Icon(Icons.calendar_month),
            onSelected: (y) => setState(() {
              _year = y;
              _searchQuery = '';
              _searchController.clear();
            }),
            itemBuilder: (_) => [
              for (final y in [_year - 1, _year, _year + 1])
                PopupMenuItem(
                  value: y,
                  child: Text('${y}-${y + 1}学年${y == _year ? ' ✓' : ''}'),
                ),
            ],
          ),
          // 学期选择
          PopupMenuButton<int>(
            tooltip: '选择学期',
            icon: const Icon(Icons.school),
            onSelected: (s) => setState(() {
              _semester = s;
              _searchQuery = '';
              _searchController.clear();
            }),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 3,
                child: Text('秋冬学期${_semester == 3 ? ' ✓' : ''}'),
              ),
              PopupMenuItem(
                value: 12,
                child: Text('春夏学期${_semester == 12 ? ' ✓' : ''}'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () => ref.invalidate(
                courseOfferingsProvider((year: _year, semester: _semester))),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(
                courseOfferingsProvider((year: _year, semester: _semester))),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索课程名称、教师、地点...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          const SizedBox(height: 8),
          // 列表
          Expanded(
            child: async.when(
              loading: () => const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 200,
                      child: LinearProgressIndicator(),
                    ),
                    SizedBox(height: 12),
                    Text('正在加载开课数据...',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              error: (err, _) => ErrorCard(message: err.toString()),
              data: (result) => result.fold(
                (offerings) => _buildList(offerings),
                (error) => ErrorCard(
                  message: error.userMessage,
                  detail: error.debugMessage,
                  hint: error.recoveryHint,
                  onRetry: () => ref.invalidate(
                      courseOfferingsProvider(
                          (year: _year, semester: _semester))),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<CourseOffering> offerings) {
    // 搜索过滤
    var filtered = offerings;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = offerings.where((o) {
        return o.courseName.toLowerCase().contains(q) ||
            (o.teacher?.toLowerCase().contains(q) ?? false) ||
            (o.location?.toLowerCase().contains(q) ?? false) ||
            (o.schedule?.toLowerCase().contains(q) ?? false) ||
            (o.courseType?.toLowerCase().contains(q) ?? false) ||
            (o.courseCode?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    if (offerings.isEmpty) {
      return const EmptyState(icon: Icons.book, title: '暂无开课数据');
    }

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('未找到匹配 "$_searchQuery" 的课程',
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    // 按课程类型分组
    final byType = <String, List<CourseOffering>>{};
    for (final o in filtered) {
      final type = o.courseType ?? '其他';
      byType.putIfAbsent(type, () => []).add(o);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _searchQuery.isNotEmpty
                ? '找到 ${filtered.length} 门课程（共 ${offerings.length} 门）'
                : '共 ${offerings.length} 门课程',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        for (final entry in byType.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Text(
              '${entry.key} (${entry.value.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          for (final o in entry.value)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _highlightText(o.courseName, _searchQuery),
                    const SizedBox(height: 6),
                    if (o.teacher != null)
                      _infoRow(Icons.person, o.teacher!, _searchQuery),
                    if (o.schedule != null && o.schedule!.isNotEmpty)
                      _infoRow(Icons.schedule, o.schedule!, _searchQuery),
                    if (o.location != null && o.location!.isNotEmpty)
                      _infoRow(Icons.room, o.location!, _searchQuery),
                    if (o.credits > 0)
                      _infoRow(Icons.star, '${o.credits} 学分', ''),
                    if (o.courseType != null)
                      _infoRow(Icons.bookmark, o.courseType!, _searchQuery),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// 带高亮的文本（匹配搜索词部分加粗）。
  Widget _highlightText(String text, String query) {
    if (query.isEmpty || text.isEmpty) {
      return Text(text,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600));
    }
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx < 0) {
      return Text(text,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600));
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 15, color: Colors.black),
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + q.length),
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
          ),
          TextSpan(text: text.substring(idx + q.length)),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, String query) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: query.isNotEmpty
                ? _highlightText(text, query)
                : Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
