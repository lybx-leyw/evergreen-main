/// 插件编排主视图 —— 三栏布局（组件面板 | 画布 | 属性编辑）。
///
/// P2/P3 实现：集成 CanvasArea / ComponentPicker / PropertyPanel / PageSorter / PreviewPanel。
library;

import 'package:flutter/material.dart';

import 'models/design_component.dart';
import 'models/design_document.dart';
import 'models/design_page.dart';
import 'models/design_slot.dart';
import 'services/auto_compile_service.dart';
import 'services/design_doc_service.dart';
import 'services/design_to_manifest.dart';
import 'services/plugin_exporter.dart';
import 'services/plugin_preloader.dart';
import 'services/preview_sync_service.dart';
import 'view/canvas_area.dart';
import 'view/component_picker.dart';
import 'view/onboarding_overlay.dart';
import 'view/page_sorter.dart';
import 'view/preview_panel.dart';
import 'view/property_panel.dart';
import 'widgets/plugin_icon_picker.dart';

/// 插件编排主视图。
///
/// 三栏布局:
/// - 左侧: 组件面板（ComponentPicker）+ 页面排序（PageSorter）
/// - 中间: 画布（CanvasArea）—— 拖拽框选 Slot、拖放组件
/// - 右侧: 属性编辑（PropertyPanel）
class PluginDesignerView extends StatefulWidget {
  final String slotKey;
  final String moduleId;
  final String? pluginsDir;

  const PluginDesignerView({
    super.key,
    required this.slotKey,
    required this.moduleId,
    this.pluginsDir,
  });

  @override
  State<PluginDesignerView> createState() => _PluginDesignerViewState();
}

class _PluginDesignerViewState extends State<PluginDesignerView> {
  // ── 数据 ──
  DesignDocument? _doc;
  int _selectedPageIndex = 0;
  int _selectedSlotIndex = -1;

  // ── 服务 ──
  DesignDocService? _docService;
  PluginPreloader? _preloader;
  PreviewSyncService? _syncService;
  AutoCompileService? _autoCompile;

  bool _initialized = false;
  bool _showPreview = false;
  bool _isSyncing = false;
  bool _hasShownOnboarding = false;
  String _statusText = '就绪';
  static const double _canvasW = 1200;
  static const double _canvasH = 900;

  // ── 选中 Slot 快捷访问 ──
  DesignSlot? get _selectedSlot {
    if (_selectedSlotIndex < 0) return null;
    final page = _currentPage;
    if (page == null) return null;
    return _selectedSlotIndex < page.slots.length
        ? page.slots[_selectedSlotIndex]
        : null;
  }

  DesignPage? get _currentPage {
    if (_doc == null) return null;
    final idx = _selectedPageIndex;
    return (idx >= 0 && idx < _doc!.pages.length)
        ? _doc!.pages[idx]
        : null;
  }

  // ═══════════════════════════════════════════════════════════
  // 生命周期
  // ═══════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  void _initServices() {
    final pluginsDir = widget.pluginsDir ?? 'plugins/';
    _docService = DesignDocService(pluginsDir);
    _preloader = PluginPreloader(pluginsDir);
    _autoCompile = AutoCompileService(pluginsDir);

    _preloader!.onChange.listen((event) {
      if (mounted) {
        setState(() => _statusText = '检测到插件变化: ${event.pluginPath}');
      }
    });

    _autoCompile!.onEvent.listen((event) {
      if (mounted) {
        setState(() => _statusText = '编译: ${event.status.name} ${event.pluginId}');
      }
    });

    _syncService = PreviewSyncService(pluginsDir, (pluginId) {
      if (mounted) {
        setState(() {
          _statusText = '已同步: $pluginId';
          _isSyncing = false;
        });
      }
    });

    _preloader!.start();
    if (mounted) setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _autoCompile?.dispose();
    _preloader?.dispose();
    _syncService?.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // 文档操作
  // ═══════════════════════════════════════════════════════════

  void _createNewDocument() {
    setState(() {
      _doc = DesignDocument(
        pluginId: 'custom-${DateTime.now().millisecondsSinceEpoch}',
        pluginName: '新插件',
      );
      _selectedPageIndex = 0;
      _selectedSlotIndex = -1;
      _statusText = '已创建新文档';
    });
  }

