/// pymupdf Agent Tool — PDF 文本提取（真实实现）。
///
/// 通过一次性子进程调用 `paper_reader.py`（pymupdf/fitz）提取 PDF 纯文本：
/// - 命令 `extract` → `{"full_text": "...", "segments": [...], "page_count": N}`
/// - 扫描版/加密 PDF 提取不到文本时抛 [StateError]，由调用方降级 OCR。
///
/// 可作为 Agent Tool 注册（[schema]），供深寻 agents 读取采集到的 PDF。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/python_env.dart';

/// pymupdf 文本提取工具。
class PymupdfTool {
  /// 工具名称（Agent 注册用）。
  static const String toolName = 'pdf_extract_text';

  /// 工具描述。
  static const String description =
      'Extract plain text from a local PDF file using pymupdf. '
      'Input: absolute PDF file path. Output: full text + paragraph segments. '
      'For scanned/image PDFs this fails — use OCR instead.';

  /// 调用 pymupdf 提取 PDF 全文（一次性子进程，独立于调用方生命周期）。
  ///
  /// [filePath] PDF 文件绝对路径。
  /// [pythonPath] Python 解释器（缺省走 [resolvePythonExe] 探测，兜底 'python'）。
  /// [scriptPath] paper_reader.py 路径（缺省 `.greenix/scripts/paper_reader.py`）。
  ///
  /// 返回提取的纯文本。失败（脚本缺失 / 扫描版 / 加密 / 超时）抛异常。
  static Future<String> extractText(
    String filePath, {
    String? pythonPath,
    String? scriptPath,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final data = await _extract(filePath,
        pythonPath: pythonPath, scriptPath: scriptPath, timeout: timeout);
    return data['full_text'] as String? ?? '';
  }

  /// 提取 PDF 全文 + 分段 + 页数。
  ///
  /// 返回 `{"full_text", "segments", "page_count"}`；扫描版抛异常。
  static Future<Map<String, dynamic>> extractSegments(
    String filePath, {
    String? pythonPath,
    String? scriptPath,
    Duration timeout = const Duration(minutes: 3),
  }) =>
      _extract(filePath,
          pythonPath: pythonPath, scriptPath: scriptPath, timeout: timeout);

  /// 工具 schema（用于 Agent 工具注册）。
  static Map<String, dynamic> get schema => {
        'name': toolName,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': {
            'file_path': {
              'type': 'string',
              'description': 'Absolute path to the PDF file',
            },
          },
          'required': ['file_path'],
        },
      };

  static Future<Map<String, dynamic>> _extract(
    String filePath, {
    String? pythonPath,
    String? scriptPath,
    required Duration timeout,
  }) async {
    final f = File(filePath);
    if (!f.existsSync()) {
      throw StateError('PDF 文件不存在: $filePath');
    }

    final py = pythonPath ?? await resolvePythonExe() ?? 'python';
    final script = scriptPath ?? p.join(greenixScriptsDir, 'paper_reader.py');
    if (!File(script).existsSync()) {
      throw StateError('未找到 paper_reader.py: $script（请先释放脚本资源）');
    }

    final proc = await Process.start(
      py,
      [script],
      mode: ProcessStartMode.normal,
    );

    final stderrBuf = StringBuffer();
    proc.stderr.transform(utf8.decoder).listen(stderrBuf.write);

    final resp = Completer<Map<String, dynamic>>();
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty) return;
      try {
        final m = jsonDecode(line) as Map<String, dynamic>;
        if (m['type'] == 'result' || m['type'] == 'error') {
          if (!resp.isCompleted) resp.complete(m);
        }
      } catch (_) {
        // 忽略非 JSON 行（如 pymupdf 警告）
      }
    });

    proc.stdin.writeln(
        jsonEncode({'command': 'extract', 'args': {'input': filePath}}));
    await proc.stdin.flush();

    Map<String, dynamic> msg;
    try {
      msg = await resp.future.timeout(timeout);
    } catch (e) {
      proc.kill();
      throw StateError('PDF 提取超时（${timeout.inSeconds}s）: $filePath');
    }

    // 结束子进程
    try {
      proc.stdin.writeln(jsonEncode({'command': 'exit'}));
      await proc.stdin.flush();
    } catch (_) {}
    proc.kill();

    if (msg['type'] == 'error') {
      throw StateError('PDF 提取失败: ${msg['message']}');
    }

    final data = (msg['data'] as Map<String, dynamic>?) ?? {};
    final fullText = (data['full_text'] as String? ?? '').trim();
    if (fullText.isEmpty) {
      throw StateError('PDF 未提取到文本（可能是扫描版或加密 PDF）: $filePath');
    }
    return data;
  }
}
