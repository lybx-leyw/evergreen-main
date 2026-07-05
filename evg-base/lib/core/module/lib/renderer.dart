/// 最简 ASCII 渲染器——将 manifest 声明可视化为终端 mock-up。
///
/// 下游工程师按图索骥：每个 ASCII 元素对应一个 manifest 字段。
library;

import 'dart:math' show max, min;
import '../modules.dart';

const _w = 64;

// ═══════ 侧边栏 ═══════

/// 渲染侧边栏导航。
String renderSidebar(ModuleRegistry registry) {
  final buf = StringBuffer();
  for (final (section, entries) in registry.navGroups) {
    buf.writeln('  ${section.label}');
    for (final e in entries) {
      buf.writeln('  ${e.label.padRight(18)} ${e.routePath}');
    }
  }
  return buf.toString();
}

// ═══════ 模块渲染 ═══════

/// 根据 manifest 渲染模块页面 mock-up。
String renderModule(ModuleDescriptor m) {
  if (m.isServiceOnly) return _renderServiceOnly(m);
  return switch (m.ui) {
    'chat'         => _renderChat(m),
    'spreadsheet'  => _renderSpreadsheet(m),
    'document'     => _renderDocument(m),
    'presentation' => _renderPresentation(m),
    _              => _renderDefault(m),
  };
}

// ═══════ 工具 ═══════

String _bar(String label) =>
    '─ $label ${'─' * max(1, _w - label.length - 4)}';

String _pad(int n, int total) => ' ' * max(0, total - n);

// ═══════ 纯服务模块 ═══════

String _renderServiceOnly(ModuleDescriptor m) {
  final buf = StringBuffer();
  buf.writeln('╔${'═' * _w}╗');
  buf.writeln('║  ⚙ ${m.name} (纯服务模块，无 UI)${_pad(m.name.length + 16, _w)}║');
  if (m.process != null) {
    buf.writeln('║  ${_bar('exe')}║');
    final exe = '${m.process!.exe}  (${m.process!.protocol})';
    buf.writeln('║    $exe${_pad(exe.length + 4, _w)}║');
  }
  if (m.dependencies.isNotEmpty) {
    buf.writeln('║  ${_bar('依赖')}║');
    final deps = m.dependencies.join(', ');
    buf.writeln('║    $deps${_pad(deps.length + 4, _w)}║');
  }
  buf.writeln('╚${'═' * _w}╝');
  return buf.toString();
}

// ═══════ Chat ═══════

