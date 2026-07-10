/// HTML render: renderForm
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderForm(Map<String, dynamic> comp) {
  final cfg = (comp['config'] as Map<String, dynamic>? ?? {})['form'] as Map<String, dynamic>? ?? {};
  final fields = cfg['fields'] as List<dynamic>? ?? [];

  final fieldHtmls = fields.map((f) {
    final fMap = f as Map<String, dynamic>? ?? {};
    final type = fMap['type'] as String? ?? 'text';
    final key = fMap['key'] as String? ?? '';
    final label = fMap['label'] as String? ?? key;
    final required = fMap['required'] == true;
    final placeholder = fMap['placeholder'] as String? ?? '';

    switch (type) {
      case 'textarea':
        return '''
<div class="evg-form-field">
  <label>${esc(label)}${required ? ' <span style="color:var(--evg-state-error)">*</span>' : ''}</label>
  <textarea rows="${fMap['rows'] ?? 3}" placeholder="${esc(placeholder)}"></textarea>
</div>''';
      case 'select':
        final options = (fMap['options'] as List<dynamic>? ?? [])
            .map((o) => '<option value="${esc(o['value'] ?? '')}">${esc(o['label'] ?? '')}</option>')
            .join('');
        return '''
<div class="evg-form-field">
  <label>${esc(label)}${required ? ' <span style="color:var(--evg-state-error)">*</span>' : ''}</label>
  <select>$options</select>
</div>''';
      case 'checkbox':
        return '''
<div class="evg-form-field inline">
  <input type="checkbox" id="f_$key" ${required ? 'required' : ''} />
  <label for="f_$key">${esc(label)}${required ? ' <span style="color:var(--evg-state-error)">*</span>' : ''}</label>
</div>''';
      case 'email':
        return '''
<div class="evg-form-field">
  <label>${esc(label)}${required ? ' <span style="color:var(--evg-state-error)">*</span>' : ''}</label>
  <input type="email" placeholder="${esc(placeholder)}" />
</div>''';
      case 'number':
        return '''
<div class="evg-form-field">
  <label>${esc(label)}${required ? ' <span style="color:var(--evg-state-error)">*</span>' : ''}</label>
  <input type="number" min="${fMap['min'] ?? ''}" max="${fMap['max'] ?? ''}" />
</div>''';
      case 'date':
        return '''
<div class="evg-form-field">
  <label>${esc(label)}</label>
  <input type="date" />
</div>''';
      case 'text':
      default:
        return '''
<div class="evg-form-field">
  <label>${esc(label)}${required ? ' <span style="color:var(--evg-state-error)">*</span>' : ''}</label>
  <input type="text" placeholder="${esc(placeholder)}" />
</div>''';
    }
  }).join('');

  return '''
<div class="evg-comp evg-comp-form">
  <div class="evg-comp-title">📋 表单</div>
  $fieldHtmls
  <button class="evg-form-submit">提交</button>
</div>''';
}
