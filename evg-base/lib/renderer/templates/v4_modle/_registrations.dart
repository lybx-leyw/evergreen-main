/// v5P Phase 1：组件自注册入口。
///
/// 在 app 启动时被 main.dart 或第一个 CompositeView 构造前 import，
/// 确保所有 45 个具名组件已注册进 [SlotRegistry]。
///
/// 新增组件只需在此文件加两行（import + register 调用），
/// 无需修改 composite_view.dart。
library;

import 'slot_registry.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'component_capability.dart';
import 'data/normalized_data.dart';

// ═══════ data/ ═══════
import 'components/data/card_list_slot.dart';
import 'components/data/chart_slot.dart';
import 'components/data/stat_tile_slot.dart';
import 'components/data/data_table_slot.dart';
import 'components/data/kanban_slot.dart';
import 'components/data/tree_slot.dart';
import 'components/data/timeline_slot.dart';
import 'components/data/map_slot.dart';
import 'components/data/calendar_slot.dart';
import 'components/data/timetable_slot.dart';

// ═══════ document/ ═══════
import 'components/document/markdown_slot.dart';
import 'components/document/video_slot.dart';
import 'components/document/audio_player_slot.dart';
import 'components/document/image_gallery_slot.dart';
import 'components/document/document_slot.dart';
import 'components/document/presentation_slot.dart';
import 'components/document/pdf_viewer_slot.dart';
import 'components/document/code_editor_slot.dart';
import 'components/document/notepad_slot.dart';
import 'components/document/diff_viewer_slot.dart';
import 'components/document/scanner_slot.dart';
import 'components/document/tech_planner_slot.dart';

// ═══════ creative/ ═══════
import 'components/creative/spreadsheet_slot.dart';
import 'components/creative/terminal_slot.dart';
import 'components/creative/whiteboard_slot.dart';
// html-creator 已迁移到 html_modle 模板，不在此注册

// ═══════ controls/ ═══════
import 'components/controls/custom_slot.dart';
import 'components/controls/webview_slot.dart';
import 'components/controls/divider_slot.dart';
import 'components/controls/lottery_wheel_slot.dart';

// ═══════ interaction/ ═══════
import 'components/interaction/form_slot.dart';
import 'components/interaction/prompt_builder_slot.dart';

// ═══════ learning/ ═══════
import 'components/learning/crossword_slot.dart';
import 'components/learning/pronunciation_slot.dart';

// ═══════ slot/ ═══════
import 'slot/slot_widgets.dart';

// ═══════ marketplace/ ═══════
import 'components/marketplace/marketplace_slot.dart';

// ═══════ placeholder/ ═══════
import 'components/placeholder/unknown_slot.dart';

// ═══════ 页面级组件 ═══════
import 'package:evergreen_base/renderer/page/settings_view.dart';
import 'package:evergreen_base/renderer/page/data_dashboard_view.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/interaction/chat/chat_controller_view.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/controls/nav_button.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/controls/button_bar.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/view/scraper_generator_view.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/plugin_designer_slot.dart';

