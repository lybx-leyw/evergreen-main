/// 论文服务 — PDF 导入、AI 分析、逐段打标签（真实接入版）。
///
/// 核心流程：
/// 1. 子进程调用 paper_reader.py → pymupdf 提取 PDF 文本 + 分段
/// 2. AI (AgentAssembly) 判断论文类型（创新 vs 综述）
/// 3. AI 逐段打标签（背景/设计理念/数学推导/实验/参考文献/其他）
/// 4. AI 提取技法名（创新论文）
/// 5. 子进程调用 paper_reader.py → pdf2zh_next BaseTranslator 逐段翻译
///
/// 不修改 pdf_translate.py，所有翻译通过 paper_reader.py 完成。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../paper_reading_models.dart';

/// 论文处理服务。
class PaperService {
  final String pythonPath;
  final String scriptPath;
  final String apiKey;
  final String? model;
  final Future<String> Function(String systemPrompt, String userMessage)?
      aiQuery;

  /// [pythonPath] Python 解释器路径。
  /// [scriptPath] paper_reader.py 绝对路径。
  /// [apiKey] DeepSeek API Key。
  /// [aiQuery] AI 查询回调（systemPrompt, userMessage）→ 返回 AI 回复。
  ///           如果为 null，则回退到模拟 AI 分析。
  PaperService({
    required this.pythonPath,
    required this.scriptPath,
    required this.apiKey,
    this.model = 'deepseek-v4-flash',
  
    this.aiQuery,
  });

  /// 导入 PDF 并执行全流程处理。
  ///
  /// [filePath] PDF 文件路径。
  /// [onProgress] 进度回调：(status, message)。
  /// 返回处理后的 PaperRecord。
  Future<PaperRecord> processPdf({
    required String filePath,
    void Function(String status, String msg)? onProgress,
  }) async {
    onProgress?.call('extracting', '正在提取 PDF 文本...');

    // ── 1. paper_reader.py extract ──
    final extractResult = await _pyCommand('extract', {
      'input': filePath,
    });
    final fullText = extractResult['full_text'] as String? ?? '';
    if (fullText.isEmpty) {
      throw Exception('PDF 文本提取失败：文件可能为扫描版或加密');
    }
    final segments = (extractResult['segments'] as List?)
            ?.cast<String>() ??
        [];
    final pageCount = extractResult['page_count'] as int? ?? 0;
    onProgress?.call(
        'extracting', '提取完成：${segments.length} 段落，$pageCount 页');

    onProgress?.call(
        'analyzing', 'AI 正在判断论文类型并逐段打标签...');

    // ── 2. AI 判断类型 ──
    final paperType = await _classifyPaperType(fullText);
    onProgress?.call('analyzing',
        '类型判定：${paperType == PaperType.innovation ? "创新论文" : "综述论文"}');

    // ── 3. AI 逐段打标签 ──
    final segmentTags = await _tagSegments(segments);
    onProgress?.call('analyzing', '逐段打标签完成');

    // ── 4. 提取技法名（创新论文）──
    String? techniqueName;
    if (paperType == PaperType.innovation) {
      techniqueName = await _extractTechniqueName(fullText);
      onProgress?.call('analyzing', '识别技法：$techniqueName');
    }

    // ── 5. 元数据提取 ──
    final title =
        await _extractTitleWithAI(fullText) ?? _fallbackTitle(fullText);
    final authors = await _extractAuthorsWithAI(fullText);
    onProgress?.call('done', '导入完成');

    return PaperRecord(
      id: _generateId(),
      title: title,
      authors: authors,
      filePath: filePath,
      paperType: paperType,
      importedAt: DateTime.now(),
      fullText: fullText,
      segments: segments,
      segmentTags: segmentTags,
      techniqueName: techniqueName,
    );
  }

