/// HTML render: renderPresentation
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderPresentation(Map<String, dynamic> comp) {
  return '''
<div class="evg-comp evg-comp-pres">
  <div class="evg-pres-slide">
    <div class="evg-pres-title">幻灯片演示</div>
    <div class="evg-pres-content">
      <p>支持动画、过渡效果、演讲者备注、多种布局模板。</p>
      <p>导出格式：PDF / PPTX / PNG / HTML</p>
    </div>
    <div class="evg-pres-page">1 / 5</div>
  </div>
  <div class="evg-pres-nav">
    <button>◀ 上一页</button>
    <button>下一页 ▶</button>
  </div>
</div>''';
}
