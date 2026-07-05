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
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/process_manager.dart';
import 'package:evergreen_base/core/log.dart';
import 'chat_view.dart';
import 'default_view.dart';
import 'editor_view.dart';
import 'dashboard_view.dart';
import 'form_view.dart';
import 'spreadsheet_view.dart';
import 'document_view.dart';
import 'presentation_view.dart';

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

  @override
  void initState() {
    super.initState();
    final pages = widget.descriptor.pages;
    _tabController = TabController(
      length: pages.isEmpty ? 1 : pages.length,
      vsync: this,
    );

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

  /// 启动指定页面的页面级和栏级进程。
  void _startProcessesForPage(int pageIndex, PageDescriptor page) {
    if (_processManager == null) return;
    final pm = _processManager!;
    final pageId = page.id;

    // 页面级进程
    pm.startPage(pageId, page.globalProcess);

    // 栏级进程
    for (final entry in page.slots.entries) {
      pm.startSlot(pageId, entry.key, entry.value.process);
    }

    debugPrint('[CompositeView:${widget.descriptor.id}] '
        '页面 "$pageId" 进程已启动');
  }

  /// 停止指定页面的页面级和栏级进程。
  void _stopProcessesForPage(int pageIndex, PageDescriptor page) {
    if (_processManager == null) return;
    final pm = _processManager!;
    final pageId = page.id;

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
        if (descriptor.actionButtons.isNotEmpty) _buildActionBar(),
      ],
    );
  }

  Widget _buildTabBar(List<PageDescriptor> pages) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: TabBar(
        controller: _tabController,
        isScrollable: pages.length > 4,
        tabs: pages
            .map((p) => Tab(
                  text: p.label,
                  iconMargin: EdgeInsets.zero,
                ))
            .toList(),
      ),
    );
  }

  Widget _buildPageContent(PageDescriptor page) {
    // CompositeView 的 TabBarView 已提供有界约束，
    // Slot 网格自管理 grid 排布（由 page.layout.grid 控制）。
    // 暂时跳过 LayoutEngine（drawers/search/panels/zoom）以避免
    // SingleChildScrollView + Expanded 嵌套导致的 RenderBox 布局错误。
    return _buildSlotGrid(page);
  }

  /// 按 [page.layout.grid.columns] 排布所有 slot。
  Widget _buildSlotGrid(PageDescriptor page) {
    final slots = page.slots;
    if (slots.isEmpty) {
      return const Center(child: Text('无内容'));
    }

    final slotEntries = slots.entries.toList();
    final grid = page.layout.grid;
    final columns = grid?.columns ?? 1;
    final gap = grid?.gap ?? 16;

    return SingleChildScrollView(
      padding: EdgeInsets.all(gap.toDouble()),
      child: columns == 1
          ? _buildSingleColumn(slotEntries)
          : _buildMultiColumn(slotEntries, columns, gap),
    );
  }

  Widget _buildSingleColumn(
      List<MapEntry<String, ComponentConfig>> entries) {
    return Column(
      children: entries
          .map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SlotDispatch(
                  slotKey: e.key,
                  config: e.value,
                  moduleDescriptor: widget.descriptor,
                ),
              ))
          .toList(),
    );
  }

  Widget _buildMultiColumn(
      List<MapEntry<String, ComponentConfig>> entries,
      int columns,
      int gap,
      ) {
    // 按列数分组，逐行渲染
    final rows = <List<MapEntry<String, ComponentConfig>>>[];
    for (var i = 0; i < entries.length; i += columns) {
      final end = (i + columns < entries.length) ? i + columns : entries.length;
      rows.add(entries.sublist(i, end));
    }

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: EdgeInsets.only(bottom: gap.toDouble()),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(columns, (colIndex) {
              if (colIndex >= row.length) {
                return const Expanded(child: SizedBox());
              }
              final entry = row[colIndex];
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: colIndex < columns - 1 ? gap.toDouble() : 0,
                  ),
                  child: SlotDispatch(
                    slotKey: entry.key,
                    config: entry.value,
                    moduleDescriptor: widget.descriptor,
                  ),
                ),
              );
            }),
          ),
        );
      }).toList(),
    );
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
        children: widget.descriptor.actionButtons.map((btn) {
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

/// Slot 调度器——根据 [ComponentConfig.component] 类型名分发到对应视图。
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
  final ComponentConfig config;

  /// 所属模块描述符（透传给组件视图）。
  final ModuleDescriptor moduleDescriptor;

  const SlotDispatch({
    super.key,
    required this.slotKey,
    required this.config,
    required this.moduleDescriptor,
  });

  @override
  Widget build(BuildContext context) {
    return _buildSlotCard(
      context,
      slotKey,
      switch (config.component) {
        // ═══ 智能交互 (4) ═══
        'ai-assistant'            => ChatView(descriptor: moduleDescriptor),
        'form'                    => FormView(
                                       form: FormDescriptor.fromJson(config.config),
                                     ),
        'code-editor'             => EditorView(descriptor: moduleDescriptor),
        'prompt-builder'          => _UnknownSlot(type: config.component, config: config.config, group: '智能交互'),

        // ═══ 数据展示 (8) ═══
        'data-table'              => DefaultView(descriptor: moduleDescriptor),
        'card-list'               => DefaultView(descriptor: moduleDescriptor),
        'chart'                   => DashboardView(descriptor: moduleDescriptor),
        'stat-tile'               => DashboardView(descriptor: moduleDescriptor),
        'kanban'                  => DefaultView(descriptor: moduleDescriptor),
        'tree'                    => _UnknownSlot(type: config.component, config: config.config, group: '数据展示'),
        'timeline'                => DashboardView(descriptor: moduleDescriptor),
        'map'                     => _UnknownSlot(type: config.component, config: config.config, group: '数据展示'),

        // ═══ 文档与媒体 (7) ═══
        'doc-viewer'              => DocumentView(descriptor: moduleDescriptor),
        'doc-editor'              => DocumentView(descriptor: moduleDescriptor),
        'video-player'            => _UnknownSlot(type: config.component, config: config.config, group: '文档与媒体'),
        'audio-player'            => _UnknownSlot(type: config.component, config: config.config, group: '文档与媒体'),
        'image-gallery'           => _UnknownSlot(type: config.component, config: config.config, group: '文档与媒体'),
        'presentation'            => PresentationView(descriptor: moduleDescriptor),
        'markdown'                => _MarkdownSlot(markdown: _extractMarkdownContent(config.config)),

        // ═══ 创作与工具 (6) ═══
        'spreadsheet'             => SpreadsheetView(descriptor: moduleDescriptor),
        'notepad'                 => _UnknownSlot(type: config.component, config: config.config, group: '创作与工具'),
        'whiteboard'              => _UnknownSlot(type: config.component, config: config.config, group: '创作与工具'),
        'mindmap'                 => _UnknownSlot(type: config.component, config: config.config, group: '创作与工具'),
        'diff-viewer'             => _UnknownSlot(type: config.component, config: config.config, group: '创作与工具'),
        'terminal'                => _UnknownSlot(type: config.component, config: config.config, group: '创作与工具'),

        // ═══ 学习专用 (5) ═══
        'type-check'              => _UnknownSlot(type: config.component, config: config.config, group: '学习专用'),
        'flashcards'              => _UnknownSlot(type: config.component, config: config.config, group: '学习专用'),
        'quiz'                    => _UnknownSlot(type: config.component, config: config.config, group: '学习专用'),
        'crossword'               => _UnknownSlot(type: config.component, config: config.config, group: '学习专用'),
        'pronunciation'           => _UnknownSlot(type: config.component, config: config.config, group: '学习专用'),

        // ═══ 特殊 (2+20) ═══
        'custom'                  => _UnknownSlot(type: config.component, config: config.config, group: '特殊'),
        'webview'                 => _UnknownSlot(type: config.component, config: config.config, group: '特殊'),
        'divider'                 => const _DividerSlot(),

        // 兜底（含 placeholder-01~20 归为预留扩展）
        _                         => _UnknownSlot(
                                       type: config.component,
                                       config: config.config,
                                       group: config.component.startsWith('placeholder-')
                                           ? '预留扩展'
                                           : '未知',
                                     ),
      },
    );
  }

  /// 从 config 中提取 markdown 内容。
  /// 支持 `config.content` (直接文本) 或 `config.src` (文件路径，暂未实现加载)。
  static String _extractMarkdownContent(Map<String, dynamic> config) {
    if (config case {'content': String content}) return content;
    if (config case {'src': String src}) return '> 📄 文件: $src\n\n*(文件加载暂未实现)*';
    return '*无内容*\n\n在 config 中设置 `content` 字段来显示 Markdown 内容。';
  }

  /// 用 Card 包裹每个 slot 内容，标注 slot key。
  Widget _buildSlotCard(
      BuildContext context, String key, Widget content) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: SizedBox(
        // 最小高度保证可见性
        child: content,
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
