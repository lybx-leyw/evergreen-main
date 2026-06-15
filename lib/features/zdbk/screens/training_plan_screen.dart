/// 培养方案查询页面 — 查看个人培养方案与进度。
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
import '../../../widgets/loading_indicator.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/zdbk_provider.dart';

class TrainingPlanScreen extends ConsumerStatefulWidget {
  const TrainingPlanScreen({super.key});

  @override
  ConsumerState<TrainingPlanScreen> createState() =>
      _TrainingPlanScreenState();
}

class _TrainingPlanScreenState extends ConsumerState<TrainingPlanScreen> {
  int _grade = 0; // 0 = 全部年级
  String _collegeFilter = '';
  String _majorFilter = '';
  List<TrainingPlan>? _cachedPlans; // 缓存全量数据，避免切换年级时重复拉取

  @override
  Widget build(BuildContext context) {
    // 始终用 key=0 拉取全量数据（API 不支持按年级过滤）
    final async = ref.watch(trainingPlansProvider(0));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('培养方案'),
        actions: [
          PopupMenuButton<int>(
            tooltip: '选择年级',
            icon: const Icon(Icons.people),
            onSelected: (g) => setState(() {
              _grade = g;
              _collegeFilter = '';
              _majorFilter = '';
            }),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 0, child: Text('全部年级')),
              for (final g in [
                DateTime.now().year,
                DateTime.now().year - 1,
                DateTime.now().year - 2,
                DateTime.now().year - 3,
                DateTime.now().year - 4,
              ])
                PopupMenuItem(
                  value: g,
                  child: Text('${g}级${g == _grade ? ' ✓' : ''}'),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              _cachedPlans = null;
              ref.invalidate(trainingPlansProvider(0));
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 200, child: LinearProgressIndicator()),
              SizedBox(height: 12),
              Text('正在加载培养方案...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        error: (err, _) => ErrorCard(message: err.toString()),
        data: (result) => result.fold(
          (plans) {
            // 缓存全量数据
            _cachedPlans ??= plans;

            // 用全量数据提取筛选选项
            final allPlans = _cachedPlans!;
            final grades = allPlans.map((p) => p.grade ?? '').where((g) => g.isNotEmpty).toSet().toList()..sort();
            final colleges = allPlans.map((p) => p.college ?? '').where((c) => c.isNotEmpty).toSet().toList()..sort();

            // 专业列表依赖当前学院筛选
            final plansForMajor = _collegeFilter.isNotEmpty
                ? allPlans.where((p) => p.college == _collegeFilter).toList()
                : allPlans;
            final majors = plansForMajor
                .map((p) => p.major ?? '').where((m) => m.isNotEmpty).toSet().toList()..sort();

            // 综合筛选（年级 + 学院 + 专业）
            var filtered = allPlans;
            if (_grade > 0) {
              filtered = filtered.where((p) => p.grade == _grade.toString()).toList();
            }
            if (_collegeFilter.isNotEmpty) {
              filtered = filtered.where((p) => p.college == _collegeFilter).toList();
            }
            if (_majorFilter.isNotEmpty) {
              filtered = filtered.where((p) => p.major == _majorFilter).toList();
            }

            return Column(
              children: [
                // 三个筛选栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      _buildFilterChip(
                        label: _grade > 0 ? '${_grade}级' : '全部年级',
                        onTap: () => _showGradePicker(),
                        color: _grade > 0 ? colorScheme.primaryContainer : null,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildFilterChip(
                          label: _collegeFilter.isNotEmpty ? _collegeFilter : '学院',
                          onTap: () => _showOptionPicker(
                            '选择学院',
                            colleges,
                            (v) => setState(() => _collegeFilter = v),
                          ),
                          color: _collegeFilter.isNotEmpty ? colorScheme.primaryContainer : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildFilterChip(
                          label: _majorFilter.isNotEmpty ? _majorFilter : '专业',
                          onTap: () => _showOptionPicker(
                            '选择专业',
                            majors,
                            (v) => setState(() => _majorFilter = v),
                          ),
                          color: _majorFilter.isNotEmpty ? colorScheme.primaryContainer : null,
                        ),
                      ),
                    ],
                  ),
                ),
                // 统计信息
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    '${filtered.length} 个方案${_grade > 0 ? "（$_grade级）" : ""}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant),
                  ),
                ),
                // 列表
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 12),
                                Text('未找到符合条件的方案',
                                    style: TextStyle(color: Colors.grey[600])),
                                const SizedBox(height: 8),
                                if (_grade > 0 || _collegeFilter.isNotEmpty || _majorFilter.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: () => setState(() {
                                      _grade = 0;
                                      _collegeFilter = '';
                                      _majorFilter = '';
                                    }),
                                    icon: const Icon(Icons.clear, size: 16),
                                    label: const Text('清除筛选'),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          children: [
                            for (final p in filtered) _buildPlanCard(p),
                          ],
                        ),
                ),
              ],
            );
          },
          (error) => ErrorCard(
            message: error.userMessage,
            detail: error.debugMessage,
            hint: error.recoveryHint,
            onRetry: () {
              _cachedPlans = null;
              ref.invalidate(trainingPlansProvider(0));
            },
          ),
        ),
      ),
    );
  }

  /// 构建一个筛选 Chip。
  Widget _buildFilterChip({
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
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
                  fontWeight: color != null ? FontWeight.w600 : FontWeight.normal,
                  color: color != null
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  /// 年级选择弹窗。
  void _showGradePicker() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择年级'),
        children: [
          for (final g in [0, DateTime.now().year, DateTime.now().year - 1,
              DateTime.now().year - 2, DateTime.now().year - 3, DateTime.now().year - 4])
            RadioListTile<int>(
              title: Text(g > 0 ? '${g}级' : '全部年级'),
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

  /// 通用选项选择弹窗（学院/专业），支持搜索过滤。
  void _showOptionPicker(String title, List<String> options, void Function(String) onSelected) {
    final searchCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
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
                    // 搜索输入框
                    TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: '搜索...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        isDense: true,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text('共 ${filtered.length} 项',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                                  style: TextStyle(color: Colors.grey[500])),
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
        );
      },
    );
  }

  /// 构建一个方案卡片。
  Widget _buildPlanCard(TrainingPlan p) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: p.planNo != null && p.planNo!.isNotEmpty ? () => _openPlanViewer(p) : null,
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
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  if (p.planNo != null && p.planNo!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      tooltip: '查看培养方案文档',
                      onPressed: () => _openPlanViewer(p),
                      visualDensity: VisualDensity.compact,
                    ),
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
              if (p.minCredits > 0)
                _infoRow(Icons.star, '最低 ${p.minCredits} 学分'),
              if (p.remarks != null && p.remarks!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    p.remarks!.length > 120
                        ? '${p.remarks!.substring(0, 120)}...'
                        : p.remarks!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPlanViewer(TrainingPlan plan) {
    if (plan.planNo == null || plan.planNo!.isEmpty) return;
    _downloadAndOpenPlan(plan);
  }

  /// 下载 PDF → 转图片 → 应用内展示（带进度）。
  Future<void> _downloadAndOpenPlan(TrainingPlan plan) async {
    final planNo = plan.planNo ?? '';
    if (planNo.isEmpty) return;

    final progressNotifier = ValueNotifier('准备中...');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: progressNotifier,
              builder: (_, msg, __) => Text(msg, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ]),
      ),
    );

    void updateProgress(String msg) { progressNotifier.value = msg; }

    try {
      // === 1. 下载 PDF ===
      updateProgress('正在下载培养方案 PDF...');
      final httpClient = ref.read(httpClientProvider);
      final auth = ref.read(authProvider);
      final service = await ref.read(zdbkServiceInstanceProvider.future);
      if (!service.isLoggedIn && auth.ssoCookie != null) {
        await service.login(httpClient, auth.ssoCookie!);
      }

      final pdfResult = await service.downloadPlanPdf(httpClient, planNo);
      if (pdfResult.isErr) { _fail((pdfResult as Err).error); return; }
      final pdfPath = (pdfResult as Ok<String>).value;

      // 保存一份到用户下载目录（如果已配置）
      final dlDir = AppConfig.downloadPath;
      if (dlDir != null && dlDir.isNotEmpty) {
        try {
          final savedName = '培养方案_${planNo}.pdf';
          final savedPath = '$dlDir${Platform.pathSeparator}$savedName';
          await File(pdfPath).copy(savedPath);
          Log().info('TrainingPlan PDF saved', data: {'path': savedPath});
        } catch (e) {
          Log().warn('TrainingPlan PDF save failed', error: e);
        }
      }

      // === 2. PDF → 图片 ===
      updateProgress('正在转换 PDF 为图片...');
      final tmpDir = Directory.systemTemp;
      final script = p.join(Directory.current.path, 'scripts', 'pdf_to_images.py');
      if (!File(script).existsSync()) {
        _fail(AppError.fileError(script, 'read', osError: '脚本不存在')); return;
      }

      final outDir = '${tmpDir.path}${Platform.pathSeparator}pyfa_img_$planNo';
      final imgProc = await Process.run('python', [
        script, '--path', pdfPath, '--output_dir', outDir, '--skip-ocr',
      ]).timeout(const Duration(seconds: 120));

      if (imgProc.exitCode != 0) {
        _fail(AppError.fileError(script, 'convert',
            osError: imgProc.stderr?.toString())); return;
      }

      final output = imgProc.stdout?.toString() ?? '';
      Map parsed;
      try { parsed = jsonDecode(output) as Map; }
      catch (e) { _fail(AppError.parseJson(output, 'pdf_to_images output')); return; }

      if (parsed['error'] != null) {
        _fail(AppError.fileError(script, 'convert',
            osError: parsed['error']?.toString())); return;
      }

      final pages = (parsed['pages'] as List?)?.cast<Map>() ?? [];
      if (pages.isEmpty) { _fail(AppError.fileError(script, 'convert',
          osError: '无页面')); return; }

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      // === 3. 跳转到图片查看器 ===
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _PdfImageViewer(
          title: plan.planName,
          pages: pages.map((p) => p['path'] as String).toList(),
        ),
      ));
    } on AppError catch (e) {
      _fail(e);
    } catch (e, stack) {
      Log().error('TrainingPlan: unexpected error', error: e, stack: stack);
      _fail(AppError.unknown(e));
    }
  }

  /// 统一错误处理：Log → 关弹窗 → 简短的 SnackBar。
  void _fail(AppError error) {
    Log().error('TrainingPlan: ${error.runtimeType}',
        data: {'msg': error.debugMessage, 'hint': error.recoveryHint});
    if (!mounted) return;
    try { Navigator.of(context).pop(); } catch (_) {}
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.userMessage)),
    );
  }

  /// 备用文本查看。
  void _showFallbackText(TrainingPlan plan) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(plan.planName, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(plan.remarks ?? '',
                style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// PDF 图片查看器 — 逐页浏览 + 缩放，类似 PptViewer。
class _PdfImageViewer extends StatefulWidget {
  final String title;
  final List<String> pages;

  const _PdfImageViewer({required this.title, required this.pages});

  @override
  State<_PdfImageViewer> createState() => _PdfImageViewerState();
}

class _PdfImageViewerState extends State<_PdfImageViewer> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: LinearProgressIndicator(
            value: (_currentPage + 1) / widget.pages.length,
            minHeight: 2,
          ),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.file(
            File(widget.pages[_currentPage]),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, size: 64),
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _currentPage > 0
                  ? () => setState(() => _currentPage--)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${_currentPage + 1} / ${widget.pages.length}'),
            IconButton(
              onPressed: _currentPage < widget.pages.length - 1
                  ? () => setState(() => _currentPage++)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
