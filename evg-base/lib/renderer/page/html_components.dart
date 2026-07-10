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

String renderComponent(Map<String, dynamic> comp) {
  final type = comp['type'] as String? ?? 'unknown';
  final fn = _renderers[type] ?? renderGeneric;
  return fn(comp);
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
  'timetable': renderTimetable,
  'custom': renderCustom, 'webview': renderWebView,
  'button': renderButton, 'nav-button': renderNavButton,
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
};
