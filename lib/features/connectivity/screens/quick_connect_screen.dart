import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/connectivity/connection_manager.dart';
import '../../../core/connectivity/data_status_manager.dart';
import '../../../core/log.dart';
import '../providers/connectivity_provider.dart'
    show connectivityCheckProvider, connectionManagerProvider, dataStatusManagerProvider,
         dataStatusTickProvider, updateDataStatus;
import '../../zdbk/providers/zdbk_provider.dart'
    show zdbkEverythingProvider, zdbkTranscriptProvider, zdbkExamsProvider,
         zdbkTimetableProvider, courseOfferingsProvider, trainingPlansProvider,
         zdbkServiceInstanceProvider;
import '../../auth/providers/auth_provider.dart' show httpClientProvider;
import '../../courses/providers/courses_provider.dart'
    show coursesListProvider, coursesExamsProvider;
import '../../classroom/providers/classroom_provider.dart'
    show classroomCoursesProvider;
import '../../todo/providers/todo_provider.dart'
    show todoListProvider;
import '../../zdbk/providers/zdbk_notifications_provider.dart'
    show zdbkNotificationsProvider;

/// 数据状态面板 — 服务连通性 + 数据新鲜度 + 上次更新时间。
///
/// 替代旧版"快速连接"，增加数据源状态展示（IDEA1 提案 1+6 合并）。
class QuickConnectScreen extends ConsumerStatefulWidget {
  const QuickConnectScreen({super.key});

  @override
  ConsumerState<QuickConnectScreen> createState() => _QuickConnectScreenState();
}

