/// OCR 附件处理器 — 文件上传→OCR→注入 context→Agent 回答管线。
///
/// 消费 core/services/ocr_pipeline.dart 的 OcrPipeline 接口，
/// 在 Agent 收到文件附件时自动触发 OCR 并将文本注入对话上下文。
///
/// ## API
/// | 方法 | 说明 |
/// |------|------|
/// | `process(List<String> filePaths)` | 批量 OCR 文件，返回 (text, path) 列表 |
/// | `toContextString(List<OcrResult>)` | 将 OCR 结果格式化为 context 注入文本 |
library;


import '../event.dart';

// ═══════ OcrResult ═══════

/// 单个文件的 OCR 处理结果。
class OcrResult {
  final String filePath;
  final String? text;
  final String? error;
  final String mimeType;

  const OcrResult({
    required this.filePath,
    this.text,
    this.error,
    this.mimeType = 'application/octet-stream',
  });

  bool get isSuccess => text != null && text!.isNotEmpty;
  bool get isImage => mimeType.startsWith('image/');
  bool get isPdf => mimeType == 'application/pdf';
}

// ═══════ OcrAttachmentHandler ═══════

/// OCR 附件处理器——封装 OCR 管线与 context 注入逻辑。
///
/// 用法：
/// ```dart
/// final handler = OcrAttachmentHandler(ocrPipeline: pipeline, sink: eventSink);
/// final results = await handler.process(['/path/to/image.png']);
/// final contextStr = handler.toContextString(results);
/// controller.send('分析这张图片', attachments: results);
/// ```
class OcrAttachmentHandler {
  /// OCR 管线接口——由外部注入（core/services/ocr_pipeline.dart）。
  final Future<String?> Function(String filePath) _recognize;

  /// 事件输出——发送 OCR 进度通知。
  final EventSink? _sink;

  OcrAttachmentHandler({
    required Future<String?> Function(String filePath) recognize,
    EventSink? sink,
  })  : _recognize = recognize,
        _sink = sink;

  /// 批量处理附件文件。
  ///
  /// 每个文件独立 OCR，失败的文件标记 error。
  /// 发送 toolProgress 事件报告进度。
  Future<List<OcrResult>> process(List<String> filePaths) async {
    final results = <OcrResult>[];

    for (var i = 0; i < filePaths.length; i++) {
      final path = filePaths[i];
      _sink?.emit(AgentEvent.notice(
          '正在识别文件 ${i + 1}/${filePaths.length}: ${path.split(RegExp(r'[/\\]')).last}'));

      try {
        final text = await _recognize(path);
        results.add(OcrResult(
          filePath: path,
          text: text,
          mimeType: _guessMimeType(path),
        ));
      } catch (e) {
        results.add(OcrResult(
          filePath: path,
          error: '$e',
          mimeType: _guessMimeType(path),
        ));
      }
    }

    final success = results.where((r) => r.isSuccess).length;
    final failed = results.where((r) => !r.isSuccess).length;
    if (success > 0) {
      _sink?.emit(AgentEvent.notice('识别完成: $success 个文件成功'
          '${failed > 0 ? ", $failed 个失败" : ""}'));
    }

    return results;
  }

  /// 将 OCR 结果格式化为可注入 context 的文本。
  ///
  /// 格式：
  /// ```
  /// ## 附件 OCR 内容
  ///
  /// ### 文件: image.png
  /// [OCR 文本内容...]
  ///
  /// ### 文件: doc.pdf (识别失败)
  /// 错误: 文件过大
  /// ```
  String toContextString(List<OcrResult> results) {
    if (results.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('## 附件 OCR 内容');
    buf.writeln();

    for (final r in results) {
      final fileName = r.filePath.split(RegExp(r'[/\\]')).last;
      if (r.isSuccess) {
        buf.writeln('### 文件: $fileName');
        buf.writeln(r.text);
      } else {
        buf.writeln('### 文件: $fileName (识别失败)');
        buf.writeln('错误: ${r.error ?? "未知错误"}');
      }
      buf.writeln();
    }

    return buf.toString().trimRight();
  }

  String _guessMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png': return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'bmp': return 'image/bmp';
      case 'pdf': return 'application/pdf';
      default: return 'application/octet-stream';
    }
  }
}
