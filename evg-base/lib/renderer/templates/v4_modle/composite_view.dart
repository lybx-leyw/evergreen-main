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
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/app/service/providers/renderer_providers.dart';
import 'package:evergreen_base/renderer/components/shared/slot_scale.dart';
// v5P Phase 1: DefaultView 作为模块级 fallback（pages 空时），保留显式 import
import 'package:evergreen_base/renderer/templates/v4_modle/components/data/card_list_slot.dart';
// v5P Phase 1: UnknownSlot 作为未注册组件的 fallback，保留显式 import
import 'package:evergreen_base/renderer/templates/v4_modle/components/placeholder/unknown_slot.dart';
// v5P Phase 1: 组件自注册表 + 集中注册入口 — 替代原有的 42 个显式 import + 62 行 switch
import 'package:evergreen_base/renderer/templates/v4_modle/slot_registry.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/_registrations.dart';
// v5P Phase 3: Schema 校验 + StylePreset 样式分离
import 'package:evergreen_base/renderer/templates/v4_modle/slot_schema.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/_schemas.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/style_preset.dart';
// v5P Gap Closure: 嵌套布局消费
import 'package:evergreen_base/renderer/templates/v4_modle/layout_engine.dart';


/// 复合视图——根据 [ModuleDescriptor.pages] 渲染多页面 Tab 界面。
///
/// 每页独立渲染其 slots：按 [LayoutPreset.columns]（V2 `layout.preset`，非旧 `layout.grid`）分栏，
/// 每栏通过 [SlotDispatch] 调度到对应组件视图。
///
/// [workingDirectory] 为模块插件目录路径（如 `plugins/vocab-tutor/`）。
/// 提供后自动管理进程生命周期；不提供时跳过进程管理（纯 UI 模式）。
class CompositeView extends ConsumerStatefulWidget {
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
  ConsumerState<CompositeView> createState() => _CompositeViewState();
}

