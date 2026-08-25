/// 星空视图 — 深蓝背景上论文星星漂浮闪烁。
///
/// 每颗星 = 一篇论文（技法原始论文 + 变体/改进论文）。
/// 末尾「＋添加论文」星星触发导入。
library;

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path_pkg;
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/config/settings.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/python_env.dart';
import '../paper_reading_models.dart';
import '../paper_reading_state.dart';
import '../services/paper_service.dart';
import '../services/paper_vision_service.dart' show PaperVisionService, VisionResult;
import '../components/paper_star.dart';

class StarfieldView extends ConsumerStatefulWidget {
  const StarfieldView({super.key});

  @override
  ConsumerState<StarfieldView> createState() =>
      _StarfieldViewState();
}

class _StarfieldViewState extends ConsumerState<StarfieldView>
    with TickerProviderStateMixin {
  late AnimationController _bgController;
  final _random = Random(42);

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final technique = selectedTechnique(ref);
    final notebook = ref.watch(innovationNotebookProvider);
    final papers = technique != null
        ? notebook.papers
            .where((p) => technique.paperIds.contains(p.id))
            .toList()
        : <PaperRecord>[];

    final colors = [
      0xFFE8C547, // gold
      0xFF7EC8E3, // blue
      0xFFA8E6CF, // green
      0xFFFFD3B6, // peach
      0xFFD5AAFF, // lavender
      0xFFFF6B6B, // coral
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => popView(ref),
        ),
        title: Text(
          '✦ ${technique?.name ?? ''} · ${technique?.fullName ?? ''} ✦',
          style: const TextStyle(
              color: Colors.white70, fontSize: 16),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // 深蓝星云背景
              AnimatedBuilder(
                animation: _bgController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _NebulaPainter(
                      animation: _bgController.value,
                    ),
                  );
                },
              ),
              // 背景星点（80颗）
              ...List.generate(80, (i) {
                final x = constraints.maxWidth *
                    _random.nextDouble();
                final y = constraints.maxHeight *
                    _random.nextDouble();
                final size = 1.0 + _random.nextDouble() * 2.0;
                final opacity =
                    0.3 + _random.nextDouble() * 0.5;
                return Positioned(
                  left: x,
                  top: y,
                  child: Opacity(
                    opacity: opacity,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
              // 论文星星（均匀分布）
              _buildPaperStars(papers, colors, constraints),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPaperStars(List<PaperRecord> papers,
      List<int> colors, BoxConstraints constraints) {
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    final padding = 80.0;
    final topOffset = 60.0;
    // 论文星星 + 1 颗添加星星
    final total = papers.length + 1;
    final cols =
        (sqrt(total * (w / h))).ceil().clamp(2, 6);
    final rows = (total / cols).ceil();
    final cw = (w - padding * 2) / cols;
    final rh = (h - padding * 2 - topOffset) / rows;

    return Stack(
      children: [
        ...papers.asMap().entries.map((entry) {
          final i = entry.key;
          final p = entry.value;
          final col = i % cols;
          final row = i ~/ cols;
          final cx = padding + cw * col + cw / 2;
          final cy =
              padding + topOffset + rh * row + rh / 2;
          final color = colors[i % colors.length];
          return Positioned(
            left: cx - 65,
            top: cy - 30,
            child: PaperStar(
              title: p.title,
              authors: p.authors.join(', '),
              color: Color(color),
              onTap: () {
                ref
                    .read(selectedPaperIdProvider.notifier)
                    .state = p.id;
                pushView(
                    ref, PaperReadingViewType.explorationTags);
              },
            ),
          );
        }),
        // 添加论文星星
        Positioned(
          left: padding + cw * (papers.length % cols) +
              cw / 2 -
              32,
          top: padding +
              topOffset +
              rh * (papers.length ~/ cols) +
              rh / 2 -
              24,
          child: PaperStar(
            title: '添加论文',
            authors: '导入新 PDF',
            color: Colors.white.withAlpha(80),
            isAdd: true,
            onTap: () => _showImportDialog(context),
          ),
        ),
      ],
    );
  }

  void _showImportDialog(BuildContext context) {
    final technique = selectedTechnique(ref);
    if (technique == null) return;
    debugPrint('[Starfield] _showImportDialog for technique=${technique.name}');

    String apiKey = '';
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY') ?? '';
      debugPrint('[Starfield] apiKey length=${apiKey.length}');
    } catch (e) {
      debugPrint('[Starfield] failed to read apiKey: $e');
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          String status = '';
          String statusMsg = '';
          bool processing = false;

          Future<void> pickAndImport() async {
            debugPrint('[Starfield] opening FilePicker...');
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom, allowedExtensions: ['pdf'],
            );
            if (result == null || result.files.isEmpty) {
              debugPrint('[Starfield] user cancelled');
              return;
            }
            final path = result.files.first.path;
            if (path == null) return;
            debugPrint('[Starfield] selected: $path');

            setDialogState(() {
              processing = true; status = 'running'; statusMsg = '启动视觉管线...';
            });

            try {
              final workDir = '${path}_vision_${DateTime.now().millisecondsSinceEpoch}';
              debugPrint('[Starfield] workDir=$workDir');

              final service = PaperVisionService(
                pythonPath:
                    (await PythonInterpreter.instance.resolve()).legacyExePath ?? 'python',
                scriptPath: path_pkg.join(greenixScriptsDir, 'paper_vision.py'),
                apiKey: apiKey,
              );

              final visionResult = await service.runFullPipeline(
                pdfPath: path, workDir: workDir,
                onProgress: (s, m, c, t) {
                  final pt = (s == 'tag' || s == 'done') ? m : '第 $c/$t 页 $m';
                  debugPrint('[Starfield] $s: $pt');
                  if (!ctx.mounted) return;
                  setDialogState(() { status = s; statusMsg = pt; });
                },
              );
              service.dispose();
              debugPrint('[Starfield] pipeline done: ${visionResult.totalParagraphs} regions');

              if (!ctx.mounted) return;
              _addVisionPaper(visionResult, technique, ctx);
            } catch (e, stack) {
              debugPrint('[Starfield] ERROR: $e\n$stack');
              if (!ctx.mounted) return;
              setDialogState(() { processing = false; status = 'error'; statusMsg = '导入失败：$e'; });
            }
          }

          return AlertDialog(
            title: const Text('添加论文到此技法'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (statusMsg.isNotEmpty) ...[
                  Row(children: [
                    if (processing)
                      const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else if (status == 'done')
                      const Icon(Icons.check_circle, size: 18, color: Color(0xFF50B86C)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(statusMsg, style: const TextStyle(fontSize: 13))),
                  ]),
                  const SizedBox(height: 12),
                ],
                Text(
                  'PDF → 渲染页面 → 区域裁切 → AI 打标签 → 逐区翻译\n归入技法「${technique.name}」',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: processing ? null : () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: processing ? null : pickAndImport,
                child: const Text('选择文件'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _addVisionPaper(VisionResult result, TechniqueEntry technique, BuildContext ctx) {
    debugPrint('[Starfield] _addVisionPaper: ${result.totalParagraphs} regions → technique=${technique.name}');
    final paperId = 'paper_${DateTime.now().millisecondsSinceEpoch}';
    final paper = PaperRecord(
      id: paperId,
      title: '导入 ${DateTime.now().toString().substring(0, 16)}',
      authors: ['Unknown'], filePath: '',
      paperType: PaperType.innovation, importedAt: DateTime.now(),
      fullText: result.fullText,
    );
    final current = ref.read(chaptersProvider);
    ref.read(chaptersProvider.notifier).state = {
      ...current, paperId: result.chapters,
    };
    final ftCurrent = ref.read(fullTextProvider);
    ref.read(fullTextProvider.notifier).state = {
      ...ftCurrent, paperId: result.fullText,
    };
    ref.read(selectedPaperIdProvider.notifier).state = paperId;

    final notebook = ref.read(innovationNotebookProvider);
    final updatedTechs = notebook.techniques.map((t) {
      if (t.id == technique.id) {
        return TechniqueEntry(
          id: t.id, name: t.name, fullName: t.fullName,
          description: t.description, orderIndex: t.orderIndex,
          paperIds: [...t.paperIds, paper.id],
        );
      }
      return t;
    }).toList();
    ref.read(innovationNotebookProvider.notifier).state = notebook.copyWith(
      techniques: updatedTechs, papers: [...notebook.papers, paper],
    );
    Navigator.pop(ctx);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('导入完成：${result.totalParagraphs} 个区域'), duration: const Duration(seconds: 2)),
    );
  }
}

/// 星云背景绘制器。
class _NebulaPainter extends CustomPainter {
  final double animation;
  _NebulaPainter({required this.animation});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
            sin(animation * 2 * pi) * 0.3,
            cos(animation * 2 * pi) * 0.2),
        radius: 1.8,
        colors: [
          const Color(0xFF1A1A3E),
          const Color(0xFF0E0E2A),
          const Color(0xFF0A0A1A),
        ],
      ).createShader(
          Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 彩色星云斑块
    final nebulae = [
      (color: const Color(0x0A7EC8E3),
       offset: Offset(size.width * 0.7, size.height * 0.3),
       radius: size.width * 0.35),
      (color: const Color(0x08E8C547),
       offset: Offset(size.width * 0.25, size.height * 0.6),
       radius: size.width * 0.3),
      (color: const Color(0x06D5AAFF),
       offset:
           Offset(size.width * 0.6, size.height * 0.75),
       radius: size.width * 0.4),
    ];

    for (final n in nebulae) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            (n.color as Color).withAlpha(20),
            (n.color as Color).withAlpha(0),
          ],
        ).createShader(Rect.fromCenter(
            center: n.offset as Offset,
            width: n.radius as double,
            height: n.radius as double));
      canvas.drawCircle(n.offset as Offset,
          n.radius as double, paint);
    }
  }

  @override
  bool shouldRepaint(_NebulaPainter oldDelegate) => true;
}
