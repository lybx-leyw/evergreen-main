import 'dart:io';

import '../../core/log.dart';

/// 反馈 Markdown 写入器。
///
/// 输出结构（每次反馈一个子目录）：
/// ```
/// test/feedback/
/// └── 20260619_170651__courses__Bug/
///     ├── feedback.md
///     └── screenshot.png
/// ```
class FeedbackWriter {
  final String outputDir;

  FeedbackWriter({this.outputDir = 'test/feedback'});

  /// 返回 session 子目录路径。
  Future<String> write({
    required int timestampUs,
    required String route,
    required String tag,
    required String description,
  }) async {
    final dt = DateTime.fromMicrosecondsSinceEpoch(timestampUs);
    final datePart = '${dt.year}${_pad(dt.month)}${_pad(dt.day)}';
    final timePart = '${_pad(dt.hour)}${_pad(dt.minute)}${_pad(dt.second)}';
    final safeRoute = route == '/' ? 'root' : route.replaceAll('/', '_').replaceAll(RegExp(r'^_'), '');
    final safeTag = tag.replaceAll(' ', '_');
    final sessionDir = '${datePart}_${timePart}_${safeRoute}_$safeTag';

    final dir = Directory('$outputDir/$sessionDir');
    if (!await dir.exists()) await dir.create(recursive: true);

    final timeStr =
        '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}.'
        '${(dt.microsecond ~/ 1000).toString().padLeft(3, '0')}';

    final buf = StringBuffer();
    buf.writeln('# 反馈 — $timeStr');
    buf.writeln();
    buf.writeln('- **时间戳**: $timestampUs μs');
    buf.writeln('- **路由**: `$route`');
    buf.writeln('- **标签**: $tag');
    buf.writeln();
    buf.writeln('## 描述');
    buf.writeln();
    buf.writeln(description);
    buf.writeln();
    buf.writeln('---');

    final mdFile = File('${dir.path}/feedback.md');
    await mdFile.writeAsString(buf.toString());

    Log().info('FEEDBACK: markdown written',
        data: {'dir': dir.path, 'route': route, 'tag': tag});

    return dir.path;
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
