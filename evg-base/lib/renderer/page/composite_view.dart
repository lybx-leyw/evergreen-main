/// 复合视图——`ui: "composite"` 模式的渲染入口。
///
/// 公开类：[CompositeView]
///
/// 结构：
/// ```
/// CompositeView
/// ├── TabBar（页面列表）
/// └── TabBarView
///     └── 每页 PageContent
///         ├── LayoutEngine（页面级 layout）
///         └── Grid/Column（slot 排布）
///             └── SlotDispatch（每个 slot → 对应组件视图）
/// ```
///
/// # ProcessManager 集成
///
/// 页面切换时自动管理四种进程作用域：
/// - 进入模块 → [ProcessManager.startModule]
/// - Tab 切换到某页 → [ProcessManager.startPage] + [ProcessManager.startSlot]
/// - Tab 切走某页 → [ProcessManager.stopPage] + [ProcessManager.stopAllSlotsOfPage]
/// - 离开模块 → [ProcessManager.dispose]
/// - 动作按钮 → [ProcessManager.runAction]
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';
import 'package:evergreen_base/core/module/process_manager.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/core/module/expose_state_writer.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/providers.dart';
import '../app/service/providers/renderer_providers.dart';
import '../components/shared/widgets/data_table.dart';
import '../components/shared/widgets/map_panel.dart';
import '../components/shared/widgets/video_player.dart';
import '../components/shared/widgets/lottery_wheel.dart';
import '../components/shared/widgets/calendar_widget.dart';
import '../components/shared/widgets/timetable_grid.dart';
import '../components/data/card_list_slot.dart';
import '../components/document/code_editor_slot.dart';
import '../components/data/chart_slot.dart';
import '../components/interaction/form_slot.dart';
import '../components/creative/spreadsheet_slot.dart';
import '../components/document/document_slot.dart';
import '../components/document/presentation_slot.dart';
import '../components/interaction/chat/chat_controller_view.dart';
import '../page/settings_view.dart';
import '../page/data_dashboard_view.dart';
import '../slot/slot_widgets.dart';
import '../app/service/theme/theme_provider.dart';
import '../components/document/audio_player_slot.dart';
import '../components/document/image_gallery_slot.dart';
import '../components/document/notepad_slot.dart';
import '../components/interaction/prompt_builder_slot.dart';
import '../components/data/tree_slot.dart';
import '../components/controls/webview_slot.dart';
import '../components/controls/custom_slot.dart';
import '../components/document/diff_viewer_slot.dart';
import '../components/creative/terminal_slot.dart';
import '../components/creative/whiteboard_slot.dart';
import '../components/learning/crossword_slot.dart';
import '../components/learning/pronunciation_slot.dart';
import '../slot/service/slot_scale.dart';
import '../components/document/markdown_slot.dart';
import '../components/document/video_slot.dart';
import '../components/controls/divider_slot.dart';
import '../components/controls/nav_button.dart';
import '../components/controls/button_bar.dart'; // ActionButtonBar
import '../components/placeholder/unknown_slot.dart';
import '../components/data/map_slot.dart';
import '../components/data/data_table_slot.dart';
import '../components/data/stat_tile_slot.dart';
import '../components/data/kanban_slot.dart';
import '../components/data/timeline_slot.dart';
import '../components/data/calendar_slot.dart';
import '../components/data/timetable_slot.dart';
import '../components/controls/lottery_wheel_slot.dart';
import '../components/document/scraper/scraper_generator_view.dart';

/// 复合视图——根据 [ModuleDescriptor.pages] 渲染多页面 Tab 界面。
///
/// 每页独立渲染其 slots：按 [PageDescriptor.layout.grid.columns] 分栏，
/// 每栏通过 [SlotDispatch] 调度到对应组件视图。
///
/// [workingDirectory] 为模块插件目录路径（如 `plugins/vocab-tutor/`）。
/// 提供后自动管理进程生命周期；不提供时跳过进程管理（纯 UI 模式）。
class CompositeView extends StatefulWidget {
  final ModuleDescriptor descriptor;

  /// 模块插件目录路径，用于 ProcessManager 进程管理。
  /// 通常为 `$pluginsDir/$moduleId/`。
  final String? workingDirectory;

  const CompositeView({
    super.key,
    required this.descriptor,
    this.workingDirectory,
  });

  @override
  State<CompositeView> createState() => _CompositeViewState();
}

