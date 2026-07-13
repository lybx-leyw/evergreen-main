/// 文档一键导出服务。
///
/// 支持导出为 Markdown、HTML、PDF（含技术决策附录和 AI 交互摘要）。
library;

import 'dart:convert';
import 'dart:io' show File;

import '../models/tech_document.dart';
import '../models/tech_version.dart';
import '../models/trace_record.dart';
import 'doc_trace_service.dart';

/// 导出格式。
enum ExportFormat {
  /// 纯 Markdown 文本。
  markdown,

  /// 含样式的 HTML 文件。
  html,

  /// PDF（通过 HTML → 打印生成）。
  pdf,
}

/// 导出结果。
class ExportResult {
  final ExportFormat format;
  final String content;
  final String? filePath;
  final int byteSize;

  const ExportResult({
    required this.format,
    required this.content,
    this.filePath,
    required this.byteSize,
  });

  String get mimeType {
    switch (format) {
      case ExportFormat.markdown:
        return 'text/markdown';
      case ExportFormat.html:
        return 'text/html';
      case ExportFormat.pdf:
        return 'application/pdf';
    }
  }

  String get defaultExtension {
    switch (format) {
      case ExportFormat.markdown:
        return 'md';
      case ExportFormat.html:
        return 'html';
      case ExportFormat.pdf:
        return 'pdf';
    }
  }
}

/// 文档导出服务。
class DocExportService {
  final TechDocument document;
  final DocTraceService? traceService;

  DocExportService({required this.document, this.traceService});

  /// 导出为 Markdown。
  ExportResult exportMarkdown() {
    final buf = StringBuffer();

    // ── 封面 ──
    buf.writeln('# ${document.title}');
    buf.writeln();
    buf.writeln(
        '> 生成时间：${document.updatedAt.toLocal().toString().substring(0, 19)}');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();

    // ── 正文 ──
    buf.writeln(document.content);
    buf.writeln();

    // ── 附录 ──
    _appendAppendixMarkdown(buf);

    final content = buf.toString();
    return ExportResult(
      format: ExportFormat.markdown,
      content: content,
      byteSize: utf8.encode(content).length,
    );
  }

