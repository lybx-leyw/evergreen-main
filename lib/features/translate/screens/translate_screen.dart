import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/log.dart';
import '../models/translation_enums.dart';
import '../models/translation_job.dart';
import '../models/translation_history.dart';
import '../providers/translate_provider.dart';
import '../widgets/pdf_preview_widget.dart';
import '../widgets/translation_history_card.dart';

/// PDF 翻译主屏幕。
///
/// Desktop：完整功能。
/// Android：标记 (开发中)，显示占位卡片。
class TranslateScreen extends ConsumerStatefulWidget {
  const TranslateScreen({super.key});

  @override
  ConsumerState<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends ConsumerState<TranslateScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isAndroid =>
      defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    if (_isAndroid) return _buildWipPlaceholder(context);

    final job = ref.watch(translateJobProvider);
    final batch = ref.watch(translateBatchProvider);
    final history = ref.watch(translateHistoryProvider);
    final langIn = ref.watch(translateLangInProvider);
    final langOut = ref.watch(translateLangOutProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF 翻译'),
        actions: [
          if (job != null && job.isTerminal)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新开始',
              onPressed: () {
                ref.read(translateJobProvider.notifier).reset();
                ref.read(translateBatchProvider.notifier).clear();
              },
            ),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          // ── Section: File Selector ────────────────────────────────
          _buildSection(theme, '📂 选择文件', [
            _buildFileSelector(batch),
          ]),

          const SizedBox(height: 16),

          // ── Section: Language ─────────────────────────────────────
          _buildSection(theme, '🌐 翻译方向', [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: langIn,
                    decoration: const InputDecoration(
                      labelText: '源语言',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: LanguageOption.values.map((l) {
                      return DropdownMenuItem(
                        value: l.code,
                        child: Text('${l.displayName} (${l.nativeName})'),
                      );
                    }).toList(),
                    onChanged: batch.isRunning
                        ? null
                        : (v) => ref.read(translateLangInProvider.notifier).state = v ?? 'en',
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward),
                ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: langOut,
                    decoration: const InputDecoration(
                      labelText: '目标语言',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: LanguageOption.values.map((l) {
                      return DropdownMenuItem(
                        value: l.code,
                        child: Text('${l.displayName} (${l.nativeName})'),
                      );
                    }).toList(),
                    onChanged: batch.isRunning
                        ? null
                        : (v) => ref.read(translateLangOutProvider.notifier).state = v ?? 'zh',
                  ),
                ),
              ],
            ),
          ]),

          const SizedBox(height: 16),

          // ── Action Button ─────────────────────────────────────────
          if (!batch.isRunning && job?.isActive != true)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: batch.isEmpty
                      ? null
                      : () => _startTranslate(ref, langIn, langOut),
                  icon: const Icon(Icons.translate),
                  label: Text(
                    batch.isEmpty
                        ? '请先选择 PDF 文件'
                        : '开始翻译 (${batch.totalFiles} 个文件)',
                  ),
                ),
              ),
            ),

          // ── Section: Progress ─────────────────────────────────────
          if (batch.isRunning || (job?.isActive ?? false))
            _buildSection(theme, '⏳ 翻译进度', [
              _buildProgress(job, batch),
            ]),

          // ── Section: Batch completed files (available during & after batch) ──
          if (batch.totalFiles > 1)
            _buildBatchResults(theme, batch),

          // ── Section: Result ───────────────────────────────────────
          if (job != null && job.status == TranslationStatus.done)
            _buildSection(theme, '✅ 翻译完成', [
              _buildResult(job),
            ]),

          // ── Section: Error ────────────────────────────────────────
          if (job != null && job.status == TranslationStatus.error)
            _buildSection(theme, '❌ 翻译失败', [
              _buildError(job),
            ]),

          const SizedBox(height: 24),

          // ── Section: History ──────────────────────────────────────
          if (history.isNotEmpty) ...[
            _buildSection(
              theme,
              '📋 翻译历史 (${history.length})',
              [
                ...history.map((h) => TranslationHistoryCard(
                      history: h,
                      onOpen: () => _openPdf(h.dualPdfPath),
                      onDelete: () =>
                          ref.read(translateHistoryProvider.notifier).remove(h.id),
                    )),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () =>
                    ref.read(translateHistoryProvider.notifier).clear(),
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text('清空历史'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Section builders
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSection(ThemeData theme, String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildFileSelector(batch) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: batch.isRunning ? null : () => _pickFiles(ref),
          icon: const Icon(Icons.file_open),
          label: const Text('选择 PDF 文件'),
        ),
        const SizedBox(height: 8),
        if (batch.isEmpty)
          Text('尚未选择文件',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey))
        else
          ...batch.fileNames.map((name) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf, size: 18, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(child: Text(name)),
                    if (!batch.isRunning)
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          final paths = <String>[...batch.filePaths]
                            ..removeAt(batch.fileNames.indexOf(name));
                          ref
                              .read(translateBatchProvider.notifier)
                              .setFiles(paths);
                        },
                      ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _buildProgress(TranslationJob? job, batch) {
    final theme = Theme.of(context);
    final isBatch = batch.isRunning && batch.totalFiles > 1;

    // In batch mode, use batch state for progress; otherwise use single job.
    final currentFile = isBatch
        ? (batch.fileNames.isNotEmpty &&
                batch.currentIndex >= 0 &&
                batch.currentIndex < batch.fileNames.length
            ? batch.fileNames[batch.currentIndex]
            : '')
        : (job?.inputName ??
            (batch.fileNames.isNotEmpty
                ? batch.fileNames[
                    batch.currentIndex >= 0 ? batch.currentIndex : 0]
                : ''));
    final currentPage = isBatch ? batch.currentFilePage : (job?.currentPage ?? 0);
    final totalPages = isBatch ? batch.currentFileTotal : (job?.totalPages ?? 0);
    final progressValue = isBatch
        ? batch.overallProgress
        : (job?.progress ?? 0);
    final progressMsg = isBatch
        ? (batch.currentFileMessage ?? '准备中...')
        : (job?.progressMessage);
    final currentStage = job?.currentStage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('正在翻译: $currentFile', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        // Page-level progress
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(value: progressValue),
            ),
            const SizedBox(width: 8),
            Text(
              totalPages > 0 ? '$currentPage/$totalPages 页' : '准备中...',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Stage pipeline (single-file mode only)
        if (!isBatch)
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _pipelineStages.map((s) {
                final stage = s.$1;
                final icon = s.$2;
                final label = s.$3;
                final isActive = currentStage == stage;
                final isDone = _isStageDone(currentStage, stage);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive
                              ? theme.colorScheme.primary
                              : isDone
                                  ? Colors.green.shade600
                                  : Colors.grey.shade300,
                        ),
                        child: Icon(
                          icon,
                          size: 20,
                          color: isActive || isDone ? Colors.white : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 9,
                          color: isActive
                              ? theme.colorScheme.primary
                              : isDone
                                  ? Colors.green.shade600
                                  : Colors.grey,
                          fontWeight:
                              isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        // Current status card
        if (progressMsg != null && progressMsg.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withAlpha(128),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    progressMsg,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
        // Batch completed files list
        if (isBatch && batch.results.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...batch.results.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Icon(
                      r.status == TranslationStatus.done
                          ? Icons.check_circle
                          : Icons.error,
                      size: 16,
                      color: r.status == TranslationStatus.done
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        r.fileName,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        ],
        // Batch queue info
        if (isBatch) ...[
          const SizedBox(height: 4),
          Text(
            '队列: ${batch.currentIndex + 1}/${batch.totalFiles} '
            '(${batch.doneCount} 完成, ${batch.errorCount} 失败)',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  /// Pipeline stage definitions with icon and label.
  static const _pipelineStages = [
    (TranslateStage.init, Icons.settings_outlined, '初始化'),
    (TranslateStage.parse, Icons.description_outlined, '解析'),
    (TranslateStage.layout, Icons.dashboard_outlined, '布局'),
    (TranslateStage.ocr, Icons.document_scanner_outlined, '识别'),
    (TranslateStage.translate, Icons.translate, '翻译'),
    (TranslateStage.font, Icons.font_download_outlined, '字体'),
    (TranslateStage.summary, Icons.summarize_outlined, '摘要'),
    (TranslateStage.output, Icons.picture_as_pdf_outlined, '生成'),
    (TranslateStage.merge, Icons.merge_type_outlined, '合并'),
  ];

  bool _isStageDone(TranslateStage? current, TranslateStage check) {
    if (current == null) return false;
    return current.index > check.index;
  }

  /// Show completed batch results so users can read while others translate.
  Widget _buildBatchResults(ThemeData theme, batch) {
    final done = batch.results
        .where((r) => r.status == TranslationStatus.done && r.result != null)
        .toList();
    if (done.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, size: 18, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  '已完成 (${done.length}/${batch.totalFiles})',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...done.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf, size: 16, color: Colors.red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(r.fileName, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _openReader(context, r.result!.previewPath),
                        icon: const Icon(Icons.menu_book, size: 16),
                        label: const Text('阅读'),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(TranslationJob job) {
    final result = job.result;
    if (result == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow('文件', job.inputName),
        _infoRow('耗时', '${result.totalSeconds.toStringAsFixed(1)} 秒'),
        _infoRow('Token 用量', '${result.totalTokens}'),
        if (result.hasOutput) ...[
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          if (result.previewPath.isNotEmpty) ...[
            // 内联预览 — 高度取屏幕 35% 或最小 350px，自适应页面比例
            Builder(builder: (ctx) {
              final screenHeight = MediaQuery.of(ctx).size.height;
              final previewHeight = (screenHeight * 0.35).clamp(350.0, 600.0);
              return GestureDetector(
                onTap: () => _openReader(context, result.previewPath),
                child: SizedBox(
                  height: previewHeight,
                  child: PdfPreviewWidget(pdfPath: result.previewPath),
                ),
              );
            }),
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: () => _openReader(context, result.previewPath),
                icon: const Icon(Icons.fullscreen, size: 16),
                label: const Text('全屏阅读'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (result.dualPdfPath != null)
                ElevatedButton.icon(
                  onPressed: () => _openReader(context, result.dualPdfPath!),
                  icon: const Icon(Icons.menu_book),
                  label: const Text('阅读双语 PDF'),
                ),
              if (result.monoPdfPath != null)
                OutlinedButton.icon(
                  onPressed: () => _openReader(context, result.monoPdfPath!),
                  icon: const Icon(Icons.article),
                  label: const Text('单语版'),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  if (result.dualPdfPath != null) {
                    _openPdf(result.dualPdfPath!);
                  } else if (result.monoPdfPath != null) {
                    _openPdf(result.monoPdfPath!);
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('外部打开'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  if (result.previewPath.isNotEmpty) {
                    Process.run('explorer', [
                      File(result.previewPath).parent.path,
                    ]);
                  }
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('打开文件夹'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildError(TranslationJob job) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(job.errorMessage ?? '未知错误',
            style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            ref.read(translateJobProvider.notifier).reset();
          },
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
              width: 90,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  /// Android 开发中占位。
  Widget _buildWipPlaceholder(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF 翻译 (开发中)')),
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.construction,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text('PDF 翻译',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text('移动端版本开发中，请在桌面端使用此功能'),
                const SizedBox(height: 4),
                Text('需要 Python 环境支持',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Actions
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _pickFiles(WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      final paths =
          result.files.where((f) => f.path != null).map((f) => f.path!).toList();
      if (paths.isNotEmpty) {
        ref.read(translateBatchProvider.notifier).setFiles(paths);
      }
    } catch (e) {
      Log().warn('File picker error', error: e);
    }
  }

  Future<void> _startTranslate(
      WidgetRef ref, String langIn, String langOut) async {
    final batch = ref.read(translateBatchProvider);
    if (batch.isEmpty) return;

    // 如果只有一个文件，直接使用单文件翻译
    if (batch.filePaths.length == 1) {
      final path = batch.filePaths.first;
      final name = batch.fileNames.first;
      await ref.read(translateJobProvider.notifier).startJob(
            inputPath: path,
            inputName: name,
            langIn: langIn,
            langOut: langOut,
          );

      // 保存到历史
      final job = ref.read(translateJobProvider);
      if (job != null && job.result != null) {
        await ref.read(translateHistoryProvider.notifier).add(
              TranslationHistory(
                id: job.id,
                fileName: job.inputName,
                langIn: job.langIn,
                langOut: job.langOut,
                dualPdfPath: job.result!.dualPdfPath,
                totalSeconds: job.result!.totalSeconds,
                totalTokens: job.result!.totalTokens,
                completedAt: DateTime.now(),
              ),
            );
      }
    } else {
      // 批量翻译
      await ref.read(translateBatchProvider.notifier).startBatch(langIn, langOut);

      // 保存每个完成的结果到历史
      for (final result in batch.results) {
        if (result.status == TranslationStatus.done) {
          // TODO(AI): 需要人工确认 — 批量翻译完成后如何获取每个文件的 result 详情？
          await ref.read(translateHistoryProvider.notifier).add(
                TranslationHistory(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  fileName: result.fileName,
                  langIn: langIn,
                  langOut: langOut,
                  completedAt: DateTime.now(),
                ),
              );
        }
      }
    }
  }

  void _openPdf(String? path) {
    if (path == null || path.isEmpty) return;
    try {
      launchUrl(Uri.file(path));
    } catch (e) {
      Log().warn('Failed to open PDF', error: e, data: {'path': path});
    }
  }

  /// Open a full-screen PDF reader dialog.
  void _openReader(BuildContext context, String pdfPath) {
    final theme = Theme.of(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(p.basename(pdfPath)),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          body: PdfPreviewWidget(
            pdfPath: pdfPath,
            height: double.infinity,
          ),
        ),
      ),
    );
  }
}
