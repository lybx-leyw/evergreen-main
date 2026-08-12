/// 培养方案视图（zju / zdbk → 培养方案）。
///
/// B3-zdbk（2026-08-12）自参考工程
/// `cp_evergreen_push/lib/features/zdbk/screens/training_plan_screen.dart`
/// 移植，改造点：
/// - 去 Scaffold/AppBar（evg-base 桌面规范：模块区页面自绘标题头）；
/// - 数据改经数据中枢 `orch.fastReadByName('zju_training_plans')`；
/// - `TrainingPlan`→`ZjuTrainingPlan`；
/// - 去掉「培养方案 PDF 查看」（依赖 translate feature 的 PdfPreviewWidget，
///   不在本轮范围；保留 planNo 展示）；年级/学院/专业筛选为本地过滤（保留）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:evergreen_base/providers.dart'
    show dataOrchestratorProvider, sharedPreferencesProvider;

import '../../shared/models/zju_training_plan.dart';
import '../../zju_auth/zju_session.dart';
import '../services/zdbk_service.dart';

/// 培养方案主视图：年级/学院/专业本地筛选 + 方案卡片列表。
class TrainingPlansView extends ConsumerStatefulWidget {
  const TrainingPlansView({super.key});

  @override
  ConsumerState<TrainingPlansView> createState() => _TrainingPlansViewState();
}

class _TrainingPlansViewState extends ConsumerState<TrainingPlansView> {
  int _grade = 0;
  String _collegeFilter = '';
  String _majorFilter = '';
  Future<Map<String, dynamic>?>? _future;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  /// 经数据中枢拉取（内存快读 → 磁盘/网络）。
  Future<Map<String, dynamic>?> _fetch() async {
    final orch = ref.read(dataOrchestratorProvider);
    if (orch.typeByName('zju_training_plans') == null) {
      throw StateError('数据源 zju_training_plans 未注册');
    }
    final mem = await orch.fastReadByName('zju_training_plans');
    if (mem != null) return mem as Map<String, dynamic>;
    final data = await orch.getByName('zju_training_plans');
    return data as Map<String, dynamic>?;
  }