  /// 导出为 HTML。
  ExportResult exportHtml() {
    final mdContent = _escapeHtml(document.content);
    final htmlContent = _renderMarkdownToHtml(mdContent);

    final html = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${_escapeHtml(document.title)}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      line-height: 1.8;
      color: #24292e;
      max-width: 900px;
      margin: 0 auto;
      padding: 40px 20px;
      background: #fff;
    }
    .cover {
      text-align: center;
      padding: 60px 0;
      border-bottom: 2px solid #e1e4e8;
      margin-bottom: 40px;
    }
    .cover h1 { font-size: 2em; color: #1a1a2e; margin-bottom: 12px; }
    .cover .meta { color: #6a737d; font-size: 0.9em; }
    .content { }
    .content h1 { border-bottom: 1px solid #e1e4e8; padding-bottom: 8px; margin: 24px 0 16px; }
    .content h2 { margin: 20px 0 12px; color: #1a1a2e; }
    .content h3 { margin: 16px 0 8px; }
    .content p { margin: 8px 0; }
    .content ul, .content ol { padding-left: 24px; margin: 8px 0; }
    .content code {
      background: #f6f8fa;
      padding: 2px 6px;
      border-radius: 3px;
      font-family: "SF Mono", "Fira Code", monospace;
      font-size: 0.9em;
    }
    .content pre {
      background: #f6f8fa;
      padding: 16px;
      border-radius: 6px;
      overflow-x: auto;
      margin: 12px 0;
    }
    .content pre code {
      background: none;
      padding: 0;
    }
    .content blockquote {
      border-left: 4px solid #dfe2e5;
      padding: 8px 16px;
      margin: 12px 0;
      color: #6a737d;
      background: #f6f8fa;
    }
    .appendix {
      margin-top: 60px;
      padding-top: 40px;
      border-top: 2px solid #e1e4e8;
    }
    .appendix h2 { color: #586069; }
    .appendix h3 { color: #6a737d; }
    .appendix table {
      width: 100%;
      border-collapse: collapse;
      margin: 16px 0;
    }
    .appendix th, .appendix td {
      border: 1px solid #e1e4e8;
      padding: 8px 12px;
      text-align: left;
    }
    .appendix th {
      background: #f6f8fa;
      font-weight: 600;
    }
    .footer {
      margin-top: 40px;
      padding-top: 20px;
      border-top: 1px solid #e1e4e8;
      color: #6a737d;
      font-size: 0.85em;
      text-align: center;
    }
    @media print {
      body { max-width: 100%; padding: 20px; }
      .appendix { page-break-before: always; }
    }
  </style>
</head>
<body>
  <div class="cover">
    <h1>${_escapeHtml(document.title)}</h1>
    <p class="meta">技术规划文档</p>
    <p class="meta">最后更新：${document.updatedAt.toLocal().toString().substring(0, 19)}</p>
  </div>

  <div class="content">
    $htmlContent
  </div>

  <div class="appendix">
    ${_renderAppendixHtml()}
  </div>

  <div class="footer">
    由 Evergreen Multi-Tools 技术规划编辑器生成
  </div>
</body>
</html>''';

    return ExportResult(
      format: ExportFormat.html,
      content: html,
      byteSize: utf8.encode(html).length,
    );
  }

  /// 导出为 PDF（生成 HTML 内容，由调用方通过打印/WebView 生成 PDF）。
  ///
  /// PDF 导出复用 HTML 导出内容，支持 `@page` 打印样式。
  ExportResult exportPdf() {
    final htmlResult = exportHtml();
    return ExportResult(
      format: ExportFormat.pdf,
      content: htmlResult.content, // 由调用方转换为 PDF
      byteSize: htmlResult.byteSize,
    );
  }

  /// 写入文件并返回文件路径。
  Future<ExportResult> exportToFile(
      ExportFormat format, String outputPath) async {
    ExportResult result;
    switch (format) {
      case ExportFormat.markdown:
        result = exportMarkdown();
        break;
      case ExportFormat.html:
        result = exportHtml();
        break;
      case ExportFormat.pdf:
        result = exportPdf();
        break;
    }

    final filePath = '$outputPath.${result.defaultExtension}';
    final file = File(filePath);
    await file.writeAsString(result.content, encoding: utf8);
    return ExportResult(
      format: format,
      content: result.content,
      filePath: filePath,
      byteSize: result.byteSize,
    );
  }

  // ═══════ 附录生成 ═══════

  void _appendAppendixMarkdown(StringBuffer buf) {
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## 附录 A：技术决策记录');
    buf.writeln();

    if (traceService != null && traceService!.traceRecords.isNotEmpty) {
      final aiRecords = traceService!.traceRecords
          .where((t) => t.isCompleted)
          .toList();

      if (aiRecords.isNotEmpty) {
        buf.writeln('| # | 时间 | 触发方式 | 决策 | AI 摘要 |');
        buf.writeln('|---|------|---------|------|---------|');

        for (var i = 0; i < aiRecords.length; i++) {
          final r = aiRecords[i];
          final time = r.createdAt.toLocal().toString().substring(0, 16);
          final trigger = _triggerLabel(r.triggerType);
          final decision = r.decision != null ? _decisionLabel(r.decision!) : '—';
          final summary =
              r.analysisReport?.understanding ?? '—';
          buf.writeln(
              '| ${i + 1} | $time | $trigger | $decision | ${summary.length > 50 ? '${summary.substring(0, 50)}...' : summary} |');
        }
        buf.writeln();
      } else {
        buf.writeln('（无 AI 交互记录）');
        buf.writeln();
      }

      buf.writeln('---');
      buf.writeln();
      buf.writeln('## 附录 B：版本历史');
      buf.writeln();

      final versions = traceService!.versions;
      buf.writeln('| 版本 | 时间 | 类型 | 说明 |');
      buf.writeln('|------|------|------|------|');
      for (final v in versions) {
        final time = v.createdAt.toLocal().toString().substring(0, 16);
        final type = _versionTypeLabel(v.changeType);
        final desc = v.description ?? '—';
        buf.writeln('| v${v.versionNumber} | $time | $type | $desc |');
      }
      buf.writeln();
    } else {
      buf.writeln('（无版本追溯记录）');
      buf.writeln();
    }

    // 文档元信息
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## 附录 C：文档元信息');
    buf.writeln();
    buf.writeln('- **文档 ID**：${document.id}');
    buf.writeln('- **创建时间**：${document.createdAt.toLocal().toString().substring(0, 19)}');
    buf.writeln(
        '- **最后更新**：${document.updatedAt.toLocal().toString().substring(0, 19)}');
    if (traceService != null) {
      buf.writeln('- **版本数**：${traceService!.versionCount}');
      buf.writeln('- **AI 交互次数**：${traceService!.traceRecords.length}');
    }
    buf.writeln();
  }

  String _renderAppendixHtml() {
    final buf = StringBuffer();
    buf.writeln('<h2>附录 A：技术决策记录</h2>');

    if (traceService != null && traceService!.traceRecords.isNotEmpty) {
      final aiRecords = traceService!.traceRecords
          .where((t) => t.isCompleted)
          .toList();

      if (aiRecords.isNotEmpty) {
        buf.writeln('<table>');
        buf.writeln('<tr><th>#</th><th>时间</th><th>触发方式</th><th>决策</th><th>AI 摘要</th></tr>');
        for (var i = 0; i < aiRecords.length; i++) {
          final r = aiRecords[i];
          final time = r.createdAt.toLocal().toString().substring(0, 16);
          final trigger = _triggerLabel(r.triggerType);
          final decision = r.decision != null ? _decisionLabel(r.decision!) : '—';
          final summary = r.analysisReport?.understanding ?? '—';
          buf.writeln(
              '<tr><td>${i + 1}</td><td>$time</td><td>$trigger</td><td>$decision</td><td>${_escapeHtml(summary)}</td></tr>');
        }
        buf.writeln('</table>');
      } else {
        buf.writeln('<p>（无 AI 交互记录）</p>');
      }

      buf.writeln('<h2>附录 B：版本历史</h2>');
      buf.writeln('<table>');
      buf.writeln('<tr><th>版本</th><th>时间</th><th>类型</th><th>说明</th></tr>');
      for (final v in traceService!.versions) {
        final time = v.createdAt.toLocal().toString().substring(0, 16);
        final type = _versionTypeLabel(v.changeType);
        final desc = v.description ?? '—';
        buf.writeln(
            '<tr><td>v${v.versionNumber}</td><td>$time</td><td>$type</td><td>${_escapeHtml(desc)}</td></tr>');
      }
      buf.writeln('</table>');
    } else {
      buf.writeln('<p>（无版本追溯记录）</p>');
    }

    buf.writeln('<h2>附录 C：文档元信息</h2>');
    buf.writeln('<ul>');
    buf.writeln('<li><strong>文档 ID</strong>：${document.id}</li>');
    buf.writeln(
        '<li><strong>创建时间</strong>：${document.createdAt.toLocal().toString().substring(0, 19)}</li>');
    buf.writeln(
        '<li><strong>最后更新</strong>：${document.updatedAt.toLocal().toString().substring(0, 19)}</li>');
    if (traceService != null) {
      buf.writeln('<li><strong>版本数</strong>：${traceService!.versionCount}</li>');
      buf.writeln(
          '<li><strong>AI 交互次数</strong>：${traceService!.traceRecords.length}</li>');
    }
    buf.writeln('</ul>');

    return buf.toString();
  }

  // ═══════ 工具方法 ═══════

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  /// 简单 Markdown → HTML 渲染（仅处理标题、列表、代码、引用）。
  String _renderMarkdownToHtml(String text) {
    final lines = text.split('\n');
    final buf = StringBuffer();
    bool inCodeBlock = false;
    bool inList = false;

    for (final line in lines) {
      final trimmed = line.trim();

      // 代码块
      if (trimmed.startsWith('```')) {
        if (inCodeBlock) {
          buf.writeln('</code></pre>');
          inCodeBlock = false;
        } else {
          buf.write('<pre><code>');
          inCodeBlock = true;
        }
        continue;
      }
      if (inCodeBlock) {
        buf.writeln(_escapeHtml(line));
        continue;
      }

      // 空行
      if (trimmed.isEmpty) {
        if (inList) {
          buf.writeln('</ul>');
          inList = false;
        }
        buf.writeln('<br>');
        continue;
      }

      // 标题
      if (trimmed.startsWith('### ')) {
        buf.writeln('<h3>${trimmed.substring(4)}</h3>');
        continue;
      }
      if (trimmed.startsWith('## ')) {
        buf.writeln('<h2>${trimmed.substring(3)}</h2>');
        continue;
      }
      if (trimmed.startsWith('# ')) {
        buf.writeln('<h1>${trimmed.substring(2)}</h1>');
        continue;
      }

      // 引用
      if (trimmed.startsWith('> ')) {
        buf.writeln('<blockquote>${trimmed.substring(2)}</blockquote>');
        continue;
      }

      // 分割线
      if (trimmed == '---') {
        buf.writeln('<hr>');
        continue;
      }

      // 列表项
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        if (!inList) {
          buf.writeln('<ul>');
          inList = true;
        }
        buf.writeln('<li>${trimmed.substring(2)}</li>');
        continue;
      }

      if (inList) {
        buf.writeln('</ul>');
        inList = false;
      }

      // 普通段落
      buf.writeln('<p>$trimmed</p>');
    }

    if (inList) buf.writeln('</ul>');
    if (inCodeBlock) buf.writeln('</code></pre>');
    return buf.toString();
  }

  static String _triggerLabel(TraceTriggerType t) {
    switch (t) {
      case TraceTriggerType.atAiManual:
        return '@ai 手动';
      case TraceTriggerType.toolbarAnalyze:
        return '工具栏分析';
      case TraceTriggerType.ghostAutoComplete:
        return '幽灵补全';
      case TraceTriggerType.ghostTabAdopt:
        return '幽灵采纳';
    }
  }

  static String _decisionLabel(TraceDecision d) {
    switch (d) {
      case TraceDecision.accepted:
        return '✅ 接受';
      case TraceDecision.rejected:
        return '❌ 拒绝';
      case TraceDecision.partial:
        return '🔶 部分';
      case TraceDecision.viewed:
        return '👁 查看';
    }
  }

  static String _versionTypeLabel(VersionChangeType t) {
    switch (t) {
      case VersionChangeType.manualEdit:
        return '手动编辑';
      case VersionChangeType.aiRevision:
        return 'AI 改写';
      case VersionChangeType.ghostAdopt:
        return '幽灵采纳';
      case VersionChangeType.initial:
        return '初始';
    }
  }
}
