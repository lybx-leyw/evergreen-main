/// V2 53 种组件类型 → HTML 模板。
///
/// 覆盖 PLAN_NOW 第四节全部 53 个组件 + SlotDispatch 中实际使用的别名。
/// 
/// 分组策略：
/// - P0 (13): V2 TARGET showcase 使用的核心类型 → 完整 HTML
/// - P1 (20): PLAN_NOW 有定义但 V2 未用的 → 完整 HTML
/// - P2 (20): placeholder-01~20 → 统一占位卡片
library;

import 'dart:convert';

// ============================================================
// 组件类型 → 渲染函数 注册表
// ============================================================

/// 根据组件类型名返回对应的 HTML 字符串。
/// 
/// [comp] 是 V2 `component` 对象: `{ type, config, input, events, process, dataSource }`
String renderComponent(Map<String, dynamic> comp) {
  final type = comp['type'] as String? ?? 'unknown';
  final fn = _renderers[type] ?? _renderGeneric;
  return fn(comp);
}

/// 获取组件类型对应的图标（用于占位或标题）。
String componentIcon(String type) {
  return _componentIcons[type] ?? '📦';
}

// ============================================================
// P0: V2 TARGET Showcase 使用的 13 个核心类型
// ============================================================

/// chat / ai-assistant — R11：必须渲染 config 中声明的真实字段
///（preset / system_prompt / tools / multi_session / global_memory 等），
/// 不得写死「介绍平台功能」之类示例对话。会话本身为运行态实时加载，
/// 仅以占位气泡说明，不伪造历史消息。
String _renderChat(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final input = comp['input'] as Map<String, dynamic>? ?? {};
  final placeholder = cfg['placeholder'] as String? ?? '输入消息...';
  final thinking = cfg['thinking'] as Map<String, dynamic>? ?? {};
  final thinkingVisible = thinking['visible'] == true;
  final bubble = cfg['bubble'] as Map<String, dynamic>? ?? {};
  final showAvatar = bubble['showAvatar'] == true;

  // ai-assistant 专用真实字段
  final preset = cfg['preset'] as String?;
  final systemPrompt = cfg['system_prompt'] as String?;
  final toolsRaw = cfg['tools'];
  final toolsList = toolsRaw is List
      ? toolsRaw
      : (toolsRaw is Map ? toolsRaw.values.toList() : <dynamic>[]);
  final tools = toolsList
      .map((t) => _esc((t is Map ? (t['name'] ?? t['id']) : t).toString()))
      .join('、');
  final multiSession = cfg['multi_session'] == true;
  final globalMemory = cfg['global_memory'] == true;

  final configPanel = (preset != null || systemPrompt != null || tools.isNotEmpty)
      ? '''
  <div class="evg-chat-config">
    ${preset != null ? '<div class="evg-chat-cfg-row"><b>预设</b>: ${_esc(preset)}</div>' : ''}
    ${systemPrompt != null ? '<div class="evg-chat-cfg-row"><b>系统提示</b>: ${_esc(systemPrompt)}</div>' : ''}
    ${tools.isNotEmpty ? '<div class="evg-chat-cfg-row"><b>工具</b>: $tools</div>' : ''}
    <div class="evg-chat-cfg-row"><b>多会话</b>: ${multiSession ? '开' : '关'} ｜ <b>全局记忆</b>: ${globalMemory ? '开' : '关'}</div>
  </div>'''
      : '';

  final qrRaw = input['quickReplies'];
  final quickReplies = (qrRaw is List ? qrRaw : <dynamic>[])
      .map((q) => '<span class="evg-quick-reply">${_esc(q is Map ? (q['label'] ?? '') : '')}</span>')
      .join('');

  return '''
<div class="evg-comp evg-comp-chat">
  $configPanel
  <div class="evg-chat-msgs">
    <div class="evg-msg assistant">
      ${showAvatar ? '<div class="evg-avatar">AI</div>' : ''}
      <div class="evg-bubble">${preset != null ? '已加载预设「${_esc(preset)}」，实时会话运行态加载。' : '实时会话运行态加载。'}${thinkingVisible ? '<br><i style="color:var(--evg-text-secondary);font-size:11px">思考中…</i>' : ''}</div>
    </div>
  </div>
  <div class="evg-chat-input">
    <input type="text" placeholder="${_esc(placeholder)}" />
    <button>发送</button>
  </div>
  ${quickReplies.isNotEmpty ? '<div class="evg-quick-replies">$quickReplies</div>' : ''}
</div>''';
}

String _renderCodeEditor(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final lang = cfg['language'] as String? ?? 'python';
  final samples = _codeSamples[lang] ?? _codeSamples['python']!;

  return '''
<div class="evg-comp evg-comp-code">
  <div class="evg-code-header">
    <span>📄 main.${_langExt(lang)}</span>
    <span class="evg-code-lang">$lang</span>
  </div>
  <div class="evg-code-body">
    <div class="evg-code-lines">${List.generate(samples.length, (i) => i + 1).join('<br>')}</div>
    <pre class="evg-code-pre">${samples.join('\n')}</pre>
  </div>
</div>''';
}

String _renderDataTable(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final display = cfg['display'] as String? ?? 'table';
  final title = cfg['title'] as String? ?? '';
  final columns = (cfg['columns'] as List<dynamic>?)
      ?.map((c) => c is Map ? c : {'key': c.toString(), 'label': c.toString()})
      .toList() ?? [{'key': 'id', 'label': 'ID'}, {'key': 'name', 'label': '名称'}, {'key': 'status', 'label': '状态'}];
  final filter = cfg['filter'] == true;
  final sortable = cfg['sortable'] == true;
  // R10 渲染日志升级：真实数据行（由外部数据源拉取后注入 config.rows）。
  final rows = (cfg['rows'] as List<dynamic>?)
      ?.whereType<Map<dynamic, dynamic>>()
      .toList() ?? const <Map<dynamic, dynamic>>[];

  if (display == 'card') return _renderDataCards(title, columns, rows);
  return _renderDataTableHTML(title, columns, filter, sortable, rows);
}

String _renderDataTableHTML(
    String title, List<dynamic> columns, bool filter, bool sortable,
    [List<Map<dynamic, dynamic>> rows = const <Map<dynamic, dynamic>>[]]) {
  final headers = columns.map((c) {
    final label = _esc(c['label'] as String? ?? '');
    return '<th>$label${sortable ? ' <span class="evg-sort">⇅</span>' : ''}</th>';
  }).join('');
  final bodyRows = rows.isEmpty
      ? '<tr><td colspan="${columns.length}" class="evg-empty">（暂无数据 / 官方空态）</td></tr>'
      : rows.map((row) {
          final cells = columns.map((c) {
            final key = c['key'] as String? ?? '';
            final val = row[key];
            final text = val == null ? '' : (val is String ? val : val.toString());
            return '<td>${_esc(text)}</td>';
          }).join('');
          return '<tr>$cells</tr>';
        }).join('');

  return '''
<div class="evg-comp evg-comp-table">
  ${title.isNotEmpty ? '<div class="evg-comp-title">$title</div>' : ''}
  ${filter ? '<div class="evg-table-filter"><input type="text" placeholder="搜索..." /></div>' : ''}
  <table class="evg-table">
    <thead><tr>$headers</tr></thead>
    <tbody>$bodyRows</tbody>
  </table>
</div>''';
}