String _renderChat(ModuleDescriptor m) {
  final buf = StringBuffer();
  final c = m.chat!;
  final input = m.input;
  final ws = m.workspace;

  // 标题栏
  buf.writeln('╔${'═' * _w}╗');
  final search = m.layout.search;
  final searchText =
      search != null && search.enabled ? '  [🔍 ${search.placeholder}]' : '';
  final title = '💬 ${m.name}$searchText';
  buf.writeln('║  $title${_pad(title.length, _w)}║');

  // 消息区
  buf.writeln('╟${'─' * _w}╢');
  if (c.stream.enabled) {
    final cursor = switch (c.stream.cursorStyle) {
      'blinking' => '▌',
      'static' => '|',
      _ => '',
    };
    buf.writeln('║  ${' ' * _w}║');
    buf.writeln('║  ┌ 消息气泡${'─' * (_w - 14)}┐║');
    final bubble = '🤖 ${c.placeholder}...$cursor';
    buf.writeln('║  │ $bubble${_pad(bubble.length + 2, _w - 1)}│║');
    buf.writeln('║  └${'─' * (_w - 4)}┘║');

    // thinking
    if (c.thinking.visible) {
      final modeLabel = c.thinking.mode == 'expand' ? '展开' : '滑动';
      final dur = c.thinking.showDuration ? ' (1.2s)' : '';
      buf.writeln(
          '║  ┌ 💭 思考中$modeLabel$dur${'─' * max(1, _w - modeLabel.length - dur.length - 13)}┐║');
      buf.writeln('║  │ 正在分析用户意图...${_pad(17, _w - 1)}│║');
      final sep = c.thinking.transparent ? '·' : '─';
      buf.writeln('║  └$sep${sep * (_w - 5)}┘║');
    }

    // tool calls
    if (c.toolCalls.visible) {
      buf.writeln('║  ┌ 🔧 工具调用${'─' * (_w - 17)}┐║');
      if (c.toolCalls.showArgs) {
        buf.writeln('║  │ query: "量子力学"${_pad(19, _w - 1)}│║');
      }
      if (c.toolCalls.showResult) {
        final collapse = c.toolCalls.autoCollapse ? ' (已折叠)' : '';
        buf.writeln('║  │ ✅ 找到 3 条$collapse${_pad(collapse.length + 15, _w - 1)}│║');
      }
      buf.writeln('║  └${'─' * (_w - 4)}┘║');
    }
  } else {
    buf.writeln('║  ${c.placeholder}${_pad(c.placeholder.length, _w)}║');
  }

  // 输入区
  buf.writeln('╟${'─' * _w}╢');
  if (input != null) {
    final parts = <String>['✏ ${c.placeholder}'];
    if (input.attachments.enabled) parts.add('📎');
    if (input.voice) parts.add('🎤');
    if (input.slashCommands) parts.add('/');
    parts.add('➤');
    final inputLine = parts.join('  ');
    if (input.multiline) {
      buf.writeln(
          '║  ┌ $inputLine${'─' * max(1, _w - inputLine.length - 2)}┐║');
      buf.writeln('║  └${'─' * (_w - 3)}┘║');
    } else {
      buf.writeln('║  │ $inputLine${_pad(inputLine.length, _w)}│║');
    }
  }

  // 工作区
  if (ws != null && ws.enabled) {
    buf.writeln('╟${'─' * _w}╢');
    final info = '📂 文件工作区 (${ws.maxFiles} 文件 / ${ws.maxSizeMb}MB)';
    buf.writeln('║  $info${_pad(info.length, _w)}║');
    buf.writeln('║     📄 literature_review.pdf${_pad(25, _w)}║');
    buf.writeln('║     📄 dataset.csv${_pad(16, _w)}║');
    if (ws.aiCreatable.isNotEmpty) {
      final ai = '🤖 AI 可生成: ${ws.aiCreatable.join(', ')}';
      buf.writeln('║  $ai${_pad(ai.length, _w)}║');
    }
  }

  // drawers
  for (final d in m.layout.drawers) {
    buf.writeln('╟${'─' * _w}╢');
    final icon =
        switch (d) { 'left' => '←', 'right' => '→', 'top' => '↑', _ => '↓' };
    final line = '$icon 抽屉: $d';
    buf.writeln('║  $line${_pad(line.length, _w)}║');
  }

  buf.writeln('╚${'═' * _w}╝');
  return buf.toString();
}

// ═══════ Default ═══════

