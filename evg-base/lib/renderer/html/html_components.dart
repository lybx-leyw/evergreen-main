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

String _renderChat(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final input = comp['input'] as Map<String, dynamic>? ?? {};
  final placeholder = cfg['placeholder'] as String? ?? '输入消息...';
  final thinking = cfg['thinking'] as Map<String, dynamic>? ?? {};
  final thinkingVisible = thinking['visible'] == true;
  final bubble = cfg['bubble'] as Map<String, dynamic>? ?? {};
  final showAvatar = bubble['showAvatar'] == true;
  final quickReplies = (input['quickReplies'] as List<dynamic>? ?? [])
      .map((q) => '<span class="evg-quick-reply">${_esc(q['label'] ?? '')}</span>')
      .join('');

  return '''
<div class="evg-comp evg-comp-chat">
  <div class="evg-chat-msgs">
    <div class="evg-msg assistant">
      ${showAvatar ? '<div class="evg-avatar">AI</div>' : ''}
      <div class="evg-bubble">你好！我是展示 AI 助手，有什么可以帮你的？</div>
    </div>
    <div class="evg-msg user">
      <div class="evg-avatar">U</div>
      <div class="evg-bubble">介绍一下这个平台的功能</div>
    </div>
    <div class="evg-msg assistant">
      ${showAvatar ? '<div class="evg-avatar">AI</div>' : ''}
      <div class="evg-bubble">
        Evergreen 是一个无账号、无服务端、本地优先的 AI 原生微工具集成平台。<br><br>
        支持 ChatGPT 式对话、代码编辑器、图表仪表盘、抽奖转盘、文档编辑器等 30+ 组件。
        ${thinkingVisible ? '<br><br><span style="color:var(--evg-text-secondary);font-size:11px"><i>思考中...</i></span>' : ''}
      </div>
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

  if (display == 'card') return _renderDataCards(title, columns);
  return _renderDataTableHTML(title, columns, filter, sortable);
}

String _renderDataTableHTML(
    String title, List<dynamic> columns, bool filter, bool sortable) {
  final headers = columns.map((c) {
    final label = _esc(c['label'] as String? ?? '');
    return '<th>$label${sortable ? ' <span class="evg-sort">⇅</span>' : ''}</th>';
  }).join('');
  final sampleRows = [1, 2, 3].map((i) {
    final cells = columns.map((c) => '<td>${_sampleCell(c['key'] as String? ?? '', i)}</td>').join('');
    return '<tr>$cells</tr>';
  }).join('');

  return '''
<div class="evg-comp evg-comp-table">
  ${title.isNotEmpty ? '<div class="evg-comp-title">$title</div>' : ''}
  ${filter ? '<div class="evg-table-filter"><input type="text" placeholder="搜索..." /></div>' : ''}
  <table class="evg-table">
    <thead><tr>$headers</tr></thead>
    <tbody>$sampleRows</tbody>
  </table>
</div>''';
}

String _renderDataCards(String title, List<dynamic> columns) {
  final cards = [1, 2, 3, 4].map((i) {
    final entries = columns.map((c) {
      final key = c['key'] as String? ?? '';
      final label = c['label'] as String? ?? key;
      return '<div class="evg-card-field"><span class="evg-card-label">$label</span><span class="evg-card-val">${_sampleCell(key, i)}</span></div>';
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

String _renderVideo(Map<String, dynamic> comp) {
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

String _renderFlashcards(Map<String, dynamic> comp) {
  return '''
<div class="evg-comp evg-comp-flash">
  <div class="evg-comp-title">🃏 闪卡</div>
  <div class="evg-flash-card">
    <div class="evg-flash-front">Python 中如何声明列表？</div>
    <div class="evg-flash-back"><code>my_list = [1, 2, 3]</code></div>
  </div>
  <div class="evg-flash-nav">
    <button>◀ 上一张</button><span>1 / 10</span><button>下一张 ▶</button>
    <button>翻转</button>
  </div>
</div>''';
}

String _renderQuiz(Map<String, dynamic> comp) {
  return '''
<div class="evg-comp evg-comp-quiz">
  <div class="evg-comp-title">❓ 测验</div>
  <div class="evg-quiz-question">
    <div class="evg-quiz-q">1. 哪个关键字用于定义 Python 函数?</div>
    <div class="evg-quiz-options">
      <label><input type="radio" name="q1" /> func</label>
      <label><input type="radio" name="q1" checked /> def</label>
      <label><input type="radio" name="q1" /> function</label>
      <label><input type="radio" name="q1" /> define</label>
    </div>
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