  Future<void> _loadExistingDocument() async {
    if (_docService == null) return;
    final ids = await _docService!.listPluginIds();
    if (ids.isEmpty || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有已保存的设计文档')),
        );
      }
      return;
    }
    final doc = await _docService!.load(ids.first);
    if (doc != null && mounted) {
      setState(() {
        _doc = doc;
        _selectedPageIndex = 0;
        _statusText = '已加载: ${doc.pluginName}';
      });
    }
  }

  Future<void> _saveDocument() async {
    if (_doc == null || _docService == null) return;
    _doc!.touch();
    await _docService!.save(_doc!);
    if (mounted) {
      setState(() => _statusText = '已保存');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设计文档已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _syncAndPreview() {
    if (_doc != null && _syncService != null) {
      setState(() {
        _isSyncing = true;
        _showPreview = true;
      });
      _syncService!.syncNow(_doc!);
    }
  }

  // ── 元数据编辑 ──

  void _showMetadataDialog() {
    if (_doc == null) return;
    showDialog(
      context: context,
      builder: (_) => _MetadataEditor(
        doc: _doc!,
        onSaved: (name, icon, desc, route, meta) {
          setState(() {
            _doc!.pluginName = name;
            _doc!.icon = icon;
            _doc!.description = desc;
            _doc!.route = route;
            _doc!.metadata.addAll(meta);
            _doc!.touch();
            _statusText = '已更新插件元数据';
          });
          _syncService?.sync(_doc!);
        },
      ),
    );
  }

  // ── 发布 ──

  Future<void> _publishPlugin() async {
    if (_doc == null) return;
    final pluginsDir = widget.pluginsDir ?? 'plugins/';
    final exporter = PluginExporter(pluginsDir);

    try {
      final result = await exporter.exportToDir(_doc!);
      if (!mounted) return;

      if (result.success) {
        setState(() => _statusText = '已发布: ${result.targetPath}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '插件已发布到 ${result.targetPath}\n共 ${result.createdFiles.length} 个文件'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: '好的',
              onPressed: () {},
            ),
          ),
        );
      } else {
        setState(() => _statusText = '发布失败: ${result.error}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发布失败: ${result.error}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusText = '发布异常: $e');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 页面操作
  // ═══════════════════════════════════════════════════════════

  void _addPage() {
    if (_doc == null) return;
    final count = _doc!.pages.length;
    final page = DesignPage(
      id: 'page_$count',
      label: '页面 ${count + 1}',
    );
    setState(() {
      _doc!.addPage(page);
      _selectedPageIndex = _doc!.pages.length - 1;
      _selectedSlotIndex = -1;
    });
  }

  void _removePage(int index) {
    if (_doc == null || _doc!.pages.length <= 1) return;
    setState(() {
      _doc!.removePage(_doc!.pages[index].id);
      if (_selectedPageIndex >= _doc!.pages.length) {
        _selectedPageIndex = _doc!.pages.length - 1;
      }
      _selectedSlotIndex = -1;
    });
  }

  void _selectPage(int index) {
    setState(() {
      _selectedPageIndex = index;
      _selectedSlotIndex = -1;
    });
  }

  // ═══════════════════════════════════════════════════════════
  // Slot 操作（画布回调）
  // ═══════════════════════════════════════════════════════════

  void _onSlotCreated(double x, double y, double w, double h) {
    final page = _currentPage;
    if (page == null) return;
    final slot = DesignSlot(
      id: 'slot_${page.slots.length}',
      rect: [x, y, w, h],
      label: '',
    );
    setState(() {
      page.addSlot(slot);
      _selectedSlotIndex = page.slots.length - 1;
      _doc!.touch();
      _statusText = '创建 Slot: ${slot.id}';
    });
    // 同步到 manifest
    _syncService?.sync(_doc!);
  }

  void _onSlotSelected(int index) {
    setState(() => _selectedSlotIndex = index);
  }

  void _onSlotMoved(int index, double dx, double dy) {
    final page = _currentPage;
    if (page == null || index >= page.slots.length) return;
    final slot = page.slots[index];
    setState(() {
      slot.rect = [
        (slot.rect[0] + dx).clamp(0, _canvasW - slot.rect[2]),
        (slot.rect[1] + dy).clamp(0, _canvasH - slot.rect[3]),
        slot.rect[2],
        slot.rect[3],
      ];
      _doc!.touch();
    });
  }

  void _onComponentDropped(int slotIndex, String componentType) {
    final page = _currentPage;
    if (page == null || slotIndex >= page.slots.length) return;
    setState(() {
      page.slots[slotIndex].component = DesignComponent(
        type: componentType,
        config: {},
      );
      page.slots[slotIndex].label = componentType;
      _selectedSlotIndex = slotIndex;
      _doc!.touch();
      _statusText = '绑定组件: $componentType → ${page.slots[slotIndex].id}';
    });
    _syncService?.sync(_doc!);
  }

  // ═══════════════════════════════════════════════════════════
  // 属性面板回调
  // ═══════════════════════════════════════════════════════════

  void _onSlotPropChanged({
    String? label,
    SlotRegion? region,
    List<double>? rect,
  }) {
    final slot = _selectedSlot;
    if (slot == null) return;
    setState(() {
      if (label != null) slot.label = label;
      if (region != null) slot.region = region;
      if (rect != null) slot.rect = rect;
      _doc!.touch();
    });
    _syncService?.sync(_doc!);
  }

  void _onComponentConfigChanged(String? type, Map<String, dynamic> config) {
    final slot = _selectedSlot;
    if (slot == null) return;
    setState(() {
      if (type == null || type.isEmpty) {
        slot.component = null;
      } else {
        slot.component = DesignComponent(type: type, config: config);
        slot.label = type;
      }
      _doc!.touch();
      _statusText = type != null ? '更新组件: $type' : '移除组件绑定';
    });
    _syncService?.sync(_doc!);
  }

  void _onComponentPickerSelect(String type) {
    // 点击左侧组件列表：如果已选中 Slot，直接绑定
    if (_selectedSlotIndex >= 0 && _selectedSlot != null) {
      _onComponentDropped(_selectedSlotIndex, type);
    } else {
      // 否则自动创建新 Slot
      final page = _currentPage;
      if (page == null) return;
      final slotCount = page.slots.length;
      final autoX = (slotCount % 3) * 220.0 + 20;
      final autoY = (slotCount ~/ 3) * 170.0 + 20;
      _onSlotCreated(autoX, autoY, 200, 150);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onComponentDropped(page.slots.length - 1, type);
      });
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 阶段判定
  // ═══════════════════════════════════════════════════════════

  bool get _phase1Module => _doc != null;                 // ① 模块已创建
  bool get _phase2Pages => _doc != null && _doc!.pages.isNotEmpty;  // ② 有页面
  bool get _phase3Slots => _doc != null && _doc!.slotCount > 0;     // ③ 有 Slot
  bool get _phase4Components {
    // ④ 至少一个 Slot 绑定了组件
    if (_doc == null) return false;
    for (final p in _doc!.pages) {
      for (final s in p.slots) {
        if (s.component != null) return true;
      }
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════
  // 构建
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_doc == null) {
      return _buildWelcomeScreen();
    }

    // 首次创建文档后自动弹出引导
    if (!_hasShownOnboarding) {
      _hasShownOnboarding = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showOnboardingOverlay(context);
      });
    }

    return Column(
      children: [
        // 工具栏
        _buildToolbar(),
        // PageSorter（页面标签栏）
        if (_doc!.pages.length > 1)
          PageSorter(
            pages: _doc!.pages,
            selectedIndex: _selectedPageIndex,
            onPageSelected: _selectPage,
            onPageAdded: _addPage,
            onPageDeleted: _removePage,
          ),
        // 三栏内容（可选四栏：含预览面板）
        Expanded(
          child: Row(
            children: [
              _buildLeftPanel(),
              _buildCanvasArea(),
              _buildRightPanel(),
              if (_showPreview)
                PreviewPanel(
                  document: _doc,
                  isRefreshing: _isSyncing,
                  width: 350,
                ),
            ],
          ),
        ),
        // 底部状态栏
        _buildStatusBar(),
      ],
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_box_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('创建或打开一个插件设计文档',
              style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createNewDocument,
            icon: const Icon(Icons.add),
            label: const Text('新建插件'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadExistingDocument,
            icon: const Icon(Icons.folder_open),
            label: const Text('打开已有设计'),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _showMetadataDialog,
            borderRadius: BorderRadius.circular(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_doc!.pluginName,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 14, color: theme.disabledColor),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${_doc!.pages.length} 页 · ${_doc!.slotCount} Slot',
              style: theme.textTheme.labelSmall),
          const Spacer(),
          // 阶段指示器（① 可点击编辑元数据）
          InkWell(
            onTap: _showMetadataDialog,
            borderRadius: BorderRadius.circular(8),
            child: _PhaseChip(label: '① 模块', active: _phase1Module),
          ),
          const SizedBox(width: 4),
          _PhaseChip(label: '② 页面', active: _phase2Pages),
          const SizedBox(width: 4),
          _PhaseChip(label: '③ Slot', active: _phase3Slots),
          const SizedBox(width: 4),
          _PhaseChip(label: '④ 组件', active: _phase4Components),
          const Spacer(),
          // 新手引导
          IconButton(
            icon: const Icon(Icons.help_outline, size: 18),
            tooltip: '使用引导',
            onPressed: () => showOnboardingOverlay(context),
          ),
          IconButton(
            icon: Icon(_showPreview ? Icons.preview : Icons.preview_outlined, size: 18),
            tooltip: _showPreview ? '关闭实时预览' : '开启实时预览',
            onPressed: () => setState(() => _showPreview = !_showPreview),
          ),
          IconButton(
            icon: const Icon(Icons.save, size: 18),
            tooltip: '保存设计文档',
            onPressed: _saveDocument,
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow, size: 18),
            tooltip: '同步到 manifest 并预览',
            onPressed: _syncAndPreview,
          ),
          IconButton(
            icon: const Icon(Icons.publish, size: 18),
            tooltip: '发布插件（导出到 plugins/ 目录）',
            onPressed: _publishPlugin,
          ),
        ],
      ),
    );
  }

  // ── 左侧面板：ComponentPicker + 页面操作 ──

  Widget _buildLeftPanel() {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Container(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: theme.dividerColor)),
        ),
        child: Column(
          children: [
            // 页面快捷操作行
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Text('第 ${_selectedPageIndex + 1}/${_doc!.pages.length} 页',
                      style: theme.textTheme.labelSmall),
                  const Spacer(),
                  _MiniIconBtn(icon: Icons.add, tooltip: '添加页面', onTap: _addPage),
                  if (_doc!.pages.length > 1)
                    _MiniIconBtn(icon: Icons.delete_outline, tooltip: '删除当前页',
                        onTap: () => _removePage(_selectedPageIndex)),
                ],
              ),
            ),
            // 组件选择器
            Expanded(
              child: ComponentPicker(
                onComponentSelected: _onComponentPickerSelect,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 中间画布 ──

  Widget _buildCanvasArea() {
    final page = _currentPage;
    if (page == null) {
      return Expanded(
        flex: 3,
        child: _buildEmptyCanvas(),
      );
    }

    return Expanded(
      flex: 3,
      child: Column(
        children: [
          // 布局预设选择器（紧凑行）
          _buildLayoutSelector(page),
          // 画布
          Expanded(
            child: CanvasArea(
              slots: page.slots,
              selectedSlotIndex: _selectedSlotIndex,
              canvasWidth: _canvasW,
              canvasHeight: _canvasH,
              onSlotSelected: _onSlotSelected,
              onSlotCreated: _onSlotCreated,
              onSlotMoved: _onSlotMoved,
              onComponentDropped: _onComponentDropped,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCanvas() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey),
          const SizedBox(height: 8),
          const Text('添加一个页面以开始编排'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _addPage,
            icon: const Icon(Icons.add),
            label: const Text('添加第一页'),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutSelector(DesignPage page) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Text('布局:', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(width: 8),
          ...LayoutPreset.values.map((preset) {
            final isActive = page.layoutPreset == preset;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text(_layoutLabel(preset), style: const TextStyle(fontSize: 11)),
                selected: isActive,
                onSelected: (_) {
                  setState(() {
                    page.layoutPreset = preset;
                    _doc!.touch();
                  });
                  _syncService?.sync(_doc!);
                },
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            );
          }),
        ],
      ),
    );
  }

  String _layoutLabel(LayoutPreset p) => switch (p) {
    LayoutPreset.fullscreen => '全屏',
    LayoutPreset.grid => '网格',
    LayoutPreset.dock => '停靠',
    LayoutPreset.flex => '弹性',
  };

  // ── 右侧面板：属性编辑 ──

  Widget _buildRightPanel() {
    return SizedBox(
      width: 240,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: PropertyPanel(
          selectedSlot: _selectedSlot,
          onSlotPropChanged: _onSlotPropChanged,
          onComponentConfigChanged: _onComponentConfigChanged,
        ),
      ),
    );
  }

  // ── 底部状态栏 ──

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Text(_statusText, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const Spacer(),
          Text(
            'P2 编排核心 · 全流程插件创作流',
            style: TextStyle(fontSize: 10, color: Theme.of(context).disabledColor),
          ),
        ],
      ),
    );
  }
}

