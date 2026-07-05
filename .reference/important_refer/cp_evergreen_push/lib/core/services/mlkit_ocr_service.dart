import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../log.dart';

/// Google ML Kit 端侧 OCR 服务（Android / iOS）。
///
/// 替代桌面端的 Tesseract Python 子进程方案，无需 Python 或网络。
/// 支持中文 + 拉丁文字的文本识别。
///
/// TextRecognizer 延迟初始化——避免在 Android 设备上因 ML Kit 模型
/// 未就绪导致构造函数崩溃 (google_ml_kit_flutter #385)。
class MlKitOcrService {
  TextRecognizer? _recognizer;

  /// 获取（或懒创建）TextRecognizer 实例。
  /// 若 ML Kit 未就绪则返回 null，调用方将优雅降级。
  TextRecognizer? get _getRecognizer {
    if (_recognizer != null) return _recognizer;
    try {
      debugPrint('[MlKitOcr] Creating TextRecognizer(chinese)...');
      _recognizer = TextRecognizer(
        script: TextRecognitionScript.chinese,
      );
      debugPrint('[MlKitOcr] TextRecognizer created successfully');
      return _recognizer;
    } catch (e, st) {
      debugPrint('[MlKitOcr] TextRecognizer init FAILED: $e');
      debugPrint('[MlKitOcr] stack: $st');
      Log().warn('ML Kit TextRecognizer init failed', error: e);
      return null;
    }
  }

  /// 从单张图片文件路径识别文本。失败返回 null。
  Future<String?> recognizeImage(String imagePath) async {
    try {
      debugPrint('[MlKitOcr] recognizeImage: $imagePath');
      final recognizer = _getRecognizer;
      if (recognizer == null) {
        debugPrint('[MlKitOcr] recognizer is null - ML Kit not available');
        return null;
      }
      final inputImage = InputImage.fromFilePath(imagePath);
      debugPrint('[MlKitOcr] processing image...');
      final recognizedText = await recognizer.processImage(inputImage);
      final text = recognizedText.text.trim();
      debugPrint('[MlKitOcr] result: ${text.length} chars');
      if (text.isNotEmpty) {
        Log().info('ML Kit OCR succeeded',
            data: {'path': imagePath, 'length': text.length});
        return text;
      }
      return null;
    } catch (e, st) {
      debugPrint('[MlKitOcr] recognizeImage FAILED: $e');
      debugPrint('[MlKitOcr] stack: $st');
      Log().warn('ML Kit OCR failed',
          data: {'path': imagePath}, error: e);
      return null;
    }
  }

  /// 从图片文件路径列表识别文本（主要用于 PDF 分页后的多页 OCR）。
  ///
  /// 多页时自动添加 "--- 第 N 页 ---" 分隔符。
  /// 合并后的文本全部为空时返回 null。
  Future<String?> recognizePages(List<String> pagePaths) async {
    if (pagePaths.isEmpty) return null;

    final buf = StringBuffer();
    for (var i = 0; i < pagePaths.length; i++) {
      final text = await recognizeImage(pagePaths[i]);
      if (text != null && text.isNotEmpty) {
        if (pagePaths.length > 1) {
          buf.writeln('--- 第 ${i + 1} 页 ---');
        }
        buf.writeln(text);
        buf.writeln();
      }
    }

    final merged = buf.toString().trim();
    return merged.isEmpty ? null : merged;
  }

  /// 释放 ML Kit 识别器资源。
  void dispose() {
    _recognizer?.close();
    _recognizer = null;
  }
}
