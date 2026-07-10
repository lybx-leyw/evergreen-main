/// HTML render: renderPromptBuilder
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderPromptBuilder(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final template = cfg['template'] as String? ?? '你是一个{role}，请帮我{task}。要求：{requirements}';
  final variables = (cfg['variables'] as Map<String, dynamic>? ?? {
    'role': 'Python 专家',
    'task': '优化这段代码的性能',
    'requirements': '保持代码可读性，添加注释',
  });

  final varInputsHtml = variables.entries.map((e) => '''
<div class="evg-pb-field">
  <label>${esc(e.key)}</label>
  <input type="text" value="${esc(e.value.toString())}" placeholder="${esc(e.key)}" />
</div>''').join('');

  return '''
<div class="evg-comp evg-comp-prompt-builder">
  <div class="evg-comp-title">🔧 Prompt 构建器</div>
  <div class="evg-pb-template">
    <div class="evg-pb-label">模板:</div>
    <pre class="evg-pb-pre">${esc(template)}</pre>
  </div>
  <div class="evg-pb-vars">
    <div class="evg-pb-label">变量:</div>
    $varInputsHtml
  </div>
  <button class="evg-pb-generate">✨ 生成 Prompt</button>
</div>''';
}