String _renderDataCards(String title, List<dynamic> columns,
    [List<Map<dynamic, dynamic>> rows = const <Map<dynamic, dynamic>>[]]) {
  final cards = rows.isEmpty
      ? '<div class="evg-card"><div class="evg-cl-body"><div class="evg-cl-text">（暂无数据 / 官方空态）</div></div></div>'
      : rows.map((row) {
          final entries = columns.map((c) {
            final key = c['key'] as String? ?? '';
            final label = c['label'] as String? ?? key;
            final val = row[key];
            final text = val == null ? '' : (val is String ? val : val.toString());
            return '<div class="evg-card-field"><span class="evg-card-label">$label</span><span class="evg-card-val">${_esc(text)}</span></div>';
          }).join('');
          return '<div class="evg-card">$entries</div>';
        }).join('');

  return '''
<div class="evg-comp evg-comp-cards">
  ${title.isNotEmpty ? '<div class="evg-comp-title">$title</div>' : ''}
  <div class="evg-card-grid">$cards</div>
</div>''';
}

String _renderChart(Map<String, dynamic> comp) {
  final chartCfg = (comp['config'] as Map<String, dynamic>? ?? {})['chart'] as Map<String, dynamic>? ?? {};
  final type = chartCfg['type'] as String? ?? 'bar';
  final title = chartCfg['title'] as String? ?? '';
  final legend = chartCfg['legend'] == true;

  switch (type) {
    case 'pie':
    case 'donut':
      return _renderPieChart(title, type == 'donut', legend);
    case 'line':
    case 'radar':
      return _renderLineChart(title, type);
    case 'bar':
    default:
      return _renderBarChart(title, chartCfg, legend);
  }
}

String _renderBarChart(String title, Map<String, dynamic> cfg, bool legend) {
  const colors = ['#ff7b72', '#d2a8ff', '#79c0ff', '#3fb950', '#d29922', '#f78166', '#a5d6ff', '#ffa198'];
  const bars = [45, 72, 38, 60, 85, 55, 93, 40, 67, 50, 78, 62];
  const labels = ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'];

  return '''
<div class="evg-comp evg-comp-chart">
  ${title.isNotEmpty ? '<div class="evg-comp-title">$title</div>' : ''}
  <div class="evg-chart-area">
    <div class="evg-chart-bars">
      ${bars.asMap().entries.map((e) => '''
        <div class="evg-bar-wrapper">
          <div class="evg-bar" style="height:${e.value}%;background:${colors[e.key % colors.length]}">
            <span class="evg-bar-val">${e.value}</span>
          </div>
          <span class="evg-bar-label">${labels[e.key]}</span>
        </div>''').join('')}
    </div>
  </div>
</div>''';
}

String _renderPieChart(String title, bool donut, bool legend) {
  const segments = [
    {'color': '#ff7b72', 'label': 'A类', 'value': 35},
    {'color': '#d2a8ff', 'label': 'B类', 'value': 25},
    {'color': '#79c0ff', 'label': 'C类', 'value': 20},
    {'color': '#3fb950', 'label': 'D类', 'value': 20},
  ];
  int pos = 0;
  final gradient = segments.map((s) {
    final deg = pos * 3.6;
    pos += s['value'] as int;
    final degEnd = pos * 3.6;
    return '${s['color']} ${deg}deg ${degEnd}deg';
  }).join(', ');

  return '''
<div class="evg-comp evg-comp-chart pie">
  ${title.isNotEmpty ? '<div class="evg-comp-title">$title</div>' : ''}
  <div class="evg-chart-pie${donut ? ' donut' : ''}" style="background:conic-gradient($gradient)"></div>
  ${legend ? '<div class="evg-chart-legend">${segments.map((s) => '<div class="evg-legend-item"><span class="evg-legend-dot" style="background:${s['color']}"></span>${s['label']} ${s['value']}%</div>').join('')}</div>' : ''}
</div>''';
}

String _renderLineChart(String title, String type) {
  return '''
<div class="evg-comp evg-comp-chart line">
  ${title.isNotEmpty ? '<div class="evg-comp-title">$title</div>' : ''}
  <div class="evg-chart-line-area">
    <svg viewBox="0 0 400 150" class="evg-line-svg">
      <polyline fill="none" stroke="#58a6ff" stroke-width="2"
        points="0,120 40,90 80,100 120,70 160,50 200,60 240,30 280,45 320,25 360,40 400,20"/>
      <polyline fill="none" stroke="#3fb950" stroke-width="2"
        points="0,100 40,110 80,95 120,85 160,60 200,70 240,55 280,40 320,50 360,35 400,30"/>
    </svg>
  </div>
</div>''';
}

String _renderLotteryWheel(Map<String, dynamic> comp) {
  final cfg = (comp['config'] as Map<String, dynamic>? ?? {})['lottery'] as Map<String, dynamic>? ?? {};
  final title = cfg['title'] as String? ?? '幸运大转盘';
  final subtitle = cfg['subtitle'] as String? ?? '';
  final buttonText = cfg['buttonText'] as String? ?? '立即抽奖!';

  return '''
<div class="evg-comp evg-comp-lottery">
  <div class="evg-lottery-header">
    <div class="evg-comp-title">🎰 $title</div>
    ${subtitle.isNotEmpty ? '<div class="evg-lottery-sub">$subtitle</div>' : ''}
  </div>
  <div class="evg-lottery-wheel-container">
    <canvas class="evg-lottery-canvas" width="200" height="200"></canvas>
    <button class="evg-lottery-btn">🎯 $buttonText</button>
  </div>
  <div class="evg-lottery-history">
    <span style="font-size:11px;color:var(--evg-text-secondary)">📜 最近: 一等奖 二等奖 三等奖...</span>
  </div>
</div>''';
}

