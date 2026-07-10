/// HTML render: renderDocument
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderDocument(Map<String, dynamic> comp) {
  final cfg = (comp['config'] as Map<String, dynamic>? ?? {})['document'] as Map<String, dynamic>? ?? {};
  final exportFormats = (cfg['exportFormats'] as List<dynamic>? ?? ['pdf', 'docx', 'md', 'html', 'txt'])
      .map((f) => '<span class="evg-doc-tag">$f</span>')
      .join('');

  return '''
<div class="evg-comp evg-comp-doc">
  <div class="evg-doc-toolbar">
    <span class="evg-doc-logo">📝 文档编辑器</span>
    <div class="evg-doc-actions">$exportFormats</div>
  </div>
  <div class="evg-doc-content">
    <h2>文档标题</h2>
    <p>这是一段示例文档内容。支持<strong>粗体</strong>、<em>斜体</em>、<u>下划线</u>、<s>删除线</s>等格式。</p>
    <blockquote>这是引用块——用于强调重要内容。</blockquote>
    <p>支持多种导出格式，包括 PDF、Word、Markdown 等。</p>
  </div>
</div>''';
}
