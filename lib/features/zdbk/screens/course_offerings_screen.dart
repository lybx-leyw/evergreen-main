/// 开课情况页面 — 打开显示缓存，刷新拉取新数据，搜索查本地。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/models/course_offering.dart';
import '../../../core/storage/database.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/empty_state.dart';
import '../providers/zdbk_provider.dart';
import '../../../widgets/freshness_badge.dart';

class CourseOfferingsScreen extends ConsumerStatefulWidget {
  const CourseOfferingsScreen({super.key});

  @override
  ConsumerState<CourseOfferingsScreen> createState() => _CourseOfferingsScreenState();
}

class _CourseOfferingsScreenState extends ConsumerState<CourseOfferingsScreen> {
  int _year = DateTime.now().month >= 9 ? DateTime.now().year : DateTime.now().year - 1;
  int _semester = DateTime.now().month >= 9 || DateTime.now().month <= 2 ? 3 : 12;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<CourseOffering> _allOfferings = [];
  bool _loading = false;

  String get _semesterLabel => _semester == 3 ? '秋冬' : '春夏';

  @override
  void initState() {
    super.initState();
    _loadFromCache();
  }

  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  void _loadFromCache() {
    final db = WebCacheDatabase.instanceOrNull;
    if (db == null) return;
    final cached = db.getCachedList('zdbk_courseOfferings_${_year}_$_semester');
    if (cached.isEmpty) return;
    try {
      _allOfferings = cached
          .map((e) => CourseOffering.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      ref.invalidate(courseOfferingsProvider((year: _year, semester: _semester)));
      await ref.read(courseOfferingsProvider((year: _year, semester: _semester)).future);
      _loadFromCache();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开课情况 刷新成功'), duration: Duration(seconds: 1)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开课情况 刷新失败'), backgroundColor: Colors.red, duration: Duration(seconds: 2)));
    }
    setState(() => _loading = false);
  }

  List<CourseOffering> get _filtered {
    if (_searchQuery.isEmpty) return _allOfferings;
    final q = _searchQuery.toLowerCase();
    return _allOfferings.where((o) =>
      o.courseName.toLowerCase().contains(q) ||
      (o.teacher?.toLowerCase().contains(q) ?? false) ||
      (o.location?.toLowerCase().contains(q) ?? false) ||
      (o.courseCode?.toLowerCase().contains(q) ?? false)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final byType = <String, List<CourseOffering>>{};
    for (final o in filtered) { byType.putIfAbsent(o.courseType ?? '其他', () => []).add(o); }

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('开课情况'),
          Text('${_year}-${_year + 1}学年 · ${_semesterLabel}学期',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
        actions: [
          FreshnessBadge(cacheKey: 'zdbk_courseOfferings_${_year}_$_semester'),
          PopupMenuButton<int>(tooltip: '选择学年', icon: const Icon(Icons.calendar_month),
            onSelected: (y) => setState(() { _year = y; _searchQuery = ''; _searchController.clear(); _loadFromCache(); }),
            itemBuilder: (_) => [
              for (final y in [_year - 1, _year, _year + 1])
                PopupMenuItem(value: y, child: Text('${y}-${y + 1}学年${y == _year ? ' ✓' : ''}')),
            ]),
          PopupMenuButton<int>(tooltip: '选择学期', icon: const Icon(Icons.school),
            onSelected: (s) => setState(() { _semester = s; _searchQuery = ''; _searchController.clear(); _loadFromCache(); }),
            itemBuilder: (_) => [
              PopupMenuItem(value: 3, child: Text('秋冬学期${_semester == 3 ? ' ✓' : ''}')),
              PopupMenuItem(value: 12, child: Text('春夏学期${_semester == 12 ? ' ✓' : ''}')),
            ]),
          IconButton(
            icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
            tooltip: '刷新', onPressed: _loading ? null : _refresh),
        ],
      ),
      body: _allOfferings.isEmpty && !_loading
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.book, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text('暂无开课数据', style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              ElevatedButton.icon(icon: const Icon(Icons.refresh), label: const Text('点击刷新'), onPressed: _refresh),
            ]))
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索课程名称、教师、地点...', prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() { _searchQuery = ''; _searchController.clear(); })) : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    filled: true, fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 4),
                child: Align(alignment: Alignment.centerLeft,
                  child: Text(_searchQuery.isNotEmpty ? '找到 ${filtered.length} 门（共 ${_allOfferings.length} 门）' : '共 ${_allOfferings.length} 门课程',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
              ),
              Expanded(child: filtered.isEmpty
                  ? Center(child: Text('未找到匹配 "$_searchQuery" 的课程', style: TextStyle(color: Colors.grey[600])))
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                      for (final entry in byType.entries) ...[
                        Padding(padding: const EdgeInsets.only(top: 6, bottom: 6), child: Text('${entry.key} (${entry.value.length})', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary))),
                        for (final o in entry.value)
                          Card(margin: const EdgeInsets.only(bottom: 6), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(o.courseName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            if (o.teacher != null) _infoRow(Icons.person, o.teacher!),
                            if (o.schedule != null && o.schedule!.isNotEmpty) _infoRow(Icons.schedule, o.schedule!),
                            if (o.location != null && o.location!.isNotEmpty) _infoRow(Icons.room, o.location!),
                            if (o.credits > 0) _infoRow(Icons.star, '${o.credits} 学分'),
                          ]))),
                      ],
                    ])),
            ]),
    );
  }

  Widget _infoRow(IconData icon, String text) => Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
    Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
    const SizedBox(width: 6),
    Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
  ]));
}
