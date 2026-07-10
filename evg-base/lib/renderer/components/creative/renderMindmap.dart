/// HTML render: renderMindmap
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderMindmap(Map<String, dynamic> comp) {
  return '''
<div class="evg-comp evg-comp-mindmap">
  <div class="evg-comp-title">🧠 思维导图</div>
  <div class="evg-mindmap-node" style="text-align:center;padding:20px">
    <div class="evg-mm-root">核心主题</div>
    <div style="display:flex;justify-content:center;gap:24px;margin-top:16px">
      <div class="evg-mm-branch">分支 A</div>
      <div class="evg-mm-branch">分支 B</div>
      <div class="evg-mm-branch">分支 C</div>
    </div>
  </div>
</div>''';
}