class _CompositeViewState extends ConsumerState<CompositeView>
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

  /// 模块级 dataBindings 拉取到的数据：dataType → 行数据列表。
  /// 经 DataOrchestrator 拉取后注入 [DefaultView]，修复其恒空问题（M2 P3）。
  Map<String, List<Map<String, dynamic>>> _tableData = const {};

  @override
  void initState() {
    super.initState();

    // Gap Fix: 显式触发组件注册，避免 Dart 懒初始化陷阱。
    initV4ModleRegistrations();

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

    // ── M2 P3：模块级 dataBindings 拉取（异步，先渲染静态/空态，到位后刷新）──
    _loadModuleTableData();
  }

  @override
  void didUpdateWidget(covariant CompositeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.descriptor != widget.descriptor) {
      _loadModuleTableData();
    }
  }

  /// 按 [ModuleDescriptor.dataBindings] 经 DataOrchestrator 拉取各 dataType 行数据，
  /// 完成后 setState 注入 [DefaultView]。拉取失败的项优雅留空（R5）。
  Future<void> _loadModuleTableData() async {
    final bindings = widget.descriptor.dataBindings;
    if (bindings.isEmpty) {
      if (_tableData.isNotEmpty && mounted) setState(() => _tableData = const {});
      return;
    }
    final orch = ref.read(dataOrchestratorProvider);
    final tableData = <String, List<Map<String, dynamic>>>{};
    for (final b in bindings) {
      try {
        final t = DataType<dynamic>(
          name: b.dataType,
          category: '',
          displayName: b.dataType,
          ttl: const Duration(minutes: 5),
        );
        final rows = await orch.fastRead(t);
        if (rows is List) {
          tableData[b.dataType] = rows
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
        }
      } catch (e, st) {
        Log().warn('dataBindings 拉取失败：dataType=${b.dataType}',
            error: e, data: {'stack': st.toString()});
      }
    }
    if (!mounted) return;
    setState(() => _tableData = tableData);
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

    // Phase 4: 事件按类型订阅（保留旧格式兼容）
    if (!_pageBuses.containsKey(pageId)) {
      final bus = PageEventBus(pageId: pageId);
      _pageBuses[pageId] = bus;

      // 订阅：ui:toggle（新格式） + slot:toggle:*（旧格式兼容）
      _busSubscriptions.add(bus.on('ui:toggle').listen((evt) {
        final target = evt.data['targetSlot'] as String?;
        if (target != null && target.isNotEmpty) _toggleSlot(pageId, target);
      }));
      // 旧格式兼容：slot:toggle:<key>
      _busSubscriptions.add(bus.all.listen((evt) {
        if (evt.event.startsWith('slot:toggle:')) {
          final targetSlot = evt.event.substring('slot:toggle:'.length);
          if (targetSlot.isNotEmpty) _toggleSlot(pageId, targetSlot);
        }
      }));

      // 订阅：nav:go（新格式） + slot:switch_page:*（旧格式兼容）
      _busSubscriptions.add(bus.on('nav:go').listen((evt) {
        final target = evt.data['targetPage'] as String?;
        if (target != null && target.isNotEmpty) navigateToPage(target);
      }));
      _busSubscriptions.add(bus.all.listen((evt) {
        if (evt.event.startsWith('slot:switch_page:')) {
          final targetPage = evt.event.substring('slot:switch_page:'.length);
          if (targetPage.isNotEmpty) navigateToPage(targetPage);
        }
      }));

      // 订阅：ui:refresh
      _busSubscriptions.add(bus.on('ui:refresh').listen((_) {
        _loadModuleTableData();
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

    // 没有 pages 配置？回退到旧默认视图（M2 P3：注入模块级 dataBindings 数据）
    if (pages.isEmpty) {
      return DefaultView(descriptor: descriptor, tableData: _tableData);
    }

    // 主题已由 app.dart 经 ColorScheme 统一下发；Phase 3 注入 StylePreset。
    return Column(
      children: [
        // 页面 Tab 栏（支持按页隐藏）
        if (!_shouldHideCurrentTab(pages)) _buildTabBar(pages),
        // 页面内容 — Phase 3: StylePresetScope 注入
        Expanded(
          child: StylePresetScope(
            preset: _resolveStylePreset(descriptor),
            child: TabBarView(
              controller: _tabController,
              children: pages.map((page) => _buildPageContent(page)).toList(),
            ),
          ),
        ),
        // 动作按钮栏
        if ((descriptor.actions?.actionButtons ?? []).isNotEmpty)
          _buildActionBar(),
      ],
    );
  }

  /// Gap Closure: 从模块描述符解析 StylePreset。
  /// 优先从 manifest style.preset 取值，缺省 standard。
  StylePreset _resolveStylePreset(ModuleDescriptor descriptor) {
    final s = descriptor.style;
    if (s.gap != null) {
      // 自定义间距 → 用 manifest 值覆写 standard
      return StylePreset(
        slotPadding: s.padding ?? 12,
        slotGap: s.gap ?? 16,
        cardRadius: s.borderRadius ?? 10,
      );
    }
    return StylePreset.standard;
  }

  /// 当前页是否需要隐藏 Tab 栏。
  bool _shouldHideCurrentTab(List<PageDescriptor> pages) {
    if (_activePageIndex < 0 || _activePageIndex >= pages.length) return false;
    return pages[_activePageIndex].hideTab;
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

  /// Gap Closure: 页面内容渲染 — 递归遍历 slot 树，支持容器型 slot。
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

    // Gap Closure: 递归渲染 slot 树（自动处理容器 slot + 原子 slot）
    final content = _buildSlotTree(contentSlots, pageId, bus,
        depth: 0, parentLayout: page.layout);

    final body = toolbar == null
        ? content
        : Column(children: [
            toolbar,
            const Divider(height: 1),
            Expanded(child: content),
          ]);

    return bus != null
        ? PageEventBusScope(bus: bus!, child: body)
        : body;
  }

  // ═══════ Gap Closure: 递归 slot 树渲染 ═══════

  static const _maxNestDepth = 4;

  /// 递归渲染 slot 树：
  /// - 原子 slot → [SlotDispatch]
  /// - 容器 slot（[SlotDescriptor.isContainer]）→ [LayoutEngine] + 递归子 slot
  Widget _buildSlotTree(
    List<MapEntry<String, SlotDescriptor>> entries,
    String pageId,
    PageEventBus? bus, {
    required int depth,
    LayoutDescriptor? parentLayout,
  }) {
    if (depth >= _maxNestDepth) {
      return const Center(child: Text('布局嵌套深度超限'));
    }
    if (entries.isEmpty) return const Center(child: Text('无内容'));

    // 分离原子 slot 和容器 slot
    final atomic = <MapEntry<String, SlotDescriptor>>[];
    final containers = <MapEntry<String, SlotDescriptor>>[];
    for (final e in entries) {
      if (e.value.isContainer) {
        containers.add(e);
      } else {
        atomic.add(e);
      }
    }

    // 辅助：渲染原子 slot。
    // 直接渲染 SlotDispatch，不用 AnimatedSize：旧代码无此包装，与 LayoutBuilder+Expanded 冲突。
    Widget buildAtomic(MapEntry<String, SlotDescriptor> e) {
      final comp = e.value.component;
      if (comp == null) return const SizedBox.shrink();
      final collapsible = depth == 0 && ((comp.config['collapsible'] as bool?) ?? true);
      final visible = _isSlotVisible(pageId, e.key, e.value);
      return SlotDispatch(
        slotKey: e.key, config: comp, moduleDescriptor: widget.descriptor,
        pageEventBus: bus,
        onToggle: collapsible ? () => _toggleSlot(pageId, e.key) : null,
        collapsed: !visible,
      );
    }

    // 辅助：渲染容器 slot — 递归展开子节点
    Widget buildContainer(MapEntry<String, SlotDescriptor> e) {
      final slot = e.value;
      final childLayout = slot.layout ?? const LayoutDescriptor(type: 'flex');
      final childEntries = slot.children!
          .asMap()
          .entries
          .map((c) => MapEntry('${e.key}/${c.key}', c.value))
          .toList();

      // 容器自身有组件时先渲染自身再渲染子节点
      if (slot.component != null) {
        final own = buildAtomic(e);
        final children = _buildSlotTree(childEntries, pageId, bus,
            depth: depth + 1, parentLayout: childLayout);
        return Column(children: [own, children]);
      }

      // 纯容器：用 LayoutEngine 排布子节点
      final childSlots = <String, SlotDescriptor>{};
      for (final ce in childEntries) { childSlots[ce.key] = ce.value; }

      return LayoutEngine.build(
        type: childLayout.type,
        preset: childLayout.preset,
        slots: childSlots,
        pageId: pageId,
        moduleDescriptor: widget.descriptor,
        bus: bus,
        slotBuilder: (entry, pid, b) => buildAtomic(entry),
      );
    }

    // 全部是原子 slot → 用父级 layout 直接排布
    if (containers.isEmpty && parentLayout != null) {
      debugPrint('[SLOT_TREE] depth=$depth atomic=${atomic.length} containers=0 → LayoutEngine.build(type=${parentLayout.type})');
      final slotMap = <String, SlotDescriptor>{};
      for (final e in atomic) { slotMap[e.key] = e.value; }
      return LayoutEngine.build(
        type: parentLayout.type,
        preset: parentLayout.preset,
        slots: slotMap,
        pageId: pageId,
        moduleDescriptor: widget.descriptor,
        bus: bus,
        slotBuilder: (entry, pid, b) => buildAtomic(entry),
      );
    }

    // 混合或纯容器 → 垂直排列 (SCSV = 无限高度 → _buildSlotCardBody 走 UNBOUNDED 路径)
    // 2026-08-01: 不能在这里加 LayoutBuilder —— _buildSlotCardBody 已有一层 LB，
    // 再嵌套会触发 _debugDoingThisLayout 重入断言。黑屏修复移至 ScraperGeneratorView
    // 内部 height fallback 兜底。
    debugPrint('[SLOT_TREE] depth=$depth atomic=${atomic.length} containers=${containers.length} → FALLBACK SingleChildScrollView');
    final widgets = <Widget>[];
    for (final e in atomic) { widgets.add(buildAtomic(e)); }
    for (final e in containers) { widgets.add(buildContainer(e)); }
    return SingleChildScrollView(
      child: Column(children: widgets),
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
    );
    // 直接渲染 SlotDispatch，不用 AnimatedSize：AnimatedSize 首次布局时
    // 启动动画会重入 markNeedsLayout，与上层 LayoutBuilder 冲突导致
    // '_debugDoingThisLayout' 断言失败 → TabBarView 子页布局中断 → 黑屏。
    // 折叠状态由 SlotDispatch 的 collapsed 参数处理（同 buildAtomic 路径）。
    return dispatch;
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
      // SingleChildScrollView 在 LayoutBuilder 外层：若在 builder 内创建
      // Scrollable，会在 performLayout 阶段挂载并重入 markNeedsLayout，
      // 触发 '_debugDoingThisLayout' 断言（黑屏根因之一）。
      child: SingleChildScrollView(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final colWidth = (constraints.maxWidth - (columns - 1) * gap) / columns;
            // 滚动容器内纵向约束无限 → 行高取固定最小值（内容超高时滚动）。
            const minRowH = 220.0;
            final rowHeight = minRowH;

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

          return gridRows;
          },
        ),
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
            // manifest 中的 0-1 fraction（设计器侧 0-100% → 编译时 /100）
            // 渲染期乘以父容器尺寸转回像素。
            final topF = _styleDouble(style, 'top');
            final bottomF = _styleDouble(style, 'bottom');
            final leftF = _styleDouble(style, 'left');
            final rightF = _styleDouble(style, 'right');
            final wF = _styleDouble(style, 'width');
            final hF = _styleDouble(style, 'height');
            double? toPxW(double? fraction) =>
                fraction == null ? null : fraction * constraints.maxWidth;
            double? toPxH(double? fraction) =>
                fraction == null ? null : fraction * constraints.maxHeight;
            final top = toPxH(topF);
            final bottom = toPxH(bottomF);
            final left = toPxW(leftF);
            final right = toPxW(rightF);
            // absolute 子组件：用 style.width/height (fraction) 作为 slot 尺寸；
            // 未指定时按 Positioned(top/left) + (bottom/right) 反推；
            // 都没有则占满 Stack。
            final wD = (wF != null)
                ? wF * constraints.maxWidth
                : (left != null && right != null)
                    ? constraints.maxWidth - left - right!
                    : constraints.maxWidth;
            final hD = (hF != null)
                ? hF * constraints.maxHeight
                : (top != null && bottom != null)
                    ? constraints.maxHeight - top - bottom!
                    : constraints.maxHeight;
            return Positioned(
              top: top,
              bottom: bottom,
              left: left,
              right: right,
              width: wD,
              height: hD,
              child: ScaledSlot(
                slotWidth: wD,
                slotHeight: hD,
                scrollableH: false,
                scrollableV: false,
                // absolute 父容器（Stack + Positioned）即使给了 width/height，
                // 仍只是给子一个 tight 约束，但当 slot 内部 widget 因动画等
                // 因素退回到 unconstrained 时需要 ScaledSlot 兜底提供 tight 约束。
                // 设为 true 让 ScaledSlot 内部用 SizedBox 注入 tight 约束，
                // 避免 Column(CrossAxisAlignment.stretch)
                // 因 BoxConstraints(w=Infinity) 崩溃。
                constrain: true,
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
    final v = switch (key) {
      'width' => style.width,
      'height' => style.height,
      'top' => style.top,
      'bottom' => style.bottom,
      'left' => style.left,
      'right' => style.right,
      _ => null,
    };
    return v is num ? v.toDouble() : null;
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

// v5P Phase 1: SlotDispatch 改用 SlotRegistry 自注册机制分派
// ────────────────────────────────────────────────────────────────
// 原有 62 行 switch(config.type) 已被替换为单次 registry lookup。
// 新增组件类型只需在对应 *_slot.dart 底部调 SlotRegistry.register()，
// 无需修改此文件。
class SlotDispatch extends StatelessWidget {
  final String slotKey;
  final ComponentDescriptor config;
  final ModuleDescriptor moduleDescriptor;
  final PageEventBus? pageEventBus;
  final VoidCallback? onToggle;
  final bool collapsed;
  final bool chrome;
  const SlotDispatch({super.key, required this.slotKey, required this.config, required this.moduleDescriptor, this.pageEventBus, this.onToggle, this.collapsed = false, this.chrome = false});

  @override
  Widget build(BuildContext context) {
    final pluginsDir = ProviderScope.containerOf(context, listen: false)
        .read(pluginsDirProvider);

    // Phase 3: config schema 校验（加载期发现 manifest 配置错误）
    ensureSchemasRegistered();
    SlotSchema.from(config.type, config.config);

    // Gap Fix: lookupEnsured 首次调用时自动触发 _registrations.dart 的懒初始化
    final builder = SlotRegistryEnsure.lookupEnsured(config.type);
    final content = builder != null
        ? builder(SlotContext(
            slotKey: slotKey,
            config: config,
            moduleDescriptor: moduleDescriptor,
            pageEventBus: pageEventBus,
            pluginsDir: pluginsDir,
          ))
        : UnknownSlot(type: config.type, config: config.config,
            group: config.type.startsWith('placeholder-') ? '预留扩展' : '未知');

    if (chrome || config.config['chrome'] == true) return content;
    return _buildSlotCard(context, slotKey, content);
  }

  Widget _buildSlotCard(BuildContext context, String key, Widget content) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final s = SlotScale.of(context).scale;
    // Phase 3: 使用 StylePreset 替代硬编码间距/圆角
    final sp = StylePresetScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = EdgeInsets.only(bottom: 2 * s);
        // 无界高度（滚动容器 / 测量场景）双问题：
        // ① Card 装饰链（Clip.antiAlias + ShapeBorder）在 0<=h<=Infinity 下
        //   抛 "RenderBox was not laid out"；
        // ② 嵌套 LayoutBuilder（外层 + _buildSlotCardBody 内层）在无界
        //   relayout 时触发 Flutter 3.35 debugResetSize 断言。
        // 故无界路径**完全不用 LayoutBuilder/Card**，直接 Column(min) 直放
        // 标题栏 + 内容（标题栏保留，测试与视觉均可接受）。
        if (!constraints.maxHeight.isFinite) {
          return Container(
            margin: margin,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSlotTitleBar(context, theme, isDark, s, sp),
                content,
              ],
            ),
          );
        }
        return Container(
          margin: margin,
          child: Card(
            elevation: sp.cardElevation,
            shadowColor: Colors.black.withValues(alpha: isDark ? 0.12 : 0.04),
            surfaceTintColor: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(sp.cardRadius * s),
              side: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            child: _buildSlotCardBody(context, key, content, theme, isDark, s, sp),
          ),
        );
      },
    );
  }

  /// 标题栏（无 LayoutBuilder，供有界/无界两条路径复用）。
  Widget _buildSlotTitleBar(BuildContext context, ThemeData theme, bool isDark,
      double s, StylePreset sp) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: sp.titlePaddingH * s, vertical: sp.titlePaddingV * s),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200)),
      ),
      child: Row(children: [
        Flexible(
          child: Text('\u{1F4CC} $key',
            style: TextStyle(fontSize: 11 * s * sp.titleScale,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: 6 * s),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 1 * s),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(sp.chipRadius * s),
          ),
          child: Text(config.type,
            style: TextStyle(fontSize: 9 * s * sp.captionScale,
                color: theme.colorScheme.primary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        if (onToggle != null)
          Semantics(
            label: collapsed ? '展开 ${config.type}' : '折叠 ${config.type}',
            button: true,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(sp.chipRadius * s),
              child: Padding(
                padding: EdgeInsets.all(2 * s),
                child: Icon(collapsed ? Icons.unfold_more : Icons.unfold_less, size: 14 * s),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildSlotCardBody(BuildContext context, String key, Widget content,
      ThemeData theme, bool isDark, double s, StylePreset sp) {
    // 标题栏：与无界路径（_buildSlotCard）共用 _buildSlotTitleBar。
    final Widget titleBar = _buildSlotTitleBar(context, theme, isDark, s, sp);

    // FAIL.md 2026-07-18: LayoutBuilder 双路径——有界约束用 Column(max)+Expanded
    // 填充空间；无界约束退避到 Column(min)+直放（SCSV 内部等测量场景）。
    // 注意：AnimatedSize 已移除（见 _buildSlotWidget 注释），故 Expanded 安全。
    // DEBUG: 日志辅助定位黑屏根因——输出约束+路径选择。
    return LayoutBuilder(
      builder: (context, constraints) {
        final finiteH = constraints.maxHeight.isFinite;
        final hVal = finiteH ? constraints.maxHeight.toStringAsFixed(1) : 'Inf';
        final finiteW = constraints.maxWidth.isFinite;
        if (collapsed) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [titleBar],
          );
        }
        if (finiteH) {
          debugPrint('[SLOT_CARD] $key H=$hVal W=${finiteW ? constraints.maxWidth.toStringAsFixed(1) : "Inf"} → BOUNDED path (Column.max+Expanded)');
          return Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBar,
              Expanded(child: content),
            ],
          );
        }
        // 无界约束：Column(min)+直放，测量安全退避。
        debugPrint('[SLOT_CARD] $key H=$hVal W=${finiteW ? constraints.maxWidth.toStringAsFixed(1) : "Inf"} → UNBOUNDED path (Column.min)');
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            titleBar,
            content,
          ],
        );
      },
    );
  }
}

