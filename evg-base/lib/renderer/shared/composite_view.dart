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
import 'package:evergreen_base/core/module/process_manager.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/core/module/expose_state_writer.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/providers.dart';
import '../widgets/data_table.dart';
import '../widgets/map_panel.dart';
import '../widgets/video_player.dart';
import '../widgets/lottery_wheel.dart';
import '../widgets/calendar_widget.dart';
import '../widgets/timetable_grid.dart';
import 'default_view.dart';
import 'editor_view.dart';
import 'dashboard_view.dart';
import 'form_view.dart';
import 'spreadsheet_view.dart';
import 'document_view.dart';
import 'presentation_view.dart';
import 'chat_controller_view.dart';
import 'settings_view.dart';
import 'data_dashboard_view.dart';
import 'slot_widgets.dart';

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

    return Column(
      children: [
        // 页面 Tab 栏
        _buildTabBar(pages),
        // 页面内容
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: pages.map((page) => _buildPageContent(page)).toList(),
          ),
        ),
        // 动作按钮栏
        if ((descriptor.actions?.actionButtons ?? []).isNotEmpty) _buildActionBar(),
      ],
    );
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

  Widget _buildPageContent(PageDescriptor page) {
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

    if (toolbar == null) return content;
    return Column(
      children: [
        toolbar,
        const Divider(height: 1),
        Expanded(child: content),
      ],
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
    final comp = entry.value.component!;
    // config.collapsible: true（默认）→ 允许折叠/展开，false → 无 tap
    final collapsible = (comp.config['collapsible'] as bool?) ?? true;
    final dispatch = SlotDispatch(
      slotKey: entry.key,
      config: comp,
      moduleDescriptor: widget.descriptor,
      pageEventBus: bus,
      onToggle: collapsible ? () => _toggleSlot(pageId, entry.key) : null,
      collapsed: !visible,
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
          return Column(
            children: rows.map((row) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: gap),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(columns, (i) {
                    if (i >= row.length) return SizedBox(width: colWidth);
                    final entry = row[i];
                    final isChrome = entry.value.component?.config['chrome'] == true;
                    final child = isChrome
                        ? SlotDispatch(
                            slotKey: entry.key,
                            config: entry.value.component!,
                            moduleDescriptor: widget.descriptor,
                            pageEventBus: bus,
                          )
                        : _slotWidget(entry, bus, pageId);
                    return SizedBox(
                      width: colWidth,
                      child: Padding(
                        padding: EdgeInsets.only(right: i < columns - 1 ? gap : 0),
                        child: child,
                      ),
                    );
                  }),
                ),
              ),
            )).toList(),
          );
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

    if (wrap) {
      return Padding(
        padding: EdgeInsets.all(gap),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: entries.map((e) => _slotWidget(e, bus, pageId)).toList(),
        ),
      );
    }

    final children = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) children.add(SizedBox(width: direction == 'row' ? gap : 0, height: direction == 'column' ? gap : 0));
      children.add(Expanded(child: _slotWidget(entries[i], bus, pageId)));
    }

    return Padding(
      padding: EdgeInsets.all(gap),
      child: direction == 'row'
          ? LayoutBuilder(
              builder: (context, constraints) {
                final h = constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : 400.0;
                return Row(
                  crossAxisAlignment: align,
                  mainAxisAlignment: justify,
                  children: entries.map((e) {
                    final isChrome = e.value.component?.config['chrome'] == true;
                    final child = isChrome
                        ? SlotDispatch(
                            slotKey: e.key,
                            config: e.value.component!,
                            moduleDescriptor: widget.descriptor,
                            pageEventBus: bus,
                          )
                        : _slotWidget(e, bus, pageId);
                    return SizedBox(height: h, child: child);
                  }).toList(),
                );
              },
            )
          : Column(
              crossAxisAlignment: align,
              mainAxisAlignment: justify,
              children: children,
            ),
    );
  }

  /// fullscreen — 单组件撑满。
  Widget _buildFullscreenLayout(
    List<MapEntry<String, SlotDescriptor>> entries,
    String pageId,
    PageEventBus? bus,
  ) {
    return _slotWidget(entries.first, bus, pageId);
  }

  /// absolute — 绝对定位（用 Stack + Positioned）。
  Widget _buildAbsoluteLayout(
    List<MapEntry<String, SlotDescriptor>> entries,
    LayoutPreset preset,
    String pageId,
    PageEventBus? bus,
  ) {
    return Stack(
      children: entries.map((e) {
        final style = e.value.style;
        // 从 StyleDescriptor 中读取定位属性
        final top = _styleDouble(style, 'top');
        final bottom = _styleDouble(style, 'bottom');
        final left = _styleDouble(style, 'left');
        final right = _styleDouble(style, 'right');
        return Positioned(
          top: top,
          bottom: bottom,
          left: left,
          right: right,
          child: _slotWidget(e, bus, pageId),
        );
      }).toList(),
    );
  }

  /// dock — 停靠布局（top / bottom / left / right / center）。
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

    Widget? top = _findSlot(entries, 'top', bus, pageId);
    Widget? bottom = _findSlot(entries, 'bottom', bus, pageId);
    Widget? left = _findSlot(entries, 'left', bus, pageId);
    Widget? right = _findSlot(entries, 'right', bus, pageId);

    // center: 优先匹配 center/fill/middle，否则取第一个非边缘 slot
    Widget center;
    final centerEntry = entries.where((e) =>
        e.key == 'center' || e.key == 'fill' || e.key == 'middle'
    ).firstOrNull;
    if (centerEntry != null) {
      center = _slotWidget(centerEntry, bus, pageId);
    } else {
      final fallback = entries.where((e) =>
          !['top', 'bottom', 'left', 'right'].contains(e.key)
      ).firstOrNull ?? entries.first;
      center = _slotWidget(fallback, bus, pageId);
    }

    return Column(
      children: [
        if (top != null) SizedBox(height: topH, child: top),
        Expanded(
          child: Row(
            children: [
              if (left != null) SizedBox(width: leftW, child: left),
              Expanded(child: center),
              if (right != null) SizedBox(width: rightW, child: right),
            ],
          ),
        ),
        if (bottom != null) SizedBox(height: bottomH, child: bottom),
      ],
    );
  }

  // ═══════ 辅助 ═══════

  Widget? _findSlot(List<MapEntry<String, SlotDescriptor>> entries, String key, PageEventBus? bus, String pageId) {
    final idx = entries.indexWhere((e) => e.key == key);
    return idx >= 0 ? _slotWidget(entries[idx], bus, pageId) : null;
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
}