  /// 刷新：重新拉取 → SnackBar 反馈（B3-ui，对齐参考 `_refresh`）。
  Future<void> _refresh() async {
    final future = _fetch();
    setState(() {
      _refreshing = true;
      _future = future;
    });
    try {
      await future;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('培养方案 刷新成功'), duration: Duration(seconds: 1)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('培养方案 刷新失败'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
    if (mounted) setState(() => _refreshing = false);
  }

  /// 本地筛选（年级/学院/专业，与参考实现一致）。
  List<ZjuTrainingPlan> _filter(List<ZjuTrainingPlan> allPlans) {
    var list = allPlans;
    if (_grade > 0) {
      list = list.where((p) => p.grade == _grade.toString()).toList();
    }
    if (_collegeFilter.isNotEmpty) {
      list = list.where((p) => p.college == _collegeFilter).toList();
    }
    if (_majorFilter.isNotEmpty) {
      list = list.where((p) => p.major == _majorFilter).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>?>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return _buildError(snap.error.toString());
              final data = snap.data;
              if (data == null) return _buildError(_statusError());
              final all = ((data['plans'] as List<dynamic>?) ?? [])
                  .map((e) =>
                      ZjuTrainingPlan.fromJson(e as Map<String, dynamic>))
                  .toList();
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
          Text('培养方案', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
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
            const Text('加载培养方案失败', style: TextStyle(fontSize: 15)),
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

  String _statusError() {
    final orch = ref.read(dataOrchestratorProvider);
    final s = orch.status('zju_training_plans');
    final err = s?.lastError;
    if (err == null || err.isEmpty) return '数据源未连接（zju_training_plans）';
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
          Icon(Icons.school, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          const Text('暂无培养方案数据', style: TextStyle(fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            '教务网培养方案公布后显示',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<ZjuTrainingPlan> allPlans) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filter(allPlans);
    final colleges = allPlans
        .map((p) => p.college ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final plansForMajor = _collegeFilter.isNotEmpty
        ? allPlans.where((p) => p.college == _collegeFilter).toList()
        : allPlans;
    final majors = plansForMajor
        .map((p) => p.major ?? '')
        .where((m) => m.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              _buildFilterChip(
                label: _grade > 0 ? '$_grade级' : '全部年级',
                onTap: _showGradePicker,
                color: _grade > 0 ? colorScheme.primaryContainer : null,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildFilterChip(
                  label: _collegeFilter.isNotEmpty ? _collegeFilter : '学院',
                  onTap: () => _showOptionPicker(
                      '选择学院', colleges,
                      (v) => setState(() {
                            _collegeFilter = v;
                            _majorFilter = '';
                          })),
                  color:
                      _collegeFilter.isNotEmpty ? colorScheme.primaryContainer : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildFilterChip(
                  label: _majorFilter.isNotEmpty ? _majorFilter : '专业',
                  onTap: () => _showOptionPicker(
                      '选择专业', majors, (v) => setState(() => _majorFilter = v)),
                  color: _majorFilter.isNotEmpty ? colorScheme.primaryContainer : null,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            '${filtered.length} 个方案${_grade > 0 ? "（$_grade级）" : ""}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    '未找到符合条件的方案',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [for (final p in filtered) _buildPlanCard(p)],
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color ?? theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      color != null ? FontWeight.w600 : FontWeight.normal,
                  color: color != null
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _showGradePicker() {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择年级'),
        children: [
          for (final g in [
            0,
            DateTime.now().year,
            DateTime.now().year - 1,
            DateTime.now().year - 2,
            DateTime.now().year - 3,
            DateTime.now().year - 4,
          ])
            RadioListTile<int>(
              title: Text(g > 0 ? '$g级' : '全部年级'),
              value: g,
              groupValue: _grade,
              onChanged: (v) {
                setState(() => _grade = v!);
                Navigator.of(ctx, rootNavigator: true).pop();
              },
            ),
        ],
      ),
    );
  }

  void _showOptionPicker(
      String title, List<String> options, void Function(String) onSelected) {
    final searchCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final query = searchCtrl.text.trim().toLowerCase();
          final filtered = query.isEmpty
              ? options
              : options.where((o) => o.toLowerCase().contains(query)).toList();
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: '搜索...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '共 ${filtered.length} 项',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        ListTile(
                          title: const Text('全部',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          dense: true,
                          onTap: () {
                            onSelected('');
                            Navigator.of(ctx, rootNavigator: true).pop();
                          },
                        ),
                        for (final opt in filtered)
                          ListTile(
                            title: Text(opt),
                            dense: true,
                            onTap: () {
                              onSelected(opt);
                              Navigator.of(ctx, rootNavigator: true).pop();
                            },
                          ),
                        if (filtered.isEmpty && query.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('未找到 "$query"',
                                style: TextStyle(color: Colors.grey.shade500)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
                child: const Text('取消'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlanCard(ZjuTrainingPlan p) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(p.planName,
                      style:
                          const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                if (p.planNo != null && p.planNo!.isNotEmpty) ...[
                  Tooltip(
                    message: '教学计划号 ${p.planNo}',
                    child: Icon(Icons.tag, size: 16,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    tooltip: '查看培养方案文档',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openPlanPdf(p),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (p.major != null && p.major!.isNotEmpty)
              _infoRow(Icons.school, p.major!),
            if (p.college != null && p.college!.isNotEmpty)
              _infoRow(Icons.domain, p.college!),
            if (p.grade != null && p.grade!.isNotEmpty)
              _infoRow(Icons.people, '${p.grade}级'),
            if (p.level != null && p.level!.isNotEmpty)
              _infoRow(Icons.cast_for_education, p.level!),
            if (p.minCredits > 0) _infoRow(Icons.star, '最低 ${p.minCredits} 学分'),
            if (p.remarks != null && p.remarks!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  p.remarks!.length > 120
                      ? '${p.remarks!.substring(0, 120)}...'
                      : p.remarks!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 下载培养方案 PDF 并用系统默认程序打开（D1 降级方案，B3-ui）。
  ///
  /// 参考实现内嵌 PdfPreviewWidget（pdfrx）阅读，evg-base 曾因 Windows 构建
  /// 失败移除 pdfx；本轮先「下载到临时目录 + url_launcher 系统打开」，
  /// pdfrx 单独验证构建通过后再升级内嵌阅读器。
  Future<void> _openPlanPdf(ZjuTrainingPlan plan) async {
    if (plan.planNo == null || plan.planNo!.isEmpty) return;
    // 加载对话框（对齐参考 `_downloadAndOpenPlan`：barrierDismissible false）。
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final service = await ensureZdbkSession(prefs: prefs);
      final path =
          await service.downloadPlanPdf(service.httpClient!, plan.planNo!);
      if (!mounted) return;
      // 必须在 post-frame 中 pop，避免 await 在 build 帧恢复时触发 _debugLocked 断言。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      });

      final opened = await launchUrl(Uri.file(path));
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已下载到 $path，请手动打开'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('培养方案 PDF 下载失败：$e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
