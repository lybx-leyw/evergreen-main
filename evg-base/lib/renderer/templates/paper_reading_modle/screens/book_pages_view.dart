/// 书本翻页视图 — 双页展开，翻页浏览技法标题卡片。
///
/// 每页只显示一个技法标题卡片（或 + 导入新技法）。
/// 创新本：每页一个技法 → 点击进入星空。
/// 综述本：每页一篇综述论文 → 点击进入探索标签。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/config/settings.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/python_env.dart';
import '../paper_reading_models.dart';
import '../paper_reading_state.dart';
import '../services/paper_service.dart';
import '../services/paper_vision_service.dart' show PaperVisionService, VisionResult;
import '../services/book_persistence.dart';
import '../components/technique_title_card.dart';

class BookPagesView extends ConsumerStatefulWidget {
  const BookPagesView({super.key});

  @override
  ConsumerState<BookPagesView> createState() => _BookPagesViewState();
}

class _BookPagesViewState extends ConsumerState<BookPagesView> {
  late PageController _pageController;
  int _currentPage = 0;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    final idx = ref.read(currentBookPageProvider);
    _currentPage = idx;
    _pageController = PageController(initialPage: idx);
    _updateTotalPages();
  }

  void _updateTotalPages() {
    final notebook = ref.read(innovationNotebookProvider);
    final type = ref.read(currentNotebookTypeProvider);
    final list = type == NotebookType.survey
        ? notebook.papers
        : notebook.techniques;
    // 每个技法/论文占一页，末页 + 添加占位
    _totalPages = list.isEmpty ? 1 : list.length + 1;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentNotebookTypeProvider, (_, __) {
      _updateTotalPages();
    });

    final notebook = ref.watch(
      ref.watch(currentNotebookTypeProvider) == NotebookType.survey
          ? surveyNotebookProvider
          : innovationNotebookProvider);
    final type = ref.watch(currentNotebookTypeProvider) ??
        NotebookType.innovation;
    final isInnovation = type == NotebookType.innovation;

    final colors = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < 600;
    final spreadWidth = isNarrow ? size.width : size.width * 0.86;

    return Scaffold(
      backgroundColor: const Color(0xFF2D1B00),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => popView(ref),
        ),
        title: Text(
            isInnovation ? '创新技法笔记本' : '综述笔记本'),
        backgroundColor: const Color(0xFF4A2C00),
        foregroundColor: const Color(0xFFD4A853),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => _showImportDialog(context),
            icon: const Icon(Icons.add, color: Color(0xFFD4A853)),
            label: const Text('导入论文',
                style: TextStyle(color: Color(0xFFD4A853))),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: Container(
          width: spreadWidth.clamp(320, 1000),
          height: size.height * 0.78,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E7),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(180),
                blurRadius: 40,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                // 书脊中线
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: CustomPaint(
                    painter: _SpinePainter(),
                  ),
                ),
                // 双页翻页
                PageView.builder(
                  controller: _pageController,
                  onPageChanged: (idx) {
                    setState(() => _currentPage = idx);
                    ref
                        .read(currentBookPageProvider.notifier)
                        .state = idx;
                  },
                  itemCount: _totalPages,
                  itemBuilder: (context, index) {
                    return _buildSpread(
                        notebook, index, isInnovation, spreadWidth);
                  },
                ),
                // 翻页控件
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: _currentPage > 0
                      ? _PageTurnButton(
                          direction: 'prev',
                          onTap: () => _pageController.previousPage(
                              duration:
                                  const Duration(milliseconds: 500),
                              curve: Curves.easeInOut),
                        )
                      : const SizedBox.shrink(),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _currentPage < _totalPages - 1
                      ? _PageTurnButton(
                          direction: 'next',
                          onTap: () => _pageController.nextPage(
                              duration:
                                  const Duration(milliseconds: 500),
                              curve: Curves.easeInOut),
                        )
                      : const SizedBox.shrink(),
                ),
                // 页码
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Text(
                    '— ${_currentPage + 1} / $_totalPages —',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          const Color(0xFF8B6914).withAlpha(153),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpread(NotebookData notebook, int index,
      bool isInnovation, double spreadWidth) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Row(
        children: [
          // 左页
          Expanded(
            child: _buildPage(notebook, index, isInnovation, true),
          ),
          // 右页
          Expanded(
            child: _buildPage(
                notebook, index + 1, isInnovation, false),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(NotebookData notebook, int globalIndex,
      bool isInnovation, bool isLeft) {
    final maxItems = isInnovation
        ? notebook.techniques.length
        : notebook.papers.length;

    if (globalIndex >= maxItems) {
      // 添加按钮
      return GestureDetector(
        onTap: () => _showImportDialog(context),
        child: Container(
          margin: EdgeInsets.only(
              left: isLeft ? 0 : 16, right: isLeft ? 16 : 0),
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0xFF8B6914).withAlpha(51),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_circle_outline,
                    size: 48, color: Color(0xFFCCAA66)),
                SizedBox(height: 12),
                Text('导入新技法',
                    style: TextStyle(
                        color: Color(0xFFBB9944),
                        fontSize: 16)),
              ],
            ),
          ),
        ),
      );
    }

    if (isInnovation) {
      final tech = notebook.techniques[globalIndex];
      return _buildTechniqueCard(notebook, tech, isLeft,
          () {
        ref
            .read(selectedTechniqueIndexProvider.notifier)
            .state = globalIndex;
        pushView(ref, PaperReadingViewType.starfield);
      });
    } else {
      // 综述本：每页一篇综述论文
      final paper = notebook.papers[globalIndex];
      return _buildSurveyCard(notebook, paper, isLeft, () {
        ref
            .read(selectedPaperIdProvider.notifier)
            .state = paper.id;
        pushView(ref, PaperReadingViewType.explorationTags);
      });
    }
  }

  Widget _buildTechniqueCard(NotebookData notebook,
      TechniqueEntry tech, bool isLeft, VoidCallback onTap) {
    final variantCount = tech.paperIds.length;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: TechniqueTitleCard(
          name: tech.name,
          fullName: tech.fullName,
          description: tech.description,
          variantCount: variantCount,
          isLeft: isLeft,
        ),
      ),
    );
  }

  Widget _buildSurveyCard(NotebookData notebook,
      PaperRecord paper, bool isLeft, VoidCallback onTap) {
    final tags = paper.title.length > 50
        ? '${paper.title.substring(0, 50)}...'
        : paper.title;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: TechniqueTitleCard(
          name: paper.title,
          fullName: paper.authors.join(', '),
          description: tags.isNotEmpty ? tags : '暂无标签',
          variantCount: paper.segments.length,
          isLeft: isLeft,
          isPaper: true,
        ),
      ),
    );
  }

  Future<void> _showImportDialog(BuildContext context) async {
    debugPrint('[BookPages] _showImportDialog');
    final pythonPath = await _resolvePythonPath();
    showDialog(
      context: context,
      builder: (ctx) => _VisionImportDialog(
        apiKey: _resolveApiKey(),
        pythonPath: pythonPath,
        scriptDir: greenixScriptsDir,
        onImport: (VisionResult result) {
          debugPrint('[BookPages] onImport: ${result.chapters.length} chapters, ${result.totalParagraphs} paras');
          final paperId = 'paper_${DateTime.now().millisecondsSinceEpoch}';
          final paper = PaperRecord(
            id: paperId,
            title: result.chapters.isNotEmpty ? result.chapters.first.title : '导入',
            authors: ['Unknown'], filePath: '',
            paperType: PaperType.innovation, importedAt: DateTime.now(),
            fullText: result.fullText,
          );
          // 存储章节
          final chCurrent = ref.read(chaptersProvider);
          ref.read(chaptersProvider.notifier).state = {...chCurrent, paperId: result.chapters};
          ref.read(fullTextProvider.notifier).state = {
            ...ref.read(fullTextProvider), paperId: result.fullText,
          };
          ref.read(selectedPaperIdProvider.notifier).state = paperId;

          final type = ref.read(currentNotebookTypeProvider) ?? NotebookType.innovation;
          if (type == NotebookType.survey) {
            final notebook = ref.read(surveyNotebookProvider);
            ref.read(surveyNotebookProvider.notifier).state =
                notebook.copyWith(papers: [...notebook.papers, paper]);
          } else {
            _showTechniqueChoiceDialog(context, paper);
          }
        },
      ),
    );
  }

  String _resolveApiKey() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY');
      if (apiKey != null && apiKey.isNotEmpty) return apiKey;
    } catch (_) {}
    return '';
  }

  String _resolveOcrApiKey() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final key = getSetting(prefs, 'DEEPSEEK_OCR_API_KEY');
      if (key != null && key.isNotEmpty) return key;
    } catch (_) {}
    return '';
  }

  Future<String> _resolvePythonPath() async => await resolvePythonExe() ?? 'python';

  void _showTechniqueChoiceDialog(BuildContext context, PaperRecord paper) {
    final notebook = ref.read(innovationNotebookProvider);
    final techName = paper.techniqueName ?? 'Unknown';
    final existingTech = notebook.techniques.where(
        (t) => t.name.toLowerCase() == techName.toLowerCase());
    final hasExisting = existingTech.isNotEmpty;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          String selectedTechId = hasExisting ? existingTech.first.id : '';
          String newTechName = '';

          return AlertDialog(
            title: const Text('论文归入技法'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('检测到技法：$techName',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                if (hasExisting) ...[
                  const Text('已有此技法，是否归入？'),
                  const SizedBox(height: 8),
                  ...existingTech.map((t) => ListTile(
                        title: Text(t.name),
                        subtitle: Text(t.fullName),
                        leading: Radio<String>(
                          value: t.id,
                          groupValue: selectedTechId,
                          onChanged: (v) =>
                              setDialogState(() => selectedTechId = v!),
                        ),
                        dense: true,
                      )),
                ],
                const Divider(),
                const Text('或创建新技法：'),
                TextField(
                  decoration: InputDecoration(
                    hintText: '新技法名称',
                    hintStyle: const TextStyle(fontSize: 13),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                  onChanged: (v) => newTechName = v,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (newTechName.isNotEmpty) {
                    // 创建新技法
                    final newTech = TechniqueEntry(
                      id: 'tech_${DateTime.now().millisecondsSinceEpoch}',
                      name: newTechName,
                      fullName: paper.title,
                      description: paper.authors.join(', '),
                      orderIndex: notebook.techniques.length,
                      paperIds: [paper.id],
                    );
                    ref.read(innovationNotebookProvider.notifier).state =
                        notebook.copyWith(
                      techniques: [...notebook.techniques, newTech],
                      papers: [...notebook.papers, paper],
                    );
                  } else if (selectedTechId.isNotEmpty) {
                    // 归入已有技法
                    final updatedTechs = notebook.techniques.map((t) {
                      if (t.id == selectedTechId) {
                        return TechniqueEntry(
                          id: t.id,
                          name: t.name,
                          fullName: t.fullName,
                          description: t.description,
                          orderIndex: t.orderIndex,
                          paperIds: [...t.paperIds, paper.id],
                        );
                      }
                      return t;
                    }).toList();
                    ref.read(innovationNotebookProvider.notifier).state =
                        notebook.copyWith(
                      techniques: updatedTechs,
                      papers: [...notebook.papers, paper],
                    );
                  } else {
                    // 未选择也未输入，归入第一个
                    final t = notebook.techniques.isNotEmpty
                        ? notebook.techniques.first
                        : TechniqueEntry(
                            id: 'tech_${DateTime.now().millisecondsSinceEpoch}',
                            name: techName,
                            fullName: paper.title,
                            description: paper.authors.join(', '),
                            orderIndex: 0,
                            paperIds: [paper.id],
                          );
                    ref.read(innovationNotebookProvider.notifier).state =
                        notebook.copyWith(
                      techniques: [...notebook.techniques, t],
                      papers: [...notebook.papers, paper],
                    );
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('已导入：${paper.title}'),
                        duration: const Duration(seconds: 2)),
                  );
                },
                child: const Text('确认归入'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 书脊中线绘制器。
class _SpinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0x1F8B6914),
          const Color(0x0F8B6914),
          Colors.transparent,
        ],
        stops: const [0.02, 0.2, 0.8, 0.98],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SpinePainter oldDelegate) => false;
}

/// 翻页按钮。
class _PageTurnButton extends StatelessWidget {
  final String direction;
  final VoidCallback onTap;

  const _PageTurnButton({
    required this.direction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: const Color(0xFF8B6914), width: 1.5),
          color:
              const Color(0xFF8B6914).withAlpha(15),
        ),
        child: Icon(
          direction == 'prev'
              ? Icons.chevron_left
              : Icons.chevron_right,
          color: const Color(0xFF8B6914),
          size: 20,
        ),
      ),
    );
  }
}

