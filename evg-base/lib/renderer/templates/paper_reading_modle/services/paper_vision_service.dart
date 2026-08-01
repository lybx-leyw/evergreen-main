/// Paper Vision Service V3 — 章节+段落管线。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../paper_reading_models.dart';

class VisionResult {
  final List<ChapterModel> chapters;
  final String fullText;
  final int totalParagraphs;
  const VisionResult({required this.chapters, required this.fullText, required this.totalParagraphs});
}

/// 平台判断：是否 Android
bool _isAndroid = Platform.isAndroid;

class PaperVisionService {
  final String pythonPath;
  final String scriptPath;
  final String apiKey;
  final String? model;

  PaperVisionService({
    required this.pythonPath, required this.scriptPath, required this.apiKey,
    this.model = 'deepseek-v4-flash',
  });

  // ── 桌面端：持久子进程 ──
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  Completer<Map<String, dynamic>>? _pendingCmd;
  void Function(String, String, int, int)? _progressCb;

  // ── 安卓端：ChaquopyRunner ──
  static final MethodChannel _pyChannel = const MethodChannel('evergreen/python');

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
    if (_isAndroid) {
      return _pyCmdAndroid(cmd, args);
    }
    return _pyCmdDesktop(cmd, args);
  }

  // ──────── 安卓：ChaquopyRunner 单次执行 ────────

  Future<Map<String, dynamic>> _pyCmdAndroid(String cmd, Map<String, dynamic> args) async {
    // 解析脚本在设备上的实际路径
    final resolvedPath = await _resolveScriptPathAndroid();
    debugPrint('[VisionSvc] Android scriptPath=$resolvedPath');
    final f = File(resolvedPath);
    if (!f.existsSync()) throw Exception('Script not found: $resolvedPath');

    final stdinJson = <String, dynamic>{'command': cmd, 'args': args};
    debugPrint('[VisionSvc] Android stdinJson keys: ${stdinJson.keys}');

    final resp = await _pyChannel.invokeMethod<Map<dynamic, dynamic>>('runScript', {
      'entry': resolvedPath,
      'args': <String>[],
      'stdinJson': stdinJson,
    });
    if (resp == null) throw Exception('Chaquopy runScript returned null');
    debugPrint('[VisionSvc] Android exitCode=${resp['exitCode']}');

    final stdout = resp['stdout'] as String? ?? '';
    final stderr = resp['stderr'] as String? ?? '';
    if (stderr.isNotEmpty) debugPrint('[VisionSvc] STDERR: $stderr');

    if ((resp['exitCode'] as int? ?? 0) != 0) {
      throw Exception(stderr.isNotEmpty ? stderr : 'Python exited non-zero');
    }

    // 解析 stdout 中的 JSON 行，找最后的 result/error
    Map<String, dynamic>? lastResult;
    final lines = const LineSplitter().convert(stdout);
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final m = jsonDecode(line.trim()) as Map<String, dynamic>;
        final t = m['type'] as String? ?? '';
        if (t == 'progress') {
          _progressCb?.call(
            m['stage'] as String? ?? '',
            m['message'] as String? ?? '',
            m['current'] as int? ?? 0,
            m['total'] as int? ?? 0,
          );
        } else if (t == 'result' || t == 'error') {
          lastResult = m;
        }
      } catch (_) {}
    }

    if (lastResult == null) throw Exception('No result in script output');
    if (lastResult['type'] == 'error') throw Exception(lastResult['message']);
    return lastResult['data'] as Map<String, dynamic>? ?? {};
  }

  /// 获取 Chaquopy 资源在设备文件系统上的绝对路径。
  Future<String> _resolveScriptPathAndroid() async {
    try {
      final assetPath = await _pyChannel.invokeMethod<String>('getAssetPath', {
        'name': 'paper_vision.py',
      });
      if (assetPath != null && assetPath.isNotEmpty) return assetPath;
    } catch (e) {
      debugPrint('[VisionSvc] getAssetPath failed: $e');
    }
    // fallback: 原生侧找不到文件 → 说明 APK 中未包含 paper_vision.py，需重新 flutter build
    throw Exception(
      'paper_vision.py not found in Chaquopy assets. '
      'Ensure android/app/src/main/python/paper_vision.py exists and APK was rebuilt.',
    );
  }

  // ──────── 桌面端：持久子进程（保持不变） ────────

  Future<Map<String, dynamic>> _pyCmdDesktop(String cmd, Map<String, dynamic> args) async {
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
    if (_isAndroid) return; // Android 无持久进程
    _process?.stdin.write('{"command":"exit"}\n');
    _process?.stdin.flush();
    _stdoutSub?.cancel();
    _process?.kill();
    _process = null; _pendingCmd = null;
  }
}
