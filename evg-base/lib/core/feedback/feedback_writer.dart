import 'dart:io';

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/feedback/github_issue_publisher.dart'
    show buildScreenshotMarkdown;

/// 反馈 Markdown / Issue 写入器。
///
/// 输出结构（每次反馈一个子目录）：
/// ```
/// test/feedback/
/// └── 20260619_170651__courses__Bug/
///     ├── feedback.md
///     └── screenshot.png
/// ```
///
/// 本地 Markdown 与 GitHub Issue 正文共用同一套「专业反馈模板」
/// （[buildFeedbackBody]），保证线上/离线格式一致。
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

    final body = buildFeedbackBody(timestampUs: timestampUs, route: route, tag: tag, description: description);

    final mdFile = File('${dir.path}/feedback.md');
    await mdFile.writeAsString(body);

    Log().info('FEEDBACK: markdown written',
        data: {'dir': dir.path, 'route': route, 'tag': tag});

    return dir.path;
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

/// 构造专业反馈正文（Markdown）。
///
/// 同时用于本地 `feedback.md` 与 GitHub Issue `body`。
/// [screenshotPath] 仅对 issue 场景有意义（本地 Markdown 不内嵌 base64，
/// 截图单独存为 screenshot.png）；传 null 时不内嵌图片。
String buildFeedbackBody({
  required int timestampUs,
  required String route,
  required String tag,
  required String description,
  String? screenshotPath,
}) {
  final dt = DateTime.fromMicrosecondsSinceEpoch(timestampUs);
  final timeStr =
      '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
      '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
  final tagEmoji = switch (tag) {
    '🐛 Bug' => 'Bug',
    '💡 建议' => 'Enhancement',
    '😤 体验' => 'UX',
    _ => tag,
  };

  final buf = StringBuffer();
  buf.writeln('# 反馈报告');
  buf.writeln();
  buf.writeln('> 本反馈由 Evergreen 客户端一键提交生成。');
  buf.writeln();
  buf.writeln('## 元信息');
  buf.writeln();
  buf.writeln('| 字段 | 值 |');
  buf.writeln('| --- | --- |');
  buf.writeln('| **类型** | $tagEmoji |');
  buf.writeln('| **触发路由** | `$route` |');
  buf.writeln('| **提交时间** | $timeStr |');
  buf.writeln('| **时间戳(μs)** | $timestampUs |');
  buf.writeln('| **平台** | ${Platform.operatingSystem} |');
  buf.writeln();
  buf.writeln('## 描述');
  buf.writeln();
  // 用户描述原样保留，去除首尾空白
  buf.writeln(description.trim().isEmpty ? '(用户未填写描述)' : description.trim());
  buf.writeln();

  // issue 场景内嵌截图 base64；本地场景不内嵌（截图独立存文件）
  if (screenshotPath != null) {
    buf.write(buildScreenshotMarkdown(screenshotPath));
  }

  buf.writeln('---');
  buf.writeln();
  buf.writeln('<sub>由 Evergreen Feedback 面板自动生成</sub>');

  return buf.toString();
}

String _pad(int n) => n.toString().padLeft(2, '0');

/// 从反馈信息构造 Issue 标题（简洁、可检索）。
String buildIssueTitle({required String tag, required String description}) {
  final prefix = switch (tag) {
    '🐛 Bug' => '[Bug]',
    '💡 建议' => '[建议]',
    '😤 体验' => '[体验]',
    _ => '[反馈]',
  };
  // 取首行前 40 字作为标题摘要
  final firstLine = description.trim().split('\n').first.trim();
  final summary = firstLine.length > 40 ? '${firstLine.substring(0, 40)}…' : firstLine;
  final safe = summary.isEmpty ? '未命名反馈' : summary;
  return '$prefix $safe';
}