String _renderDefault(ModuleDescriptor m) {
  final buf = StringBuffer();
  buf.writeln('╔${'═' * _w}╗');
  buf.writeln('║  📋 ${m.name}${_pad(m.name.length + 5, _w)}║');
  buf.writeln('╟${'─' * _w}╢');

  // search
  if (m.layout.search != null && m.layout.search!.enabled) {
    final s = m.layout.search!;
    buf.writeln('║  🔍 ${s.placeholder}${'─' * max(1, _w - s.placeholder.length - 5)}║');
  }

  // panels (tabs)
  if (m.layout.panels.isNotEmpty) {
    final tabs = m.layout.panels
        .map((p) => p.isDefault ? '[${p.label}]' : ' ${p.label} ')
        .join(' │ ');
    buf.writeln('║  $tabs${_pad(tabs.length, _w)}║');
    buf.writeln('╟${'─' * _w}╢');
  }

  // grid or single-column
  final grid = m.layout.grid;
  if (grid != null) {
    final cellW =
        max(10, (_w - 4 - (grid.columns - 1) * grid.gap) ~/ grid.columns);
    final top = List.filled(grid.columns, '┌${'─' * (cellW - 2)}┐').join('   ');
    buf.writeln('║  $top${_pad(top.length, _w)}║');
    final bindings = m.dataBindings;
    for (var i = 0; i < min(bindings.length, grid.columns * 2); i++) {
      if (i > 0 && i % grid.columns == 0) {
        final sep =
            List.filled(grid.columns, '├${'─' * (cellW - 2)}┤').join('   ');
        buf.writeln('║  $sep${_pad(sep.length, _w)}║');
      }
      final d = bindings[min(i, bindings.length - 1)];
      final icon = switch (d.display) {
        'table' => '📊',
        'chart' => '📈',
        'card' => '🃏',
        _ => '📄'
      };
      buf.write('║  │ $icon ${d.dataType}${_pad(d.dataType.length + 3, cellW - 1)}│');
      if ((i + 1) % grid.columns == 0) buf.writeln('  ║');
    }
    if (grid.columns > 1) {
      final bot =
          List.filled(grid.columns, '└${'─' * (cellW - 2)}┘').join('   ');
      buf.writeln('║  $bot${_pad(bot.length, _w)}║');
    }
  } else {
    for (final d in m.dataBindings) {
      final icon = switch (d.display) {
        'table' => '📊',
        'chart' => '📈',
        'card' => '🃏',
        _ => '📄'
      };
      final extra = d.filter ? ' (可筛选)' : '';
      buf.writeln(
          '║  $icon ${d.dataType} (${d.display}$extra)${_pad(d.dataType.length + d.display.length + extra.length + 6, _w)}║');
    }
  }

  // actions toolbar
  final a = m.actions;
  if (a != null) {
    buf.writeln('╟${'─' * _w}╢');
    final tools = <String>[];
    if (a.selection != 'none') {
      tools.add(a.selection == 'multi' ? '☑ 多选' : '○ 单选');
    }
    if (a.creatable) tools.add('➕ 新增');
    if (a.editable) tools.add('✏ 编辑');
    if (a.deletable != null && a.deletable!.enabled) {
      tools.add('🗑 删除${a.deletable!.confirm ? "(确认)" : ""}');
    }
    if (a.exportable.isNotEmpty) tools.add('📤 ${a.exportable.join("/")}');
    if (a.sortable.isNotEmpty) tools.add('↕ 排序: ${a.sortable.join(",")}');
    if (a.refresh != null && a.refresh!.enabled) {
      tools.add(a.refresh!.pullToRefresh
          ? '↻ 下拉刷新'
          : '↻ 自动${a.refresh!.autoInterval > 0 ? " ${a.refresh!.autoInterval}s" : ""}');
    }
    final toolLine = tools.join(' │ ');
    buf.writeln('║  $toolLine${_pad(toolLine.length, _w)}║');
  }

  // drawers
  for (final d in m.layout.drawers) {
    buf.writeln('╟${'─' * _w}╢');
    final icon =
        switch (d) { 'left' => '←', 'right' => '→', 'top' => '↑', _ => '↓' };
    final line = '$icon 抽屉: $d';
    buf.writeln('║  $line${_pad(line.length, _w)}║');
  }

  buf.writeln('╚${'═' * _w}╝');
  return buf.toString();
}

// ═══════ Spreadsheet ═══════

String _renderSpreadsheet(ModuleDescriptor m) {
  final buf = StringBuffer();
  final ss = m.spreadsheet!;
  buf.writeln('╔${'═' * _w}╗');
  buf.writeln('║  📊 ${m.name}${_pad(m.name.length + 5, _w)}║');
  buf.writeln('╟${'─' * _w}╢');
  final cols = min(ss.columns, 8);
  final header = List.generate(cols, (i) => ' ${_colName(i)} ').join('│');
  buf.writeln('║  │$header│${_pad(header.length + 4, _w)}║');
  final sep = List.generate(cols, (_) => '───').join('│');
  buf.writeln('║  │$sep│${_pad(sep.length + 4, _w)}║');
  for (var r = 1; r <= min(ss.rows, 5); r++) {
    final row = List.generate(cols, (_) => '   ').join('│');
    buf.writeln('║  │$row│${_pad(row.length + 4, _w)}║');
  }
  buf.writeln('╟${'─' * _w}╢');
  final caps = <String>['📋 ${ss.columns}×${ss.rows}'];
  if (ss.formulas) caps.add('fx 公式');
  if (ss.charts) caps.add('📈 图表');
  if (ss.sheets) caps.add('📑 多Sheet');
  if (ss.conditionalFormatting) caps.add('🎨 条件格式');
  final capLine = caps.join(' │ ');
  buf.writeln('║  $capLine${_pad(capLine.length, _w)}║');
  buf.writeln('╚${'═' * _w}╝');
  return buf.toString();
}

