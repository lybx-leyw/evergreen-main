/// HTML render: renderTypeCheck
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderTypeCheck(Map<String, dynamic> comp) {

  return '''
<div class="evg-comp evg-comp-typecheck">
  <div class="evg-comp-title">✅ 类型检查</div>
  <div class="evg-tc-question">
    <span class="evg-tc-q-number">Q1.</span>
    <span class="evg-tc-q-text">以下哪个是正确的 Python 列表声明？</span>
  </div>
  <div class="evg-tc-options">
    <div class="evg-tc-opt">A. list = (1, 2, 3)</div>
    <div class="evg-tc-opt correct">B. list = [1, 2, 3]</div>
    <div class="evg-tc-opt">C. list = {1, 2, 3}</div>
    <div class="evg-tc-opt">D. list = <1, 2, 3></div>
  </div>
  <div class="evg-tc-score">得分: <span style="color:var(--evg-state-success)">1/1</span> | 尝试: 1</div>
</div>''';
}