/// 阶段指示器 Chip。
class _PhaseChip extends StatelessWidget {
  final String label;
  final bool active;
  const _PhaseChip({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active ? theme.colorScheme.primaryContainer : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: active ? theme.colorScheme.primary : Colors.grey,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}

/// 迷你图标按钮。
class _MiniIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _MiniIconBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: Colors.grey.shade600),
        ),
      ),
    );
  }
}

/// 插件元数据编辑对话框。
///
/// 编辑插件名称、图标、描述、路由、版本等信息。
/// P4 实现：点击 ① 模块 phase chip 或标题旁的编辑图标触发。
class _MetadataEditor extends StatefulWidget {
  final DesignDocument doc;
  final void Function(
    String name,
    String? icon,
    String? description,
    String? route,
    Map<String, dynamic> meta,
  ) onSaved;

  const _MetadataEditor({required this.doc, required this.onSaved});

  @override
  State<_MetadataEditor> createState() => _MetadataEditorState();
}

class _MetadataEditorState extends State<_MetadataEditor> {
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _routeCtrl;
  late TextEditingController _versionCtrl;
  late TextEditingController _authorCtrl;
  String? _iconName;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.doc.pluginName);
    _descCtrl = TextEditingController(text: widget.doc.description ?? '');
    _routeCtrl = TextEditingController(text: widget.doc.route ?? '');
    _versionCtrl = TextEditingController(
        text: (widget.doc.metadata['version'] as String?) ?? '1.0.0');
    _authorCtrl = TextEditingController(
        text: (widget.doc.metadata['author'] as String?) ?? '');
    _iconName = widget.doc.icon;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _routeCtrl.dispose();
    _versionCtrl.dispose();
    _authorCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final result = await showPluginIconPicker(context, currentIcon: _iconName);
    if (result != null && mounted) {
      setState(() => _iconName = result);
    }
  }

  IconData? get _selectedIconData {
    if (_iconName == null) return null;
    // 尝试从 Material Icons 中匹配
    return _kIconMap[_iconName] ?? Icons.widgets;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final meta = <String, dynamic>{};
    if (_versionCtrl.text.trim().isNotEmpty) {
      meta['version'] = _versionCtrl.text.trim();
    }
    if (_authorCtrl.text.trim().isNotEmpty) {
      meta['author'] = _authorCtrl.text.trim();
    }
    // 保留原有 metadata 中非版本/作者的字段
    for (final entry in widget.doc.metadata.entries) {
      if (entry.key != 'version' && entry.key != 'author') {
        meta[entry.key] = entry.value;
      }
    }
    widget.onSaved(
      _nameCtrl.text.trim(),
      _iconName,
      _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      _routeCtrl.text.trim().isEmpty ? null : _routeCtrl.text.trim(),
      meta,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('插件元数据'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 图标选择
                Center(
                  child: InkWell(
                    onTap: _pickIcon,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: _iconName != null
                          ? Icon(_selectedIconData,
                              size: 32, color: theme.colorScheme.primary)
                          : Icon(Icons.add,
                              size: 32, color: theme.disabledColor),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _pickIcon,
                  icon: const Icon(Icons.emoji_symbols, size: 16),
                  label: Text(_iconName ?? '选择图标'),
                ),
                const SizedBox(height: 12),
                // 名称
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '插件名称 *',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '名称不能为空' : null,
                ),
                const SizedBox(height: 12),
                // 描述
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: '描述',
                    hintText: '简要描述插件的功能',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                // 路由
                TextFormField(
                  controller: _routeCtrl,
                  decoration: const InputDecoration(
                    labelText: '路由',
                    hintText: '如 /my-plugin（留空自动生成）',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // 版本 + 作者
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _versionCtrl,
                        decoration: const InputDecoration(
                          labelText: '版本',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _authorCtrl,
                        decoration: const InputDecoration(
                          labelText: '作者',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  // 图标名 → IconData 映射（与 plugin_icon_picker 保持一致）
  static const _kIconMap = <String, IconData>{
    'home': Icons.home,
    'dashboard': Icons.dashboard,
    'settings': Icons.settings,
    'star': Icons.star,
    'favorite': Icons.favorite,
    'extension': Icons.extension,
    'widgets': Icons.widgets,
    'apps': Icons.apps,
    'store': Icons.store,
    'cloud': Icons.cloud,
    'school': Icons.school,
    'psychology': Icons.psychology,
    'science': Icons.science,
    'description': Icons.description,
    'code': Icons.code,
    'brush': Icons.brush,
    'bar_chart': Icons.bar_chart,
    'calendar_month': Icons.calendar_month,
    'map': Icons.map,
    'chat': Icons.chat,
    'computer': Icons.computer,
    'folder': Icons.folder,
    'build': Icons.build,
    'rocket_launch': Icons.rocket_launch,
    'lightbulb': Icons.lightbulb,
  };
}
