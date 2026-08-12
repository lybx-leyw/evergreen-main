/// 我的课程（zju / courses）——courses.zju.edu.cn 选课列表 + 周课表。
///
/// B3（2026-08-12）自参考工程
/// `cp_evergreen_push/lib/features/courses/screens/courses_screen.dart` 改造：
/// - 去 Scaffold/AppBar（evg-base 桌面规范：模块区无 per-module AppBar，页面自绘标题头）；
/// - 数据不再走 Riverpod service provider，改经数据中枢
///   `orch.typeByName('zju_courses') → fastRead ?? get`（html_modle 同款模式）；
/// - 课表视图依赖 zdbk timetable（B3-ui 接入）：当前学年读数据中枢
///   `zju_timetable`，历史/未来学年直连 `ZjuZdbkService.getTimetable`
///   （classroom 同款模式）；ZDBK 忽略 xqm 返回整个学年，学期切换为本地
///   位掩码过滤（参考实现同款行为）。
/// - 课程 Tile 三操作按钮（B3-ui，对齐参考）：查老师 → /zju-teachers、
///   查看成绩 → /zju-scores、下载资料 → downloads 未移植，SnackBar 提示。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:evergreen_base/providers.dart'
    show dataOrchestratorProvider, sharedPreferencesProvider;

import '../../shared/models/zju_timetable_session.dart';
import '../../zdbk/services/zdbk_service.dart';
import '../../zju_auth/zju_session.dart';
import '../models/course.dart';
import '../widgets/timetable_grid.dart';

/// 我的课程主视图：课程列表 ↔ 周课表切换。
class CoursesView extends ConsumerStatefulWidget {
  const CoursesView({super.key});

  @override
  ConsumerState<CoursesView> createState() => _CoursesViewState();
}

class _CoursesViewState extends ConsumerState<CoursesView> {
  String _searchQuery = '';
  Future<Map<String, dynamic>?>? _future;

  // ── 课表视图状态（B3-ui）──────────────────────────────────────────
  bool _showTimetable = false;
  late int _timetableYear; // 学年起始年（默认当前学年）
  late int _timetableSeason; // 位掩码: 春=1, 夏=2, 短①=4, 秋=8, 冬=16, 短②=32, 暑=64
  Future<List<ZjuTimetableSession>>? _timetableFuture;
  final Map<int, List<ZjuTimetableSession>> _timetableCache = {};

  @override
  void initState() {
    super.initState();
    _future = _fetch();
    final now = DateTime.now();
    _timetableYear = _currentAcademicYear(now);
    _timetableSeason = _currentSemesterMask(now);
  }

  /// 当前学年起始年（9月起为新学年，对齐 `_currentZjuSemester`）。
  static int _currentAcademicYear(DateTime now) =>
      (now.month >= 9) ? now.year : now.year - 1;

  /// 当前学期位掩码（秋/冬 → 秋=8；春/夏 → 春=1）。
  static int _currentSemesterMask(DateTime now) =>
      (now.month >= 9 || now.month <= 2) ? 8 : 1;

  /// 经数据中枢拉取（内存快读 → 磁盘/网络）。
  ///
  /// 注：`typeByName` 返回 `DataType<dynamic>`，无法直接传 `fastRead<Map>`，
  /// 故用字符串版 `fastReadByName` / `getByName`（返回 dynamic 再 cast）。
  Future<Map<String, dynamic>?> _fetch() async {
    final orch = ref.read(dataOrchestratorProvider);
    if (orch.typeByName('zju_courses') == null) {
      throw StateError('数据源 zju_courses 未注册');
    }
    final mem = await orch.fastReadByName('zju_courses');
    if (mem != null) return mem as Map<String, dynamic>;
    final data = await orch.getByName('zju_courses');
    return data as Map<String, dynamic>?;
  }

  void _reload() => setState(() => _future = _fetch());

  // ── 课表数据加载（B3-ui）───────────────────────────────────────────