/// Slot 调度器——根据 [ComponentDescriptor.component] 类型名分发到对应视图。
///
/// 覆盖 PLAN_NOW §四 的 53 个组件类型。已有视图直接映射，未实现组件回退到分组占位卡片。
///
/// | 分组 | 组件 | 视图 |
/// |------|------|------|
/// | **智能交互** | `ai-assistant` | [ChatView] |
/// | | `form` | [FormView] |
/// | | `code-editor` | [EditorView] |
/// | | `prompt-builder` | 占位 |
/// | **数据展示** | `data-table` / `card-list` / `kanban` | [DefaultView] |
/// | | `chart` / `stat-tile` / `timeline` | [DashboardView] |
/// | | `tree` | 占位 |
/// | | `map` | 占位 |
/// | **文档媒体** | `doc-viewer` / `doc-editor` | [DocumentView] |
/// | | `presentation` | [PresentationView] |
/// | | `spreadsheet` | [SpreadsheetView] |
/// | | `markdown` | 内置 Markdown 渲染 |
/// | | `divider` | 内置分割线 |
/// | | `video-player` / `audio-player` / `image-gallery` | 占位 |
/// | **创作工具** | `notepad` / `whiteboard` / `mindmap` / `diff-viewer` / `terminal` | 占位 |
/// | **学习专用** | `type-check` / `flashcards` / `quiz` / `crossword` / `pronunciation` | 占位 |
/// | **特殊** | `webview` / `custom` / `placeholder-*` | 占位 |
class SlotDispatch extends StatelessWidget {
  /// 栏位键名（如 `"left"`、`"right"`）。
  final String slotKey;

