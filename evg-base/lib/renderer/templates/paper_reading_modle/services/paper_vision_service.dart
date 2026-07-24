/// Paper Vision Service V3 — 章节+段落管线。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../paper_reading_models.dart';

class VisionResult {
  final List<ChapterModel> chapters;
  final String fullText;
  final int totalParagraphs;
  const VisionResult({required this.chapters, required this.fullText, required this.totalParagraphs});
}

class PaperVisionService {
  final String pythonPath;
  final String scriptPath;
  final String apiKey;
  final String? model;

  PaperVisionService({
    required this.pythonPath, required this.scriptPath, required this.apiKey,
    this.model = 'deepseek-v4-flash',
  });

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  Completer<Map<String, dynamic>>? _pendingCmd;
  void Function(String, String, int, int)? _progressCb;

  Future<VisionResult> runFullPipeline({
    required String pdfPath, required String workDir,
    void Function(String stage, String msg, int cur, int tot)? onProgress,
  }) async {
    _progressCb = onProgress;
    final result = await _pyCmd('full_pipeline', {
      'input': pdfPath, 'work_dir': workDir, 'api_key': apiKey,
      'model': model,
    });
    final chaptersRaw = result['chapters'] as List? ?? [];
    final chapters = chaptersRaw.asMap().entries
        .map((e) => ChapterModel.fromJson(e.value as Map<String, dynamic>, e.key))
        .toList();
    return VisionResult(
      chapters: chapters,
      fullText: result['full_text'] as String? ?? '',
      totalParagraphs: result['total_paragraphs'] as int? ?? 0,
    );
  }

  Future<String> translateText(String text, {String langOut = 'zh'}) async {
    final r = await _pyCmd('translate_text', {'text': text, 'api_key': apiKey, 'lang_out': langOut, 'model': model});
    return r['translated'] as String? ?? '';
  }

  Future<Map<String, dynamic>> _pyCmd(String cmd, Map<String, dynamic> args) async {
    if (_process == null) {
      final f = File(scriptPath);
      if (!f.existsSync()) throw Exception('Script not found: $scriptPath');
      _process = await Process.start(pythonPath, [scriptPath], mode: ProcessStartMode.normal);
      _process!.stderr.transform(utf8.decoder).transform(const LineSplitter())
          .listen((l) => debugPrint('[VisionSvc] STDERR: $l'));
      _stdoutSub = _process!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (line.isEmpty) return;
        try {
          final m = jsonDecode(line) as Map<String, dynamic>;
          final t = m['type'] as String? ?? '';
          if (t == 'progress') {
            _progressCb?.call(m['stage'] as String? ?? '', m['message'] as String? ?? '',
                m['current'] as int? ?? 0, m['total'] as int? ?? 0);
          } else if (t == 'result' || t == 'error') {
            if (_pendingCmd != null && !_pendingCmd!.isCompleted) _pendingCmd!.complete(m);
          }
        } catch (_) {}
      });
    }
    _process!.stdin.write('${jsonEncode({'command': cmd, 'args': args})}\n');
    await _process!.stdin.flush();
    _pendingCmd = Completer<Map<String, dynamic>>();
    final resp = await _pendingCmd!.future.timeout(const Duration(minutes: 60));
    if (resp['type'] == 'error') throw Exception(resp['message']);
    return resp['data'] as Map<String, dynamic>? ?? {};
  }

  void dispose() {
    _process?.stdin.write('{"command":"exit"}\n');
    _process?.stdin.flush();
    _stdoutSub?.cancel();
    _process?.kill();
    _process = null; _pendingCmd = null;
  }
}
