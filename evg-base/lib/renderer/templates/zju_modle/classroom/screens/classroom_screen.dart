/// 智云课堂主视图（zju / classroom，无 Scaffold 桌面规范）。
///
/// B3-classroom（2026-08-12）自参考工程 `cp_evergreen_push/lib/features/
/// classroom/screens/classroom_screen.dart` 移植，改造要点：
/// - 去 Scaffold/AppBar（evg-base 桌面规范：模块区无 per-module AppBar，
///   页面自绘标题头，照抄 exams_screen 模式）；
/// - 课程列表改经数据中枢 `orch.fastReadByName('zju_classroom_courses')`
///   （fetcher 已注册；TTL 30 分钟，JSON 缓存）；
/// - 视频列表为即时数据（需 courseId 参数，中枢 fetcher 无参数支持），
///   本页经 `ZjuClassroomService.listVideos` 直连（SSO cookie Dio）；
/// - 点击视频 → 临时路由打开全屏 [ClassroomViewerScreen]（Scaffold）。
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:evergreen_base/providers.dart'
    show dataOrchestratorProvider, sharedPreferencesProvider;

import '../../shared/models/zju_classroom_course.dart';
import '../../shared/models/zju_classroom_video.dart';
import '../../zju_auth/zju_session.dart';
import '../services/classroom_service.dart';
import 'classroom_viewer_screen.dart';

/// 智云课堂主视图：课程下拉选择 → 视频列表 → 打开查看器。
class ClassroomView extends ConsumerStatefulWidget {
  const ClassroomView({super.key});

  @override
  ConsumerState<ClassroomView> createState() => _ClassroomViewState();
}

class _ClassroomViewState extends ConsumerState<ClassroomView> {
  static const _service = ZjuClassroomService();

  Future<Map<String, dynamic>?>? _coursesFuture;
  Future<Dio>? _dioFuture;
  ZjuClassroomCourse? _selectedCourse;
  Future<List<ZjuClassroomVideo>>? _videosFuture;

  /// 已解析的课程列表缓存。
  ///
  /// 必须在 future 完成时**一次性**解析并缓存，而非在 build 里每次 fromJson：
  /// DropdownButton 的 value 与 items 按 `==`（此处为 id 相等）匹配，
  /// 若每次 build 重建实例，选中项与 items 虽 id 相同但对象不同；
  /// 即使模型重写了 `==`，缓存列表仍可避免无谓的重复解析开销。
  List<ZjuClassroomCourse> _courses = const [];

  @override
  void initState() {
    super.initState();
    _dioFuture = ensureZjuSession(prefs: ref.read(sharedPreferencesProvider));
    _coursesFuture = _fetchCourses();
  }

  /// 经数据中枢拉取课程列表（内存快读 → 磁盘/网络）。
  Future<Map<String, dynamic>?> _fetchCourses() async {
    final orch = ref.read(dataOrchestratorProvider);
    if (orch.typeByName('zju_classroom_courses') == null) {
      throw StateError('数据源 zju_classroom_courses 未注册');
    }
    final mem = await orch.fastReadByName('zju_classroom_courses');
    final data = mem != null
        ? mem as Map<String, dynamic>
        : await orch.getByName('zju_classroom_courses') as Map<String, dynamic>?;
    _courses = _parseCourses(data);
    return data;
  }

  /// 从中枢返回的 JSON 解析课程列表（纯函数，便于单测）。
  static List<ZjuClassroomCourse> _parseCourses(Map<String, dynamic>? data) {
    if (data == null) return const [];
    return ((data['courses'] as List<dynamic>?) ?? [])
        .map((e) => ZjuClassroomCourse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _reload() {
    setState(() {
      _coursesFuture = _fetchCourses();
      _selectedCourse = null;
      _videosFuture = null;
    });
  }

  /// 选中课程后拉取视频列表（直连智云接口，带 SSO cookie）。
  Future<void> _selectCourse(ZjuClassroomCourse course) async {
    setState(() {
      _selectedCourse = course;
      _videosFuture = _loadVideos(course.id);
    });
  }

  Future<List<ZjuClassroomVideo>> _loadVideos(int courseId) async {
    final dio = await _dioFuture;
    if (dio == null) throw StateError('SSO 会话初始化失败');
    return _service.listVideos(dio, courseId);
  }

  void _openViewer(ZjuClassroomVideo v) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClassroomViewerScreen(
          courseId: v.courseId,
          subId: v.subId,
          title: v.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        _buildCoursePicker(),
        Expanded(child: _buildVideos()),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Text('智云课堂', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _reload,
          ),
        ],
      ),
    );
  }

  /// 课程选择区（下拉框 + 加载/错误态）。
  Widget _buildCoursePicker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: FutureBuilder<Map<String, dynamic>?>(
        future: _coursesFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator(minHeight: 2);
          }
          if (snap.hasError) {
            return _buildInlineError('课程列表加载失败', snap.error.toString());
          }
          final data = snap.data;
          if (data == null) return _buildInlineError('课程列表为空', _statusError());
          // 使用 future 完成时缓存的列表（见 _fetchCourses 注释），避免每次
          // rebuild 重新 fromJson 产生新实例导致 Dropdown value 匹配失败。
          final courses = _courses;
          if (courses.isEmpty) {
            return _buildInlineError('暂无课程', '智云课堂暂无课程，或账号未加入课程');
          }
          return DropdownButtonFormField<ZjuClassroomCourse>(
            key: const Key('classroom-course-dropdown'),
            value: _selectedCourse,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '选择课程',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: courses
                .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(
                        c.teacher != null && c.teacher!.isNotEmpty
                            ? '${c.title}（${c.teacher}）'
                            : c.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) _selectCourse(v);
            },
          );
        },
      ),
    );
  }

  /// 视频列表区。
  Widget _buildVideos() {
    if (_selectedCourse == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              '请先选择课程',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<List<ZjuClassroomVideo>>(
      future: _videosFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _buildError('视频列表加载失败', snap.error.toString());
        }
        final videos = snap.data ?? [];
        if (videos.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.video_library, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                const Text('暂无视频', style: TextStyle(fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  '该课程暂无已发布的录播',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: videos.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final v = videos[i];
            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text(v.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(v.startAt ?? ''),
                trailing: FilledButton.tonal(
                  onPressed: () => _openViewer(v),
                  child: const Text('查看内容'),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 从中枢状态读取 lastError 作为错误细节。
  String _statusError() {
    final orch = ref.read(dataOrchestratorProvider);
    final s = orch.status('zju_classroom_courses');
    final err = s?.lastError;
    if (err == null || err.isEmpty) return '数据源未连接（zju_classroom_courses）';
    if (err.contains('未配置') || err.contains('设置')) {
      return '$err\n请先在「设置」中填写学号密码，再点重试。';
    }
    return err;
  }

  Widget _buildInlineError(String title, String detail) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              size: 18, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onErrorContainer)),
                Text(
                  detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String title, String detail) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