class _QuickConnectScreenState extends ConsumerState<QuickConnectScreen>
    with WidgetsBindingObserver {
  final Map<String, AsyncValue<ConnectionResult>> _retryResults = {};
  final Set<String> _retrying = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.invalidate(connectionManagerProvider);
      ref.invalidate(connectivityCheckProvider);
      ref.invalidate(dataStatusManagerProvider);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(connectionManagerProvider);
      ref.invalidate(connectivityCheckProvider);
      ref.invalidate(dataStatusManagerProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectivityAsync = ref.watch(connectivityCheckProvider);
    final dataStatusAsync = ref.watch(dataStatusManagerProvider);
    ref.watch(dataStatusTickProvider); // 监听刷新 tick，确保状态灯实时更新
    final manager = ref.read(connectionManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据状态'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '全部刷新',
            onPressed: () => _refreshAll(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshAll(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 汇总卡片 ──
            _buildSummaryCard(connectivityAsync, dataStatusAsync),
            const SizedBox(height: 16),

            // ── Section 1: 服务连通性 ──
            _sectionHeader('服务连通性', Icons.wifi_tethering),
            const SizedBox(height: 8),
            ...connectivityAsync.when(
              loading: () => [_loadingSection()],
              error: (err, _) => [_errorCard('检查失败: $err')],
              data: (allResults) {
                final merged = _mergeResults(allResults);
                return merged.map((r) => _connectivityCard(r, manager)).toList();
              },
            ),

            const SizedBox(height: 8),
            if (_retryResults.isNotEmpty)
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新检查全部连通性'),
                  onPressed: () {
                    _retryResults.clear();
                    _retrying.clear();
                    ref.invalidate(connectionManagerProvider);
                    ref.invalidate(connectivityCheckProvider);
                  },
                ),
              ),

            const SizedBox(height: 20),

            // ── Section 2: 数据新鲜度 ──
            _sectionHeader('数据新鲜度', Icons.access_time),
            const SizedBox(height: 8),
            ...dataStatusAsync.when(
              loading: () => [_loadingSection()],
              error: (err, _) => [_errorCard('加载失败: $err')],
              data: (manager) => _buildFreshnessList(manager),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 汇总卡片
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSummaryCard(
    AsyncValue<List<ConnectionResult>> connectivityAsync,
    AsyncValue<DataStatusManager?> dataStatusAsync,
  ) {
    final connected = connectivityAsync.whenOrNull(data: (r) => r.where((e) => e.ok).length) ?? 0;
    final totalConn = connectivityAsync.whenOrNull(data: (r) => r.length) ?? 6;
    final fresh = dataStatusAsync.whenOrNull(data: (m) => m?.freshCount) ?? 0;
    final totalFresh = dataStatusAsync.whenOrNull(data: (m) => m?.totalCount) ?? 0;

    final allConnected = connected == totalConn && totalConn > 0;
    final allFresh = fresh == totalFresh && totalFresh > 0;

    return Card(
      color: (allConnected && allFresh)
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              allConnected && allFresh ? Icons.check_circle : Icons.info_outline,
              size: 36,
              color: allConnected && allFresh
                  ? Colors.green
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    allConnected && allFresh ? '全部正常' : '需要关注',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$connected/$totalConn 连通 · $fresh/$totalFresh 数据新鲜',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Section 1: 服务连通性
  // ═══════════════════════════════════════════════════════════════════

  Widget _connectivityCard(ConnectionResult r, ConnectionManager manager) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Icon(
          r.ok ? Icons.check_circle : Icons.cancel,
          color: r.ok ? Colors.green : Colors.red,
          size: 24,
        ),
        title: Text(r.service, style: const TextStyle(fontSize: 14)),
        subtitle: r.ok
            ? Text('${r.elapsed.inMilliseconds}ms',
                style: const TextStyle(fontSize: 12, color: Colors.grey))
            : Text(
                r.message ?? '未知错误',
                style: const TextStyle(fontSize: 12, color: Colors.red),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: _retrying.contains(r.service)
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : r.ok
                ? const Icon(Icons.verified, color: Colors.green, size: 20)
                : IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.orange),
                    tooltip: '重试',
                    onPressed: () => _retryService(manager, r.service),
                  ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Section 2: 数据新鲜度
  // ═══════════════════════════════════════════════════════════════════

  List<Widget> _buildFreshnessList(DataStatusManager manager) {
    final sources = manager.sources;
    final categories = manager.categories;

    final widgets = <Widget>[];
    for (final cat in categories) {
      final items = manager.byCategory(cat);
      if (items.isEmpty) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4, left: 4),
        child: Text(
          cat,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 0.5,
          ),
        ),
      ));
      for (final s in items) {
        widgets.add(_freshnessCard(s));
      }
    }
    return widgets;
  }

  Widget _freshnessCard(DataSourceStatus s) {
    final Color badgeColor;
    final String badgeText;
    if (s.lastFetchedAt == null) {
      badgeColor = Colors.grey;
      badgeText = '从未';
    } else if (s.isFresh) {
      badgeColor = Colors.green;
      badgeText = '新鲜';
    } else {
      badgeColor = Colors.orange;
      badgeText = '过期';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            badgeText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ),
        title: Text(s.name, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          s.cacheKey == null ? '在线' : s.relativeTime,
          style: TextStyle(
            fontSize: 12,
            color: s.lastFetchedAt == null
                ? Colors.grey
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: '刷新 ${s.name}',
          onPressed: () => _refreshDataSource(s.name),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 共享组件
  // ═══════════════════════════════════════════════════════════════════

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _loadingSection() {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _errorCard(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message, style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 重试逻辑
  // ═══════════════════════════════════════════════════════════════════

  List<ConnectionResult> _mergeResults(List<ConnectionResult> all) {
    final map = {for (final r in all) r.service: r};
    for (final entry in _retryResults.entries) {
      final value = entry.value;
      value.whenData((r) => map[entry.key] = r);
    }
    return all.map((r) => map[r.service] ?? r).toList();
  }

  Future<void> _retryService(ConnectionManager manager, String service) async {
    setState(() => _retrying.add(service));
    try {
      final result = await manager.checkOne(service);
      setState(() {
        _retryResults[service] = AsyncValue.data(result);
        _retrying.remove(service);
      });
    } catch (e) {
      setState(() {
        _retryResults[service] = AsyncValue.error(e, StackTrace.current);
        _retrying.remove(service);
      });
    }
  }

  /// 全部刷新 — 连通性 + 所有数据源。
  Future<void> _refreshAll() async {
    _retryResults.clear();
    _retrying.clear();

    // 无效化所有数据 provider
    ref.invalidate(connectionManagerProvider);
    ref.invalidate(connectivityCheckProvider);
    ref.invalidate(zdbkEverythingProvider);
    ref.invalidate(zdbkExamsProvider);
    ref.invalidate(zdbkTimetableProvider);
    ref.invalidate(courseOfferingsProvider);
    ref.invalidate(trainingPlansProvider);
    ref.invalidate(zdbkNotificationsProvider);
    ref.invalidate(coursesListProvider);
    ref.invalidate(coursesExamsProvider);
    ref.invalidate(classroomCoursesProvider);
    ref.invalidate(todoListProvider);

    // 等待连通性检查完成
    final results = await ref.read(connectivityCheckProvider.future);
    final ok = results.where((r) => r.ok).length;
    final total = results.length;
    final allOk = ok == total;

    ref.invalidate(dataStatusManagerProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(allOk ? Icons.check_circle : Icons.warning_amber,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(allOk
                  ? '全部刷新完成 — $ok/$total 连通，数据已更新'
                  : '刷新完成 — $ok/$total 连通，有服务异常'),
            ],
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: allOk ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  /// 刷新单个数据源 —— invalidate Provider 并等待结果，反馈成功/失败。
  Future<void> _refreshDataSource(String name) async {
    // 显示进度
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name 刷新中...'), duration: const Duration(seconds: 1)),
      );
    }

    bool ok = false;
    String? error;

    try {
      switch (name) {
        case 'ZDBK 成绩':
          ref.invalidate(zdbkEverythingProvider);
          final result = await ref.read(zdbkEverythingProvider.future);
          ok = result.isOk;
          if (!ok) error = (result as dynamic).error?.userMessage;
          break;
        case 'ZDBK 主修成绩':
          final svc = await ref.read(zdbkServiceInstanceProvider.future);
          final hc = ref.read(httpClientProvider);
          final result = await svc.getMajorGrade(hc);
          ok = result.isOk;
          if (!ok) error = (result as dynamic).error?.userMessage;
          break;
        case 'ZDBK 考试':
          ref.invalidate(zdbkExamsProvider);
          final result = await ref.read(zdbkExamsProvider.future);
          ok = result.isOk;
          if (!ok) error = (result as dynamic).error?.userMessage;
          break;
        case 'ZDBK 课表':
          ref.invalidate(zdbkTimetableProvider);
          final result = await ref.read(zdbkTimetableProvider.future);
          ok = result.isOk;
          if (!ok) error = (result as dynamic).error?.userMessage;
          break;
        case '开课情况':
          ref.invalidate(courseOfferingsProvider);
          await Future.delayed(const Duration(milliseconds: 300));
          ok = true;
          break;
        case '培养方案':
          ref.invalidate(trainingPlansProvider);
          final result = await ref.read(trainingPlansProvider(0).future);
          ok = result.isOk;
          if (!ok) error = (result as dynamic).error?.userMessage;
          break;
        case '学在浙大 课程':
          ref.invalidate(coursesListProvider);
          final result = await ref.read(coursesListProvider.future);
          ok = result.isOk;
          if (!ok) error = (result as dynamic).error?.userMessage;
          break;
        case '学在浙大 考试':
          ref.invalidate(coursesExamsProvider);
          final result = await ref.read(coursesExamsProvider.future);
          ok = result.isOk;
          if (!ok) error = (result as dynamic).error?.userMessage;
          break;
        case '智云课堂':
          ref.invalidate(classroomCoursesProvider);
          final result = await ref.read(classroomCoursesProvider.future);
          ok = result.isOk;
          if (!ok) error = (result as dynamic).error?.userMessage;
          break;
        case '教务通知':
          ref.invalidate(zdbkNotificationsProvider);
          final result = await ref.read(zdbkNotificationsProvider.future);
          ok = result.isOk;
          if (!ok) error = (result as dynamic).error?.userMessage;
          break;
        case '待办事项':
          ref.invalidate(todoListProvider);
          await ref.read(todoListProvider.future);
          ok = true;
          break;
        case 'PTA 编程题':
        case 'DeepSeek AI':
          ref.invalidate(connectionManagerProvider);
          ref.invalidate(connectivityCheckProvider);
          final results = await ref.read(connectivityCheckProvider.future);
          final target = results.where((r) => r.service == name).firstOrNull;
          ok = target?.ok ?? false;
          error = target?.message;
          break;
        default:
          Log().warn('DataStatusPanel: unknown source', data: {'name': name});
          return;
      }
    } catch (e) {
      ok = false;
      error = e.toString();
    }

    // 更新数据状态管理器中的对应条目
    updateDataStatus(ref, name, ok: ok, error: error);

    // 反馈结果
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(ok ? Icons.check_circle : Icons.error, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(ok ? '$name ✅' : (error ?? '$name 失败'))),
            ],
          ),
          duration: Duration(seconds: ok ? 1 : 3),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    }
  }
}
