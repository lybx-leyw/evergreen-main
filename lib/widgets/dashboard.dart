import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/todo/providers/todo_provider.dart';
import '../features/exams/providers/exams_provider.dart';
import '../features/courses/providers/courses_provider.dart';
import '../features/classroom/providers/classroom_provider.dart';
import '../features/zdbk/providers/zdbk_provider.dart';
import '../features/connectivity/providers/connectivity_provider.dart';
import '../core/utils/auto_refresh.dart';
import 'responsive_scroll_view.dart';
// import '../features/ecard/providers/ecard_provider.dart'; // 待 BlueWare token 获取实现后启用

/// Dashboard home screen — grid of feature cards organized by category.
///
/// Displays real-time data summaries on cards with available providers,
/// falls back to static navigation descriptions for others.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      // 不再自动刷新：前端永远读缓存，刷新由数据状态面板手动触发
      ref.invalidate(zdbkEverythingProvider);
      ref.invalidate(todoListProvider);
      ref.invalidate(examsListProvider);
      ref.invalidate(connectivityCheckProvider);
      ref.invalidate(coursesListProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('仪表盘'),
      ),
      body: ResponsiveScrollView(
        padding: const EdgeInsets.all(24),
        children: [
            _buildSection(context, '学习', [
              _coursesCard(ref),
              _previewCard(title: '开课情况', icon: Icons.book, path: '/course-offerings', subtitle: '学期课程查询'),
              _previewCard(title: '培养方案', icon: Icons.account_tree, path: '/training-plans', subtitle: '专业培养方案'),
              _TodoBadgeCard(ref),
              _scoresCard(ref),
              _ExamBadgeCard(ref),
              _previewCard(title: '计划管理', icon: Icons.assignment, path: '/plan', subtitle: '学习计划与目标'),
              _previewCard(title: '下载', icon: Icons.download, path: '/downloads', subtitle: '课程资料下载管理'),
            ]),
            const SizedBox(height: 24),
            _buildSection(context, 'AI 工具', [
              _previewCard(title: 'AI 助手', icon: Icons.smart_toy, path: '/agent', subtitle: 'DeepSeek 多会话 AI 对话'),
              _previewCard(title: 'AI 笔记', icon: Icons.auto_awesome, path: '/notes', subtitle: 'Keshav 三遍法 + SQ3R'),
              _classroomCard(ref),
            ]),
            const SizedBox(height: 24),
            _buildSection(context, '校园', [
              _previewCard(title: '教务通知', icon: Icons.campaign, path: '/zdbk-notifications', subtitle: 'ZDBK 教务通知'),
              _previewCard(title: '查老师', icon: Icons.person_search, path: '/teachers', subtitle: '教师评分查询'),
              _previewCard(title: '课表导出', icon: Icons.calendar_month, path: '/schedule-export', subtitle: '学期课表'),
              _ptaCard(ref),
            ]),
            const SizedBox(height: 24),
            _buildSection(context, '系统', [
              _quickConnectCard(ref),
              _previewCard(title: '设置', icon: Icons.settings, path: '/settings', subtitle: '账号与偏好配置'),
            ]),
          ],
        ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: children,
        ),
      ],
    );
  }

  // ── Reusable card builders ──────────────────────────────────

  /// Static navigation card with icon, title and subtitle.
  Widget _previewCard({
    required String title,
    required IconData icon,
    required String path,
    String subtitle = '',
    Widget? trailing,
    Widget? dataContent,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth > 0 ? constraints.maxWidth : 400.0;
      final double cardW = w < 400 ? w : (w < 650 ? (w - 16) / 2 : (w < 900 ? (w - 32) / 3 : 220.0));
      return SizedBox(
        width: cardW,
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.go(path),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 28,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      if (trailing != null) ...[
                        const Spacer(),
                        trailing,
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  dataContent ??
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  /// Small loading indicator for card data areas.
  Widget _compactLoader(String hint) {
    return Row(
      children: [
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 6),
        Text(
          hint,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  // ── Data-aware cards ────────────────────────────────────────

  /// Courses card — active course count + progress bar.
  Widget _coursesCard(WidgetRef ref) {
    final async = ref.watch(coursesListProvider);
    return _previewCard(
      title: '课程',
      icon: Icons.school,
      path: '/courses',
      subtitle: '查看课程列表与详情',
      dataContent: async.when(
        data: (result) => result.fold(
          (courses) => Text(
            '${courses.length} 门课程',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          (_) => const Text(
            '查看课程列表与详情',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        loading: () => _compactLoader('加载课程...'),
        error: (_, __) => const Text(
          '查看课程列表与详情',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }

  /// Scores card — GPA summary from ZDBK.
  Widget _scoresCard(WidgetRef ref) {
    final async = ref.watch(zdbkEverythingProvider);
    return _previewCard(
      title: '成绩',
      icon: Icons.grade,
      path: '/scores',
      subtitle: 'GPA 概览与成绩查询',
      dataContent: async.when(
        data: (result) => result.fold(
          (data) {
            final gpa = data.domesticGpa;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '五分制: ${gpa.fivePoint.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                Text(
                  '四分制: ${gpa.fourPoint.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  '学分: ${gpa.earnedCredits.toStringAsFixed(1)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            );
          },
          (_) => const Text(
            'GPA 概览与成绩查询',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        loading: () => _compactLoader('加载绩点...'),
        error: (_, __) => const Text(
          'GPA 概览与成绩查询',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }

  /// PTA card — login status & exam count.
  Widget _ptaCard(WidgetRef ref) {
    final status = ref.watch(ptaStatusProvider);
    return _previewCard(
      title: 'PTA',
      icon: Icons.code,
      path: '/pintia-login',
      subtitle: status.when(
        data: (s) {
          if (s == '已连接') return '编程题目集 · 已登录';
          if (s == '未配置') return '设置中配置手机号';
          return '需登录验证码';
        },
        loading: () => '连接中...',
        error: (_, __) => '连接失败',
      ),
      trailing: status.when(
        data: (s) {
          if (s == '已连接') {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('在线',
                  style: TextStyle(fontSize: 10, color: Colors.green.shade800)),
            );
          }
          if (s == '需要登录') {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('需登录',
                  style: TextStyle(fontSize: 10, color: Colors.orange.shade800)),
            );
          }
          return null;
        },
        loading: () => null,
        error: (_, __) => null,
      ),
    );
  }

  /// WIP card — feature under development.
  Widget _wipCard(String title, String subtitle, IconData icon) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth > 0 ? constraints.maxWidth : 400.0;
      final double cardW = w < 400 ? w : (w < 650 ? (w - 16) / 2 : (w < 900 ? (w - 32) / 3 : 220.0));
      return SizedBox(
        width: cardW,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Icon(icon, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('开发中',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange.shade800)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(subtitle,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ),
      );
    });
  }

  /// Classroom card — course count.
  Widget _classroomCard(WidgetRef ref) {
    final async = ref.watch(classroomCoursesProvider);
    return _previewCard(
      title: '智云课堂',
      icon: Icons.video_library,
      path: '/classroom',
      subtitle: 'PPT + 字幕 + 视频',
      dataContent: async.when(
        data: (result) => result.fold(
          (courses) => Text(
            '${courses.length} 门课程',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          (_) => const Text(
            'PPT + 字幕 + 视频',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        loading: () => _compactLoader('加载课程...'),
        error: (_, __) => const Text(
          'PPT + 字幕 + 视频',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }

  /// Todo card with badge — counts items within 7-day window.
  Widget _TodoBadgeCard(WidgetRef ref) {
    final badge = ref.watch(todoListProvider).when(
      data: (todos) {
        final now = DateTime.now();
        final urgent = todos.where((t) {
          if (t.deadline == null) return false;
          final deadline = DateTime.tryParse(t.deadline!);
          if (deadline == null) return false;
          // 仅计未来 3 天内，已过期不计数
          return deadline.isAfter(now) && deadline.difference(now).inDays <= 3;
        }).length;
        return urgent;
      },
      error: (_, __) => 0,
      loading: () => 0,
    );

    return _previewCard(
      title: '待办',
      icon: Icons.checklist,
      path: '/todo',
      subtitle: badge > 0 ? '$badge 项即将到期' : '作业与考试倒计时',
      trailing: badge > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge > 99 ? '99+' : '$badge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      dataContent: badge > 0
          ? Text(
              '$badge 项即将到期',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            )
          : null,
    );
  }

  /// Exam card with badge — counts exams within 21 days.
  Widget _ExamBadgeCard(WidgetRef ref) {
    final badge = ref.watch(examsListProvider).when(
      data: (exams) {
        final now = DateTime.now();
        final upcoming = exams.where((e) {
          if (e.startTime == null) return false;
          return e.startTime!.difference(now).inDays <= 21;
        }).length;
        return upcoming;
      },
      error: (_, __) => 0,
      loading: () => 0,
    );

    return _previewCard(
      title: '考试',
      icon: Icons.event,
      path: '/exams',
      subtitle: badge > 0 ? '$badge 场即将到来' : '考试日程与倒计时',
      trailing: badge > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge > 99 ? '99+' : '$badge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      dataContent: badge > 0
          ? Text(
              '$badge 场即将到来',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            )
          : null,
    );
  }

  /// Quick connect card — check all services connectivity.
  Widget _quickConnectCard(WidgetRef ref) {
    final status = ref.watch(connectivityCheckProvider);
    return _previewCard(
      title: '数据状态',
      icon: Icons.wifi_tethering,
      path: '/quick-connect',
      subtitle: status.when(
        data: (results) {
          final ok = results.where((r) => r.ok).length;
          final total = results.length;
          if (ok == total) return '全部连通 ($total/$total)';
          return '连通 $ok/$total · 点击检查';
        },
        loading: () => '检查中...',
        error: (_, __) => '检查失败',
      ),
      trailing: status.when(
        data: (results) {
          final ok = results.where((r) => r.ok).length;
          final total = results.length;
          if (ok == total) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('在线',
                  style: TextStyle(fontSize: 10, color: Colors.green.shade800)),
            );
          }
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: ok > 0 ? Colors.orange.shade100 : Colors.red.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(ok > 0 ? '部分离线' : '离线',
                style: TextStyle(
                    fontSize: 10,
                    color: ok > 0
                        ? Colors.orange.shade800
                        : Colors.red.shade800)),
          );
        },
        loading: () => null,
        error: (_, __) => null,
      ),
    );
  }
}
