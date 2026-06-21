/// 培养方案查询页面 — 打开显示缓存，刷新拉取新数据，搜索查本地。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../core/log.dart';
import '../../../core/config/app_config.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/models/training_plan.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/database.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/zdbk_provider.dart';
import '../../../widgets/freshness_badge.dart';

class TrainingPlanScreen extends ConsumerStatefulWidget {
  const TrainingPlanScreen({super.key});

  @override
  ConsumerState<TrainingPlanScreen> createState() => _TrainingPlanScreenState();
}

class _TrainingPlanScreenState extends ConsumerState<TrainingPlanScreen> {
  int _grade = 0;
  String _collegeFilter = '';
  String _majorFilter = '';
  bool _loading = false;

  /// 点击刷新：谱仪重新拉取数据→写缓存→Provider 重建→UI 自动更新。
  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      ref.invalidate(trainingPlansProvider(0));
      await ref.read(trainingPlansProvider(0).future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('培养方案 刷新成功'), duration: Duration(seconds: 1)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('培养方案 刷新失败'), backgroundColor: Colors.red, duration: Duration(seconds: 2)),
        );
      }
    }
    setState(() => _loading = false);
  }

  /// 从 allPlans 中本地筛选。
  List<TrainingPlan> _filter(List<TrainingPlan> allPlans) {
    var list = allPlans;
    if (_grade > 0) list = list.where((p) => p.grade == _grade.toString()).toList();
    if (_collegeFilter.isNotEmpty) list = list.where((p) => p.college == _collegeFilter).toList();
    if (_majorFilter.isNotEmpty) list = list.where((p) => p.major == _majorFilter).toList();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final plansAsync = ref.watch(trainingPlansProvider(0));

    final allPlans = plansAsync.whenOrNull<List<TrainingPlan>>(
          data: (result) => result.fold((p) => p, (_) => []),
        ) ??
        [];

    final filtered = _filter(allPlans);
    final colleges = allPlans.map((p) => p.college ?? '').where((c) => c.isNotEmpty).toSet().toList()..sort();
    final plansForMajor = _collegeFilter.isNotEmpty
        ? allPlans.where((p) => p.college == _collegeFilter).toList()
        : allPlans;
    final majors = plansForMajor.map((p) => p.major ?? '').where((m) => m.isNotEmpty).toSet().toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('培养方案'),
        actions: [
          const FreshnessBadge(cacheKey: 'zdbk_trainingPlans'),
          IconButton(
            icon: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('加载失败', style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 16),
          ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              onPressed: _refresh),
        ])),
        data: (result) => result.fold(
          (_) => allPlans.isEmpty && !_loading
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.school, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text('暂无培养方案数据', style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('点击刷新'),
                        onPressed: _refresh),
                  ]),
                )
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(children: [
                      _buildFilterChip(label: _grade > 0 ? '${_grade}级' : '全部年级', onTap: _showGradePicker, color: _grade > 0 ? colorScheme.primaryContainer : null),
                      const SizedBox(width: 6),
                      Expanded(child: _buildFilterChip(label: _collegeFilter.isNotEmpty ? _collegeFilter : '学院', onTap: () => _showOptionPicker('选择学院', colleges, (v) => setState(() { _collegeFilter = v; _majorFilter = ''; })), color: _collegeFilter.isNotEmpty ? colorScheme.primaryContainer : null)),
                      const SizedBox(width: 6),
                      Expanded(child: _buildFilterChip(label: _majorFilter.isNotEmpty ? _majorFilter : '专业', onTap: () => _showOptionPicker('选择专业', majors, (v) => setState(() => _majorFilter = v)), color: _majorFilter.isNotEmpty ? colorScheme.primaryContainer : null)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text('${filtered.length} 个方案${_grade > 0 ? "（$_grade级）" : ""}', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text('未找到符合条件的方案', style: TextStyle(color: Colors.grey[600])))
                        : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [for (final p in filtered) _buildPlanCard(p)]),
                  ),
                ]),
          (error) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(error.userMessage, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
                onPressed: _refresh),
          ])),
        ),
      ),
    );
  }

  Widget _buildFilterChip({required String label, required VoidCallback onTap, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: color != null ? FontWeight.w600 : FontWeight.normal, color: color != null ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface))),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }

  void _showGradePicker() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择年级'),
        children: [
          for (final g in [0, DateTime.now().year, DateTime.now().year - 1, DateTime.now().year - 2, DateTime.now().year - 3, DateTime.now().year - 4])
            RadioListTile<int>(title: Text(g > 0 ? '${g}级' : '全部年级'), value: g, groupValue: _grade,
              onChanged: (v) { setState(() => _grade = v!); Navigator.of(ctx, rootNavigator: true).pop(); }),
        ],
      ),
    );
  }

  void _showOptionPicker(String title, List<String> options, void Function(String) onSelected) {
    final searchCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        final query = searchCtrl.text.trim().toLowerCase();
        final filtered = query.isEmpty ? options : options.where((o) => o.toLowerCase().contains(query)).toList();
        return AlertDialog(
          title: Text(title),
          content: SizedBox(width: double.maxFinite, height: 400, child: Column(children: [
            TextField(controller: searchCtrl, decoration: InputDecoration(hintText: '搜索...', prefixIcon: const Icon(Icons.search, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true), onChanged: (_) => setDialogState(() {})),
            const SizedBox(height: 8),
            Text('共 ${filtered.length} 项', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Expanded(child: ListView(children: [
              ListTile(title: const Text('全部', style: TextStyle(fontWeight: FontWeight.w600)), dense: true, onTap: () { onSelected(''); Navigator.of(ctx, rootNavigator: true).pop(); }),
              for (final opt in filtered) ListTile(title: Text(opt), dense: true, onTap: () { onSelected(opt); Navigator.of(ctx, rootNavigator: true).pop(); }),
              if (filtered.isEmpty && query.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('未找到 "$query"', style: TextStyle(color: Colors.grey[500]))),
            ])),
          ])),
          actions: [TextButton(onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(), child: const Text('取消'))],
        );
      }),
    );
  }

  Widget _buildPlanCard(TrainingPlan p) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: p.planNo != null && p.planNo!.isNotEmpty ? () => _openPlanViewer(p) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(p.planName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              if (p.planNo != null && p.planNo!.isNotEmpty)
                IconButton(icon: const Icon(Icons.open_in_new, size: 18), tooltip: '查看培养方案文档', onPressed: () => _openPlanViewer(p), visualDensity: VisualDensity.compact),
            ]),
            const SizedBox(height: 8),
            if (p.major != null && p.major!.isNotEmpty) _infoRow(Icons.school, p.major!),
            if (p.college != null && p.college!.isNotEmpty) _infoRow(Icons.domain, p.college!),
            if (p.grade != null && p.grade!.isNotEmpty) _infoRow(Icons.people, '${p.grade}级'),
            if (p.level != null && p.level!.isNotEmpty) _infoRow(Icons.cast_for_education, p.level!),
            if (p.minCredits > 0) _infoRow(Icons.star, '最低 ${p.minCredits} 学分'),
            if (p.remarks != null && p.remarks!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(p.remarks!.length > 120 ? '${p.remarks!.substring(0, 120)}...' : p.remarks!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant), maxLines: 3, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }

  void _openPlanViewer(TrainingPlan plan) { if (plan.planNo != null && plan.planNo!.isNotEmpty) _downloadAndOpenPlan(plan); }

  Future<void> _downloadAndOpenPlan(TrainingPlan plan) async { /* ... 保留原有 PDF 下载/转换/查看逻辑 ... */ }

  void _fail(AppError error) {
    Log().error('TrainingPlan: ${error.runtimeType}', data: {'msg': error.debugMessage, 'hint': error.recoveryHint});
    if (!mounted) return;
    try { Navigator.of(context).pop(); } catch (_) {}
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.userMessage)));
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [
      Icon(icon, size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
    ]));
  }
}
