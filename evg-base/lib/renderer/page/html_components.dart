/// V2 HTML component dispatch map — renders co-located with Dart in components/<domain>/.
library;

import 'dart:convert';
import '../components/shared/html_helpers.dart';
import '../components/interaction/renderChat.dart';
import '../components/interaction/renderForm.dart';
import '../components/interaction/renderSettings.dart';
import '../components/interaction/renderPromptBuilder.dart';
import '../components/document/renderCodeEditor.dart';
import '../components/document/renderMarkdown.dart';
import '../components/document/renderVideo.dart';
import '../components/document/renderPdfViewer.dart';
import '../components/document/renderScanner.dart';
import '../components/document/tech_planner/renderTechPlannerCard.dart';
import '../components/document/scraper/renderScraperGenerator.dart';
import '../components/document/renderAudioPlayer.dart';
import '../components/document/renderImageGallery.dart';
import '../components/document/renderDocument.dart';
import '../components/document/renderNotepad.dart';
import '../components/document/renderDiffViewer.dart';
import '../components/document/renderPresentation.dart';
import '../components/data/renderDataTable.dart';
import '../components/data/renderChart.dart';
import '../components/data/renderStatTile.dart';
import '../components/data/renderCardList.dart';
import '../components/data/renderKanban.dart';
import '../components/data/renderTree.dart';
import '../components/data/renderTimeline.dart';
import '../components/data/renderMap.dart';
import '../components/data/renderCalendar.dart';
import '../components/data/renderTimetable.dart';
import '../components/data/renderDataDashboard.dart';
import '../components/creative/renderSpreadsheet.dart';
import '../components/creative/renderMindmap.dart';
import '../components/creative/renderWhiteboard.dart';
import '../components/creative/renderTerminal.dart';
import '../components/learning/renderTypeCheck.dart';
import '../components/learning/renderFlashcards.dart';
import '../components/learning/renderQuiz.dart';
import '../components/learning/renderCrossword.dart';
import '../components/learning/renderPronunciation.dart';
import '../components/controls/renderButton.dart';
import '../components/controls/renderNavButton.dart';
import '../components/controls/renderDivider.dart';
import '../components/controls/renderLotteryWheel.dart';
import '../components/controls/renderCustom.dart';
import '../components/controls/renderWebView.dart';
import '../../core/data/data.dart';
import '../../core/module/module_descriptor.dart';
import '../data/data_source_resolver.dart';

/// 渲染单个组件为 HTML 片段。
///
/// M2 P3-2（R7 双端一致）：若 [comp] 携带 `dataSource` 且提供 [orch]，
/// 先在 Dart 侧经 [resolveDataSource] 拉取并合并进 `config` 对应字段，
/// 再交给各 `renderXxx` 同步渲染。无 dataSource / 无 orch 时维持原静态渲染。
Future<String> renderComponent(Map<String, dynamic> comp, DataOrchestrator? orch) async {
  final resolved = await _resolveComp(comp, orch);
  final type = resolved['type'] as String? ?? 'unknown';
  final fn = _renderers[type] ?? renderGeneric;
  return fn(resolved);
}

/// 解析组件 dataSource 并把拉取结果合并进 `config` 真实字段（与 Dart 端同映射）。
Future<Map<String, dynamic>> _resolveComp(Map<String, dynamic> comp, DataOrchestrator? orch) async {
  final dsMap = comp['dataSource'];
  if (dsMap is! Map || orch == null) return comp;
  final ds = DataSourceDescriptor.fromJson(dsMap as Map<String, dynamic>);
  if (ds.endpoint == null || ds.endpoint!.isEmpty) return comp;

  final resolved = await resolveDataSource(ds: ds, orch: orch);
  if (resolved == null) return comp;

  final type = comp['type'] as String? ?? '';
  final merged = <String, dynamic>{...comp};
  final cfg = (comp['config'] is Map)
      ? Map<String, dynamic>.from(comp['config'] as Map)
      : <String, dynamic>{};
  _mergeIntoConfig(type, cfg, resolved);
  merged['config'] = cfg;
  return merged;
}