String _colName(int i) {
  if (i < 26) return String.fromCharCode(65 + i);
  return String.fromCharCode(64 + i ~/ 26) + String.fromCharCode(65 + i % 26);
}

// ═══════ Document ═══════

String _renderDocument(ModuleDescriptor m) {
  final buf = StringBuffer();
  final doc = m.document!;
  buf.writeln('╔${'═' * _w}╗');
  buf.writeln('║  📝 ${m.name}${_pad(m.name.length + 5, _w)}║');
  buf.writeln('╟${'─' * _w}╢');
  buf.writeln('║  ┌${'─' * (_w - 5)}─┐║');
  buf.writeln(
      '║  │ [B] [I] [U] │ 左 中 右 │ 🔤 │${'─' * max(1, _w - 34)}│║');
  buf.writeln('║  │${'─' * (_w - 3)}│║');
  buf.writeln(
      '║  │ Lorem ipsum dolor sit amet, consectetur${_pad(45, _w - 1)}│║');
  buf.writeln(
      '║  │ adipiscing elit. Sed do eiusmod tempor.${_pad(45, _w - 1)}│║');
  buf.writeln('║  │${'─' * (_w - 3)}│║');
  if (doc.trackChanges) {
    buf.writeln(
        '║  │ ─ 修订: 删除旧表述 → 新增表述${_pad(28, _w - 1)}│║');
  }
  if (doc.comments) {
    buf.writeln(
        '║  │ 💬 批注: [评审人] 需补充引用${_pad(27, _w - 1)}│║');
  }
  buf.writeln('║  └${'─' * (_w - 5)}─┘║');
  buf.writeln('╟${'─' * _w}╢');
  final caps = <String>[];
  if (doc.trackChanges) caps.add('📝 修订');
  if (doc.comments) caps.add('💬 批注');
  if (doc.tableOfContents) caps.add('📑 目录');
  if (doc.footnotes) caps.add('¹ 脚注');
  if (doc.headersFooters) caps.add('页眉页脚');
  caps.add('📤 ${doc.exportFormats.join("/")}');
  final capLine = caps.join(' │ ');
  buf.writeln('║  $capLine${_pad(capLine.length, _w)}║');
  buf.writeln('╚${'═' * _w}╝');
  return buf.toString();
}

// ═══════ Presentation ═══════

String _renderPresentation(ModuleDescriptor m) {
  final buf = StringBuffer();
  final ppt = m.presentation!;
  buf.writeln('╔${'═' * _w}╗');
  buf.writeln('║  🎬 ${m.name}${_pad(m.name.length + 5, _w)}║');
  buf.writeln('╟${'─' * _w}╢');
  buf.writeln(
      '║  ┌ 幻灯片 1 ┐ ┌ 幻灯片 2 ┐ ┌ 幻灯片 3 ┐${_pad(46, _w)}║');
  buf.writeln(
      '║  │          │ │  ┌───┐   │ │  ★       │${_pad(46, _w)}║');
  buf.writeln(
      '║  │  标题    │ │  │图片│   │ │  要点 1  │${_pad(46, _w)}║');
  buf.writeln(
      '║  │  正文    │ │  └───┘   │ │  要点 2  │${_pad(46, _w)}║');
  buf.writeln(
      '║  └──────────┘ └──────────┘ └──────────┘${_pad(46, _w)}║');
  buf.writeln('╟${'─' * _w}╢');
  final caps = <String>[];
  if (ppt.transitions) caps.add('🎬 切换动画');
  if (ppt.animations) caps.add('✨ 元素动画');
  if (ppt.speakerNotes) caps.add('📝 备注');
  if (ppt.presenterView) caps.add('🖥 双屏');
  if (ppt.slideMaster) caps.add('📐 母版');
  caps.add('📤 ${ppt.exportFormats.join("/")}');
  final capLine = caps.join(' │ ');
  buf.writeln('║  $capLine${_pad(capLine.length, _w)}║');
  buf.writeln('╚${'═' * _w}╝');
  return buf.toString();
}