/// 导入论文弹窗 — 纯视觉管线（FilePicker + 处理进度）。
class _VisionImportDialog extends StatefulWidget {
  final String apiKey;
  final String pythonPath;
  final String scriptDir;
  final void Function(VisionResult result) onImport;

  const _VisionImportDialog({
    required this.apiKey,
    required this.pythonPath,
    required this.scriptDir,
    required this.onImport,
  });

  @override
  State<_VisionImportDialog> createState() =>
      _VisionImportDialogState();
}

class _VisionImportDialogState
    extends State<_VisionImportDialog> {
  String _status = '';
  String _statusMsg = '';
  bool _processing = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入论文（视觉管线）'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_statusMsg.isNotEmpty) ...[
            Row(children: [
              if (_processing)
                const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else if (_status == 'done')
                const Icon(Icons.check_circle, size: 18, color: Color(0xFF50B86C))
              else if (_status == 'error')
                const Icon(Icons.error, size: 18, color: Color(0xFFE06060)),
              const SizedBox(width: 10),
              Expanded(child: Text(_statusMsg, style: const TextStyle(fontSize: 13))),
            ]),
            const SizedBox(height: 12),
          ],
          const Text(
            'PDF → 渲染页面 → 区域裁切 → AI 打标签 → 逐区翻译',
            style: TextStyle(fontSize: 11, color: Color(0xFF8B6914)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _processing ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _processing ? null : _pickAndImport,
          child: const Text('选择文件'),
        ),
      ],
    );
  }

  Future<void> _pickAndImport() async {
    debugPrint('[VisionImport] opening FilePicker...');
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.isEmpty) {
      debugPrint('[VisionImport] user cancelled');
      return;
    }
    final path = result.files.first.path;
    if (path == null) return;
    debugPrint('[VisionImport] selected: $path');

    setState(() { _processing = true; _status = 'running'; _statusMsg = '启动视觉管线...'; });

    try {
      final workDir = '${path}_vision_${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('[VisionImport] workDir=$workDir');

      final service = PaperVisionService(
        pythonPath: widget.pythonPath,
        scriptPath: '${widget.scriptDir}/paper_vision.py',
        apiKey: widget.apiKey,
      );

      final visionResult = await service.runFullPipeline(
        pdfPath: path,
        workDir: workDir,
        onProgress: (stage, msg, current, total) {
          final pageText = (stage == 'tag' || stage == 'done')
              ? msg
              : '第 $current/$total 页 $msg';
          debugPrint('[VisionImport] $stage: $pageText');
          if (!mounted) return;
          setState(() { _status = stage; _statusMsg = pageText; });
        },
      );
      service.dispose();

      debugPrint('[VisionImport] done: ${visionResult.chapters.length} chapters, ${visionResult.totalParagraphs} paras');
      if (!mounted) return;
      setState(() { _status = 'done'; _statusMsg = '✅ 完成！等待技法归属...'; });
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.pop(context);
      widget.onImport(visionResult);
    } catch (e, stack) {
      debugPrint('[VisionImport] ERROR: $e\n$stack');
      if (!mounted) return;
      setState(() { _processing = false; _status = 'error'; _statusMsg = '导入失败：$e'; });
    }
  }
}
