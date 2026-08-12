/// 开课情况视图（zju / zdbk → 开课情况）。
///
/// B3-zdbk（2026-08-12）自参考工程
/// `cp_evergreen_push/lib/features/zdbk/screens/course_offerings_screen.dart`
/// 移植，改造点：
/// - 去 Scaffold/AppBar（evg-base 桌面规范：模块区页面自绘标题头）；
/// - 数据不再走 Riverpod `courseOfferingsProvider`（provider family），改经数据中枢
///   `orch.fastReadByName('zju_course_offerings')`（fetcher 自动检测当前学年学期，
///   返回 JSON 带 year/semester 供标题展示；历史学期数据中枢不缓存）；
/// - `CourseOffering`→`ZjuCourseOffering`、`AppTheme`→主题色；
/// - 保留搜索（课程名/教师/地点/课号）与按课程性质分组列表。
///
/// B3-ui（2026-08-13）补齐参考实现的学年/学期切换 + 刷新 SnackBar：
/// - header 增加学年/学期 PopupMenu（对齐参考 AppBar actions）与学年学期标签；
/// - 默认学年学期读数据中枢；切换历史学年/学期时直连
///   `ZjuZdbkService.getCourseOfferings`（classroom 同款模式，结果按 key 缓存）；
/// - 刷新成功/失败 SnackBar 反馈（对齐参考 `_refresh`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/providers.dart'
    show dataOrchestratorProvider, sharedPreferencesProvider;

import '../../shared/models/zju_course_offering.dart';
import '../../zju_auth/zju_session.dart';
import '../services/zdbk_service.dart';

/// 开课情况主视图：学年学期切换 + 搜索 + 按课程性质分组列表。
class CourseOfferingsView extends ConsumerStatefulWidget {
  const CourseOfferingsView({super.key});

  @override
  ConsumerState<CourseOfferingsView> createState() =>
      _CourseOfferingsViewState();
}

