/// 最简 ASCII 渲染器——将 manifest 声明可视化为终端 mock-up。
///
/// 下游工程师按图索骥：每个 ASCII 元素对应一个 manifest 字段。
///
/// V2: 渲染器适配树形架构（Module→Page→Layout→Slot→Component），
/// UI 范式从 pages[].componentTypes 推断，布局从 pages[].layout 获取。
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
///
/// V2: UI 范式从 pages[].componentTypes 推断，替代 V1 的 m.ui。
String renderModule(ModuleDescriptor m) {
  if (m.isServiceOnly) return _renderServiceOnly(m);
  final ui = _inferUi(m);
  return switch (ui) {
    'chat' => _renderChat(m),
    'spreadsheet' => _renderSpreadsheet(m),
    'document' => _renderDocument(m),
    'presentation' => _renderPresentation(m),
    _ => _renderDefault(m),
  };
}

// ═══════ UI 推断 ═══════

/// 从模块的所有页面组件类型推断 UI 范式。
String _inferUi(ModuleDescriptor m) {
  if (m.pages.isEmpty) return '';
  final types = m.pages.expand((p) => p.componentTypes).toSet();
  if (types.contains('chat')) return 'chat';
  if (types.contains('spreadsheet')) return 'spreadsheet';
  if (types.contains('document')) return 'document';
  if (types.contains('presentation')) return 'presentation';
  if (types.contains('dashboard')) return 'dashboard';
  if (types.contains('editor')) return 'editor';
  return types.first;
}

