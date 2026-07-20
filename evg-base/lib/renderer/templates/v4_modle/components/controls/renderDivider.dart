/// HTML render: renderDivider — 模板引擎渲染，读取 config.style（白名单校验）。
library;
import 'package:evergreen_base/renderer/components/shared/template_engine.dart';

const _tpl = '''
<div class="evg-comp evg-comp-divider"><hr style="border-top-style:{{ config.style | allow('solid','dashed','dotted','solid') }}" /></div>
''';

String renderDivider(Map<String, dynamic> comp) => renderTemplate(_tpl, comp);