class _CompositeViewState extends State<CompositeView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _activePageIndex = 0;
  ProcessManager? _processManager;

  /// 页级事件总线映射：pageId → PageEventBus。
  /// 每个页面激活时创建独立的 bus，切走时 dispose。
  final Map<String, PageEventBus> _pageBuses = {};

  /// expose_state 写入器列表（按页面管理，切走时 dispose）。
  final List<ExposeStateWriter> _exposeWriters = [];

  /// EventBus 订阅列表（页面切走时 cancel）。
  final List<StreamSubscription> _busSubscriptions = [];

  /// 当前页面的五层主题构建者（由 build() 设置，供子方法使用）。
  LayerThemeBuilder? _themeBuilder;

  @override
  void initState() {
    super.initState();
    final pages = widget.descriptor.pages;

    // V2: 从 GoRouter 当前路径解析 pageId，确定初始 Tab
    int initialIndex = 0;
    try {
      final uri = GoRouterState.of(context).uri;
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        final lastSegment = segments.last;
        final idx = pages.indexWhere((p) => p.id == lastSegment);
        if (idx >= 0) initialIndex = idx;
      }
    } catch (_) {}

    _tabController = TabController(
      length: pages.isEmpty ? 1 : pages.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _activePageIndex = initialIndex;

    // ── 初始化 ProcessManager ──
    // 注意：模块级进程由 ModuleLoader 管理，此处仅管理页面/栏/动作级进程。
    if (widget.workingDirectory != null) {
      _processManager = ProcessManager(
        moduleId: widget.descriptor.id,
        workingDirectory: widget.workingDirectory!,
      );
      // 启动当前页面的页面级 + 栏级进程
      if (pages.isNotEmpty) {
        _startProcessesForPage(0, pages[0]);
      }
    }

    _tabController.addListener(_onTabChanged);
  }

  /// Tab 切换——停止旧页面进程，启动新页面进程。
  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final newIndex = _tabController.index;
      final oldIndex = _activePageIndex;

      if (newIndex != oldIndex && _processManager != null) {
        final pages = widget.descriptor.pages;

        // 停止旧页面进程
        if (oldIndex < pages.length) {
          _stopProcessesForPage(oldIndex, pages[oldIndex]);
        }

        // 启动新页面进程
        if (newIndex < pages.length) {
          _startProcessesForPage(newIndex, pages[newIndex]);
        }
      }

      setState(() => _activePageIndex = newIndex);
    }
  }

  /// 启动指定页面的页面级进程、栏级进程、EventBus、expose_state。
  void _startProcessesForPage(int pageIndex, PageDescriptor page) {
    final pageId = page.id;
    final moduleId = widget.descriptor.id;

    // EventBus — 页面激活时创建
    if (!_pageBuses.containsKey(pageId)) {
      final bus = PageEventBus(pageId: pageId);
      _pageBuses[pageId] = bus;

      // 订阅事件总线
      _busSubscriptions.add(bus.all.listen((evt) {
        // slot:toggle:<key> — 折叠/展开 slot
        if (evt.event.startsWith('slot:toggle:')) {
          final targetSlot = evt.event.substring('slot:toggle:'.length);
          if (targetSlot.isNotEmpty) {
            debugPrint('[CompositeView:$moduleId] 抽屉事件: ${evt.sourceSlot} → toggle $targetSlot');
            _toggleSlot(pageId, targetSlot);
          }
        }
        // slot:switch_page:<pageId> — 切换到指定页面（与点击 Tab 效果相同）
        if (evt.event.startsWith('slot:switch_page:')) {
          final targetPage = evt.event.substring('slot:switch_page:'.length);
          if (targetPage.isNotEmpty) {
            debugPrint('[CompositeView:$moduleId] 页面切换: ${evt.sourceSlot} → $targetPage');
            navigateToPage(targetPage);
          }
        }
      }));

      debugPrint('[CompositeView:$moduleId] EventBus "$pageId" 已创建');
    }

    // expose_state writers — PLAN_NOW §9.2
    final bus = _pageBuses[pageId]!;
    final wsRoot = greenixWorkspaceDir(moduleId);
    for (final entry in page.layout.slots.entries) {
      final comp = entry.value.component;
      if (comp == null) continue;
      final exposeState = comp.config['exposeState'] as Map<String, dynamic>?;
      if (exposeState == null || exposeState.isEmpty) continue;
      final stateCfg = ExposeStateConfig.fromJson(exposeState);
      if (stateCfg.events.isEmpty) continue;
      final writer = ExposeStateWriter(
        moduleId: moduleId,
        slotKey: entry.key,
        config: stateCfg,
        bus: bus,
        workspaceRoot: wsRoot,
      );
      _exposeWriters.add(writer);
    }

    if (_processManager == null) return;
    final pm = _processManager!;

    // 页面级进程 (V2: process list)
    for (final p in page.process) {
      pm.startPage(pageId, p);
    }

    // 栏级进程
    for (final entry in page.layout.slots.entries) {
      for (final p in entry.value.process) {
        pm.startSlot(pageId, entry.key, p);
      }
    }

    debugPrint('[CompositeView:$moduleId] '
        '页面 "$pageId" 进程已启动');
  }

  /// 停止指定页面的进程、EventBus、expose_state。
  void _stopProcessesForPage(int pageIndex, PageDescriptor page) {
    final pageId = page.id;

    // expose_state writers（页面切走时释放）
    _exposeWriters.removeWhere((w) {
      if (w.moduleId == widget.descriptor.id) {
        w.dispose();
        return true;
      }
      return false;
    });

    // EventBus — 页面切走时释放
    _pageBuses[pageId]?.dispose();
    _pageBuses.remove(pageId);
    _busSubscriptions.removeWhere((s) { s.cancel(); return true; });

    if (_processManager == null) return;
    final pm = _processManager!;

    pm.stopAllSlotsOfPage(pageId);
    pm.stopPage(pageId);

    debugPrint('[CompositeView:${widget.descriptor.id}] '
        '页面 "$pageId" 进程已停止');
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _processManager?.dispose();
    for (final bus in _pageBuses.values) {
      bus.dispose();
    }
    _pageBuses.clear();
    super.dispose();
  }

  /// 根据路由中的 pageId 切换到对应 Tab。
  void navigateToPage(String pageId) {
    final pages = widget.descriptor.pages;
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].id == pageId) {
        _tabController.animateTo(i);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final descriptor = widget.descriptor;
    final pages = descriptor.pages;

    // 没有 pages 配置？回退到旧默认视图
    if (pages.isEmpty) {
      return DefaultView(descriptor: descriptor);
    }

    // ── 主题：读取活跃 ThemeDescriptor，构建 LayerThemeBuilder ──
    final themeDesc = _readThemeDescriptor(context);
    final themeBuilder = LayerThemeBuilder(
      descriptor: themeDesc,
      moduleOverride: descriptor.theme,
    );
    _themeBuilder = themeBuilder;

    // App 层 → Module 层 → 内容
    return LayerThemeScope(
      layerName: 'app',
      data: themeBuilder.appLayer,
      child: LayerThemeScope(
        layerName: 'module',
        data: themeBuilder.moduleLayer,
        child: Column(
          children: [
            // 页面 Tab 栏（支持按页隐藏）
            if (!_shouldHideCurrentTab(pages)) _buildTabBar(pages),
            // 页面内容
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: pages
                    .map((page) => _buildPageContent(page, themeBuilder))
                    .toList(),
              ),
            ),
            // 动作按钮栏
            if ((descriptor.actions?.actionButtons ?? []).isNotEmpty)
              _buildActionBar(),
          ],
        ),
      ),
    );
  }

  /// 当前页是否需要隐藏 Tab 栏。
  bool _shouldHideCurrentTab(List<PageDescriptor> pages) {
    if (_activePageIndex < 0 || _activePageIndex >= pages.length) return false;
    return pages[_activePageIndex].hideTab;
  }

  /// 从 Riverpod 读取活跃主题；未加载时返回内置默认。
  ThemeDescriptor _readThemeDescriptor(BuildContext context) {
    try {
      final container = _riverpodContainer(context);
      return container.read(themeDescriptorProvider) ?? _builtinDefault();
    } catch (_) {
      return _builtinDefault();
    }
  }

  /// 内置 default 主题（程序化构造，无需依赖 theme.json 加载）。
  ThemeDescriptor _builtinDefault() {
    return ThemeDescriptor(
      id: 'default',
      name: '品牌蓝',
      app: _defaultAppTokens(),
      module: _defaultModuleTokens(),
      page: _defaultPageTokens(),
      slot: _defaultSlotTokens(),
      components: _defaultComponentTokens(),
    );
  }

  ProviderContainer _riverpodContainer(BuildContext context) {
    // ignore: invalid_use_of_protected_member
    return ProviderScope.containerOf(context);
  }

  Widget _buildTabBar(List<PageDescriptor> pages) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      color: theme.colorScheme.surfaceContainerLow,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
              width: 0.5,
            ),
          ),
        ),
        child: TabBar(
          controller: _tabController,
          isScrollable: pages.length > 4,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          indicatorWeight: 3,
          indicatorColor: theme.colorScheme.primary,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(width: 3, color: theme.colorScheme.primary),
            insets: const EdgeInsets.symmetric(horizontal: 16),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
          ),
          splashBorderRadius: BorderRadius.circular(8),
          dividerColor: Colors.transparent,
          tabAlignment: pages.length > 4 ? TabAlignment.start : TabAlignment.fill,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          labelPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          tabs: pages
              .map((p) => _buildTab(p.label, isDark))
              .toList(),
        ),
      ),
    );
  }

  /// 从 label 中提取 emoji 前缀和文本，分别渲染为图标和文字。
  Widget _buildTab(String label, bool isDark) {
    // 用 rune 判断首字符是否为 emoji（BMP 之外或已知 emoji 范围）
    if (label.isNotEmpty) {
      final firstRune = label.runes.first;
      final isEmoji = firstRune > 0x1F000 ||
          (firstRune >= 0x2600 && firstRune <= 0x27BF) ||
          (firstRune >= 0x2300 && firstRune <= 0x23FF) ||
          (firstRune >= 0x2B50 && firstRune <= 0x2B55) ||
          (firstRune >= 0x2702 && firstRune <= 0x27B0) ||
          firstRune == 0x26A1 || // ⚡
          firstRune == 0x2714 || // ✅
          firstRune == 0x26A0 || // ⚠️
          firstRune == 0x2139 || // ℹ️
          firstRune == 0x1F4A1;  // 💡
      if (isEmoji) {
        // 分离 emoji 前缀（可能含 variation selector 0xFE0F 和 ZWJ 0x200D）
        var end = 1;
        final runes = label.runes.toList();
        while (end < runes.length &&
            (runes[end] == 0xFE0F || runes[end] == 0x200D || runes[end] > 0x1F000)) {
          end++;
          if (runes[end - 1] == 0x200D && end < runes.length) end++; // ZWJ + next emoji
        }
        final emoji = String.fromCharCodes(runes.sublist(0, end));
        final text = label.substring(emoji.length).trim();
        if (text.isNotEmpty) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 4),
              Text(text),
            ],
          );
        }
      }
    }
    return Tab(text: label, iconMargin: EdgeInsets.zero);
  }

  Widget _buildPageContent(PageDescriptor page, LayerThemeBuilder themeBuilder) {
    final allSlots = page.layout.slots;
    final pageId = page.id;
    final bus = _pageBuses[pageId];

    // 分离工具栏 slot（有 align 字段）和内容 slot
    final toolbarSlots = <MapEntry<String, SlotDescriptor>>[];
    final contentSlots = <MapEntry<String, SlotDescriptor>>[];
    for (final e in allSlots.entries) {
      if (e.value.component != null &&
          e.value.component!.config['align'] != null) {
        toolbarSlots.add(e);
      } else {
        contentSlots.add(e);
      }
    }

    // 工具栏
    final toolbar = toolbarSlots.isNotEmpty
        ? _buildToolbar(toolbarSlots, pageId, bus)
        : null;

    // 内容区（用过滤后的 contentSlots）
    final content = _buildLayoutFromEntries(contentSlots, page.layout.type, page.layout.preset, pageId, bus);

    final pageData = themeBuilder.pageLayer.merge(page.theme);

    final body = toolbar == null
        ? content
        : Column(
            children: [
              toolbar,
              const Divider(height: 1),
              Expanded(child: content),
            ],
          );

    // Page 层主题注入
    return LayerThemeScope(
      layerName: 'page',
      data: pageData,
      child: body,
    );
  }

  /// 工具栏——直接渲染 chrome slot 组件，无 AnimatedSize / Card 包装。
  Widget _buildToolbar(
    List<MapEntry<String, SlotDescriptor>> chromeSlots,
    String pageId,
    PageEventBus? bus,
  ) {
    final lefts = <Widget>[];
    final rights = <Widget>[];
    for (final e in chromeSlots) {
      final align = e.value.component?.config['align'] as String? ?? 'left';
      final w = SlotDispatch(
        slotKey: e.key,
        config: e.value.component!,
        moduleDescriptor: widget.descriptor,
        pageEventBus: bus,
        chrome: true,  // 工具栏 slot：跳过 Card 壳，直接渲染组件
        baseSlotTokens: _themeBuilder?.descriptor.slot ?? const {},
        baseComponentsTokens: _themeBuilder?.descriptor.components ?? const {},
        slotThemeOverride: e.value.theme,
        componentThemeOverride: e.value.component?.theme,
      );
      if (align == 'right') { rights.add(w); } else { lefts.add(w); }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (lefts.isNotEmpty) ...lefts,
          if (lefts.isNotEmpty && rights.isNotEmpty) const Spacer(),
          if (rights.isNotEmpty) ...rights,
        ],
      ),
    );
  }

  /// 根据 [LayoutDescriptor.type] 选择布局范式（与 HTML 引擎对齐）。
  Widget _buildLayoutFromEntries(
    List<MapEntry<String, SlotDescriptor>> entries,
    String type,
    LayoutPreset preset,
    String pageId,
    PageEventBus? bus,
  ) {
    if (entries.isEmpty) return const Center(child: Text('无内容'));
    return switch (type) {
      'grid'       => _buildGridLayout(entries, preset, pageId, bus),
      'flex'       => _buildFlexLayout(entries, preset, pageId, bus),
      'fullscreen' => _buildFullscreenLayout(entries, pageId, bus),
      'absolute'   => _buildAbsoluteLayout(entries, preset, pageId, bus),
      'dock'       => _buildDockLayout(entries, preset, pageId, bus),
      _            => _buildFlexLayout(entries, const LayoutPreset(direction: 'column'), pageId, bus),
    };
  }

  // ═══════ Slot 可见性 ═══════

  /// 每个页面的隐藏 slot key 集合。
  final Map<String, Set<String>> _hiddenSlots = {};

  void _toggleSlot(String pageId, String slotKey) {
    setState(() {
      _hiddenSlots.putIfAbsent(pageId, () => {});
      if (_hiddenSlots[pageId]!.contains(slotKey)) {
        _hiddenSlots[pageId]!.remove(slotKey);
      } else {
        _hiddenSlots[pageId]!.add(slotKey);
      }
    });
  }

  bool _isSlotVisible(String pageId, String slotKey, SlotDescriptor slot) {
    final hidden = _hiddenSlots[pageId]?.contains(slotKey) ?? false;
    return !hidden;
  }

  /// 渲染单个 slot 组件（支持折叠/展开 + 动画）。折叠时保留头栏。
  Widget _slotWidget(MapEntry<String, SlotDescriptor> entry, PageEventBus? bus, String pageId) {
    final visible = _isSlotVisible(pageId, entry.key, entry.value);
    final slotDesc = entry.value;
    final comp = slotDesc.component!;
    // config.collapsible: true（默认）→ 允许折叠/展开，false → 无 tap
    final collapsible = (comp.config['collapsible'] as bool?) ?? true;
    final dispatch = SlotDispatch(
      slotKey: entry.key,
      config: comp,
      moduleDescriptor: widget.descriptor,
      pageEventBus: bus,
      onToggle: collapsible ? () => _toggleSlot(pageId, entry.key) : null,
      collapsed: !visible,
      baseSlotTokens: _themeBuilder?.descriptor.slot ?? const {},
      baseComponentsTokens: _themeBuilder?.descriptor.components ?? const {},
      slotThemeOverride: slotDesc.theme,
      componentThemeOverride: comp.theme,
    );
    // 仅可折叠 slot 使用 AnimatedSize；不可折叠 slot 直接渲染以避免布局冲突
    if (!collapsible) return dispatch;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: dispatch,
    );
  }

  // ═══════ 5 种布局范式 ═══════

  /// grid — 多列网格。
  Widget _buildGridLayout(
    List<MapEntry<String, SlotDescriptor>> entries,
    LayoutPreset preset,
    String pageId,
    PageEventBus? bus,
  ) {
    final columns = (preset.columns ?? 1).clamp(1, 12);
    final gap = (preset.gap ?? 16.0).toDouble();

    // 按列数分组
    final rows = <List<MapEntry<String, SlotDescriptor>>>[];
    for (var i = 0; i < entries.length; i += columns) {
      final end = (i + columns < entries.length) ? i + columns : entries.length;
      rows.add(entries.sublist(i, end));
    }

    return Padding(
      padding: EdgeInsets.all(gap),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final colWidth = (constraints.maxWidth - (columns - 1) * gap) / columns;
          final avH = constraints.maxHeight;
          final rowCount = rows.length;
          // grid 纵向可滚动 → 行高等高分配，最小 160px 确保看板等复杂组件够用
          const minRowH = 160.0;
          final naturalH = avH.isFinite
              ? (avH - gap * (rowCount - 1)) / rowCount
              : avH;
          final rowHeight = naturalH.isFinite ? naturalH.clamp(minRowH, double.infinity) : minRowH;

          final gridRows = Column(
            mainAxisSize: MainAxisSize.min,
            children: rows.map((row) => SizedBox(
              height: rowHeight,
              child: Padding(
                padding: EdgeInsets.only(bottom: gap),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(columns, (i) {
                    if (i >= row.length) return SizedBox(width: colWidth);
                    final entry = row[i];
                    final isChrome = entry.value.component?.config['chrome'] == true;
                    Widget content = isChrome
                        ? SlotDispatch(
                            slotKey: entry.key,
                            config: entry.value.component!,
                            moduleDescriptor: widget.descriptor,
                            pageEventBus: bus,
                            baseSlotTokens:
                                _themeBuilder?.descriptor.slot ?? const {},
                            baseComponentsTokens:
                                _themeBuilder?.descriptor.components ??
                                    const {},
                            slotThemeOverride: entry.value.theme,
                            componentThemeOverride:
                                entry.value.component?.theme,
                          )
                        : _slotWidget(entry, bus, pageId);
                    // 纵向可滚动 → vScale=1.0；横向不可滚动 → hScale 自适应 colWidth
                    content = ScaledSlot(
                      slotWidth: colWidth,
                      slotHeight: rowHeight,
                      scrollableV: true,
                      scrollableH: false,
                      child: content,
                    );
                    return SizedBox(
                      width: colWidth,
                      child: Padding(
                        padding: EdgeInsets.only(right: i < columns - 1 ? gap : 0),
                        child: content,
                      ),
                    );
                  }),
                ),
              ),
            )).toList(),
          );

          return SingleChildScrollView(child: gridRows);
        },
      ),
    );
  }

  /// flex — 弹性布局（Row / Column / Wrap）。
  Widget _buildFlexLayout(
    List<MapEntry<String, SlotDescriptor>> entries,
    LayoutPreset preset,
    String pageId,
    PageEventBus? bus,
  ) {
    final direction = preset.direction ?? 'column';
    final gap = (preset.gap ?? 16.0).toDouble();
    final wrap = preset.wrap ?? false;
    final justify = _mainAlign(preset.justify);
    final align = _crossAlign(preset.align);

    // flex/wrap 不可滚动 → 两个方向均需自适应
    if (wrap) {
      return Padding(
        padding: EdgeInsets.all(gap),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: entries.map((e) {
                return ScaledSlot(
                  slotWidth: constraints.maxWidth,
                  slotHeight: constraints.maxHeight,
                  scrollableH: false,
                  scrollableV: false,
                  child: _slotWidget(e, bus, pageId),
                );
              }).toList(),
            );
          },
        ),
      );
    }

    final slotCount = entries.length;
    return Padding(
      padding: EdgeInsets.all(gap),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availW = constraints.maxWidth;
          final availH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 400.0;

          final children = <Widget>[];
          for (var i = 0; i < entries.length; i++) {
            if (i > 0) {
              children.add(SizedBox(
                width: direction == 'row' ? gap : 0,
                height: direction == 'column' ? gap : 0,
              ));
            }
            final e = entries[i];
            final isChrome = e.value.component?.config['chrome'] == true;
            Widget slot = isChrome
                ? SlotDispatch(
                    slotKey: e.key,
                    config: e.value.component!,
                    moduleDescriptor: widget.descriptor,
                    pageEventBus: bus,
                    baseSlotTokens:
                        _themeBuilder?.descriptor.slot ?? const {},
                    baseComponentsTokens:
                        _themeBuilder?.descriptor.components ?? const {},
                    slotThemeOverride: e.value.theme,
                    componentThemeOverride: e.value.component?.theme,
                  )
                : _slotWidget(e, bus, pageId);

            // 不可滚动 → 两个方向均需自适应
            slot = ScaledSlot(
              slotWidth: direction == 'row'
                  ? (availW - gap * (slotCount - 1)) / slotCount
                  : availW,
              slotHeight: direction == 'column'
                  ? (availH - gap * (slotCount - 1)) / slotCount
                  : availH,
              scrollableH: false,
              scrollableV: false,
              child: slot,
            );
            children.add(Expanded(child: slot));
          }

          return direction == 'row'
              ? Row(
                  crossAxisAlignment: align,
                  mainAxisAlignment: justify,
                  children: children,
                )
              : Column(
                  crossAxisAlignment: align,
                  mainAxisAlignment: justify,
                  children: children,
                );
        },
      ),
    );
  }

  /// fullscreen — 单组件撑满（不可滚动 → 双向自适应）。
  Widget _buildFullscreenLayout(
    List<MapEntry<String, SlotDescriptor>> entries,
    String pageId,
    PageEventBus? bus,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ScaledSlot(
          slotWidth: constraints.maxWidth,
          slotHeight: constraints.maxHeight,
          scrollableH: false,
          scrollableV: false,
          child: _slotWidget(entries.first, bus, pageId),
        );
      },
    );
  }

  /// absolute — 绝对定位（不可滚动 → 双向自适应）。
  Widget _buildAbsoluteLayout(
    List<MapEntry<String, SlotDescriptor>> entries,
    LayoutPreset preset,
    String pageId,
    PageEventBus? bus,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: entries.map((e) {
            final style = e.value.style;
            final top = _styleDouble(style, 'top');
            final bottom = _styleDouble(style, 'bottom');
            final left = _styleDouble(style, 'left');
            final right = _styleDouble(style, 'right');
            // absolute 子组件：用 Positioned 指定的尺寸作为 slot 尺寸
            final w = (left != null && right != null)
                ? constraints.maxWidth - left - right!
                : constraints.maxWidth;
            final h = (top != null && bottom != null)
                ? constraints.maxHeight - top - bottom!
                : constraints.maxHeight;
            return Positioned(
              top: top,
              bottom: bottom,
              left: left,
              right: right,
              child: ScaledSlot(
                slotWidth: w,
                slotHeight: h,
                scrollableH: false,
                scrollableV: false,
                child: _slotWidget(e, bus, pageId),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// dock — 停靠布局（不可滚动 → 各区域按实际尺寸缩放）。
  Widget _buildDockLayout(
    List<MapEntry<String, SlotDescriptor>> entries,
    LayoutPreset preset,
    String pageId,
    PageEventBus? bus,
  ) {
    final regions = preset.regions;
    final topH = _regionHeight(regions, 'top');
    final bottomH = _regionHeight(regions, 'bottom');
    final leftW = _regionWidth(regions, 'left');
    final rightW = _regionWidth(regions, 'right');

    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = constraints.maxWidth - leftW - rightW;
        final ch = constraints.maxHeight - topH - bottomH;

        Widget? top = _findSlot(entries, 'top', bus, pageId,
            constraints.maxWidth, topH);
        Widget? bottom = _findSlot(entries, 'bottom', bus, pageId,
            constraints.maxWidth, bottomH);
        Widget? left = _findSlot(entries, 'left', bus, pageId, leftW, ch);
        Widget? right = _findSlot(entries, 'right', bus, pageId, rightW, ch);

        final centerEntry = entries.where((e) =>
            e.key == 'center' || e.key == 'fill' || e.key == 'middle'
        ).firstOrNull ??
            entries.where((e) =>
                !['top', 'bottom', 'left', 'right'].contains(e.key)
            ).firstOrNull ??
            entries.first;

        final center = ScaledSlot(
          slotWidth: cw,
          slotHeight: ch,
          scrollableH: false,
          scrollableV: false,
          child: _slotWidget(centerEntry, bus, pageId),
        );

        return Column(
          children: [
            if (top != null) SizedBox(width: constraints.maxWidth, height: topH, child: top),
            Expanded(
              child: Row(
                children: [
                  if (left != null) SizedBox(width: leftW, child: left),
                  Expanded(child: center),
                  if (right != null) SizedBox(width: rightW, child: right),
                ],
              ),
            ),
            if (bottom != null) SizedBox(width: constraints.maxWidth, height: bottomH, child: bottom),
          ],
        );
      },
    );
  }

  // ═══════ 辅助 ═══════

  Widget? _findSlot(List<MapEntry<String, SlotDescriptor>> entries, String key,
      PageEventBus? bus, String pageId,
      [double? slotW, double? slotH]) {
    final idx = entries.indexWhere((e) => e.key == key);
    if (idx < 0) return null;
    final child = _slotWidget(entries[idx], bus, pageId);
    if (slotW != null && slotH != null) {
      return ScaledSlot(
        slotWidth: slotW,
        slotHeight: slotH,
        scrollableH: false,
        scrollableV: false,
        child: child,
      );
    }
    return child;
  }

  MainAxisAlignment _mainAlign(String? v) => switch (v) {
    'end'     => MainAxisAlignment.end,
    'center'  => MainAxisAlignment.center,
    'between' => MainAxisAlignment.spaceBetween,
    'around'  => MainAxisAlignment.spaceAround,
    'evenly'  => MainAxisAlignment.spaceEvenly,
    _         => MainAxisAlignment.start,
  };

  CrossAxisAlignment _crossAlign(String? v) => switch (v) {
    'end'     => CrossAxisAlignment.end,
    'center'  => CrossAxisAlignment.center,
    'stretch' => CrossAxisAlignment.stretch,
    _         => CrossAxisAlignment.start,
  };

  double? _styleDouble(StyleDescriptor style, String key) {
    return null; // absolute 定位暂不解析 StyleDescriptor
  }

  double _regionHeight(Map<String, dynamic>? regions, String key) {
    if (regions == null) return 0;
    final r = regions[key];
    if (r is Map) return (r['height'] as num?)?.toDouble() ?? 0;
    return 0;
  }

  double _regionWidth(Map<String, dynamic>? regions, String key) {
    if (regions == null) return 0;
    final r = regions[key];
    if (r is Map) return (r['width'] as num?)?.toDouble() ?? 0;
    return 0;
  }

  /// 动作按钮栏。
  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: (widget.descriptor.actions?.actionButtons ?? []).map((btn) {
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilledButton.tonal(
              onPressed: () {
                debugPrint(
                    '[CompositeView:${widget.descriptor.id}] '
                    '动作按钮 "${btn.label}" 被触发');
                if (btn.process != null && _processManager != null) {
                  _processManager!.runAction(btn.process);
                }
              },
              child: Text(btn.label),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════ 内置默认主题 Token（无 theme.json 时回退） ═══════

  static const _appColors = {
    'sidebar': {'bg': '#F2F3F5', 'text': '#1A1D21', 'active': '#1677FF', 'hover': '#E8EAED', 'divider': '#D0D5DD'},
    'header': {'bg': '#FFFFFF', 'text': '#1A1D21', 'border': '#D0D5DD'},
    'footer': {'bg': '#F5F6F8', 'text': '#656D78', 'border': '#D0D5DD'},
    'blank': {'bg': '#F5F6F8'},
    'commandPalette': {'bg': '#FFFFFF', 'text': '#1A1D21', 'highlight': '#1677FF', 'border': '#D0D5DD'},
  };

  static const _moduleColors = {
    'chrome': {'bg': '#FFFFFF', 'border': '#D0D5DD'},
  };

  static const _pageColors = {
    'tabBar': {'bg': '#FFFFFF', 'text': '#656D78', 'active': '#1677FF', 'indicator': '#1677FF', 'hover': '#E8EAED', 'border': '#D0D5DD'},
    'background': {'color': '#F5F6F8'},
  };

  static const _slotColors = {
    'header': {'bg': '#F2F3F5', 'text': '#656D78', 'border': '#D0D5DD'},
    'background': {'color': '#FFFFFF'},
    'border': {'color': '#D0D5DD', 'width': '1'},
  };

  static const _componentColors = {
    // 导航 (5)
    'sidebar': {'bg': '#F2F3F5', 'text': '#1A1D21', 'active': '#1677FF', 'hover': '#E8EAED'},
    'tab': {'text': '#656D78', 'active': '#1677FF', 'indicator': '#1677FF', 'hover': '#E8EAED'},
    'breadcrumb': {'text': '#656D78', 'link': '#1677FF', 'separator': '#D0D5DD'},
    'pagination': {'bg': '#FFFFFF', 'active': '#1677FF', 'text': '#1A1D21', 'hover': '#E8EAED'},
    'stepper': {'done': '#52C41A', 'active': '#1677FF', 'pending': '#D0D5DD', 'line': '#D0D5DD'},
    // 对话 (5)
    'bubble': {'user': '#1677FF', 'assistant': '#F2F3F5', 'text': '#1A1D21', 'timestamp': '#656D78'},
    'thinking': {'bg': '#F2F3F5', 'text': '#0958D9', 'border': '#D0D5DD'},
    'toolCall': {'bg': '#F2F3F5', 'text': '#1A1D21', 'border': '#D0D5DD'},
    'codeBlock': {'bg': '#1A1D21', 'text': '#E6EDF3', 'border': '#30363D', 'header': '#21262D'},
    'blockquote': {'border': '#1677FF', 'text': '#656D78', 'bg': '#F5F6F8'},
    // 表单 (7)
    'input': {'bg': '#F2F3F5', 'text': '#1A1D21', 'border': '#D0D5DD', 'focus': '#1677FF', 'placeholder': '#656D78', 'error': '#FF4D4F'},
    'checkbox': {'border': '#D0D5DD', 'fill': '#1677FF', 'check': '#FFFFFF'},
    'radio': {'border': '#D0D5DD', 'fill': '#1677FF'},
    'switch_': {'track': '#D0D5DD', 'thumb': '#FFFFFF', 'trackActive': '#1677FF'},
    'slider': {'track': '#E8EAED', 'fill': '#1677FF', 'thumb': '#FFFFFF'},
    'dropdown': {'bg': '#FFFFFF', 'text': '#1A1D21', 'border': '#D0D5DD', 'itemHover': '#E8EAED'},
    'datePicker': {'header': '#1677FF', 'selected': '#1677FF', 'today': '#E8EAED', 'hover': '#F5F6F8'},
    // 反馈 (6)
    'progressBar': {'track': '#E8EAED', 'fill': '#1677FF', 'text': '#FFFFFF'},
    'spinner': {'color': '#1677FF', 'track': '#E8EAED'},
    'skeleton': {'bg': '#E8EAED', 'shimmer': '#F5F6F8'},
    'toast': {'bg': '#FFFFFF', 'text': '#1A1D21', 'border': '#D0D5DD', 'success': '#52C41A', 'error': '#FF4D4F', 'warning': '#FA8C16', 'info': '#1677FF'},
    'alert': {'bg': '#FFFFFF', 'text': '#1A1D21', 'border': '#D0D5DD', 'icon': '#FA8C16'},
    'emptyState': {'icon': '#D0D5DD', 'text': '#656D78', 'action': '#1677FF'},
    // 数据展示 (9)
    'table': {'header': '#F2F3F5', 'stripe': '#F5F6F8', 'text': '#1A1D21', 'border': '#D0D5DD', 'hover': '#E8EAED'},
    'card': {'bg': '#FFFFFF', 'border': '#D0D5DD', 'shadow': '#000000', 'text': '#1A1D21'},
    'list': {'bg': '#FFFFFF', 'hover': '#E8EAED', 'divider': '#D0D5DD'},
    'chip': {'bg': '#E8EAED', 'text': '#1A1D21', 'border': '#D0D5DD', 'close': '#656D78'},
    'avatar': {'bg': '#1677FF', 'text': '#FFFFFF', 'border': '#FFFFFF'},
    'badge': {'bg': '#FF4D4F', 'text': '#FFFFFF'},
    'tooltip': {'bg': '#1A1D21', 'text': '#FFFFFF'},
    'calendar': {'header': '#1677FF', 'selected': '#1677FF', 'today': '#E8EAED', 'otherMonth': '#D0D5DD', 'event': '#FF4D4F'},
    'timeline': {'line': '#D0D5DD', 'dot': '#1677FF', 'card': '#FFFFFF'},
    // 按钮 (3)
    'button': {'primary': '#1677FF', 'hover': '#0958D9', 'active': '#0958D9', 'disabled': '#D0D5DD', 'text': '#FFFFFF'},
    'iconButton': {'color': '#656D78', 'hover': '#E8EAED', 'active': '#1677FF'},
    'fab': {'bg': '#1677FF', 'icon': '#FFFFFF', 'shadow': '#000000'},
    // 布局 (6)
    'drawer': {'bg': '#FFFFFF', 'text': '#1A1D21', 'overlay': '#000000'},
    'modal': {'bg': '#FFFFFF', 'overlay': '#000000', 'text': '#1A1D21', 'border': '#D0D5DD'},
    'header': {'bg': '#FFFFFF', 'text': '#1A1D21', 'border': '#D0D5DD'},
    'footer': {'bg': '#F5F6F8', 'text': '#656D78', 'border': '#D0D5DD'},
    'divider': {'color': '#E8EAED', 'thickness': '1'},
    'scrollbar': {'thumb': '#D0D5DD', 'track': '#F5F6F8'},
    // 图表 (1)
    'chart': {'colors': '#1677FF,#52C41A,#FA8C16,#FF4D4F,#722ED1', 'axis': '#D0D5DD', 'grid': '#E8EAED', 'tooltip': '#1A1D21'},
    // 媒体 (3)
    'videoPlayer': {'controls': '#FFFFFF', 'progress': '#1677FF', 'overlay': '#000000'},
    'audioPlayer': {'controls': '#1677FF', 'waveform': '#E8EAED', 'progress': '#1677FF'},
    'imageViewer': {'bg': '#000000', 'overlay': '#000000'},
    // 杂项 (5)
    'link': {'text': '#1677FF', 'hover': '#0958D9', 'visited': '#722ED1'},
    'menu': {'bg': '#FFFFFF', 'text': '#1A1D21', 'hover': '#E8EAED', 'divider': '#D0D5DD'},
    'commandPalette': {'bg': '#FFFFFF', 'text': '#1A1D21', 'highlight': '#1677FF', 'border': '#D0D5DD'},
    'contextMenu': {'bg': '#FFFFFF', 'text': '#1A1D21', 'hover': '#E8EAED', 'divider': '#D0D5DD'},
    'search': {'bg': '#F2F3F5', 'text': '#1A1D21', 'border': '#D0D5DD', 'focus': '#1677FF', 'icon': '#656D78'},
    // 范式 (4)
    'spreadsheet': {'header': '#F2F3F5', 'grid': '#D0D5DD', 'cell': '#FFFFFF', 'cellSelected': '#E8EAED', 'formulaBar': '#F5F6F8', 'tab': '#E8EAED'},
    'document': {'bg': '#F5F6F8', 'text': '#1A1D21', 'ruler': '#D0D5DD', 'pageShadow': '#000000', 'comment': '#FFFBE6', 'selection': '#1677FF'},
    'presentation': {'bg': '#F5F6F8', 'canvas': '#FFFFFF', 'slideBorder': '#D0D5DD', 'toolbar': '#F2F3F5', 'notes': '#FFFBE6'},
    'workspace': {'bg': '#F5F6F8', 'tabBar': '#F2F3F5', 'panel': '#FFFFFF', 'resizeHandle': '#D0D5DD', 'empty': '#F5F6F8'},
  };

  LayerTokens _defaultAppTokens() => _cloneTokens(_appColors);

  LayerTokens _defaultModuleTokens() => _cloneTokens(_moduleColors);

  LayerTokens _defaultPageTokens() => _cloneTokens(_pageColors);

  LayerTokens _defaultSlotTokens() => _cloneTokens(_slotColors);

  LayerTokens _defaultComponentTokens() => _cloneTokens(_componentColors);

  static LayerTokens _cloneTokens(Map<String, Map<String, String>> source) {
    return source.map((k, v) => MapEntry(k, Map<String, String>.from(v)));
  }
}

class SlotDispatch extends StatelessWidget {
  final String slotKey;
  final ComponentDescriptor config;
  final ModuleDescriptor moduleDescriptor;
  final PageEventBus? pageEventBus;
  final VoidCallback? onToggle;
  final bool collapsed;
  final bool chrome;
  final LayerTokens baseSlotTokens;
  final LayerTokens baseComponentsTokens;
  final Map<String, Map<String, String>>? slotThemeOverride;
  final Map<String, Map<String, String>>? componentThemeOverride;
  const SlotDispatch({super.key, required this.slotKey, required this.config, required this.moduleDescriptor, this.pageEventBus, this.onToggle, this.collapsed = false, this.chrome = false, this.baseSlotTokens = const {}, this.baseComponentsTokens = const {}, this.slotThemeOverride, this.componentThemeOverride});
  @override
  Widget build(BuildContext context) {
    final content = switch (config.type) {
        'ai-assistant' => ChatControllerView(descriptor: moduleDescriptor, embedded: true, compact: true, pageEventBus: pageEventBus, agentConfig: config.config, slotKey: slotKey),
        'chat' => ChatControllerView(descriptor: moduleDescriptor, embedded: true, compact: true, pageEventBus: pageEventBus, agentConfig: config.config, slotKey: slotKey),
        'form' => FormView(form: FormDescriptor.fromJson(config.config)),
        'settings' => SettingsView(descriptor: moduleDescriptor),
        'data-dashboard' => DataDashboardView(descriptor: moduleDescriptor),
        'code-editor' => EditorView(descriptor: moduleDescriptor, component: config),
        'prompt-builder' => PromptBuilderSlot(config: config),
        'data-table' => DataTableSlot(config: config),
        'card-list' => CardListSlot(config: config),
        'chart' => ChartSlot(config: config),
        'stat-tile' => StatTileSlot(config: config),
        'kanban' => KanbanSlot(config: config),
        'tree' => TreeSlot(config: config),
        'timeline' => TimelineSlot(config: config),
        'map' => MapSlot(config: config),
        'doc-viewer' => DocumentView(descriptor: moduleDescriptor, component: config),
        'doc-editor' => DocumentView(descriptor: moduleDescriptor, component: config),
        'document' => DocumentView(descriptor: moduleDescriptor, component: config),
        'video-player' => VideoSlot(config: config),
        'video' => VideoSlot(config: config),
        'audio-player' => AudioPlayerSlot(config: config),
        'image-gallery' => ImageGallerySlot(config: config),
        'presentation' => PresentationView(descriptor: moduleDescriptor, component: config),
        'nav-button' => NavButton(label: config.config['label'] as String? ?? '', icon: config.config['icon'] as String? ?? '', target: config.config['target'] as String? ?? '', pageEventBus: pageEventBus),
        'button' => ActionButtonBar(config: config.config, pageEventBus: pageEventBus),
        'timetable' => TimetableSlot(config: config),
        'markdown' => MarkdownSlot(markdown: _extractMarkdownContent(config.config), showHeader: config.config['showHeader'] as bool? ?? true),
        'spreadsheet' => SpreadsheetView(descriptor: moduleDescriptor, component: config),
        'notepad' => NotepadSlot(config: config),
        'whiteboard' => WhiteboardSlot(config: config),
        'mindmap' => MindmapSlot(slotKey: slotKey, config: config),
        'diff-viewer' => DiffViewerSlot(config: config),
        'terminal' => TerminalSlot(config: config),
        'type-check' => TypeCheckSlot(slotKey: slotKey, config: config, pageEventBus: pageEventBus, moduleId: moduleDescriptor.id),
        'flashcards' => FlashcardsSlot(slotKey: slotKey, config: config, pageEventBus: pageEventBus, moduleId: moduleDescriptor.id),
        'quiz' => QuizSlot(slotKey: slotKey, config: config, pageEventBus: pageEventBus, moduleId: moduleDescriptor.id),
        'crossword' => CrosswordSlot(config: config),
        'pronunciation' => PronunciationSlot(config: config),
        'custom' => CustomSlot(config: config),
        'webview' => WebViewSlot(config: config),
        'divider' => const DividerSlot(),
        'lottery-wheel' => LotteryWheelSlot(config: config),
        'calendar' => CalendarSlot(config: config),
        'scraper-generator' => ScraperGeneratorView(descriptor: moduleDescriptor, config: config, slotKey: slotKey, pageEventBus: pageEventBus),
        _ => UnknownSlot(type: config.type, config: config.config, group: config.type.startsWith('placeholder-') ? '预留扩展' : '未知'),
      };
    final slotData = LayerThemeData.fromTokens(baseSlotTokens).merge(slotThemeOverride);
    final compData = LayerThemeData.fromTokens(baseComponentsTokens).merge(componentThemeOverride);
    final themedContent = LayerThemeScope(layerName: 'components', data: compData, child: content);
    if (chrome || config.config['chrome'] == true) return LayerThemeScope(layerName: 'slot', data: slotData, child: themedContent);
    return LayerThemeScope(layerName: 'slot', data: slotData, child: _buildSlotCard(context, slotKey, themedContent));
  }
  static String _extractMarkdownContent(Map<String, dynamic> config) {
    if (config case {'content': String content}) return content;
    if (config case {'src': String src}) return '> 📄 文件: $src\n\n*(文件加载暂未实现)*';
    return '*无内容*\n\n在 config 中设置 `content` 字段来显示 Markdown 内容。';
  }
  Widget _buildSlotCard(BuildContext context, String key, Widget content) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final s = SlotScale.of(context).scale;
    return Card(elevation: 1, shadowColor: Colors.black.withValues(alpha: isDark ? 0.12 : 0.04), surfaceTintColor: theme.colorScheme.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * s), side: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200, width: 1)), clipBehavior: Clip.antiAlias, margin: EdgeInsets.only(bottom: 2 * s), child: Column(mainAxisSize: MainAxisSize.max, crossAxisAlignment: CrossAxisAlignment.stretch, children: [Container(padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s), decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, border: Border(bottom: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200))), child: Row(children: [Text('📌 $key', style: TextStyle(fontSize: 11 * s, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)), SizedBox(width: 6 * s), Container(padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 1 * s), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(4 * s)), child: Text(config.type, style: TextStyle(fontSize: 9 * s, color: Theme.of(context).colorScheme.primary))), const Spacer(), if (onToggle != null) InkWell(onTap: onToggle, borderRadius: BorderRadius.circular(4 * s), child: Padding(padding: EdgeInsets.all(2 * s), child: Icon(collapsed ? Icons.unfold_more : Icons.unfold_less, size: 14 * s)))]), ), if (!collapsed) Expanded(child: content)]));
  }
}