/// 注册所有 v4_modle 具名组件到 [SlotRegistry]。
///
/// 注意：Dart 顶层变量是懒初始化的，必须在消费方显式引用以触发执行。
/// [composite_view.dart] 的 [CompositeViewState.initState] 中调用此函数。
void initV4ModleRegistrations() {
  print('[v4_modle] 组件注册触发...');
  // ═══════ data/ ═══════
  SlotRegistry.register('card-list', (ctx) => CardListSlot(config: ctx.config));
  SlotRegistry.register('chart', (ctx) => ChartSlot(config: ctx.config));
  SlotRegistry.register('stat-tile', (ctx) => StatTileSlot(config: ctx.config));
  SlotRegistry.register('data-table', (ctx) => DataTableSlot(config: ctx.config));
  SlotRegistry.register('kanban', (ctx) => KanbanSlot(config: ctx.config));
  SlotRegistry.register('tree', (ctx) => TreeSlot(config: ctx.config));
  SlotRegistry.register('timeline', (ctx) => TimelineSlot(config: ctx.config));
  SlotRegistry.register('map', (ctx) => MapSlot(config: ctx.config));
  SlotRegistry.register('calendar', (ctx) => CalendarSlot(config: ctx.config));
  SlotRegistry.register('timetable', (ctx) => TimetableSlot(config: ctx.config));

  // ═══════ document/ ═══════
  // markdown: 需要预处理 content/src 提取 → 在 builder 内处理
  String _extractMd(Map<String, dynamic> c) {
    if (c case {'content': String content}) return content;
    if (c case {'src': String src}) return '> 📄 文件: $src\n\n*(文件加载暂未实现)*';
    return '*无内容*\n\n在 config 中设置 `content` 字段来显示 Markdown 内容。';
  }
  SlotRegistry.register('markdown', (ctx) => MarkdownSlot(
      markdown: _extractMd(ctx.config.config),
      showHeader: ctx.config.config['showHeader'] as bool? ?? true));

  SlotRegistry.register('video-player', (ctx) => VideoSlot(
      config: ctx.config, moduleId: ctx.moduleDescriptor.id, pluginsDir: ctx.pluginsDir!),
      aliases: ['video']);
  SlotRegistry.register('audio-player', (ctx) => AudioPlayerSlot(
      config: ctx.config, moduleId: ctx.moduleDescriptor.id, pluginsDir: ctx.pluginsDir!));
  SlotRegistry.register('image-gallery', (ctx) => ImageGallerySlot(
      config: ctx.config, moduleId: ctx.moduleDescriptor.id, pluginsDir: ctx.pluginsDir!));
  SlotRegistry.register('document', (ctx) => DocumentView(
      descriptor: ctx.moduleDescriptor, component: ctx.config),
      aliases: ['doc-viewer', 'doc-editor']);
  SlotRegistry.register('presentation', (ctx) => PresentationView(
      descriptor: ctx.moduleDescriptor, component: ctx.config));
  SlotRegistry.register('pdf-viewer', (ctx) => PdfViewerSlot(
      config: ctx.config, moduleId: ctx.moduleDescriptor.id, pluginsDir: ctx.pluginsDir!));
  SlotRegistry.register('code-editor', (ctx) => EditorView(
      descriptor: ctx.moduleDescriptor, component: ctx.config));
  SlotRegistry.register('notepad', (ctx) => NotepadSlot(config: ctx.config));
  SlotRegistry.register('diff-viewer', (ctx) => DiffViewerSlot(config: ctx.config));
  SlotRegistry.register('scanner', (ctx) => ScannerSlot(
      slotKey: ctx.slotKey, config: ctx.config, pageEventBus: ctx.pageEventBus,
      moduleId: ctx.moduleDescriptor.id));
  SlotRegistry.register('tech-planner', (ctx) => TechPlannerSlot(
      component: ctx.config, moduleId: ctx.moduleDescriptor.id));

  // ═══════ creative/ ═══════
  SlotRegistry.register('spreadsheet', (ctx) => SpreadsheetView(
      descriptor: ctx.moduleDescriptor, component: ctx.config));
  SlotRegistry.register('terminal', (ctx) => TerminalSlot(config: ctx.config));
  SlotRegistry.register('whiteboard', (ctx) => WhiteboardSlot(config: ctx.config));
  // html-creator 已迁移到 html_modle 模板，不在此注册

  // ═══════ controls/ ═══════
  SlotRegistry.register('custom', (ctx) => CustomSlot(config: ctx.config));
  SlotRegistry.register('webview', (ctx) => WebViewSlot(
      config: ctx.config, moduleId: ctx.moduleDescriptor.id, pluginsDir: ctx.pluginsDir!));
  SlotRegistry.register('divider', (ctx) => const DividerSlot());
  SlotRegistry.register('lottery-wheel', (ctx) => LotteryWheelSlot(config: ctx.config));
  SlotRegistry.register('nav-button', (ctx) => NavButton(
      label: ctx.config.config['label'] as String? ?? '',
      icon: ctx.config.config['icon'] as String? ?? '',
      target: ctx.config.config['target'] as String? ?? '',
      pageEventBus: ctx.pageEventBus));
  SlotRegistry.register('button', (ctx) => ActionButtonBar(
      config: ctx.config.config, pageEventBus: ctx.pageEventBus));

  // ═══════ interaction/ ═══════
  SlotRegistry.register('form', (ctx) => FormView(
      form: FormDescriptor.fromJson(ctx.config.config)));
  SlotRegistry.register('prompt-builder', (ctx) => PromptBuilderSlot(config: ctx.config));

  // ═══════ learning/ ═══════
  SlotRegistry.register('crossword', (ctx) => CrosswordSlot(config: ctx.config));
  SlotRegistry.register('pronunciation', (ctx) => PronunciationSlot(config: ctx.config));

  // ═══════ slot/ (学习类 slot_widgets) ═══════
  SlotRegistry.register('mindmap', (ctx) =>
      MindmapSlot(slotKey: ctx.slotKey, config: ctx.config));
  SlotRegistry.register('type-check', (ctx) => TypeCheckSlot(
      slotKey: ctx.slotKey, config: ctx.config,
      pageEventBus: ctx.pageEventBus, moduleId: ctx.moduleDescriptor.id));
  SlotRegistry.register('flashcards', (ctx) => FlashcardsSlot(
      slotKey: ctx.slotKey, config: ctx.config,
      pageEventBus: ctx.pageEventBus, moduleId: ctx.moduleDescriptor.id));
  SlotRegistry.register('quiz', (ctx) => QuizSlot(
      slotKey: ctx.slotKey, config: ctx.config,
      pageEventBus: ctx.pageEventBus, moduleId: ctx.moduleDescriptor.id));

  // ═══════ 页面级组件 ═══════
  SlotRegistry.register('ai-assistant', (ctx) => ChatControllerView(
      descriptor: ctx.moduleDescriptor, embedded: false,
      pageEventBus: ctx.pageEventBus, agentConfig: ctx.config.config,
      slotKey: ctx.slotKey), aliases: ['chat']);

  SlotRegistry.register('settings', (ctx) => SettingsView(
      descriptor: ctx.moduleDescriptor));
  SlotRegistry.register('data-dashboard', (ctx) => DataDashboardView(
      descriptor: ctx.moduleDescriptor));
  SlotRegistry.register('scraper-generator', (ctx) => ScraperGeneratorView(
      descriptor: ctx.moduleDescriptor, config: ctx.config,
      slotKey: ctx.slotKey, pageEventBus: ctx.pageEventBus));
  SlotRegistry.register('plugin-designer', (ctx) => PluginDesignerSlot(
      slotKey: ctx.slotKey, moduleId: ctx.moduleDescriptor.id));

  // ═══════ marketplace ═══════
  SlotRegistry.register('marketplace', (ctx) => MarketplaceSlot(
      config: {
        ...ctx.config.config,
        'pluginsDir': ctx.pluginsDir,
      }));

  print('[v4_modle] ✅ 注册完成: ${SlotRegistry.registeredTypes.length} 个类型');
}