  /// 组件配置。
  final ComponentDescriptor config;

  /// 所属模块描述符（透传给组件视图）。
  final ModuleDescriptor moduleDescriptor;

  /// 页级事件总线（页面激活时创建，切走时销毁）。
  final PageEventBus? pageEventBus;

  /// slot 折叠/展开回调（null = 不可折叠）。
  final VoidCallback? onToggle;

  /// 当前是否处于折叠状态（仅头栏可见）。
  final bool collapsed;

  /// 是否为工具栏 chrome slot——跳过 Card 壳 + AnimatedSize，直接渲染内容。
  final bool chrome;

  const SlotDispatch({
    super.key,
    required this.slotKey,
    required this.config,
    required this.moduleDescriptor,
    this.pageEventBus,
    this.onToggle,
    this.collapsed = false,
    this.chrome = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = switch (config.type) {
        // ═══ 智能交互 (4) ═══
        'ai-assistant'            => ChatControllerView(
                                       descriptor: moduleDescriptor,
                                       embedded: true,
                                       compact: true,
                                       pageEventBus: pageEventBus,
                                       agentConfig: config.config,
                                       slotKey: slotKey,
                                     ),
        'chat'                    => ChatControllerView(
                                       descriptor: moduleDescriptor,
                                       embedded: true,
                                       compact: true,
                                       pageEventBus: pageEventBus,
                                       agentConfig: config.config,
                                       slotKey: slotKey,
                                     ),
        'form'                    => FormView(
                                       form: FormDescriptor.fromJson(config.config),
                                     ),
        'settings'                => SettingsView(descriptor: moduleDescriptor),
        'data-dashboard'          => DataDashboardView(descriptor: moduleDescriptor),
        'code-editor'             => EditorView(descriptor: moduleDescriptor, component: config),
        'prompt-builder'          => _UnknownSlot(type: config.type, config: config.config, group: '智能交互'),

        // ═══ 数据展示 (8) ═══
        'data-table'              => _DataTableSlot(config: config),
        'card-list'               => DefaultView(descriptor: moduleDescriptor),
        'chart'                   => DashboardView(descriptor: moduleDescriptor),
        'stat-tile'               => DashboardView(descriptor: moduleDescriptor),
        'kanban'                  => DefaultView(descriptor: moduleDescriptor),
        'tree'                    => _UnknownSlot(type: config.type, config: config.config, group: '数据展示'),
        'timeline'                => DashboardView(descriptor: moduleDescriptor),
        'map'                     => _MapSlot(config: config),

        // ═══ 文档与媒体 (7) ═══
        'doc-viewer'              => DocumentView(descriptor: moduleDescriptor, component: config),
        'doc-editor'              => DocumentView(descriptor: moduleDescriptor, component: config),
        'document'                => DocumentView(descriptor: moduleDescriptor, component: config),
        'video-player'            => _VideoSlot(config: config),
        'video'                   => _VideoSlot(config: config),
        'audio-player'            => _UnknownSlot(type: config.type, config: config.config, group: '文档与媒体'),
        'image-gallery'           => _UnknownSlot(type: config.type, config: config.config, group: '文档与媒体'),
        'presentation'            => PresentationView(descriptor: moduleDescriptor, component: config),
        'nav-button'              => _NavButton(
                                       label: config.config['label'] as String? ?? '',
                                       icon: config.config['icon'] as String? ?? '',
                                       target: config.config['target'] as String? ?? '',
                                       pageEventBus: pageEventBus,
                                     ),
        'button'                  => _ButtonBar(
                                       config: config.config,
                                       pageEventBus: pageEventBus,
                                     ),
        'timetable'               => _TimetableSlot(config: config),
        'markdown'                => _MarkdownSlot(markdown: _extractMarkdownContent(config.config)),

        // ═══ 创作与工具 (6) ═══
        'spreadsheet'             => SpreadsheetView(descriptor: moduleDescriptor, component: config),
        'notepad'                 => _UnknownSlot(type: config.type, config: config.config, group: '创作与工具'),
        'whiteboard'              => _UnknownSlot(type: config.type, config: config.config, group: '创作与工具'),
        'mindmap'                 => MindmapSlot(slotKey: slotKey, config: config),
        'diff-viewer'             => _UnknownSlot(type: config.type, config: config.config, group: '创作与工具'),
        'terminal'                => _UnknownSlot(type: config.type, config: config.config, group: '创作与工具'),

        // ═══ 学习专用 (5) ═══
        'type-check'              => TypeCheckSlot(
                                       slotKey: slotKey,
                                       config: config,
                                       pageEventBus: pageEventBus,
                                       moduleId: moduleDescriptor.id,
                                     ),
        'flashcards'              => FlashcardsSlot(
                                       slotKey: slotKey,
                                       config: config,
                                       pageEventBus: pageEventBus,
                                       moduleId: moduleDescriptor.id,
                                     ),
        'quiz'                    => QuizSlot(
                                       slotKey: slotKey,
                                       config: config,
                                       pageEventBus: pageEventBus,
                                       moduleId: moduleDescriptor.id,
                                     ),
        'crossword'               => _UnknownSlot(type: config.type, config: config.config, group: '学习专用'),
        'pronunciation'           => _UnknownSlot(type: config.type, config: config.config, group: '学习专用'),

        // ═══ 特殊 (2+20) ═══
        'custom'                  => _UnknownSlot(type: config.type, config: config.config, group: '特殊'),
        'webview'                 => _UnknownSlot(type: config.type, config: config.config, group: '特殊'),
        'divider'                 => const _DividerSlot(),

        // ═══ 占位组件 ═══
        'lottery-wheel'           => _LotteryWheelSlot(config: config),
        'calendar'                => _CalendarSlot(config: config),

        // 兜底（含 placeholder-01~20 归为预留扩展）
        _                         => _UnknownSlot(
                                       type: config.type,
                                       config: config.config,
                                       group: config.type.startsWith('placeholder-')
                                           ? '预留扩展'
                                           : '未知',
                                     ),
      };
    // chrome slot：跳过 Card 壳，直接渲染内容（高度约束由布局层提供）
    if (chrome || config.config['chrome'] == true) return content;
    return _buildSlotCard(context, slotKey, content);
  }

  /// 从 config 中提取 markdown 内容。
  /// 支持 `config.content` (直接文本) 或 `config.src` (文件路径，暂未实现加载)。
  static String _extractMarkdownContent(Map<String, dynamic> config) {
    if (config case {'content': String content}) return content;
    if (config case {'src': String src}) return '> 📄 文件: $src\n\n*(文件加载暂未实现)*';
    return '*无内容*\n\n在 config 中设置 `content` 字段来显示 Markdown 内容。';
  }

  /// 用 Card 包裹每个 slot 内容（对齐 HTML .evg-slot 样式，并增强视觉层次）。
  Widget _buildSlotCard(
      BuildContext context, String key, Widget content) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isCompact = config.type == 'lottery-wheel' ||
        config.type == 'calendar';

    return Card(
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.12 : 0.04),
      surfaceTintColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 对齐 HTML .evg-slot-header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                ),
              ),
            ),
            child: Row(
              children: [
                Text('📌 $key',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(config.type,
                      style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.primary)),
                ),
                const Spacer(),
                if (onToggle != null)
                  InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        collapsed ? Icons.unfold_more : Icons.unfold_less,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 对齐 HTML .evg-slot-body — 折叠时隐藏
          if (!collapsed)
            Flexible(
              fit: FlexFit.loose,
              child: content,
            ),
        ],
      ),
    );
  }
}