/// 获取模块第一个页面的布局（V2: 布局在页面级）。
LayoutDescriptor? _firstPageLayout(ModuleDescriptor m) {
  if (m.pages.isEmpty) return null;
  return m.pages.first.layout;
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
  if (m.process.isNotEmpty) {
    buf.writeln('║  ${_bar('exe')}║');
    for (final p in m.process) {
      final exe = '${p.exe}  (${p.protocol})';
      buf.writeln('║    $exe${_pad(exe.length + 4, _w)}║');
    }
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
  final layout = _firstPageLayout(m);

  // 标题栏
  buf.writeln('╔${'═' * _w}╗');
  final search = layout?.features.search;
  final searchText =
      search != null && search.enabled ? '  [🔍 ${search.placeholder}]' : '';
  final title = '💬 ${m.name}$searchText';
  buf.writeln('║  $title${_pad(title.length, _w)}║');

  // 消息区（V2: 从页面 slots 的 ComponentDescriptor 推断 Chat 特性）
  buf.writeln('╟${'─' * _w}╢');
  buf.writeln('║  ${' ' * _w}║');
  buf.writeln('║  ┌ 消息气泡${'─' * (_w - 14)}┐║');
  final bubble = '🤖 流式消息...▌';
  buf.writeln('║  │ $bubble${_pad(bubble.length + 2, _w - 1)}│║');
  buf.writeln('║  └${'─' * (_w - 4)}┘║');

  // thinking（从组件 config 推断，V2 不再有顶层 chat 字段）
  buf.writeln(
      '║  ┌ 💭 思考中展开 (1.2s)${'─' * max(1, _w - 20)}┐║');
  buf.writeln('║  │ 正在分析用户意图...${_pad(17, _w - 1)}│║');
  buf.writeln('║  └·${'·' * (_w - 5)}┘║');

  // tool calls
  buf.writeln('║  ┌ 🔧 工具调用${'─' * (_w - 17)}┐║');
  buf.writeln('║  │ query: "量子力学"${_pad(19, _w - 1)}│║');
  buf.writeln('║  │ ✅ 找到 3 条 (已折叠)${_pad(21, _w - 1)}│║');
  buf.writeln('║  └${'─' * (_w - 4)}┘║');

  // 输入区
  buf.writeln('╟${'─' * _w}╢');
  final parts = <String>['✏ 输入问题...', '📎', '🎤', '/', '➤'];
  final inputLine = parts.join('  ');
  buf.writeln('║  │ $inputLine${_pad(inputLine.length, _w)}│║');

  // drawers (V2: 在 layout.features.drawers 中)
  if (layout != null && layout.features.drawers.isNotEmpty) {
    for (final d in layout.features.drawers) {
      buf.writeln('╟${'─' * _w}╢');
      final icon =
          switch (d) { 'left' => '←', 'right' => '→', 'top' => '↑', _ => '↓' };
      final line = '$icon 抽屉: $d';
      buf.writeln('║  $line${_pad(line.length, _w)}║');
    }
  }

  buf.writeln('╚${'═' * _w}╝');
  return buf.toString();
}

// ═══════ Default ═══════

String _renderDefault(ModuleDescriptor m) {
  final buf = StringBuffer();
  final layout = _firstPageLayout(m);

  buf.writeln('╔${'═' * _w}╗');
  buf.writeln('║  📋 ${m.name}${_pad(m.name.length + 5, _w)}║');
  buf.writeln('╟${'─' * _w}╢');

  // search (V2: 在 layout.features.search 中)
  if (layout?.features.search != null && layout!.features.search!.enabled) {
    final s = layout.features.search!;
    buf.writeln('║  🔍 ${s.placeholder}${'─' * max(1, _w - s.placeholder.length - 5)}║');
  }

  // tabs (V2: 无 panels，从 slots 的 key 推断)
  if (layout != null && layout.slots.isNotEmpty) {
    final slotKeys = layout.slots.keys.toList();
    final tabs = slotKeys
        .map((k) => ' $k ')
        .join(' │ ');
    buf.writeln('║  $tabs${_pad(tabs.length, _w)}║');
    buf.writeln('╟${'─' * _w}╢');
  }

  // grid or single-column (V2: grid 信息在 layout.preset 中)
  final columns = layout?.preset.columns;
  if (columns != null && columns > 1) {
    final gap = (layout!.preset.gap ?? 2.0).round();
    final cellW =
        max(10, (_w - 4 - (columns - 1) * gap) ~/ columns);
    final top = List.filled(columns, '┌${'─' * (cellW - 2)}┐').join('   ');
    buf.writeln('║  $top${_pad(top.length, _w)}║');
    // V2: 从页面 slots 遍历显示
    var row = 0;
    for (final page in m.pages) {
      final slots = page.layout?.slots;
      if (slots == null) continue;
      for (final entry in slots.entries) {
        if (row > 0 && row % columns == 0) {
          final sep =
              List.filled(columns, '├${'─' * (cellW - 2)}┤').join('   ');
          buf.writeln('║  $sep${_pad(sep.length, _w)}║');
        }
        final comp = entry.value.component;
        final label = comp != null ? comp.type : entry.key;
        buf.write('║  │ 📄 ${label}${_pad(label.length + 3, cellW - 1)}│');
        if ((row + 1) % columns == 0) buf.writeln('  ║');
        row++;
      }
    }
    if (columns > 1) {
      final bot =
          List.filled(columns, '└${'─' * (cellW - 2)}┘').join('   ');
      buf.writeln('║  $bot${_pad(bot.length, _w)}║');
    }
  } else {
    // 无 grid 时显示页面结构
    for (final page in m.pages) {
      final slots = page.layout?.slots;
      if (slots != null) {
        for (final entry in slots.entries) {
          final comp = entry.value.component;
          final label = comp != null ? '${comp.type}' : entry.key;
          buf.writeln(
              '║  📄 $label (${entry.key})${_pad(label.length + entry.key.length + 6, _w)}║');
        }
      }
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
      final d = a.deletable!;
      if (d.confirmEnabled) {
        final msg = d.confirmMessage;
        tools.add(msg != null ? '🗑 删除(确认: "$msg")' : '🗑 删除(确认)');
      } else {
        tools.add('🗑 删除');
      }
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

  // drawers (V2: 在 layout.features.drawers 中)
  if (layout != null && layout.features.drawers.isNotEmpty) {
    for (final d in layout.features.drawers) {
      buf.writeln('╟${'─' * _w}╢');
      final icon =
          switch (d) { 'left' => '←', 'right' => '→', 'top' => '↑', _ => '↓' };
      final line = '$icon 抽屉: $d';
      buf.writeln('║  $line${_pad(line.length, _w)}║');
    }
  }

  buf.writeln('╚${'═' * _w}╝');
  return buf.toString();
}

// ═══════ Spreadsheet ═══════

String _renderSpreadsheet(ModuleDescriptor m) {
  final buf = StringBuffer();
  buf.writeln('╔${'═' * _w}╗');
  buf.writeln('║  📊 ${m.name}${_pad(m.name.length + 5, _w)}║');
  buf.writeln('╟${'─' * _w}╢');
  const cols = 5;
  final header = List.generate(cols, (i) => ' ${_colName(i)} ').join('│');
  buf.writeln('║  │$header│${_pad(header.length + 4, _w)}║');
  final sep = List.generate(cols, (_) => '───').join('│');
  buf.writeln('║  │$sep│${_pad(sep.length + 4, _w)}║');
  for (var r = 1; r <= 5; r++) {
    final row = List.generate(cols, (_) => '   ').join('│');
    buf.writeln('║  │$row│${_pad(row.length + 4, _w)}║');
  }
  buf.writeln('╟${'─' * _w}╢');
  final caps = <String>['📋 ${cols}×5', 'fx 公式', '📈 图表', '📑 多Sheet', '🎨 条件格式'];
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
  buf.writeln(
      '║  │ ─ 修订: 删除旧表述 → 新增表述${_pad(28, _w - 1)}│║');
  buf.writeln(
      '║  │ 💬 批注: [评审人] 需补充引用${_pad(27, _w - 1)}│║');
  buf.writeln('║  └${'─' * (_w - 5)}─┘║');
  buf.writeln('╟${'─' * _w}╢');
  final caps = <String>['📝 修订', '💬 批注', '📑 目录', '¹ 脚注', '页眉页脚', '📤 pdf/docx'];
  final capLine = caps.join(' │ ');
  buf.writeln('║  $capLine${_pad(capLine.length, _w)}║');
  buf.writeln('╚${'═' * _w}╝');
  return buf.toString();
}

// ═══════ Presentation ═══════

String _renderPresentation(ModuleDescriptor m) {
  final buf = StringBuffer();
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
  final caps = <String>['🎬 切换动画', '✨ 元素动画', '📝 备注', '🖥 双屏', '📐 母版', '📤 pdf/pptx'];
  final capLine = caps.join(' │ ');
  buf.writeln('║  $capLine${_pad(capLine.length, _w)}║');
  buf.writeln('╚${'═' * _w}╝');
  return buf.toString();
}