class _CourseOfferingsViewState extends ConsumerState<CourseOfferingsView> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _refreshing = false;

  // ── 学年学期状态（B3-ui，默认当前学年学期）────────────────────────
  late int _year;
  late int _semester; // ZJU 学期码: 3=秋冬, 12=春夏
  Future<List<ZjuCourseOffering>>? _offeringsFuture;
  final Map<String, List<ZjuCourseOffering>> _offeringsCache = {};

  String get _semKey => '$_year-$_semester';
  String get _semesterLabel => _semester == 3 ? '秋冬' : '春夏';

  @override
  void initState() {
    super.initState();
    final sem = _currentSemester();
    _year = sem.year;
    _semester = sem.semester;
    _offeringsFuture = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 当前学年 + 学期码（对齐 `zju_data_sources._currentZjuSemester`）。
  static ({int year, int semester}) _currentSemester() {
    final now = DateTime.now();
    final isAutumnWinter = now.month >= 9 || now.month <= 2;
    return (
      year: isAutumnWinter ? now.year : now.year - 1,
      semester: isAutumnWinter ? 3 : 12,
    );
  }

  /// 加载开课数据：当前学年学期读数据中枢 `zju_course_offerings`，
  /// 历史/未来学年学期直连 service（classroom 同款模式，按 key 缓存）。
  Future<List<ZjuCourseOffering>> _load() async {
    final cacheKey = _semKey;
    final cached = _offeringsCache[cacheKey];
    if (cached != null) return cached;

    final current = _currentSemester();
    List<ZjuCourseOffering> list;
    if (_year == current.year && _semester == current.semester) {
      final orch = ref.read(dataOrchestratorProvider);
      if (orch.typeByName('zju_course_offerings') == null) {
        throw StateError('数据源 zju_course_offerings 未注册');
      }
      final mem = await orch.fastReadByName('zju_course_offerings');
      final data = mem ?? await orch.getByName('zju_course_offerings');
      if (data == null) throw StateError(_statusError());
      list = ((data['offerings'] as List<dynamic>?) ?? [])
          .map((e) => ZjuCourseOffering.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      final prefs = ref.read(sharedPreferencesProvider);
      final service = await ensureZdbkSession(prefs: prefs);
      list = await service.getCourseOfferings(
        service.httpClient!,
        year: _year,
        semester: _semester,
      );
    }
    _offeringsCache[cacheKey] = list;
    return list;
  }

  /// 刷新：清该学年学期缓存 → 重新拉取 → SnackBar 反馈（对齐参考 `_refresh`）。
  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _refreshing = true;
      _offeringsFuture = future;
    });
    try {
      await future;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开课情况 刷新成功'), duration: Duration(seconds: 1)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('开课情况 刷新失败'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
    if (mounted) setState(() => _refreshing = false);
  }

  /// 切换学年学期（对齐参考 PopupMenu onSelected：清搜索 + 重新加载）。
  void _switchSemester(int? year, int? semester) {
    if (year == null && semester == null) return;
    setState(() {
      if (year != null) _year = year;
      if (semester != null) _semester = semester;
      _searchQuery = '';
      _searchController.clear();
      _offeringsFuture = _load();
    });
  }

  List<ZjuCourseOffering> _filter(List<ZjuCourseOffering> all) {
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all
        .where((o) =>
            o.courseName.toLowerCase().contains(q) ||
            (o.teacher?.toLowerCase().contains(q) ?? false) ||
            (o.location?.toLowerCase().contains(q) ?? false) ||
            (o.courseCode?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        Expanded(
          child: FutureBuilder<List<ZjuCourseOffering>>(
            future: _offeringsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return _buildError(snap.error.toString());
              final all = snap.data ?? const <ZjuCourseOffering>[];
              if (all.isEmpty) return _buildEmpty();
              return _buildList(all);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('开课情况', style: Theme.of(context).textTheme.titleLarge),
                Text(
                  '${_year}-${_year + 1}学年 · ${_semesterLabel}学期',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // 学年选择（对齐参考 PopupMenuButton<int> calendar_month）
          PopupMenuButton<int>(
            tooltip: '选择学年',
            icon: const Icon(Icons.calendar_month, size: 20),
            onSelected: (y) => _switchSemester(y, null),
            itemBuilder: (_) => [
              for (final y in [_year - 1, _year, _year + 1])
                PopupMenuItem(
                  value: y,
                  child: Text('${y}-${y + 1}学年${y == _year ? ' ✓' : ''}'),
                ),
            ],
          ),
          // 学期选择（对齐参考 PopupMenuButton<int> school）
          PopupMenuButton<int>(
            tooltip: '选择学期',
            icon: const Icon(Icons.school, size: 20),
            onSelected: (s) => _switchSemester(null, s),
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
          // 刷新（对齐参考：加载中转圈 + SnackBar 反馈）
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _refreshing ? null : _refresh,
          ),
        ],
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
            const Text('加载开课情况失败', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 从中枢状态读取 lastError 作为错误细节（fetcher 抛错被捕获后记录于此）。
  String _statusError() {
    final orch = ref.read(dataOrchestratorProvider);
    final s = orch.status('zju_course_offerings');
    final err = s?.lastError;
    if (err == null || err.isEmpty) return '数据源未连接（zju_course_offerings）';
    if (err.contains('未配置') || err.contains('设置')) {
      return '$err\n请先在「设置」中填写学号密码，再点重试。';
    }
    return err;
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.book, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          const Text('暂无开课数据', style: TextStyle(fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            '教务网开课情况将在选课季公布后显示',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<ZjuCourseOffering> all) {
    final filtered = _filter(all);
    final byType = <String, List<ZjuCourseOffering>>{};
    for (final o in filtered) {
      byType.putIfAbsent(o.courseType ?? '其他', () => []).add(o);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
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
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            _searchQuery.isNotEmpty
                ? '找到 ${filtered.length} 门（共 ${all.length} 门）'
                : '共 ${all.length} 门课程',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    '未找到匹配 "$_searchQuery" 的课程',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    for (final entry in byType.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 6),
                        child: Text(
                          '${entry.key} (${entry.value.length})',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
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
                                Text(
                                  o.courseName,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                if (o.teacher != null)
                                  _infoRow(Icons.person, o.teacher!),
                                if (o.schedule != null &&
                                    o.schedule!.isNotEmpty)
                                  _infoRow(Icons.schedule, o.schedule!),
                                if (o.location != null &&
                                    o.location!.isNotEmpty)
                                  _infoRow(Icons.room, o.location!),
                                if (o.credits > 0)
                                  _infoRow(Icons.star, '${o.credits} 学分'),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