/// 未知组件类型的占位卡片——按分组提供有意义的提示。
class _UnknownSlot extends StatelessWidget {
  final String type;
  final Map<String, dynamic> config;
  final String group;

  const _UnknownSlot({
    required this.type,
    required this.config,
    required this.group,
  });

  /// 各分组对应的 Material Icon。
  static final Map<String, IconData> _groupIcons = {
    '智能交互': Icons.psychology,
    '数据展示': Icons.analytics,
    '文档与媒体': Icons.description,
    '创作与工具': Icons.build,
    '学习专用': Icons.school,
    '特殊': Icons.extension,
    '预留扩展': Icons.more_horiz,
    '未知': Icons.help_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _groupIcons[group] ?? Icons.help_outline;
    final color = _groupColor(group, theme);

    return Container(
      padding: const EdgeInsets.all(24),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  type,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  group,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '组件 "$type" 尚未实现渲染',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (config.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'config: ${_truncateConfig(config)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _groupColor(String group, ThemeData theme) {
    return switch (group) {
      '智能交互' => Colors.indigo,
      '数据展示' => Colors.teal,
      '文档与媒体' => Colors.blue,
      '创作与工具' => Colors.orange,
      '学习专用' => Colors.green,
      '特殊' => Colors.purple,
      '预留扩展' => theme.colorScheme.outline,
      _          => theme.colorScheme.onSurfaceVariant,
    };
  }

  String _truncateConfig(Map<String, dynamic> cfg) {
    final s = cfg.toString();
    return s.length > 80 ? '${s.substring(0, 80)}...' : s;
  }
}

/// Markdown 内容渲染——轻量实现，仅展示内容。
class _MarkdownSlot extends StatelessWidget {
  final String markdown;

  const _MarkdownSlot({required this.markdown});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.article, size: 18,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Markdown',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            markdown,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分割线组件——纯视觉分隔。
class _DividerSlot extends StatelessWidget {
  const _DividerSlot();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(height: 1),
    );
  }
}

/// 数据表格 slot——委托 [DataTableWidget] 渲染。
class _DataTableSlot extends ConsumerStatefulWidget {
  final ComponentDescriptor config;
  const _DataTableSlot({required this.config});