  /// 加载课表：当前学年读数据中枢 `zju_timetable`（缓存复用），
  /// 历史/未来学年直连 service（classroom 同款模式，不落中枢）。
  Future<List<ZjuTimetableSession>> _loadTimetable(int year) async {
    final cached = _timetableCache[year];
    if (cached != null) return cached;

    final currentYear = _currentAcademicYear(DateTime.now());
    List<ZjuTimetableSession> sessions;
    if (year == currentYear) {
      final orch = ref.read(dataOrchestratorProvider);
      if (orch.typeByName('zju_timetable') == null) {
        throw StateError('数据源 zju_timetable 未注册');
      }
      final mem = await orch.fastReadByName('zju_timetable');
      final data = mem ?? await orch.getByName('zju_timetable');
      if (data == null) throw StateError(_statusError());
      sessions = ((data['sessions'] as List<dynamic>?) ?? [])
          .map((e) => ZjuTimetableSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      final prefs = ref.read(sharedPreferencesProvider);
      final service = await ensureZdbkSession(prefs: prefs);
      sessions = await service.getTimetable(
        service.httpClient!,
        year: year,
        semester: 3, // xqm 被忽略，任意值即可（参考同款）
      );
    }
    _timetableCache[year] = sessions;
    return sessions;
  }

  void _reloadTimetable() {
    _timetableCache.remove(_timetableYear);
    setState(() {
      _timetableFuture = _loadTimetable(_timetableYear);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        if (_showTimetable)
          Expanded(child: _buildTimetable())
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索课程名称 / 教师 / 课程号...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) return _buildError(snap.error.toString());
                final data = snap.data;
                if (data == null) {
                  // fetcher 抛错 → 中枢返回 null 并记录 lastError；此处读状态补全提示。
                  return _buildError(_statusError());
                }
                final list = ((data['courses'] as List<dynamic>?) ?? [])
                    .map((e) => ZjuCourse.fromJson(e as Map<String, dynamic>))
                    .toList();
                final filtered = _searchQuery.isEmpty
                    ? list
                    : list.where((c) {
                        final q = _searchQuery.toLowerCase();
                        return c.name.toLowerCase().contains(q) ||
                            (c.teacherName?.toLowerCase().contains(q) ??
                                false) ||
                            (c.courseCode?.toLowerCase().contains(q) ?? false);
                      }).toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.school_outlined,
                            size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isNotEmpty ? '未找到匹配的课程' : '暂无课程',
                          style: const TextStyle(fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _searchQuery.isNotEmpty
                              ? '尝试其他搜索词'
                              : '请检查学在浙大账号是否有选课记录',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _CourseTile(course: filtered[i]),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  // ── 课表视图（B3-ui，对齐参考 `_buildTimetable`）─────────────────────

  Widget _buildTimetable() {
    final semKey = '$_timetableYear-$_timetableSeason';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('学年', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _timetableYear,
                  underline: const SizedBox(),
                  items: [
                    for (final y in [
                      _timetableYear - 1,
                      _timetableYear,
                      _timetableYear + 1,
                    ])
                      DropdownMenuItem(
                        value: y,
                        child: Text('$y-${y + 1}',
                            style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null || v == _timetableYear) return;
                    setState(() {
                      _timetableYear = v;
                      _timetableSeason = _currentSemesterMask(DateTime.now());
                      _timetableFuture = _loadTimetable(v);
                    });
                  },
                ),
                const SizedBox(width: 16),
                const Text('学期', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _timetableSeason,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(
                        value: 1, child: Text('春', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 2, child: Text('夏', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 4, child: Text('短①', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 8, child: Text('秋', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 16, child: Text('冬', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 32, child: Text('短②', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 64, child: Text('暑', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (v) =>
                      setState(() => _timetableSeason = v ?? _timetableSeason),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ZjuTimetableSession>>(
            future: _timetableFuture ??= _loadTimetable(_timetableYear),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _buildError(
                  '课表加载失败\n${snap.error}',
                  onRetry: _reloadTimetable,
                );
              }
              final sessions = snap.data ?? const <ZjuTimetableSession>[];
              // 按学期过滤：ZDBK 忽略 xqm 返回整个学年；semester 位掩码
              // 春=1, 夏=2, 短①=4, 秋=8, 冬=16, 短②=32, 暑=64（参考同款）。
              final year = _timetableYear;
              final mask = _timetableSeason;
              final filtered = sessions
                  .where((s) =>
                      (s.courseYear == null || s.courseYear == year) &&
                      ((s.semester ?? 0) & mask) != 0)
                  .toList();
              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_view_week,
                          size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      const Text('暂未获取到课表数据', style: TextStyle(fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                        '当前选择 $year-$year 学年 · 学期 $semKey\n请切换学年学期或刷新重试',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: _reloadTimetable,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('刷新'),
                      ),
                    ],
                  ),
                );
              }
              return TimetableGrid(sessions: filtered);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Text(_showTimetable ? '周课表' : '我的课程',
              style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            icon: Icon(_showTimetable ? Icons.list : Icons.calendar_view_week),
            tooltip: _showTimetable ? '列表视图' : '课表视图',
            onPressed: () => setState(() {
              _showTimetable = !_showTimetable;
              if (_showTimetable) {
                _timetableFuture ??= _loadTimetable(_timetableYear);
              }
            }),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _showTimetable ? _reloadTimetable : _reload,
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message, {VoidCallback? onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            const Text('加载课程失败', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry ?? _reload,
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
    final s = orch.status('zju_courses');
    final err = s?.lastError;
    if (err == null || err.isEmpty) return '数据源未连接（zju_courses）';
    if (err.contains('未配置')) {
      return '$err\n请先在「设置」中填写学号密码，再点重试。';
    }
    return err;
  }
}

/// 课程行——三操作按钮（B3-ui，对齐参考 `_CourseTile`）：
/// 查老师 → 教师评价模块；查看成绩 → 成绩模块；下载资料 → 建设中提示。
class _CourseTile extends ConsumerWidget {
  final ZjuCourse course;
  const _CourseTile({required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(course.name),
      subtitle: Text(
        [
          if (course.teacherName != null) course.teacherName!,
          if (course.courseTypeName != null) course.courseTypeName!,
          course.statusLabel,
        ].join(' · '),
      ),
      trailing: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.person_search, size: 20),
            tooltip: '查老师评分',
            visualDensity: VisualDensity.compact,
            onPressed: () => context.go('/zju-teachers'),
          ),
          IconButton(
            icon: const Icon(Icons.download, size: 20),
            tooltip: '下载资料',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('下载资料模块建设中，敬请期待'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.grade, size: 20),
            tooltip: '查看成绩',
            visualDensity: VisualDensity.compact,
            onPressed: () => context.go('/zju-scores'),
          ),
        ],
      ),
    );
  }
}