String _renderDocument(Map<String, dynamic> comp) {
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

String _renderSpreadsheet(Map<String, dynamic> comp) {
  const cols = ['A', 'B', 'C', 'D', 'E'];

  return '''
<div class="evg-comp evg-comp-sheet">
  <div class="evg-sheet-header">
    <span>📊 电子表格</span>
    <span style="font-size:11px;color:var(--evg-text-secondary)">10列 × 50行</span>
  </div>
  <div class="evg-sheet-table">
    <table>
      <thead><tr><th></th>${cols.map((c) => '<th>$c</th>').join('')}</tr></thead>
      <tbody>${[1, 2, 3, 4, 5].map((r) => '<tr><td class="evg-row-num">$r</td>${cols.map((c) => '<td contenteditable="true">${c == 'A' ? '数据$r' : ''}</td>').join('')}</tr>').join('')}</tbody>
    </table>
  </div>
</div>''';
}

/// R10 渲染日志升级：config.url 提供真实视频源时渲染真实 <video> 播放器
/// （不增加原 video 组件描述外功能；url 为空时仍是运行态占位）。
String _renderVideo(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final url = cfg['url'] as String? ?? '';
  if (url.isNotEmpty) {
    return '''
<div class="evg-comp evg-comp-video">
  <div class="evg-video-placeholder">
    <video src="${_esc(url)}" controls style="max-width:100%;border-radius:8px"></video>
  </div>
</div>''';
  }
  return '''
<div class="evg-comp evg-comp-video">
  <div class="evg-video-placeholder">
    <div class="evg-video-icon">▶</div>
    <div class="evg-video-text">视频播放器</div>
    <div class="evg-video-controls">
      <span>▶</span><span>⏸</span><span>🔊</span>
      <span style="flex:1;height:4px;background:var(--evg-border-default);border-radius:2px;margin:0 8px"></span>
      <span>⛶</span><span>⚙</span>
    </div>
  </div>
</div>''';
}

String _renderPresentation(Map<String, dynamic> comp) {
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

String _renderTypeCheck(Map<String, dynamic> comp) {

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

String _renderForm(Map<String, dynamic> comp) {
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
  <label>${_esc(label)}${required ? ' <span style="color:var(--evg-state-error)">*</span>' : ''}</label>
  <textarea rows="${fMap['rows'] ?? 3}" placeholder="${_esc(placeholder)}"></textarea>
</div>''';
      case 'select':
        final options = (fMap['options'] as List<dynamic>? ?? [])
            .map((o) => '<option value="${_esc(o['value'] ?? '')}">${_esc(o['label'] ?? '')}</option>')
            .join('');
        return '''
<div class="evg-form-field">
  <label>${_esc(label)}${required ? ' <span style="color:var(--evg-state-error)">*</span>' : ''}</label>
  <select>$options</select>
</div>''';
      case 'checkbox':
        return '''
<div class="evg-form-field inline">
  <input type="checkbox" id="f_$key" ${required ? 'required' : ''} />
  <label for="f_$key">${_esc(label)}${required ? ' <span style="color:var(--evg-state-error)">*</span>' : ''}</label>
</div>''';
      case 'email':
        return '''
<div class="evg-form-field">
  <label>${_esc(label)}${required ? ' <span style="color:var(--evg-state-error)">*</span>' : ''}</label>
  <input type="email" placeholder="${_esc(placeholder)}" />
</div>''';
      case 'number':
        return '''
<div class="evg-form-field">
  <label>${_esc(label)}${required ? ' <span style="color:var(--evg-state-error)">*</span>' : ''}</label>
  <input type="number" min="${fMap['min'] ?? ''}" max="${fMap['max'] ?? ''}" />
</div>''';
      case 'date':
        return '''
<div class="evg-form-field">
  <label>${_esc(label)}</label>
  <input type="date" />
</div>''';
      case 'text':
      default:
        return '''
<div class="evg-form-field">
  <label>${_esc(label)}${required ? ' <span style="color:var(--evg-state-error)">*</span>' : ''}</label>
  <input type="text" placeholder="${_esc(placeholder)}" />
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

String _renderCalendar(Map<String, dynamic> comp) {
  const dayHeaders = ['一', '二', '三', '四', '五', '六', '日'];
  // 简单 7×5 网格日历
  final cells = <String>[];
  for (var i = 1; i <= 31; i++) {
    cells.add('<div class="evg-cal-day${i == 15 ? ' active' : ''}">$i</div>');
  }
  // Pad remaining
  for (var i = 32; i <= 35; i++) {
    cells.add('<div class="evg-cal-day"></div>');
  }

  return '''
<div class="evg-comp evg-comp-cal">
  <div class="evg-cal-header">
    <button>◀</button>
    <span>2026年 7月</span>
    <button>▶</button>
  </div>
  <div class="evg-cal-grid">
    ${dayHeaders.map((d) => '<div class="evg-cal-dh">$d</div>').join('')}
    ${cells.join('')}
  </div>
</div>''';
}

String _renderMap(Map<String, dynamic> comp) {
  final cfg = (comp['config'] as Map<String, dynamic>? ?? {})['map'] as Map<String, dynamic>? ?? {};
  final center = cfg['center'] as Map<String, dynamic>? ?? {};
  final lat = center['lat'] ?? '39.9042';
  final lng = center['lng'] ?? '116.4074';

  return '''
<div class="evg-comp evg-comp-map">
  <div class="evg-map-placeholder">
    <div class="evg-map-pin">📍</div>
    <div class="evg-map-coords">$lat, $lng</div>
    <div class="evg-map-zoom">
      <button>+</button><button>−</button>
    </div>
  </div>
</div>''';
}

// ============================================================
// P1: PLAN_NOW 有定义，V2 showcase 未使用的 20 个类型
// ============================================================

String _renderMarkdown(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final content = cfg['content'] as String? ?? '# Markdown 内容\n\n在 config.content 中设置你的 Markdown 文本。';

  return '''
<div class="evg-comp evg-comp-md">
  <div class="evg-comp-title">📄 Markdown</div>
  <div class="evg-md-content" style="white-space:pre-wrap;line-height:1.8;padding:12px">${_esc(content)}</div>
</div>''';
}

String _renderDivider(Map<String, dynamic> comp) {
  return '<div class="evg-comp evg-comp-divider"><hr /></div>';
}

/// flashcards — 闪卡复习（间隔重复）。
/// R11：必须渲染 config.wordList 中的真实词（由 harness 从 words.json 注入），
/// 不得写死示例卡。wordList 元素可为 {word, meaning} 或纯字符串。
String _renderFlashcards(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final raw = cfg['wordList'];
  final words = raw is List
      ? raw
      : <dynamic>[];
  final algorithm = cfg['algorithm'] as String? ?? 'spaced-repetition';
  final total = words.length;

  if (total == 0) {
    return _renderEmpty('flashcards', '暂无词卡（运行时加载词库）');
  }

  final first = words.first;
  final front = first is Map ? (first['word'] ?? first['term'] ?? '') : first.toString();
  final back = first is Map ? (first['meaning'] ?? first['def'] ?? first['definition'] ?? '') : '';

  final cardsHtml = words.take(8).map((w) {
    final f = w is Map ? (w['word'] ?? w['term'] ?? '') : w.toString();
    final b = w is Map ? (w['meaning'] ?? w['def'] ?? w['definition'] ?? '') : '';
    return '''
<div class="evg-flash-card">
  <div class="evg-flash-front">${_esc(f.toString())}</div>
  <div class="evg-flash-back"><code>${_esc(b.toString())}</code></div>
</div>''';
  }).join('');

  return '''
<div class="evg-comp evg-comp-flash">
  <div class="evg-comp-title">🃏 闪卡复习（$algorithm）</div>
  <div class="evg-flash-deck">$cardsHtml</div>
  <div class="evg-flash-nav">
    <button>◀ 上一张</button><span>1 / $total</span><button>下一张 ▶</button>
    <button>翻转</button>
  </div>
</div>''';
}

/// quiz — 答题测验。R11：必须从 config.wordList 生成真实题目，不得写死。
/// wordList 元素 {word, meaning} 或字符串；据此生成「选出正确释义」选择题。
String _renderQuiz(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final raw = cfg['wordList'];
  final words = raw is List ? raw : <dynamic>[];
  final types = (cfg['questionTypes'] as List<dynamic>? ?? []).cast<String>();
  final timeLimit = cfg['timeLimit'] as int? ?? 0;
  final passScore = cfg['passScore'] as int? ?? 0;

  if (words.isEmpty) {
    return _renderEmpty('quiz', '暂无题目（运行时加载词库）');
  }

  final first = words.first;
  final qWord = first is Map ? (first['word'] ?? first['term'] ?? '') : first.toString();
  final qMeaning = first is Map ? (first['meaning'] ?? first['def'] ?? '') : '';
  // 取其它词的释义作为干扰项
  final distractors = words.skip(1).take(3).map((w) {
    final m = w is Map ? (w['meaning'] ?? w['def'] ?? '') : '';
    return m.toString();
  }).where((s) => s.isNotEmpty).toList();
  final options = [qMeaning.toString(), ...distractors];
  options.shuffle();

  final optsHtml = options.asMap().entries.map((e) {
    final letter = String.fromCharCode(65 + e.key);
    return '<label><input type="radio" name="q1" /> $letter. ${_esc(e.value)}</label>';
  }).join('');

  return '''
<div class="evg-comp evg-comp-quiz">
  <div class="evg-comp-title">❓ 测验（${types.join('/')} · 限时 ${timeLimit}s · 及格 $passScore 分）</div>
  <div class="evg-quiz-question">
    <div class="evg-quiz-q">1. 「${_esc(qWord.toString())}」的正确释义是？</div>
    <div class="evg-quiz-options">$optsHtml</div>
  </div>
  <button class="evg-quiz-submit">提交答案</button>
</div>''';
}

String _renderMindmap(Map<String, dynamic> comp) {
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

// ============================================================
// P2: 完整实现 — 16 个组件（原占位 → 有意义 HTML）
// ============================================================

/// stat-tile — 统计卡片（数值 + 标签 + 趋势）
String _renderStatTile(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final title = cfg['title'] as String? ?? '统计';
  final value = cfg['value'] as String? ?? '—';
  final subtitle = cfg['subtitle'] as String? ?? '';
  final trend = cfg['trend'] as String?;
  final trendUp = cfg['trendUp'] as bool?;
  final icon = cfg['icon'] as String? ?? '';

  final trendHtml = trend != null
      ? '<span class="evg-stat-trend${trendUp == true ? ' up' : ' down'}">${trendUp == true ? '▲' : '▼'} $trend</span>'
      : '';

  return '''
<div class="evg-comp evg-comp-stat-tile">
  <div class="evg-stat-header">
    ${icon.isNotEmpty ? '<span class="evg-stat-icon">$icon</span>' : ''}
    <span class="evg-stat-title">${_esc(title)}</span>
  </div>
  <div class="evg-stat-value">${_esc(value)}</div>
  $trendHtml
  ${subtitle.isNotEmpty ? '<div class="evg-stat-subtitle">${_esc(subtitle)}</div>' : ''}
</div>''';
}

/// timeline — 时间线（事件列表）
String _renderTimeline(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final items = (cfg['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  final title = cfg['title'] as String? ?? '时间线';

  if (items.isEmpty) {
    return _renderPlaceholder('timeline', cfg);
  }

  final itemsHtml = items.asMap().entries.map((e) {
    final item = e.value;
    final time = item['time'] as String? ?? '';
    final label = item['label'] as String? ?? '';
    final desc = item['description'] as String? ?? '';
    final isLast = e.key == items.length - 1;
    return '''
<div class="evg-tl-item">
  <div class="evg-tl-marker"></div>
  ${isLast ? '' : '<div class="evg-tl-line"></div>'}
  <div class="evg-tl-content">
    <div class="evg-tl-time">${_esc(time)}</div>
    <div class="evg-tl-label">${_esc(label)}</div>
    ${desc.isNotEmpty ? '<div class="evg-tl-desc">${_esc(desc)}</div>' : ''}
  </div>
</div>''';
  }).join('');

  return '''
<div class="evg-comp evg-comp-timeline">
  <div class="evg-comp-title">📅 ${_esc(title)}</div>
  <div class="evg-tl-container">$itemsHtml</div>
</div>''';
}

/// card-list — 卡片列表
String _renderCardList(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final cards = (cfg['cards'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  final title = cfg['title'] as String? ?? '卡片列表';

  if (cards.isEmpty) {
    // 回退到 data-table 的卡片模式
    return _renderDataCards(title, cfg['columns'] as List<dynamic>? ?? []);
  }

  final cardsHtml = cards.map((card) {
    final image = card['image'] as String?;
    final header = card['title'] as String? ?? '';
    final body = card['body'] as String? ?? '';
    final footer = card['footer'] as String? ?? '';
    return '''
<div class="evg-cl-card">
  ${image != null ? '<div class="evg-cl-image" style="background-image:url(${_esc(image)})"></div>' : ''}
  <div class="evg-cl-body">
    <div class="evg-cl-title">${_esc(header)}</div>
    <div class="evg-cl-text">${_esc(body)}</div>
  </div>
  ${footer.isNotEmpty ? '<div class="evg-cl-footer">${_esc(footer)}</div>' : ''}
</div>''';
  }).join('');

  return '''
<div class="evg-comp evg-comp-card-list">
  ${title.isNotEmpty ? '<div class="evg-comp-title">🃏 ${_esc(title)}</div>' : ''}
  <div class="evg-cl-grid">$cardsHtml</div>
</div>''';
}

/// kanban — 看板（列式状态管理）
String _renderKanban(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final columns = (cfg['columns'] as List<dynamic>? ?? [
    {'title': '待办', 'items': ['任务 A', '任务 B']},
    {'title': '进行中', 'items': ['任务 C']},
    {'title': '已完成', 'items': ['任务 D', '任务 E']},
  ]).cast<Map<String, dynamic>>();

  final colsHtml = columns.map((col) {
    final colTitle = col['title'] as String? ?? '';
    final items = (col['items'] as List<dynamic>? ?? []).map((it) {
      final text = it is Map ? (it['text'] ?? it['label'] ?? '') : it.toString();
      final tag = it is Map ? it['tag'] as String? : null;
      return '''
<div class="evg-kb-card">
  <span>${_esc(text)}</span>
  ${tag != null ? '<span class="evg-kb-tag">${_esc(tag)}</span>' : ''}
</div>''';
    }).join('');

    return '''
<div class="evg-kb-column">
  <div class="evg-kb-col-header">
    <span>${_esc(colTitle)}</span>
    <span class="evg-kb-count">${items.length}</span>
  </div>
  <div class="evg-kb-col-body">$items</div>
</div>''';
  }).join('');

  return '''
<div class="evg-comp evg-comp-kanban">
  <div class="evg-kb-board">$colsHtml</div>
</div>''';
}

/// tree — 树形视图
String _renderTree(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final root = cfg['root'] as Map<String, dynamic>? ?? {
    'label': '根节点',
    'children': [
      {'label': '子节点 A', 'children': [{'label': '叶子 A1'}, {'label': '叶子 A2'}]},
      {'label': '子节点 B'},
      {'label': '子节点 C', 'children': [{'label': '叶子 C1'}]},
    ],
  };

  String _renderNode(Map<String, dynamic> node, int depth) {
    final label = node['label'] as String? ?? '';
    final children = (node['children'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final hasChildren = children.isNotEmpty;
    final indent = depth * 20;
    final icon = node['icon'] as String? ?? (hasChildren ? '📁' : '📄');

    final childrenHtml = children.map((c) => _renderNode(c, depth + 1)).join('');

    return '''
<div class="evg-tree-node" style="padding-left:${indent}px">
  <div class="evg-tree-row">
    <span class="evg-tree-toggle">${hasChildren ? '▶' : '  '}</span>
    <span class="evg-tree-icon">$icon</span>
    <span class="evg-tree-label">${_esc(label)}</span>
  </div>
  $childrenHtml
</div>''';
  }

  return '''
<div class="evg-comp evg-comp-tree">
  <div class="evg-comp-title">🌳 树形视图</div>
  <div class="evg-tree-container">${_renderNode(root, 0)}</div>
</div>''';
}

/// audio-player — 音频播放器
String _renderAudioPlayer(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final src = cfg['src'] as String? ?? '';
  final title = cfg['title'] as String? ?? '音频播放器';

  final audioEl = src.isNotEmpty
      ? '<audio controls style="width:100%"><source src="${_esc(src)}" /></audio>'
      : '<div class="evg-audio-placeholder">🎵 音频文件未指定<br><span style="font-size:11px;color:var(--evg-text-tertiary)">在 config.src 中设置音频 URL</span></div>';

  return '''
<div class="evg-comp evg-comp-audio">
  <div class="evg-comp-title">🎵 ${_esc(title)}</div>
  <div class="evg-audio-body">$audioEl</div>
</div>''';
}

/// image-gallery — 图片画廊
String _renderImageGallery(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final images = (cfg['images'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  final title = cfg['title'] as String? ?? '图片画廊';

  if (images.isEmpty) {
    return _renderPlaceholder('image-gallery', cfg);
  }

  final thumbsHtml = images.map((img) {
    final url = img['url'] as String? ?? img['src'] as String? ?? '';
    final caption = img['caption'] as String? ?? '';
    return '''
<div class="evg-gal-item">
  <div class="evg-gal-thumb" style="background-image:url(${_esc(url)})">
    <div class="evg-gal-overlay">🔍</div>
  </div>
  ${caption.isNotEmpty ? '<div class="evg-gal-caption">${_esc(caption)}</div>' : ''}
</div>''';
  }).join('');

  return '''
<div class="evg-comp evg-comp-gallery">
  <div class="evg-comp-title">🖼️ ${_esc(title)}</div>
  <div class="evg-gal-grid">$thumbsHtml</div>
</div>''';
}

/// notepad — 记事本（纯文本编辑器）
String _renderNotepad(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final content = cfg['content'] as String? ?? '';
  final placeholder = cfg['placeholder'] as String? ?? '在这里写点什么...';

  return '''
<div class="evg-comp evg-comp-notepad">
  <div class="evg-np-toolbar">
    <span>📝 记事本</span>
    <span class="evg-np-status">已保存</span>
  </div>
  <textarea class="evg-np-editor" placeholder="${_esc(placeholder)}">${_esc(content)}</textarea>
</div>''';
}

/// whiteboard — 白板（绘图画布）
String _renderWhiteboard(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};

  return '''
<div class="evg-comp evg-comp-whiteboard">
  <div class="evg-wb-toolbar">
    <button class="evg-wb-tool" title="画笔">✏️</button>
    <button class="evg-wb-tool" title="橡皮">🧹</button>
    <button class="evg-wb-tool" title="形状">⬜</button>
    <button class="evg-wb-tool" title="文字">🔤</button>
    <span style="flex:1"></span>
    <button class="evg-wb-tool" title="撤销">↩️</button>
    <button class="evg-wb-tool" title="重做">↪️</button>
    <button class="evg-wb-tool" title="清空">🗑️</button>
  </div>
  <div class="evg-wb-canvas">
    <div class="evg-wb-placeholder">
      <span style="font-size:48px;opacity:.3">🎨</span>
      <span style="font-size:14px;color:var(--evg-text-secondary)">白板画布 — 在此区域绘图</span>
    </div>
  </div>
</div>''';
}

/// diff-viewer — 差异对比器
String _renderDiffViewer(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final leftLabel = cfg['leftLabel'] as String? ?? '原文件';
  final rightLabel = cfg['rightLabel'] as String? ?? '新文件';

  // 示例 diff 行
  const diffLines = [
    {'type': 'same', 'text': 'import json'},
    {'type': 'same', 'text': 'from pathlib import Path'},
    {'type': 'same', 'text': ''},
    {'type': 'del', 'text': '- def old_function():'},
    {'type': 'add', 'text': '+ def new_function(data: dict) -> dict:'},
    {'type': 'add', 'text': '+     """处理数据并返回结果"""'},
    {'type': 'same', 'text': '      result = {}'},
    {'type': 'del', 'text': '-     result["count"] = 0'},
    {'type': 'add', 'text': '+     result["count"] = len(data)'},
    {'type': 'same', 'text': '      return result'},
  ];

  final linesHtml = diffLines.map((l) {
    final cls = switch (l['type']) {
      'add' => 'evg-diff-add',
      'del' => 'evg-diff-del',
      _ => 'evg-diff-same',
    };
    return '<div class="evg-diff-line $cls"><code>${_esc(l['text']!)}</code></div>';
  }).join('');

  return '''
<div class="evg-comp evg-comp-diff">
  <div class="evg-diff-header">
    <span class="evg-diff-label left">📄 ${_esc(leftLabel)}</span>
    <span class="evg-diff-label right">📄 ${_esc(rightLabel)}</span>
  </div>
  <div class="evg-diff-body">$linesHtml</div>
</div>''';
}

/// terminal — 终端模拟器
String _renderTerminal(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final cwd = cfg['cwd'] as String? ?? '~/projects';
  const lines = [
    {'prompt': '❯', 'text': 'git status', 'color': '#58a6ff'},
    {'prompt': '', 'text': 'On branch main', 'color': '#c9d1d9'},
    {'prompt': '', 'text': 'nothing to commit, working tree clean', 'color': '#3fb950'},
    {'prompt': '❯', 'text': 'ls -la', 'color': '#58a6ff'},
    {'prompt': '', 'text': 'total 24', 'color': '#c9d1d9'},
    {'prompt': '', 'text': 'drwxr-xr-x  5 user  staff   160 Jul  6 14:00 .', 'color': '#8b949e'},
    {'prompt': '', 'text': 'drwxr-xr-x  3 user  staff    96 Jul  6 13:00 ..', 'color': '#8b949e'},
    {'prompt': '', 'text': '-rw-r--r--  1 user  staff  1024 Jul  6 14:00 README.md', 'color': '#8b949e'},
    {'prompt': '❯', 'text': '<span class="evg-term-cursor">█</span>', 'color': '#58a6ff'},
  ];

  final linesHtml = lines.map((l) {
    final prompt = l['prompt'] as String;
    final text = l['text'] as String;
    final color = l['color'] as String;
    return '<div class="evg-term-line">${prompt.isNotEmpty ? '<span class="evg-term-prompt">$prompt</span>' : ''}<span style="color:$color">$text</span></div>';
  }).join('');

  return '''
<div class="evg-comp evg-comp-terminal">
  <div class="evg-term-header">
    <span class="evg-term-dot" style="background:#ff5f56"></span>
    <span class="evg-term-dot" style="background:#ffbd2e"></span>
    <span class="evg-term-dot" style="background:#27c93f"></span>
    <span class="evg-term-title">${_esc(cwd)} — bash</span>
  </div>
  <div class="evg-term-body">$linesHtml</div>
</div>''';
}

/// crossword — 填字游戏
String _renderCrossword(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final title = cfg['title'] as String? ?? '填字游戏';

  // 简单 5x5 网格
  final gridHtml = List.generate(5, (row) {
    final cells = List.generate(5, (col) {
      final letter = _crosswordGrid[row][col];
      return '<div class="evg-cw-cell${letter != null ? ' filled' : ''}">${letter ?? ''}</div>';
    }).join('');
    return '<div class="evg-cw-row">$cells</div>';
  }).join('');

  return '''
<div class="evg-comp evg-comp-crossword">
  <div class="evg-comp-title">🔤 ${_esc(title)}</div>
  <div class="evg-cw-grid">$gridHtml</div>
  <div class="evg-cw-clues">
    <div class="evg-cw-clue-title">横向:</div>
    <div class="evg-cw-clue">1. Python关键字 — def</div>
    <div class="evg-cw-clue">2. 列表声明 — list</div>
    <div class="evg-cw-clue-title" style="margin-top:8px">纵向:</div>
    <div class="evg-cw-clue">1. 数据类型 — dict</div>
    <div class="evg-cw-clue">2. 循环 — for</div>
  </div>
</div>''';
}

/// 5x5 填字游戏模板
const _crosswordGrid = [
  ['D', 'E', 'F', null, null],
  ['I', null, 'O', null, null],
  ['C', null, 'R', null, null],
  ['T', null, null, null, null],
  [null, null, null, null, null],
];

/// pronunciation — 发音练习
String _renderPronunciation(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final word = cfg['word'] as String? ?? 'hello';
  final phonetic = cfg['phonetic'] as String? ?? '/həˈloʊ/';

  return '''
<div class="evg-comp evg-comp-pronunciation">
  <div class="evg-comp-title">🔊 发音练习</div>
  <div class="evg-pron-word">${_esc(word)}</div>
  <div class="evg-pron-phonetic">${_esc(phonetic)}</div>
  <div class="evg-pron-controls">
    <button class="evg-pron-btn">▶ 播放</button>
    <button class="evg-pron-btn">🎤 录音</button>
    <button class="evg-pron-btn">🔄 对比</button>
  </div>
  <div class="evg-pron-score">
    <span style="color:var(--evg-text-secondary)">发音评分:</span>
    <span style="color:var(--evg-state-success);font-size:18px;font-weight:700">85</span>
    <span style="color:var(--evg-text-secondary)">/100</span>
  </div>
</div>''';
}

/// prompt-builder — Prompt 构建器
String _renderPromptBuilder(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final template = cfg['template'] as String? ?? '你是一个{role}，请帮我{task}。要求：{requirements}';
  final variables = (cfg['variables'] as Map<String, dynamic>? ?? {
    'role': 'Python 专家',
    'task': '优化这段代码的性能',
    'requirements': '保持代码可读性，添加注释',
  });

  final varInputsHtml = variables.entries.map((e) => '''
<div class="evg-pb-field">
  <label>${_esc(e.key)}</label>
  <input type="text" value="${_esc(e.value.toString())}" placeholder="${_esc(e.key)}" />
</div>''').join('');

  return '''
<div class="evg-comp evg-comp-prompt-builder">
  <div class="evg-comp-title">🔧 Prompt 构建器</div>
  <div class="evg-pb-template">
    <div class="evg-pb-label">模板:</div>
    <pre class="evg-pb-pre">${_esc(template)}</pre>
  </div>
  <div class="evg-pb-vars">
    <div class="evg-pb-label">变量:</div>
    $varInputsHtml
  </div>
  <button class="evg-pb-generate">✨ 生成 Prompt</button>
</div>''';
}

/// custom — 自定义组件（iframe 嵌入或自定义 HTML）
String _renderCustom(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final html = cfg['html'] as String?;
  final src = cfg['src'] as String?;

  if (html != null) {
    return '''
<div class="evg-comp evg-comp-custom">
  $html
</div>''';
  }

  if (src != null) {
    return '''
<div class="evg-comp evg-comp-custom">
  <iframe src="${_esc(src)}" class="evg-custom-iframe" sandbox="allow-scripts allow-same-origin"></iframe>
</div>''';
  }

  return _renderPlaceholder('custom', cfg);
}

/// webview — WebView 嵌入
String _renderWebView(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final url = cfg['url'] as String? ?? 'about:blank';
  final allowScripts = cfg['allowScripts'] as bool? ?? true;

  return '''
<div class="evg-comp evg-comp-webview">
  <div class="evg-wv-toolbar">
    <button class="evg-wv-btn" title="后退">◀</button>
    <button class="evg-wv-btn" title="前进">▶</button>
    <button class="evg-wv-btn" title="刷新">🔄</button>
    <span class="evg-wv-url">${_esc(url)}</span>
  </div>
  <div class="evg-wv-content">
    <iframe src="${_esc(url)}" class="evg-wv-iframe" ${allowScripts ? 'sandbox="allow-scripts allow-same-origin"' : 'sandbox=""'}></iframe>
  </div>
</div>''';
}

/// 已实现的组件在无数据时的干净空态（区别于"待实现"占位）。
String _renderEmpty(String type, String hint) {
  return '''
<div class="evg-comp evg-comp-empty">
  <div class="evg-empty-icon">📭</div>
  <div class="evg-empty-hint">$hint</div>
</div>''';
}

/// 通用占位（保留给 placeholder-01~20 等未命名组件）
String _renderPlaceholder(String type, Map<String, dynamic> config) {
  final icon = componentIcon(type);
  final cfgStr = config.isNotEmpty
      ? '<pre style="font-size:10px;color:var(--evg-text-secondary);overflow:auto;max-height:60px">${_esc(const JsonEncoder.withIndent('  ').convert(config))}</pre>'
      : '';

  return '''
<div class="evg-comp evg-comp-placeholder">
  <div class="evg-ph-icon">$icon</div>
  <div class="evg-ph-type">$type</div>
  <div class="evg-ph-hint">组件 "$type" 待实现</div>
  $cfgStr
</div>''';
}

String _renderGeneric(Map<String, dynamic> comp) {
  return _renderPlaceholder(comp['type'] as String? ?? 'unknown', comp['config'] as Map<String, dynamic>? ?? {});
}

/// button — 工具栏按钮组（读取 config.buttons 真实声明）。
String _renderButton(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final align = cfg['align'] as String? ?? 'left';
  final buttons = (cfg['buttons'] as List<dynamic>? ?? [])
      .map((b) {
        final m = b as Map<String, dynamic>? ?? {};
        final label = m['label'] as String? ?? '';
        final icon = m['icon'] as String? ?? '';
        final style = m['style'] as String? ?? 'filled';
        final event = m['event'] as String? ?? '';
        return '<button class="evg-btn evg-btn-$style" data-event="${_esc(event)}">'
            '${icon != null && icon!.isNotEmpty ? '$icon ' : ''}${_esc(label)}</button>';
      })
      .join('');
  return '''
<div class="evg-comp evg-comp-button">
  <div class="evg-btn-bar" style="justify-content:${align == 'right' ? 'flex-end' : align == 'center' ? 'center' : 'flex-start'}">$buttons</div>
</div>''';
}

/// nav-button — 导航卡片（读取 label/icon/target 真实声明）。
String _renderNavButton(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final label = cfg['label'] as String? ?? '导航';
  final icon = cfg['icon'] as String? ?? '📌';
  final target = cfg['target'] as String? ?? '#';
  return '''
<div class="evg-comp evg-comp-navbtn">
  <a class="evg-navbtn" href="${_esc(target)}">
    <span class="evg-navbtn-icon">$icon</span>
    <span class="evg-navbtn-label">${_esc(label)}</span>
  </a>
</div>''';
}

/// timetable — 周课表（读取 config.sessions 真实课次）。
/// session: {courseName, teacher, location, dayOfWeek(1-7), periods:[int], courseId}
String _renderTimetable(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final sessions = (cfg['sessions'] as List<dynamic>? ?? [])
      .whereType<Map<dynamic, dynamic>>()
      .toList();
  if (sessions.isEmpty) {
    return _renderEmpty('timetable', '暂无课表数据（官方空态）');
  }
  // 计算最大节次，构建 7 列网格
  var maxPeriod = 1;
  for (final s in sessions) {
    final ps = (s['periods'] as List<dynamic>? ?? []);
    for (final p in ps) {
      final n = p is int ? p : int.tryParse(p.toString()) ?? 0;
      if (n > maxPeriod) maxPeriod = n;
    }
  }
  final dayHeaders = ['一', '二', '三', '四', '五', '六', '日'];
  final grid = <String>[];
  for (var p = 1; p <= maxPeriod; p++) {
    final row = <String>[];
    for (var d = 1; d <= 7; d++) {
      final cellSessions = sessions.where((s) {
        final dow = s['dayOfWeek'] is int
            ? s['dayOfWeek'] as int
            : int.tryParse(s['dayOfWeek'].toString()) ?? 0;
        final ps = (s['periods'] as List<dynamic>? ?? [])
            .map((x) => x is int ? x : int.tryParse(x.toString()) ?? 0)
            .toList();
        return dow == d && ps.contains(p);
      }).toList();
      if (cellSessions.isEmpty) {
        row.add('<td class="evg-tt-cell"></td>');
      } else {
        final inner = cellSessions.map((s) {
          final name = _esc((s['courseName'] ?? s['name'] ?? '?').toString());
          final teacher = _esc((s['teacher'] ?? '').toString());
          final loc = _esc((s['location'] ?? '').toString());
          return '<div class="evg-tt-session"><div class="evg-tt-name">$name</div>'
              '${teacher.isNotEmpty ? '<div class="evg-tt-teacher">$teacher</div>' : ''}'
              '${loc.isNotEmpty ? '<div class="evg-tt-loc">$loc</div>' : ''}</div>';
        }).join('');
        row.add('<td class="evg-tt-cell evg-tt-filled">$inner</td>');
      }
    }
    grid.add('<tr><th class="evg-tt-period">第$p节</th>${row.join('')}</tr>');
  }

  return '''
<div class="evg-comp evg-comp-timetable">
  <div class="evg-comp-title">📅 周课表（${sessions.length} 节课次）</div>
  <table class="evg-tt-table">
    <thead><tr><th></th>${dayHeaders.map((d) => '<th>周$d</th>').join('')}</tr></thead>
    <tbody>${grid.join('')}</tbody>
  </table>
</div>''';
}

/// settings — 设置面板（读取 config.settings 真实条目；由 harness 注入插件 config.json）。
String _renderSettings(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final settings = (cfg['settings'] as List<dynamic>? ?? [])
      .whereType<Map<dynamic, dynamic>>()
      .toList();
  if (settings.isEmpty) {
    return _renderEmpty('settings', '暂无设置项');
  }
  final rows = settings.map((s) {
    final label = _esc((s['label'] ?? s['key'] ?? '').toString());
    final type = _esc((s['type'] ?? 'string').toString());
    final hint = s['hint'] != null ? '<div class="evg-set-hint">${_esc(s['hint'].toString())}</div>' : '';
    final value = s['value'] ?? s['default'] ?? '';
    final ctrl = switch (type) {
      'bool' => '<input type="checkbox" ${value == true || value == 'true' ? 'checked' : ''} />',
      'option' => '<select>${((s['options'] as List<dynamic>? ?? []).map((o) {
        final ov = o is Map ? o['value'] : o;
        final ol = o is Map ? o['label'] : o;
        return '<option ${ov == value ? 'selected' : ''}>${_esc(ol.toString())}</option>';
      }).join(''))}</select>',
      _ => '<input type="text" value="${_esc(value.toString())}" />',
    };
    return '''
<div class="evg-set-row">
  <div class="evg-set-label">$label $hint</div>
  <div class="evg-set-ctrl">$ctrl</div>
</div>''';
  }).join('');
  return '''
<div class="evg-comp evg-comp-settings">
  <div class="evg-comp-title">⚙️ 设置</div>
  <div class="evg-set-list">$rows</div>
</div>''';
}

// ============================================================
// 渲染函数注册表
// ============================================================

typedef _Renderer = String Function(Map<String, dynamic> comp);

final Map<String, _Renderer> _renderers = {
  // ── P0: V2 核心 ──
  'chat': _renderChat,
  'code-editor': _renderCodeEditor,
  'data-table': _renderDataTable,
  'chart': _renderChart,
  'lottery-wheel': _renderLotteryWheel,
  'document': _renderDocument,
  'spreadsheet': _renderSpreadsheet,
  'video': _renderVideo,
  'presentation': _renderPresentation,
  'type-check': _renderTypeCheck,
  'form': _renderForm,
  'calendar': _renderCalendar,
  'map': _renderMap,
  'button': _renderButton,
  'nav-button': _renderNavButton,
  'timetable': _renderTimetable,
  'settings': _renderSettings,

  // ── P1: 别名 & PLAN_NOW 类型 ──
  'ai-assistant': _renderChat,        // 别名 → chat
  'doc-viewer': _renderDocument,       // 别名 → document
  'doc-editor': _renderDocument,       // 别名 → document
  'video-player': _renderVideo,        // 别名 → video
  'markdown': _renderMarkdown,
  'divider': _renderDivider,
  'flashcards': _renderFlashcards,
  'quiz': _renderQuiz,
  'mindmap': _renderMindmap,
  // ── P2: 完整实现 ──
  'stat-tile': _renderStatTile,
  'timeline': _renderTimeline,
  'card-list': _renderCardList,
  'kanban': _renderKanban,
  'tree': _renderTree,
  'audio-player': _renderAudioPlayer,
  'image-gallery': _renderImageGallery,
  'notepad': _renderNotepad,
  'whiteboard': _renderWhiteboard,
  'diff-viewer': _renderDiffViewer,
  'terminal': _renderTerminal,
  'crossword': _renderCrossword,
  'pronunciation': _renderPronunciation,
  'prompt-builder': _renderPromptBuilder,
  'custom': _renderCustom,
  'webview': _renderWebView,
};

/// 组件类型 → 图标映射
const _componentIcons = <String, String>{
  'chat': '💬', 'ai-assistant': '🤖',
  'code-editor': '💻',
  'data-table': '📊', 'card-list': '🃏', 'kanban': '📋',
  'chart': '📈', 'stat-tile': '📉', 'timeline': '📅',
  'lottery-wheel': '🎰',
  'document': '📝', 'doc-viewer': '📄', 'doc-editor': '✏️',
  'spreadsheet': '📊',
  'video': '🎬', 'video-player': '▶️', 'audio-player': '🎵', 'image-gallery': '🖼️',
  'presentation': '📽️',
  'type-check': '✅',
  'form': '📋',
  'calendar': '📅',
  'map': '🗺️',
  'markdown': '📄',
  'divider': '➖',
  'flashcards': '🃏',
  'quiz': '❓',
  'mindmap': '🧠',
  'tree': '🌳',
  'notepad': '📝',
  'whiteboard': '🎨',
  'diff-viewer': '🔍',
  'terminal': '⬛',
  'crossword': '🔤',
  'pronunciation': '🔊',
  'prompt-builder': '🔧',
  'custom': '🔌',
  'webview': '🌐',
};

// ============================================================
// 辅助
// ============================================================

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _sampleCell(String key, int i) {
  return switch (key) {
    'id' || 'line' => '${1000 + i}',
    'name' || 'item' || 'title' => '项目 $i',
    'status' || 'type' || 'category' || 'rarity' => ['运行中', '已停止', '警告'][(i - 1) % 3],
    'value' || 'score' || 'count' || 'calls_today' => '${(i * 37) % 100}',
    'trend' || 'success_rate' => '${85 + i}%',
    'avg_latency_ms' => '${12 + i}',
    'message' || 'fact' || 'bio' => '这是示例数据行 $i 的内容',
    _ => '—',
  };
}

String _langExt(String lang) => switch (lang) {
  'javascript' => 'js',
  'typescript' => 'ts',
  'dart' => 'dart',
  'html' => 'html',
  'css' => 'css',
  'json' => 'json',
  'yaml' => 'yml',
  'powershell' => 'ps1',
  'bash' || 'shell' => 'sh',
  _ => 'py',
};

const _codeSamples = <String, List<String>>{
  'python': [
    '<span class="evg-kw">import</span> json',
    '<span class="evg-kw">from</span> pathlib <span class="evg-kw">import</span> Path',
    '',
    '<span class="evg-kw">def</span> <span class="evg-fn">analyze_data</span>(filepath: <span class="evg-kw">str</span>) -> <span class="evg-kw">dict</span>:',
    '    <span class="evg-cmt"># 读取并分析 JSON 数据文件</span>',
    '    data = json.loads(Path(filepath).read_text())',
    '    result = {',
    '        <span class="evg-str">"total"</span>: <span class="evg-num">len</span>(data),',
    '        <span class="evg-str">"keys"</span>: <span class="evg-num">list</span>(data[<span class="evg-num">0</span>].keys()) <span class="evg-kw">if</span> data <span class="evg-kw">else</span> [],',
    '    }',
    '    <span class="evg-kw">return</span> result',
  ],
  'javascript': [
    '<span class="evg-kw">const</span> <span class="evg-fn">fetchData</span> = <span class="evg-kw">async</span> (url) => {',
    '  <span class="evg-kw">const</span> res = <span class="evg-kw">await</span> fetch(url);',
    '  <span class="evg-kw">return</span> res.json();',
    '};',
  ],
  'dart': [
    '<span class="evg-kw">import</span> <span class="evg-str">\'dart:convert\'</span>;',
    '',
    '<span class="evg-kw">void</span> <span class="evg-fn">main</span>() {',
    '  <span class="evg-kw">final</span> data = {<span class="evg-str">\'name\'</span>: <span class="evg-str">\'Evergreen\'</span>};',
    '  <span class="evg-num">print</span>(jsonEncode(data));',
    '}',
  ],
};