  @override
  ConsumerState<_DataTableSlot> createState() => _DataTableSlotState();
}

class _DataTableSlotState extends ConsumerState<_DataTableSlot> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ds = widget.config.config['dataSource'] as Map<String, dynamic>?;
    if (ds == null) {
      _rows = (widget.config.config['rows'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ?? [];
      return;
    }
    setState(() => _loading = true);
    // 重试：数据源可能尚未注册，最多等 10 秒
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        final ports = ref.read(modulePortsProvider);
        final dataPort = ports['Data'];
        final data = await _fetchFromData(ds, dataPort: dataPort);
        final dp = ds['dataPath'] as String? ?? 'data';
        final list = _extractList(data, dp);
        if (list != null) {
          _rows = list;
          _error = null;
          break;
        }
        _error = '数据格式不匹配: 期望 "$dp" 为数组';
        break;
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('未注册') && attempt < 19) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        _error = msg;
        break;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>>? _extractList(Map<String, dynamic> data, String dataPath) {
    final parts = dataPath.split('/');
    dynamic current = data;
    for (final part in parts) {
      if (current is Map<String, dynamic>) {
        current = current[part];
      } else {
        return null;
      }
    }
    if (current is List) {
      return current.map((e) => Map<String, dynamic>.from(e is Map ? e : {})).toList();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final columns = (widget.config.config['columns'] as List<dynamic>?)
            ?.map((e) {
              if (e is Map) return (e['label'] ?? e['key']).toString();
              return e.toString();
            })
            .toList() ??
        ['A', 'B', 'C'];
    final sortEnabled = widget.config.config['sortable'] == true;
    final sortable = sortEnabled ? columns : <String>[];

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildErrorView();

    return DataTableWidget(columns: columns, sortable: sortable, rows: _rows);
  }

  Widget _buildErrorView() {
    final theme = Theme.of(context);
    final ds = widget.config.config['dataSource'] as Map<String, dynamic>?;
    final typeName = ds?['name'] as String? ?? '未知';

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(
            '数据加载失败',
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          Text(
            '数据源: $typeName',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              setState(() { _loading = true; _error = null; });
              _load();
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

/// 地图 slot——委托 [MapPanel] 渲染。
class _MapSlot extends StatelessWidget {
  final ComponentDescriptor config;
  const _MapSlot({required this.config});

  @override
  Widget build(BuildContext context) {
    final map = MapDescriptor.fromJson(config.config);
    return MapPanel(map: map);
  }
}

/// 视频 slot——委托 [VideoPlayer] 渲染。
class _VideoSlot extends StatelessWidget {
  final ComponentDescriptor config;
  const _VideoSlot({required this.config});

  @override
  Widget build(BuildContext context) {
    final media = MediaDescriptor.fromJson(config.config);
    return VideoPlayer(media: media);
  }
}

/// 抽奖转盘 slot——自绘交互式转盘。
class _LotteryWheelSlot extends StatelessWidget {
  final ComponentDescriptor config;
  const _LotteryWheelSlot({required this.config});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = _parseSegments(config.config);

    if (segments.isEmpty) {
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.casino, size: 48,
                color: theme.colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('抽奖转盘', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '在 config 中设置 segments 字段',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LotteryWheel(
            segments: segments,
            size: 240,
            spinLabel: '开始抽奖',
            onResult: (seg) {
              debugPrint('[LotteryWheel] 结果: ${seg.label}');
            },
          ),
        ),
      ),
    );
  }

  List<WheelSegment> _parseSegments(Map<String, dynamic> cfg) {
    if (cfg['segments'] is List) {
      return (cfg['segments'] as List).map<WheelSegment>((s) {
        if (s is Map) {
          return WheelSegment(
            label: (s['label'] as String?) ?? '?',
            color: _parseColor(s['color']),
          );
        }
        if (s is String) {
          return WheelSegment(label: s);
        }
        return WheelSegment(label: s.toString());
      }).toList();
    }
    // 默认段
    if (cfg['labels'] is List) {
      return (cfg['labels'] as List).map<WheelSegment>((l) {
        return WheelSegment(label: l.toString());
      }).toList();
    }
    // 回退：默认选项
    return [
      const WheelSegment(label: '一等奖'),
      const WheelSegment(label: '二等奖'),
      const WheelSegment(label: '三等奖'),
      const WheelSegment(label: '参与奖'),
    ];
  }

  Color _parseColor(dynamic c) {
    if (c is String) {
      try {
        final hex = c.replaceFirst('#', '');
        return Color(int.parse('FF$hex', radix: 16));
      } catch (_) {}
    }
    return Colors.blue;
  }
}

/// 日历 slot——自绘月历组件。
class _CalendarSlot extends StatefulWidget {
  final ComponentDescriptor config;
  const _CalendarSlot({required this.config});

  @override
  State<_CalendarSlot> createState() => _CalendarSlotState();
}

class _CalendarSlotState extends State<_CalendarSlot> {
  DateTime? _selected;

  List<CalendarEvent> _parseEvents(Map<String, dynamic> cfg) {
    if (cfg['events'] is List) {
      return (cfg['events'] as List).map<CalendarEvent>((e) {
        if (e is Map) {
          final dateStr = e['date'] as String? ?? '';
          DateTime date;
          try {
            date = DateTime.parse(dateStr);
          } catch (_) {
            date = DateTime.now();
          }
          return CalendarEvent(
            date: date,
            title: (e['title'] as String?) ?? '',
            color: _parseColor(e['color']),
          );
        }
        return CalendarEvent(date: DateTime.now(), title: e.toString());
      }).toList();
    }
    return [];
  }

  Color? _parseColor(dynamic c) {
    if (c is String) {
      try {
        final hex = c.replaceFirst('#', '');
        return Color(int.parse('FF$hex', radix: 16));
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = _parseEvents(widget.config.config);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Row(
              children: [
                Icon(Icons.calendar_month, size: 18,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('日历',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            CalendarWidget(
              events: events,
              selectedDate: _selected,
              onDateSelected: (date) {
                setState(() => _selected = date);
                debugPrint('[Calendar] 选中: $date');
              },
            ),
            // 选中日期的事件列表
            if (_selected != null && events.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...events
                  .where((e) =>
                      e.date.year == _selected!.year &&
                      e.date.month == _selected!.month &&
                      e.date.day == _selected!.day)
                  .map((e) => ListTile(
                        dense: true,
                        leading: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: e.color ?? theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(e.title,
                            style: theme.textTheme.bodySmall),
                      )),
            ],
          ],
        ),
      ),
    );
  }
}

/// 导航按钮——emit `slot:switch_page:<target>` 实现页面跳转。
class _NavButton extends StatelessWidget {
  final String label;
  final String icon;
  final String target;
  final PageEventBus? pageEventBus;

  const _NavButton({
    required this.label,
    required this.icon,
    required this.target,
    this.pageEventBus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (target.isNotEmpty && pageEventBus != null) {
            pageEventBus!.emit('slot:switch_page:$target', sourceSlot: 'nav');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 32)),
              const SizedBox(height: 12),
              Text(label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

/// 按钮栏——从 config.buttons 数组渲染 Material 3 按钮，emit PageEventBus 事件。
class _ButtonBar extends StatelessWidget {
  final Map<String, dynamic> config;
  final PageEventBus? pageEventBus;

  const _ButtonBar({required this.config, this.pageEventBus});

  @override
  Widget build(BuildContext context) {
    final buttons = (config['buttons'] as List<dynamic>?) ?? [];
    if (buttons.isEmpty) return const SizedBox.shrink();

    final direction = config['direction'] as String? ?? 'row';
    final gap = (config['gap'] as num?)?.toDouble() ?? 8;

    final children = <Widget>[];
    for (final raw in buttons) {
      if (raw is! Map) continue;
      final btn = raw.cast<String, dynamic>();
      final label = btn['label'] as String?;
      final icon = btn['icon'] as String?;
      final event = btn['event'] as String? ?? '';
      final style = btn['style'] as String? ?? 'tonal';
      final onPressed = (event.isNotEmpty && pageEventBus != null)
          ? () => pageEventBus!.emit(event, sourceSlot: 'button')
          : null;

      final child = _buildButton(context, label, icon, style, onPressed);
      if (child != null) children.add(child);
    }

    if (children.isEmpty) return const SizedBox.shrink();

    if (direction == 'column') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _interleave(children, SizedBox(height: gap)),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _interleave(children, SizedBox(width: gap)),
    );
  }

  Widget? _buildButton(BuildContext context, String? label, String? icon,
      String style, VoidCallback? onPressed) {
    final theme = Theme.of(context);

    Widget? child;
    switch (style) {
      case 'filled':
        if (icon != null && label != null) {
          child = FilledButton.icon(onPressed: onPressed, icon: Text(icon), label: Text(label));
        } else if (label != null) {
          child = FilledButton(onPressed: onPressed, child: Text(label));
        } else {
          return null;
        }
      case 'outlined':
        if (icon != null && label != null) {
          child = OutlinedButton.icon(onPressed: onPressed, icon: Text(icon), label: Text(label));
        } else if (label != null) {
          child = OutlinedButton(onPressed: onPressed, child: Text(label));
        } else {
          return null;
        }
      case 'icon':
        return IconButton(
          onPressed: onPressed,
          icon: Text(icon ?? ''),
          tooltip: label,
        );
      case 'text':
        child = TextButton.icon(
          onPressed: onPressed,
          icon: icon != null ? Text(icon) : const SizedBox.shrink(),
          label: label != null ? Text(label) : const SizedBox.shrink(),
        );
      case 'tonal':
      default:
        if (icon != null && label != null) {
          child = FilledButton.tonalIcon(onPressed: onPressed, icon: Text(icon), label: Text(label));
        } else if (label != null) {
          child = FilledButton.tonal(onPressed: onPressed, child: Text(label));
        } else if (icon != null) {
          child = FilledButton.tonalIcon(onPressed: onPressed, icon: Text(icon), label: const Text(''));
        } else {
          return null;
        }
    }
    return child;
  }

  List<Widget> _interleave(List<Widget> items, Widget separator) {
    if (items.length <= 1) return items;
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) result.add(separator);
      result.add(items[i]);
    }
    return result;
  }
}

class _TimetableSlot extends ConsumerStatefulWidget {
  final ComponentDescriptor config;
  const _TimetableSlot({required this.config});

  @override
  ConsumerState<_TimetableSlot> createState() => _TimetableSlotState();
}

class _TimetableSlotState extends ConsumerState<_TimetableSlot> {
  List<TimetableSession> _sessions = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ds = widget.config.config['dataSource'] as Map<String, dynamic>?;
    if (ds == null) {
      _sessions = (widget.config.config['sessions'] as List<dynamic>?)
              ?.map((s) => TimetableSession.fromJson(s as Map<String, dynamic>))
              .toList() ?? [];
      return;
    }
    setState(() => _loading = true);
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        final ports = ref.read(modulePortsProvider);
        final dataPort = ports['Data'];
        final data = await _fetchFromData(ds, dataPort: dataPort);
        final dp = ds['dataPath'] as String? ?? 'data';
        final parts = dp.split('/');
        dynamic current = data;
        for (final part in parts) {
          if (current is Map<String, dynamic>) current = current[part];
        }
        if (current is List) {
          _sessions = current
              .whereType<Map<String, dynamic>>()
              .map((e) => TimetableSession.fromJson(e))
              .toList();
          _error = null;
        } else {
          _error = '课表数据格式错误: 期望 "$dp" 为数组';
        }
        break;
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('未注册') && attempt < 19) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        _error = msg;
        break;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildErrorView();
    return TimetableGrid(sessions: _sessions);
  }

  Widget _buildErrorView() {
    final theme = Theme.of(context);
    final ds = widget.config.config['dataSource'] as Map<String, dynamic>?;
    final typeName = ds?['name'] as String? ?? '未知';

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(
            '课表数据加载失败',
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          Text(
            '数据源: $typeName',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              setState(() { _loading = true; _error = null; });
              _load();
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

/// 从 DataHttpServer 拉取已注册数据源。
///
/// [dataPort] 为 DataHttpServer 的监听端口。传入非空值时可跳过文件探测，
/// 避免因 CWD 与项目根不一致导致的 ".data_port" 未命中问题。
Future<Map<String, dynamic>> _fetchFromData(Map<String, dynamic> ds, {int? dataPort}) async {
  // ds['name'] = data type name (registered in DataOrchestrator)
  final typeName = (ds['name'] as String?) ?? (ds['endpoint'] as String?)?.split('/').last ?? 'unknown';

  // 端口发现：优先使用传入的端口，其次尝试绝对路径，最后尝试相对路径
  int? port = dataPort;
  if (port == null || port == 0) {
    // 尝试从项目根目录读取（与 main.dart 写入位置一致）
    try {
      // 从可执行文件路径向上查找 pubspec.yaml 定位项目根
      String? projectRoot;
      var dir = Directory(p.dirname(Platform.resolvedExecutable));
      while (true) {
        if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
          projectRoot = dir.path;
          break;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      if (projectRoot != null) {
        final absPortFile = File(p.join(projectRoot, '.data_port'));
        if (await absPortFile.exists()) {
          port = int.tryParse((await absPortFile.readAsString()).trim());
        }
      }
    } catch (_) {}
  }
  if (port == null || port == 0) {
    // 最后回退：相对路径（CWD）
    try {
      final f = File('.data_port');
      if (await f.exists()) {
        port = int.tryParse((await f.readAsString()).trim());
      }
    } catch (_) {}
  }
  if (port == null || port == 0) throw Exception('数据服务未启动（找不到 .data_port）');

  final url = 'http://127.0.0.1:$port/data/types/$typeName';
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close().timeout(const Duration(seconds: 5));
    final body = await resp.transform(utf8.decoder).join();
    final decoded = (jsonDecode(body) as Map<String, dynamic>);
    // 优先检查响应体中的 error 字段（DataHttpServer 现在在 502/404 时也返回 JSON 错误体）
    if (decoded.containsKey('error')) {
      throw Exception(decoded['error'] as String? ?? '未知数据错误');
    }
    if (resp.statusCode == 404) throw Exception('数据源 "$typeName" 未注册');
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    return decoded;
  } finally {
    client.close();
  }
}
