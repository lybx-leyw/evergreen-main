/// 技术规划文档 HTML 静态渲染器（Phase 2）。
///
/// 提供非交互式的静态 HTML 预览，用于 WebView 预览模式。
/// 不依赖 Flutter widget 树——纯字符串拼接生成合法 HTML。
library;

import 'models/tech_document.dart';
import 'services/doc_export_service.dart';

/// 静态 HTML 渲染器。
///
/// 将 [TechDocument] 渲染为完整的独立 HTML 页面。
/// 用于 WebView 预览、打印、分享等场景。
class RenderTechPlanner {
  final TechDocument document;

  /// 可选的 AI 分析报告（用于附录渲染）。
  final TechAnalysisReport? analysisReport;

  const RenderTechPlanner({
    required this.document,
    this.analysisReport,
  });

  /// 渲染为完整 HTML 文档。
  String render() {
    final title = _esc(document.title);
    final contentHtml = _mdToHtml(document.content);
    final meta = _renderMeta();
    final appendix = _renderAppendix();

    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$title</title>
  <style>
    ${_css()}
  </style>
</head>
<body>
  <article class="tech-plan">
    <header>
      <h1>$title</h1>
      $meta
    </header>
    <main class="content">
      $contentHtml
    </main>
    $appendix
    <footer>
      由 Evergreen Multi-Tools 技术规划编辑器生成
    </footer>
  </article>
</body>
</html>''';
  }

  /// 渲染正文内容为 HTML 片段（不含 head/body）。
  String renderBodyOnly() {
    return _mdToHtml(document.content);
  }

  /// 使用 [DocExportService] 导出完整 HTML。
  ///
  /// 提供与导出服务一致的表单（含附录 A/B/C）。
  String renderWithExportService(DocExportService exportService) {
    final result = exportService.exportHtml();
    return result.content;
  }

  // ═══════ 内部 ═══════

  String _esc(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  String _renderMeta() {
    final updated = document.updatedAt.toLocal().toString().substring(0, 19);
    return '<p class="meta">最后更新：$updated</p>';
  }

  String _renderAppendix() {
    if (analysisReport == null || analysisReport!.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('<section class="appendix">');
    buf.writeln('<h2>AI 技术调研摘要</h2>');
    buf.writeln('<p><strong>设计理解：</strong>${_esc(analysisReport!.understanding)}</p>');

    if (analysisReport!.evidence.isNotEmpty) {
      buf.writeln('<h3>技术参考</h3><ul>');
      for (final e in analysisReport!.evidence) {
        buf.write('<li><strong>${_esc(e.source)}</strong>：${_esc(e.content)}');
        if (e.url != null && e.url!.isNotEmpty) {
          buf.write('（<a href="${_esc(e.url!)}" target="_blank">来源</a>）');
        }
        buf.writeln('</li>');
      }
      buf.writeln('</ul>');
    }

    if (analysisReport!.newIdeas.isNotEmpty) {
      buf.writeln('<h3>AI 建议</h3><ul>');
      for (final idea in analysisReport!.newIdeas) {
        buf.writeln('<li>${_esc(idea)}</li>');
      }
      buf.writeln('</ul>');
    }

    buf.writeln('</section>');
    return buf.toString();
  }

  /// 精简 Markdown → HTML 转换器。
  ///
  /// 处理：标题 #/##/###、粗体 **、斜体 *、代码块 ```、
  /// 列表 -/*、引用 >、分割线 ---、行内代码 `。
  String _mdToHtml(String md) {
    final lines = md.split('\n');
    final buf = StringBuffer();
    bool inCodeBlock = false;
    bool inUl = false;
    bool inOl = false;

    for (final line in lines) {
      final trimmed = line.trim();

      // ── 代码块 ──
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
        buf.writeln(_esc(line));
        continue;
      }

      // ── 空行 ──
      if (trimmed.isEmpty) {
        if (inUl) { buf.writeln('</ul>'); inUl = false; }
        if (inOl) { buf.writeln('</ol>'); inOl = false; }
        continue;
      }

      // ── 标题 ──
      if (trimmed.startsWith('### ')) {
        buf.writeln('<h3>${_inlineMd(trimmed.substring(4))}</h3>');
        continue;
      }
      if (trimmed.startsWith('## ')) {
        buf.writeln('<h2>${_inlineMd(trimmed.substring(3))}</h2>');
        continue;
      }
      if (trimmed.startsWith('# ')) {
        buf.writeln('<h1>${_inlineMd(trimmed.substring(2))}</h1>');
        continue;
      }

      // ── 引用 ──
      if (trimmed.startsWith('> ')) {
        buf.writeln('<blockquote>${_inlineMd(trimmed.substring(2))}</blockquote>');
        continue;
      }

      // ── 分割线 ──
      if (trimmed == '---' || trimmed == '***') {
        buf.writeln('<hr>');
        continue;
      }

      // ── 无序列表 ──
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        if (!inUl) { buf.writeln('<ul>'); inUl = true; }
        buf.writeln('<li>${_inlineMd(trimmed.substring(2))}</li>');
        continue;
      }

      // ── 有序列表 ──
      final olMatch = RegExp(r'^(\d+)\.\s').firstMatch(trimmed);
      if (olMatch != null) {
        if (!inOl) { buf.writeln('<ol>'); inOl = true; }
        final text = trimmed.substring(olMatch.end);
        buf.writeln('<li>${_inlineMd(text)}</li>');
        continue;
      }

      // ── 普通段落 ──
      if (inUl) { buf.writeln('</ul>'); inUl = false; }
      if (inOl) { buf.writeln('</ol>'); inOl = false; }
      buf.writeln('<p>${_inlineMd(trimmed)}</p>');
    }

    if (inUl) buf.writeln('</ul>');
    if (inOl) buf.writeln('</ol>');
    if (inCodeBlock) buf.writeln('</code></pre>');
    return buf.toString();
  }

  /// 行内 Markdown 转换：**粗体**、*斜体*、`代码`、[链接](url)。
  String _inlineMd(String text) {
    // 注意顺序：粗体在斜体之前
    String result = text;
    // 粗体 **text**
    result = result.replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*'),
      (m) => '<strong>${_esc(m.group(1)!)}</strong>',
    );
    // 斜体 *text*
    result = result.replaceAllMapped(
      RegExp(r'\*(.+?)\*'),
      (m) => '<em>${_esc(m.group(1)!)}</em>',
    );
    // 行内代码 `text`
    result = result.replaceAllMapped(
      RegExp(r'`(.+?)`'),
      (m) => '<code>${_esc(m.group(1)!)}</code>',
    );
    // 链接 [text](url)
    result = result.replaceAllMapped(
      RegExp(r'\[(.+?)\]\((.+?)\)'),
      (m) => '<a href="${_esc(m.group(2)!)}" target="_blank">${_esc(m.group(1)!)}</a>',
    );
    return result;
  }

  /// 内嵌 CSS 样式表。
  String _css() => '''
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans SC", sans-serif;
  line-height: 1.8;
  color: #24292e;
  background: #fff;
  padding: 40px 20px;
}
.tech-plan {
  max-width: 860px;
  margin: 0 auto;
}
header {
  text-align: center;
  padding: 40px 0 30px;
  border-bottom: 2px solid #e1e4e8;
  margin-bottom: 40px;
}
header h1 { font-size: 2em; color: #1a1a2e; margin-bottom: 8px; }
.meta { color: #6a737d; font-size: 0.9em; }
.content h1 { border-bottom: 1px solid #e1e4e8; padding-bottom: 8px; margin: 28px 0 16px; }
.content h2 { margin: 24px 0 12px; color: #1a1a2e; font-size: 1.4em; }
.content h3 { margin: 18px 0 8px; font-size: 1.15em; }
.content p { margin: 10px 0; }
.content ul, .content ol { padding-left: 24px; margin: 10px 0; }
.content li { margin: 4px 0; }
.content code {
  background: #f6f8fa; padding: 2px 6px; border-radius: 3px;
  font-family: "SF Mono", "Fira Code", "Cascadia Code", monospace;
  font-size: 0.9em;
}
.content pre {
  background: #f6f8fa; padding: 16px; border-radius: 6px;
  overflow-x: auto; margin: 14px 0;
}
.content pre code { background: none; padding: 0; }
.content blockquote {
  border-left: 4px solid #0366d6; padding: 8px 16px; margin: 14px 0;
  color: #6a737d; background: #f1f8ff;
}
.content hr { border: none; border-top: 1px solid #e1e4e8; margin: 24px 0; }
.content a { color: #0366d6; text-decoration: none; }
.content a:hover { text-decoration: underline; }
.appendix {
  margin-top: 60px; padding-top: 30px;
  border-top: 2px solid #e1e4e8;
}
.appendix h2 { color: #586069; margin-bottom: 12px; }
.appendix h3 { color: #6a737d; margin: 16px 0 8px; }
footer {
  margin-top: 50px; padding-top: 20px;
  border-top: 1px solid #e1e4e8;
  color: #6a737d; font-size: 0.85em; text-align: center;
}
@media print {
  body { padding: 0; }
  .tech-plan { max-width: 100%; }
  .appendix { page-break-before: always; }
}
''';
}