/// 把拉取到的 [resolved] 合并进 [cfg] 的对应真实字段（M2 §4.5 映射）。
void _mergeIntoConfig(String type, Map<String, dynamic> cfg, dynamic resolved) {
  switch (type) {
    case 'data-table':
      if (resolved is List) {
        cfg['rows'] = resolved;
      } else if (resolved is Map && resolved['rows'] is List) {
        cfg['rows'] = resolved['rows'];
      }
    case 'chart':
      if (resolved is Map) {
        cfg['chart'] = resolved;
      } else if (resolved is List) {
        cfg['chart'] = {'series': resolved};
      }
    case 'calendar':
      if (resolved is List) {
        cfg['events'] = resolved;
      } else if (resolved is Map && resolved['events'] is List) {
        cfg['events'] = resolved['events'];
      } else if (resolved is Map) {
        cfg.addAll(resolved.cast<String, dynamic>());
      }
    case 'timeline':
      if (resolved is List) {
        cfg['items'] = resolved;
      } else if (resolved is Map && resolved['items'] is List) {
        cfg['items'] = resolved['items'];
      }
    case 'timetable':
      if (resolved is List) {
        cfg['sessions'] = resolved;
      } else if (resolved is Map && resolved['sessions'] is List) {
        cfg['sessions'] = resolved['sessions'];
      }
    case 'card-list':
      if (resolved is List) {
        cfg['cards'] = resolved;
      } else if (resolved is Map && resolved['cards'] is List) {
        cfg['cards'] = resolved['cards'];
      }
    case 'kanban':
      if (resolved is Map && resolved['columns'] is List) {
        cfg['columns'] = resolved['columns'];
      } else if (resolved is List) {
        cfg['columns'] = resolved;
      }
    case 'tree':
      if (resolved is Map) cfg['root'] = resolved;
    case 'map':
      if (resolved is Map) cfg['map'] = resolved;
    case 'flashcards':
    case 'quiz':
      final words = _extractWordListHtml(resolved);
      if (words != null) cfg['wordList'] = words;
      if (resolved is Map) {
        if (resolved['questionTypes'] is List) cfg['questionTypes'] = resolved['questionTypes'];
        if (resolved['timeLimit'] != null) cfg['timeLimit'] = resolved['timeLimit'];
        if (resolved['passScore'] != null) cfg['passScore'] = resolved['passScore'];
      }
    case 'stat-tile':
      if (resolved is Map) {
        if (resolved['value'] != null) cfg['value'] = resolved['value'];
        if (resolved['subtitle'] != null) cfg['subtitle'] = resolved['subtitle'];
        if (resolved['trend'] != null) cfg['trend'] = resolved['trend'];
      }
  }
}

/// 从 wordList 形态（List 或 `{wordList:[...]}`）提取词卡列表。
List<Map<String, dynamic>>? _extractWordListHtml(dynamic resolved) {
  List? rawList;
  if (resolved is List) {
    rawList = resolved;
  } else if (resolved is Map && resolved['wordList'] is List) {
    rawList = resolved['wordList'] as List;
  }
  if (rawList == null) return null;
  return rawList
      .whereType<Map>()
      .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
      .toList();
}

String componentIcon(String type) {
  return _componentIcons[type] ?? '📦';
}

final _renderers = <String, String Function(Map<String, dynamic>)>{
  'ai-assistant': renderChat, 'chat': renderChat,
  'code-editor': renderCodeEditor, 'markdown': renderMarkdown,
  'divider': renderDivider, 'data-table': renderDataTable,
  'chart': renderChart, 'stat-tile': renderStatTile,
  'card-list': renderCardList, 'kanban': renderKanban,
  'tree': renderTree, 'timeline': renderTimeline, 'map': renderMap,
  'document': renderDocument, 'doc-viewer': renderDocument,
  'doc-editor': renderDocument, 'video-player': renderVideo,
  'video': renderVideo, 'audio-player': renderAudioPlayer,
  'image-gallery': renderImageGallery, 'presentation': renderPresentation,
  'spreadsheet': renderSpreadsheet, 'notepad': renderNotepad,
  'whiteboard': renderWhiteboard, 'mindmap': renderMindmap,
  'diff-viewer': renderDiffViewer, 'terminal': renderTerminal,
  'type-check': renderTypeCheck, 'flashcards': renderFlashcards,
  'quiz': renderQuiz, 'crossword': renderCrossword,
  'pronunciation': renderPronunciation, 'prompt-builder': renderPromptBuilder,
  'form': renderForm, 'settings': renderSettings,
  'lottery-wheel': renderLotteryWheel, 'calendar': renderCalendar,
  'timetable': renderTimetable, 'data-dashboard': renderDataDashboard,
  'custom': renderCustom, 'webview': renderWebView,
  'button': renderButton, 'nav-button': renderNavButton,
  'pdf-viewer': renderPdfViewer, 'scanner': renderScanner,
  'tech-planner': renderTechPlanner, 'scraper-generator': renderScraperGenerator,
};

final _componentIcons = <String, String>{
  'ai-assistant': '🤖', 'chat': '💬', 'form': '📝', 'settings': '⚙️',
  'code-editor': '⌨️', 'data-table': '📊', 'chart': '📈', 'stat-tile': '📊',
  'card-list': '📋', 'kanban': '📌', 'tree': '🌲', 'timeline': '⏳', 'map': '🗺️',
  'document': '📄', 'video-player': '🎬', 'audio-player': '🎵',
  'image-gallery': '🖼', 'presentation': '📊', 'spreadsheet': '📈',
  'notepad': '📝', 'whiteboard': '🎨', 'mindmap': '🧠', 'diff-viewer': '🔍',
  'terminal': '💻', 'type-check': '⌨️', 'flashcards': '📇', 'quiz': '❓',
  'crossword': '🔢', 'pronunciation': '🎙', 'prompt-builder': '💡',
  'data-dashboard': '📊', 'calendar': '📅', 'timetable': '📅',
  'lottery-wheel': '🎰', 'custom': '📋', 'webview': '🌐',
  'button': '🔘', 'nav-button': '🔁', 'divider': '―',
  'pdf-viewer': '📕', 'scanner': '📷',
  'tech-planner': '📐', 'scraper-generator': '🕷️',
};