  /// 翻译指定段落的文本（调用 paper_reader.py translate_batch）。
  Future<List<String>> translateSegments(
      List<String> segments) async {
    if (segments.isEmpty) return [];

    final result = await _pyCommand('translate_batch', {
      'segments': segments,
      'api_key': apiKey,
      'model': model ?? 'deepseek-v4-flash',
      'lang_in': 'en',
      'lang_out': 'zh',
    });

    final translations = result['translations'] as List?;
    if (translations == null) return segments;

    // 按 index 排序还原
    final map = <int, String>{};
    for (final t in translations) {
      if (t is Map) {
        map[t['index'] as int] =
            t['translated'] as String? ?? '';
      }
    }
    return List.generate(segments.length,
        (i) => map[i] ?? segments[i]);
  }

  // ═══════════════════════════════
  // 子进程通信
  // ═══════════════════════════════

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  Completer<Map<String, dynamic>>? _pendingCmd;

  Future<Map<String, dynamic>> _pyCommand(
      String cmd, Map<String, dynamic> args) async {
    // 确保子进程存活
    if (_process == null) {
      _process = await Process.start(
        pythonPath,
        [scriptPath],
        mode: ProcessStartMode.normal,
      );
      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.isEmpty) return;
        try {
          final msg = jsonDecode(line) as Map<String, dynamic>;
          if (_pendingCmd != null && !_pendingCmd!.isCompleted) {
            _pendingCmd!.complete(msg);
          }
        } catch (_) {
          // 忽略非 JSON 行
        }
      });
    }

    // 发送命令
    final request = {
      'command': cmd,
      'args': args,
    };
    _process!.stdin
        .write('${jsonEncode(request)}\n');
    await _process!.stdin.flush();

    // 等待响应
    _pendingCmd = Completer<Map<String, dynamic>>();
    final response = await _pendingCmd!.future
        .timeout(const Duration(minutes: 3));

    if (response['type'] == 'error') {
      throw Exception(
          'paper_reader error: ${response['message']}');
    }
    return response['data'] as Map<String, dynamic>? ?? {};
  }

  /// 关闭子进程。
  void dispose() {
    if (_process != null) {
      _process!.stdin.write('{"command":"exit"}\n');
      _process!.stdin.flush();
      _stdoutSub?.cancel();
      _process?.kill();
      _process = null;
      _pendingCmd = null;
    }
  }

  // ═══════════════════════════════
  // AI 分析（AgentAssembly / fallback）
  // ═══════════════════════════════

  Future<PaperType> _classifyPaperType(String text) async {
    final firstChunk = text.length > 3000
        ? text.substring(0, 3000)
        : text;

    if (aiQuery != null) {
      final response = await aiQuery!(
        '你是一位论文评审专家。'
        '请判断以下论文属于创新论文(innovation)还是综述论文(survey)。'
        '创新论文提出新的方法/策略/模型；综述论文汇总和分析已有工作。'
        '只需回复一个单词：innovation 或 survey。',
        firstChunk,
      );
      final clean = response.trim().toLowerCase();
      if (clean.contains('innovation')) {
        return PaperType.innovation;
      } else if (clean.contains('survey')) {
        return PaperType.survey;
      }
      // 默认创新
      return PaperType.innovation;
    }

    // fallback: 基于关键词的简单推断
    final lower = firstChunk.toLowerCase();
    final surveyKeywords = [
      'survey', 'review', 'comprehensive', 'overview', 'state-of-the-art',
      '综述', '回顾', '调查',
    ];
    for (final kw in surveyKeywords) {
      if (lower.contains(kw)) return PaperType.survey;
    }
    return PaperType.innovation;
  }

  Future<List<Set<SectionCategory>>> _tagSegments(
      List<String> segments) async {
    if (aiQuery != null && segments.isNotEmpty) {
      // 分批：每 5 段合并成一次请求
      const batchSize = 5;
      final allTags =
          List<Set<SectionCategory>>.filled(segments.length, {});

      for (var i = 0; i < segments.length; i += batchSize) {
        final end =
            (i + batchSize).clamp(0, segments.length);
        final batch = segments.sublist(i, end);

        // 构建编号后的段落文本
        final batchText = batch
            .asMap()
            .entries
            .map((e) =>
                '[Segment ${i + e.key}]\n${e.value}')
            .join('\n\n');

        final response = await aiQuery!(
          '你是一位论文结构分析专家。'
          '请为以下每个 [Segment N] 段落分配一个或多个标签。'
          '可用标签：background（背景与问题），designPhilosophy（设计理念），'
          'mathDerivation（数学推导），experiment（实验与结果），'
          'reference（参考文献），other（其他/杂项）。\n'
          '请严格按以下 JSON 格式回复，不要添加其他文字：\n'
          '{"0": ["background","designPhilosophy"], "1": ["mathDerivation"], ...}',
          batchText,
        );

        try {
          final parsed = _parseTagResponse(
              response, batch.length, i);
          for (var j = 0; j < batch.length; j++) {
            allTags[i + j] = parsed[j] ?? {SectionCategory.other};
          }
        } catch (_) {
          // 解析失败：默认 other
          for (var j = 0; j < batch.length; j++) {
            allTags[i + j] = {SectionCategory.other};
          }
        }
      }
      return allTags;
    }

    // fallback: 基于关键词的启发式标签
    return segments.map((seg) {
      final tags = <SectionCategory>{};
      final lower = seg.toLowerCase();

      if (_hasAny(lower, [
        'problem', 'challenge', 'limitation', 'existing',
        '背景', '问题', '缺陷', '现有',
      ])) {
        tags.add(SectionCategory.background);
      }
      if (_hasAny(lower, [
        'propose', 'motivation', 'insight', 'design', 'philosophy',
        '提出', '设计', '动机', '理念',
      ])) {
        tags.add(SectionCategory.designPhilosophy);
      }
      if (_hasAny(lower, [
        'equation', 'theorem', 'proof', 'deriv', 'loss', 'gradient',
        '公式', '定理', '证明', '推导', '梯度',
      ]) ||
          RegExp(r'[=≈∑∏∫∂∇]').hasMatch(seg)) {
        tags.add(SectionCategory.mathDerivation);
      }
      if (_hasAny(lower, [
        'experiment', 'dataset', 'result', 'accuracy', 'table',
        '实验', '数据集', '结果', '准确率',
      ])) {
        tags.add(SectionCategory.experiment);
      }
      if (_hasAny(lower, [
        'reference', 'et al', '[1]', 'cite', 'bibliography',
        '参考文献', '引用',
      ])) {
        tags.add(SectionCategory.reference);
      }
      if (tags.isEmpty) {
        tags.add(SectionCategory.other);
      }
      return tags;
    }).toList();
  }

  bool _hasAny(String text, List<String> keywords) {
    return keywords.any((kw) => text.contains(kw));
  }

  /// 解析 AI 返回的 JSON 标签。
  Map<int, Set<SectionCategory>> _parseTagResponse(
      String response, int batchSize, int startIndex) {
    // 提取 JSON 块
    final jsonMatch = RegExp(r'\{[^}]*\}').firstMatch(response);
    if (jsonMatch == null) return {};

    final parsed =
        jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
    final result = <int, Set<SectionCategory>>{};

    for (final entry in parsed.entries) {
      final idx = int.tryParse(entry.key);
      if (idx == null) continue;

      final tags = <SectionCategory>{};
      if (entry.value is List) {
        for (final t in entry.value as List) {
          final cat = _parseCategory(t.toString());
          if (cat != null) tags.add(cat);
        }
      }
      // 确保索引在 batch 范围内
      final localIdx = idx - startIndex;
      if (localIdx >= 0 && localIdx < batchSize) {
        result[localIdx] = tags;
      }
    }
    return result;
  }

  SectionCategory? _parseCategory(String name) {
    switch (name.trim().toLowerCase()) {
      case 'background':
        return SectionCategory.background;
      case 'designphilosophy':
      case 'design':
      case 'philosophy':
        return SectionCategory.designPhilosophy;
      case 'mathderivation':
      case 'math':
      case 'derivation':
      case 'theory':
        return SectionCategory.mathDerivation;
      case 'experiment':
      case 'experiments':
      case 'results':
      case 'evaluation':
        return SectionCategory.experiment;
      case 'reference':
      case 'references':
        return SectionCategory.reference;
      case 'other':
        return SectionCategory.other;
      default:
        return null;
    }
  }

  Future<String> _extractTechniqueName(String text) async {
    final firstChunk =
        text.length > 4000 ? text.substring(0, 4000) : text;

    if (aiQuery != null) {
      final response = await aiQuery!(
        '你是一位机器学习论文分析专家。'
        '请从以下论文摘要中提取核心技法/方法名称（如 IRM、MAML、Dropout）。'
        '只需回复技法名称，不要添加其他文字。如果论文未提出新技法，回复 "Unknown"。',
        firstChunk,
      );
      final clean = response.trim();
      if (clean.isNotEmpty &&
          clean.length < 50 &&
          clean != 'Unknown') {
        return clean;
      }
    }

    // fallback: 常见技法名匹配
    final knownTechniques = [
      'IRM',
      'MAML',
      'Dropout',
      'Adam',
      'BatchNorm',
      'LayerNorm',
      'ViT',
      'BERT',
      'GPT',
      'ResNet',
      'GAN',
      'VAE',
      'LSTM',
      'GRU',
      'Diffusion',
      'CLIP',
      'SimCLR',
      'MoCo',
      'BYOL',
      'DINO',
    ];
    for (final t in knownTechniques) {
      if (text.contains(t)) return t;
    }
    return 'Unknown';
  }

  Future<String> _extractTitleWithAI(String text) async {
    // 从文本前几行提取标题
    final lines = text.split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(10)
        .toList();

    if (lines.isEmpty) return 'Unknown Title';

    if (aiQuery != null && lines.length >= 2) {
      final response = await aiQuery!(
        '请从以下论文开头文本中提取论文标题。只需回复标题文本。',
        lines.join('\n'),
      );
      final clean = response.trim();
      if (clean.isNotEmpty && clean.length < 300) {
        return clean;
      }
    }

    return _fallbackTitle(text);
  }

  String _fallbackTitle(String text) {
    final lines = text.split('\n')
        .map((l) => l.trim())
        .where((l) =>
            l.isNotEmpty &&
            l.length > 10 &&
            l.length < 200 &&
            !l.startsWith('http') &&
            !l.startsWith('doi:') &&
            !l.startsWith('arXiv:') &&
            !RegExp(r'^\d+\.').hasMatch(l))
        .toList();

    if (lines.isNotEmpty) {
      return lines.first.length > 100
          ? '${lines.first.substring(0, 97)}...'
          : lines.first;
    }
    return 'Unknown Title';
  }

  Future<List<String>> _extractAuthorsWithAI(
      String text) async {
    final firstChunk =
        text.length > 2000 ? text.substring(0, 2000) : text;

    if (aiQuery != null) {
      final response = await aiQuery!(
        '请从以下论文开头文本中提取作者姓名列表。'
        '只需回复逗号分隔的作者姓名，如 "Alice Smith, Bob Jones"。',
        firstChunk,
      );
      final names = response
          .split(',')
          .map((n) => n.trim())
          .where((n) =>
              n.isNotEmpty &&
              n.length < 50 &&
              !n.contains('Abstract') &&
              !n.contains('University'))
          .toList();
      if (names.isNotEmpty) return names;
    }

    // fallback: 匹配首行类似 "Alice Smith, Bob Jones" 的模式
    final firstLine = text.split('\n').firstWhere(
        (l) =>
            l.trim().isNotEmpty &&
            l.trim().contains(','),
        orElse: () => '');
    if (firstLine.isNotEmpty) {
      return firstLine
          .split(',')
          .map((s) => s.trim())
          .where((s) =>
              s.isNotEmpty &&
              s.length < 50)
          .toList();
    }
    return ['Unknown Author'];
  }

  // ═══════════════════════════════
  // 工具方法
  // ═══════════════════════════════

  static String _generateId() {
    final now = DateTime.now();
    return 'paper_${now.millisecondsSinceEpoch}_'
        '${Random().nextInt(10000)}';
  }
}
