import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 用于截图的全屏 RepaintBoundary Key。
final GlobalKey _screenshotKey = GlobalKey();
GlobalKey get screenshotKey => _screenshotKey;

/// 截取当前屏幕，保存为 PNG 到 [sessionDir]/screenshot.png。
///
/// 返回文件路径，失败返回 null。
Future<String?> captureScreenshot({
  required String sessionDir,
}) async {
  try {
    final context = _screenshotKey.currentContext;
    if (context == null) return null;
    final boundary = context.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    final dir = Directory(sessionDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    final file = File('${dir.path}/screenshot.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file.path;
  } catch (_) {
    return null;
  }
}
