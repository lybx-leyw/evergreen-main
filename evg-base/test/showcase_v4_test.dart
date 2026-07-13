// 展示大厅 v4 专项验证：覆盖全部 47 具名组件 + 真实资产存在性 + 无写死串（M4）。
//
// 运行：cd evg-base && flutter test test/showcase_v4_test.dart
//
// 与 v3 的区别：v4 覆盖全部 47 具名（含 ai-assistant/chat、M3 的 pdf-viewer/scanner、
// 以及表外已注册的 tech-planner/scraper-generator），指标刷新到 67 / M3 完成。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _plugin = 'showcase-v4-html';
const String _manifestRel = '../plugins/$_plugin/module/manifest.json';

// 47 个具名组件（20 个 placeholder 跳过）
const Set<String> _expected = <String>{
  // 智能交互(9)
  'ai-assistant', 'chat', 'form', 'settings', 'data-dashboard', 'code-editor',
  'prompt-builder', 'pdf-viewer', 'scanner',
  // 数据展示(8)
  'data-table', 'card-list', 'chart', 'stat-tile', 'kanban',
  'tree', 'timeline', 'map',
  // 文档与媒体(12)
  'doc-viewer', 'doc-editor', 'document', 'video-player', 'video',
  'audio-player', 'image-gallery', 'presentation', 'nav-button', 'button',
  'timetable', 'markdown',
  // 创作与工具(6)
  'spreadsheet', 'notepad', 'whiteboard', 'mindmap', 'diff-viewer', 'terminal',
  // 学习专用(5)
  'type-check', 'flashcards', 'quiz', 'crossword', 'pronunciation',
  // 特殊与扩展(5)
  'custom', 'webview', 'divider', 'lottery-wheel', 'calendar',
  // 表外已注册(2)
  'tech-planner', 'scraper-generator',
};

// R11 禁用写死串
const List<String> _banned = <String>[
  'lorem ipsum', '占位示例', 'TODO数据', '项目 1', '运行中', '展示 AI 助手',
  '介绍这个平台', 'Python 中如何声明列表', '哪个关键字用于定义 Python 函数',
  '核心主题', '本学期各科目', '这是一段示例文档内容',
];

void main() {
  final manifestFile = File(_manifestRel);
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;

  Set<String> _collect(Map<String, dynamic> m, Set<String> acc) {
    final t = m['type'] as String?;
    if (t != null) acc.add(t);
    final comp = m['component'] as Map<String, dynamic>?;
    if (comp != null) _collect(comp, acc);
    final lay = m['layout'] as Map<String, dynamic>?;
    if (lay != null) {
      final sl = lay['slots'] as Map<String, dynamic>?;
      sl?.forEach((_, v) => _collect(v as Map<String, dynamic>, acc));
    }
    return acc;
  }

  test('展示大厅 v4 覆盖全部 47 具名组件', () {
    final found = <String>{};
    for (final p in (manifest['pages'] as List<dynamic>)) {
      _collect(p as Map<String, dynamic>, found);
    }
    expect(found, hasLength(47));
    expect(found, equals(_expected));
  });

  test('展示大厅 v4 无写死示例串（R11）', () {
    final raw = manifestFile.readAsStringSync().toLowerCase();
    final hits = _banned.where((b) => raw.contains(b.toLowerCase())).toList();
    expect(hits, isEmpty, reason: '发现写死串: $hits');
  });

  test('展示大厅 v4 含真实项目可核数据（M4 / 67 / 47）', () {
    final raw = manifestFile.readAsStringSync();
    for (final fact in const [
      '67', '47', '28', '6', '59', 'M3', 'Evergreen',
    ]) {
      expect(raw.contains(fact), isTrue, reason: '缺少真实数据: $fact');
    }
  });

  test('展示大厅 v4 真实资产文件均存在（供用户检验）', () {
    final base = manifestFile.parent.parent; // plugins/showcase-v4-html
    final assets = base.path + '/assets';
    final must = <String>[
      '$assets/video/evergreen_title.mp4',
      '$assets/code/notepad_slot.dart',
      '$assets/code/showcase_module.py',
      '$assets/img/logo.svg',
      '$assets/img/arch.svg',
      '$assets/audio/sample.wav',
      '$assets/doc/evergreen_overview.pdf',
    ];
    for (final f in must) {
      expect(File(f).existsSync(), isTrue, reason: '缺失真实资产: $f');
    }
    // 资产体积合理（非空、非占位）
    expect(File('$assets/video/evergreen_title.mp4').lengthSync(), greaterThan(10000));
    expect(File('$assets/doc/evergreen_overview.pdf').lengthSync(), greaterThan(300));
    expect(File('$assets/code/showcase_module.py').lengthSync(), greaterThan(1000));
  });

  test('展示大厅 v4 媒体组件指向真实资产', () {
    final raw = manifestFile.readAsStringSync();
    expect(raw.contains('assets/video/evergreen_title.mp4'), isTrue);
    expect(raw.contains('assets/audio/sample.wav'), isTrue);
    expect(raw.contains('assets/img/logo.svg'), isTrue);
    // M3 新增 pdf-viewer 指向真实 PDF 资产
    expect(raw.contains('assets/doc/evergreen_overview.pdf'), isTrue);
  });
}