// ═══════ Phase 5: ComponentCapability 元数据注册 ═══════

void _registerCapabilities() {
  // ── 数据可视化 ──
  ComponentCapability.register(const ComponentCapability(type: 'chart', displayName: '图表', category: '数据可视化',
      description: '支持柱状图、折线图、饼图。可绑定数据源自动刷新。',
      tags: ['data', 'chart'], supportedDataShapes: [DataShape.simpleList, DataShape.labeledSeries],
      supportsDataSource: true, minWidth: 200, minHeight: 180,
      accessibility: AccessibilityInfo(role: 'image', labelFrom: 'config.title')));
  ComponentCapability.register(const ComponentCapability(type: 'stat-tile', displayName: '统计卡片', category: '数据可视化',
      description: 'KPI 指标卡片，支持趋势箭头和副标题。',
      tags: ['data', 'dashboard', 'kpi'], supportedDataShapes: [DataShape.scalar],
      supportsDataSource: true, minWidth: 120, minHeight: 100));

  // ── 数据展示 ──
  ComponentCapability.register(const ComponentCapability(type: 'card-list', displayName: '卡片列表', category: '数据展示',
      description: '以卡片网格展示数据列表。每条数据渲染为一个卡片。',
      tags: ['data', 'list'], supportedDataShapes: [DataShape.simpleList], supportsDataSource: true,
      accessibility: AccessibilityInfo(role: 'list')));
  ComponentCapability.register(const ComponentCapability(type: 'data-table', displayName: '数据表格', category: '数据展示',
      description: '结构化数据表格，支持行列渲染和可编辑模式。',
      tags: ['data', 'table', 'editable'], supportedDataShapes: [DataShape.simpleList, DataShape.table],
      supportsDataSource: true, interactive: true, minWidth: 300, minHeight: 200,
      accessibility: AccessibilityInfo(role: 'grid', keyboardNavigable: true)));
  ComponentCapability.register(const ComponentCapability(type: 'kanban', displayName: '看板', category: '数据展示',
      description: '多列看板视图，每列包含一组卡片。',
      tags: ['data', 'kanban'], supportedDataShapes: [DataShape.simpleList], supportsDataSource: true));
  ComponentCapability.register(const ComponentCapability(type: 'tree', displayName: '树形视图', category: '数据展示',
      description: '无限嵌套的树形结构展示。支持动态数据源注入根节点。',
      tags: ['data', 'tree', 'hierarchy'], supportedDataShapes: [DataShape.tree], supportsDataSource: true));
  ComponentCapability.register(const ComponentCapability(type: 'timeline', displayName: '时间线', category: '数据展示',
      description: '时间顺序排列的事件/日志列表。',
      tags: ['data', 'timeline', 'history'], supportedDataShapes: [DataShape.simpleList], supportsDataSource: true));
  ComponentCapability.register(const ComponentCapability(type: 'map', displayName: '地图', category: '数据展示',
      description: '地理位置展示，支持中心点、缩放和标记点。',
      tags: ['data', 'geo', 'location'], supportedDataShapes: [DataShape.geo], supportsDataSource: true, minWidth: 200, minHeight: 200));
  ComponentCapability.register(const ComponentCapability(type: 'calendar', displayName: '日历', category: '数据展示',
      description: '月/周/日视图日历，支持事件标记。',
      tags: ['data', 'calendar', 'schedule'], supportedDataShapes: [DataShape.simpleList], supportsDataSource: true,
      accessibility: AccessibilityInfo(role: 'grid', keyboardNavigable: true)));
  ComponentCapability.register(const ComponentCapability(type: 'timetable', displayName: '课表', category: '数据展示',
      description: '周课表网格，按时间和天排列课程。',
      tags: ['data', 'timetable', 'schedule'], supportedDataShapes: [DataShape.simpleList], supportsDataSource: true));

  // ── 文档与媒体 ──
  ComponentCapability.register(const ComponentCapability(type: 'markdown', displayName: 'Markdown', category: '文档与媒体',
      description: 'Markdown 文本渲染，支持 content 或 src 配置。',
      tags: ['document', 'text'], minWidth: 200));
  ComponentCapability.register(const ComponentCapability(type: 'document', displayName: '富文本编辑器', category: '文档与媒体',
      description: '所见即所得富文本文档编辑。别名: doc-viewer, doc-editor。',
      tags: ['document', 'editor'], interactive: true, minWidth: 300, minHeight: 200));
  ComponentCapability.register(const ComponentCapability(type: 'code-editor', displayName: '代码编辑器', category: '文档与媒体',
      description: '多标签页代码编辑器，支持语法高亮。',
      tags: ['code', 'editor'], interactive: true, minWidth: 300, minHeight: 200));
  ComponentCapability.register(const ComponentCapability(type: 'notepad', displayName: '记事本', category: '文档与媒体',
      description: '纯文本记事本。',
      tags: ['text', 'note'], interactive: true));
  ComponentCapability.register(const ComponentCapability(type: 'presentation', displayName: '幻灯片', category: '文档与媒体',
      description: '幻灯片演示查看器。',
      tags: ['document', 'presentation'], minWidth: 300, minHeight: 200));
  ComponentCapability.register(const ComponentCapability(type: 'video-player', displayName: '视频播放器', category: '文档与媒体',
      description: '视频播放器（media_kit）。别名: video。',
      tags: ['media', 'video'], minWidth: 300, minHeight: 200));
  ComponentCapability.register(const ComponentCapability(type: 'audio-player', displayName: '音频播放器', category: '文档与媒体',
      description: '音频播放器。',
      tags: ['media', 'audio'], minWidth: 200, minHeight: 60));
  ComponentCapability.register(const ComponentCapability(type: 'image-gallery', displayName: '图片画廊', category: '文档与媒体',
      description: '图片浏览画廊，支持缩放和翻页。',
      tags: ['media', 'image'], minWidth: 200, minHeight: 150));
  ComponentCapability.register(const ComponentCapability(type: 'pdf-viewer', displayName: 'PDF 查看器', category: '文档与媒体',
      description: 'PDF 文档预览。',
      tags: ['document', 'pdf'], minWidth: 250, minHeight: 300));
  ComponentCapability.register(const ComponentCapability(type: 'diff-viewer', displayName: '差异对比', category: '文档与媒体',
      description: '文本/代码差异对比视图。',
      tags: ['code', 'diff'], minWidth: 300, minHeight: 200));
  ComponentCapability.register(const ComponentCapability(type: 'scanner', displayName: '扫码器', category: '文档与媒体',
      description: '二维码/条码扫描。', tags: ['utility', 'scan'], minWidth: 200, minHeight: 200));

  // ── 创作工具 ──
  ComponentCapability.register(const ComponentCapability(type: 'spreadsheet', displayName: '电子表格', category: '创作工具',
      description: '可编辑电子表格，支持公式和图表。',
      tags: ['data', 'editor', 'spreadsheet'], interactive: true, minWidth: 300, minHeight: 200));
  ComponentCapability.register(const ComponentCapability(type: 'terminal', displayName: '终端', category: '创作工具',
      description: 'xterm 真实终端模拟器。',
      tags: ['dev', 'terminal'], interactive: true, minWidth: 300, minHeight: 150));
  ComponentCapability.register(const ComponentCapability(type: 'whiteboard', displayName: '白板', category: '创作工具',
      description: '自由涂鸦白板。', tags: ['creative', 'drawing'], interactive: true, minWidth: 200, minHeight: 150));
  ComponentCapability.register(const ComponentCapability(type: 'mindmap', displayName: '思维导图', category: '创作工具',
      description: '交互式思维导图。',
      tags: ['creative', 'mindmap', 'visualization'], minWidth: 200, minHeight: 200));
  ComponentCapability.register(const ComponentCapability(type: 'plugin-designer', displayName: '插件设计器', category: '创作工具',
      description: '所见即所得插件编排设计器。',
      tags: ['dev', 'designer', 'plugin'], interactive: true, minWidth: 500, minHeight: 400));

  // ── 智能交互 ──
  ComponentCapability.register(const ComponentCapability(type: 'ai-assistant', displayName: 'AI 助手', category: '智能交互',
      description: '全屏 AI 对话助手（含 Agent 工具调用）。别名: chat。',
      tags: ['ai', 'chat', 'agent'], interactive: true, minWidth: 300, minHeight: 300));
  ComponentCapability.register(const ComponentCapability(type: 'form', displayName: '表单', category: '智能交互',
      description: '动态表单，从 manifest 声明生成表单字段。',
      tags: ['ui', 'form', 'input'], interactive: true, minWidth: 200, minHeight: 150,
      accessibility: AccessibilityInfo(role: 'form', labelFrom: 'config.title', keyboardNavigable: true)));
  ComponentCapability.register(const ComponentCapability(type: 'prompt-builder', displayName: '提示词构建器', category: '智能交互',
      description: 'AI 提示词模板构建器。',
      tags: ['ai', 'prompt'], interactive: true, minWidth: 250, minHeight: 200));
  ComponentCapability.register(const ComponentCapability(type: 'settings', displayName: '设置面板', category: '智能交互',
      description: '模块设置面板。',
      tags: ['ui', 'settings', 'config'], interactive: true, minWidth: 250));
  ComponentCapability.register(const ComponentCapability(type: 'data-dashboard', displayName: '数据仪表盘', category: '智能交互',
      description: '模块级数据状态总览仪表盘。',
      tags: ['data', 'dashboard'], supportsDataSource: true, minWidth: 300, minHeight: 200));

  // ── 学习工具 ──
  ComponentCapability.register(const ComponentCapability(type: 'type-check', displayName: '打字背词', category: '学习工具',
      description: '中→英 / 英→中 打字背词模式。',
      tags: ['learning', 'vocabulary'], interactive: true, minWidth: 200, minHeight: 150,
      supportsDataSource: true));
  ComponentCapability.register(const ComponentCapability(type: 'flashcards', displayName: '闪卡', category: '学习工具',
      description: '闪卡复习（翻转动画），支持 dataSource。',
      tags: ['learning', 'memory'], interactive: true, minWidth: 200, minHeight: 150,
      supportsDataSource: true));
  ComponentCapability.register(const ComponentCapability(type: 'quiz', displayName: '测验', category: '学习工具',
      description: '综合测验（单选/填空/配对，计时 + 及格线）。',
      tags: ['learning', 'test'], interactive: true, minWidth: 250, minHeight: 200,
      supportsDataSource: true, accessibility: AccessibilityInfo(role: 'form', keyboardNavigable: true)));
  ComponentCapability.register(const ComponentCapability(type: 'crossword', displayName: '填字游戏', category: '学习工具',
      description: '交互式填字游戏。', tags: ['learning', 'game'], interactive: true, minWidth: 250, minHeight: 250));
  ComponentCapability.register(const ComponentCapability(type: 'pronunciation', displayName: '发音练习', category: '学习工具',
      description: '语音发音练习。', tags: ['learning', 'speech'], interactive: true, minWidth: 200, minHeight: 120));

  // ── 导航与控件 ──
  ComponentCapability.register(const ComponentCapability(type: 'nav-button', displayName: '导航按钮', category: '导航与控件',
      description: '页面跳转按钮。', tags: ['ui', 'navigation'], interactive: true, minWidth: 60, minHeight: 36));
  ComponentCapability.register(const ComponentCapability(type: 'button', displayName: '动作按钮', category: '导航与控件',
      description: '可配置的动作按钮栏。', tags: ['ui', 'action'], interactive: true));
  ComponentCapability.register(const ComponentCapability(type: 'divider', displayName: '分割线', category: '导航与控件',
      description: '视觉分割线。', tags: ['ui'], minWidth: 0, minHeight: 2));
  ComponentCapability.register(const ComponentCapability(type: 'custom', displayName: '自定义 HTML', category: '导航与控件',
      description: '自定义 HTML 内容注入。', tags: ['ui', 'html']));
  ComponentCapability.register(const ComponentCapability(type: 'webview', displayName: 'WebView', category: '导航与控件',
      description: 'Edge WebView2 内嵌浏览器。', tags: ['ui', 'browser'], interactive: true, minWidth: 300, minHeight: 200));
  ComponentCapability.register(const ComponentCapability(type: 'lottery-wheel', displayName: '抽奖转盘', category: '导航与控件',
      description: '交互式抽奖转盘。', tags: ['ui', 'game'], interactive: true, minWidth: 200, minHeight: 200));

  // ── 开发工具 ──
  ComponentCapability.register(const ComponentCapability(type: 'scraper-generator', displayName: '爬虫生成器', category: '开发工具',
      description: 'WYSIWYG 爬虫脚本生成器（WebView 抓包 + AI 工作区）。',
      tags: ['dev', 'scraper', 'ai'], interactive: true, minWidth: 400, minHeight: 300));
  ComponentCapability.register(const ComponentCapability(type: 'tech-planner', displayName: '技术规划', category: '开发工具',
      description: '技术规划编辑器（MD 编辑 + AI 辅助）。',
      tags: ['dev', 'planning', 'ai'], interactive: true, minWidth: 400, minHeight: 300));

  // ── 插件市场 ──
  ComponentCapability.register(const ComponentCapability(type: 'marketplace', displayName: '插件市场', category: '插件市场',
      description: 'Evergreen 插件市场，扫描和管理本地插件。',
      tags: ['system', 'plugin', 'market'], interactive: true, minWidth: 300, minHeight: 200));
}

/// 懒初始化守卫：首次 lookup 时自动执行全部注册。
bool _ensureRegistered() {
  if (!_registered) { _registered = true; initV4ModleRegistrations(); _registerCapabilities(); }
  return true;
}
bool _registered = false;

/// SlotRegistry 公开接口加上懒初始化守卫。
extension SlotRegistryEnsure on SlotRegistry {
  static SlotBuilder? lookupEnsured(String type) {
    _ensureRegistered();
    return SlotRegistry.lookup(type);
  }
}
