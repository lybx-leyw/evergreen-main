/// 插件编排主视图 —— 按钮式设计器（v3）。
///
/// 对标 规划A-可视化.html 全流程，移除拖拽画布，改用按钮驱动：
///   左面板：页面管理 + Slot 列表 + 组件选择 + 属性编辑
///   右面板：CompositePreviewFrame 实时预览（走真实渲染管线）
///
/// 两阶段：
///   阶段一（蓝色，节点1-3）：数据采集向导 → 三件套产出 → 热注册 orch://<type>
///   阶段二（绿色，节点4-7）：按钮式布局编辑器
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/data/register_data_source.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

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
import 'view/component_picker.dart';
import 'view/onboarding_overlay.dart';
import 'view/page_sorter.dart';
import 'view/property_panel.dart';
import 'view/ai_generate_dialog.dart';
import 'view/data_source_capture_dialog.dart';
import 'view/data_collection_wizard.dart';
import 'widgets/composite_preview_frame.dart';
import 'widgets/plugin_icon_picker.dart';

/// Designer 阶段。
enum _DesignPhase {
  dataCollection,
  layoutEditing,
}

/// 插件编排主视图（v3 按钮式）。
///
/// 布局：
/// - 左侧（280px）：页面管理 + Slot 操作按钮 + 组件下拉选择 + 属性面板
/// - 右侧：CompositePreviewFrame 实时 Dart 渲染预览
class PluginDesignerView extends ConsumerStatefulWidget {
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
  ConsumerState<PluginDesignerView> createState() => _PluginDesignerViewState();
}

class _PluginDesignerViewState extends ConsumerState<PluginDesignerView> {
  // ── 阶段 ──
  /// v3 按钮式：默认直接进入布局编辑，数据采集通过工具栏按钮按需触发。
  _DesignPhase _designPhase = _DesignPhase.layoutEditing;

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
  bool _isSyncing = false;
  bool _hasShownOnboarding = false;
  String _statusText = '就绪';

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
    final String pluginsDir = widget.pluginsDir ?? ref.read(pluginsDirProvider);
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
      setState(() => _isSyncing = true);
      _syncService!.syncNow(_doc!);
    }
  }

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

  // ═══════════════════════════════════════════════════════════
  // 发布 / 安装
  // ═══════════════════════════════════════════════════════════

  Future<void> _publishPlugin() async {
    if (_doc == null) return;
    final String pluginsDir = widget.pluginsDir ?? ref.read(pluginsDirProvider);
    final exporter = PluginExporter(pluginsDir);

    try {
      final result = await exporter.exportToDir(_doc!);
      if (!mounted) return;

      if (result.success) {
        setState(() => _statusText = '已发布: ${result.targetPath}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('插件已发布到 ${result.targetPath}\n共 ${result.createdFiles.length} 个文件'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(label: '好的', onPressed: () {}),
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
      if (mounted) setState(() => _statusText = '发布异常: $e');
    }
  }

  String _findProjectRoot() => resolveProjectRoot() ?? Directory.current.path;

  Future<void> _installAndOpen() async {
    if (_doc == null) return;
    final String pluginsDir = widget.pluginsDir ?? ref.read(pluginsDirProvider);
    final exporter = PluginExporter(pluginsDir);

    try {
      final result = await exporter.exportToDir(_doc!);
      if (!mounted) return;

      if (!result.success) {
        setState(() => _statusText = '安装失败: ${result.error}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('安装失败: ${result.error}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      final route = _doc!.route ?? '/${_doc!.pluginId}';
      if (_doc!.route == null) {
        setState(() => _doc!.route = route);
      }

      final registry = ref.read(moduleRegistryProvider);
      final descriptor = ModuleDescriptor.fromJson(DesignToManifest.compile(_doc!));
      final ok = registry.reloadModule(descriptor);

      if (!ok) {
        setState(() => _statusText = '已导出，依赖缺失需重启');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已导出到 ${result.targetPath}\n依赖缺失，重启 Evergreen 后生效'),
          ),
        );
        return;
      }

      ref.read(moduleRegistryProvider.notifier).state = registry;

      setState(() => _statusText = '已安装并加载: $route');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('插件已安装并加载，正在打开…'),
          duration: Duration(seconds: 2),
        ),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          context.go(route);
        } catch (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已加载，可点击侧边栏入口进入')),
          );
        }
      });
    } catch (e) {
      if (mounted) setState(() => _statusText = '安装异常: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 页面操作（v3：按钮驱动）
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
    _syncService?.sync(_doc!);
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
    _syncService?.sync(_doc!);
  }

  void _selectPage(int index) {
    setState(() {
      _selectedPageIndex = index;
      _selectedSlotIndex = -1;
    });
  }

  // ═══════════════════════════════════════════════════════════
  // Slot 操作（v3：按钮驱动，无画布拖拽）
  // ═══════════════════════════════════════════════════════════

  void _addSlot() {
    final page = _currentPage;
    if (page == null) return;
    final slot = DesignSlot(
      id: 'slot_${page.slots.length}',
      label: '',
      region: _defaultRegionForLayout(page.layoutPreset, page.slots.length),
    );
    setState(() {
      page.addSlot(slot);
      _selectedSlotIndex = page.slots.length - 1;
      _doc!.touch();
      _statusText = '创建 Slot: ${slot.id}';
    });
    _syncService?.sync(_doc!);
    debugPrint('[PluginDesignerView] ➕ addSlot: ${slot.id} region=${slot.region.name}');
  }

  /// 按布局预设 + 已有 slot 数量分配默认区域。
  SlotRegion _defaultRegionForLayout(DesignPageLayout layout, int count) {
    return switch (layout) {
      DesignPageLayout.fullscreen || DesignPageLayout.flex || DesignPageLayout.absolute => SlotRegion.center,
      DesignPageLayout.dock => switch (count % 5) {
        0 => SlotRegion.top,
        1 => SlotRegion.left,
        2 => SlotRegion.center,
        3 => SlotRegion.right,
        _ => SlotRegion.bottom,
      },
      DesignPageLayout.grid => SlotRegion.center,
    };
  }

  void _removeSlot() {
    final page = _currentPage;
    if (page == null || _selectedSlotIndex < 0) return;
    final slotId = page.slots[_selectedSlotIndex].id;
    setState(() {
      page.removeSlot(slotId);
      if (_selectedSlotIndex >= page.slots.length) {
        _selectedSlotIndex = page.slots.length - 1;
      }
      _doc!.touch();
      _statusText = '删除 Slot: $slotId';
    });
    _syncService?.sync(_doc!);
    debugPrint('[PluginDesignerView] ➖ removeSlot: $slotId');
  }

  void _selectSlot(int index) {
    setState(() => _selectedSlotIndex = index);
  }

  void _setSlotComponent(String componentType) {
    final page = _currentPage;
    if (page == null || _selectedSlotIndex < 0) return;
    if (_selectedSlotIndex >= page.slots.length) return;
    setState(() {
      page.slots[_selectedSlotIndex].component = DesignComponent(
        type: componentType,
        config: {},
      );
      page.slots[_selectedSlotIndex].label = componentType;
      _doc!.touch();
      _statusText = '绑定组件: $componentType → ${page.slots[_selectedSlotIndex].id}';
    });
    _syncService?.sync(_doc!);
    debugPrint('[PluginDesignerView] 🔗 setSlotComponent: $componentType');
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

  // ═══════════════════════════════════════════════════════════
  // 阶段判定
  // ═══════════════════════════════════════════════════════════

  bool get _phase1Module => _doc != null;
  bool get _phase2Pages => _doc != null && _doc!.pages.isNotEmpty;
  bool get _phase3Slots => _doc != null && _doc!.slotCount > 0;
  bool get _phase4Components {
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

    if (_designPhase == _DesignPhase.dataCollection) {
      return _buildDataCollectionPhase();
    }

    if (_doc == null) {
      return _buildWelcomeScreen();
    }

    if (!_hasShownOnboarding) {
      _hasShownOnboarding = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showOnboardingOverlay(context);
      });
    }

    return Column(
      children: [
        _buildToolbar(),
        if (_doc!.pages.length > 1)
          PageSorter(
            pages: _doc!.pages,
            selectedIndex: _selectedPageIndex,
            onPageSelected: _selectPage,
            onPageAdded: _addPage,
            onPageDeleted: _removePage,
          ),
        // v3：两栏布局（左：操作面板，右：实时预览）— 窄屏竖排
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              if (isWide) {
                return Row(
                  children: [
                    _buildLeftPanel(),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildPreviewPanel()),
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(child: _buildLeftPanel()),
                  const Divider(height: 1),
                  Expanded(child: _buildPreviewPanel()),
                ],
              );
            },
          ),
        ),
        _buildStatusBar(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 欢迎屏 / 数据采集阶段
  // ═══════════════════════════════════════════════════════════

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

  Widget _buildDataCollectionPhase() {
    final String pluginsDir = widget.pluginsDir ?? ref.read(pluginsDirProvider);
    final orch = ref.read(dataOrchestratorProvider);
    final configServer = ref.read(configHttpServerProvider);
    final projectRoot = _findProjectRoot();

    return DataCollectionWizard(
      pluginsDir: pluginsDir,
      orch: orch,
      configServer: configServer,
      projectRoot: projectRoot,
      onCompleted: _onDataCollectionComplete,
    );
  }

  void _onDataCollectionComplete(DataCollectionResult result) {
    if (_doc == null) _createNewDocument();
    setState(() {
      _designPhase = _DesignPhase.layoutEditing;
      _statusText = '✅ 数据采集完成: orch://${result.typeName} — 开始布局';
    });
    debugPrint('[PluginDesignerView] 🔄 阶段切换: 数据采集 → 布局编辑 (orch://${result.typeName})');
  }

  void _openDataCollectionWizard() {
    final String pluginsDir = widget.pluginsDir ?? ref.read(pluginsDirProvider);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DataCollectionWizard(
          pluginsDir: pluginsDir,
          onCompleted: (result) {
            final orch = ref.read(dataOrchestratorProvider);
            final projectRoot = _findProjectRoot();
            final registered = registerDataSourcesFromManifest(
              orch: orch,
              pluginDir: result.outputDir,
              projectRoot: projectRoot,
              onlyType: result.typeName,
            );
            if (registered.contains(result.typeName)) {
              debugPrint('[PluginDesignerView] ✅ 节点2热注册 orch://${result.typeName}');
              _syncService?.sync(_doc!);
            } else {
              debugPrint('[PluginDesignerView] ⚠ 节点2注册未生效 orch://${result.typeName}');
            }
            if (mounted) {
              setState(() => _statusText = '数据采集完成: orch://${result.typeName}');
            }
          },
        ),
      ),
    );
  }

  void _openAiGenerate({DesignDocument? base}) {
    if (_doc == null) return;
    showDialog(
      context: context,
      builder: (_) => AiGenerateDialog(
        baseDoc: base,
        onGenerated: (doc) {
          setState(() {
            _doc = doc;
            _selectedPageIndex = 0;
            _selectedSlotIndex = -1;
            _statusText = base != null
                ? 'AI 已改稿: ${doc.pluginName}'
                : 'AI 已生成: ${doc.pluginName}';
          });
          _syncService?.sync(_doc!);
        },
      ),
    );
  }

  void _openAutoDataSourceCapture() {
    final slot = _selectedSlot;
    if (slot == null || _doc == null) return;
    final String pluginsDir = widget.pluginsDir ?? ref.read(pluginsDirProvider);

    final existing = ref.read(dataOrchestratorProvider).registeredTypes.toList();

    showDialog(
      context: context,
      builder: (_) => DataSourceCaptureDialog(
        doc: _doc!,
        slotId: slot.id,
        pluginsDir: pluginsDir,
        existingDataTypes: existing,
        onEndpointWritten: (endpoint) {
          final comp = slot.component;
          if (comp != null) {
            comp.config['dataSource'] = {'endpoint': endpoint};
          }
          _doc!.touch();
          _syncService?.sync(_doc!);
          if (mounted) setState(() {});
        },
        onGenerated: (type, outputDir) {
          final orch = ref.read(dataOrchestratorProvider);
          final projectRoot = _findProjectRoot();
          final registered = registerDataSourcesFromManifest(
            orch: orch,
            pluginDir: outputDir,
            projectRoot: projectRoot,
            onlyType: type,
          );
          if (registered.contains(type)) {
            debugPrint('[PluginDesignerView] ✅ 运行期热注册 orch://$type → $outputDir');
            _syncService?.sync(_doc!);
          } else {
            debugPrint('[PluginDesignerView] ⚠ 运行期注册未生效 orch://$type');
          }
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 工具栏
  // ═══════════════════════════════════════════════════════════

  Widget _buildToolbar() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(width: 12),
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
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.help_outline, size: 18),
              tooltip: '使用引导',
              onPressed: () => showOnboardingOverlay(context),
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
            IconButton(
              icon: const Icon(Icons.rocket_launch, size: 18),
              tooltip: '安装到 Evergreen 并在应用中打开',
              onPressed: _installAndOpen,
            ),
            IconButton(
              icon: const Icon(Icons.auto_awesome, size: 18),
              tooltip: '✨ AI 生成插件（自然语言描述）',
              onPressed: _openAiGenerate,
            ),
            IconButton(
              icon: const Icon(Icons.auto_fix_high, size: 18),
              tooltip: '✨ AI 改稿（基于当前设计迭代）',
              onPressed: () => _openAiGenerate(base: _doc),
            ),
            IconButton(
              icon: const Icon(Icons.wifi_find_rounded, size: 18),
              tooltip: '📡 采集数据',
              onPressed: _openDataCollectionWizard,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 左面板（v3：按钮式页面/Slot 管理 + 属性编辑）
  // ═══════════════════════════════════════════════════════════

  static const double _leftPanelWidth = 300;

  Widget _buildLeftPanel() {
    final theme = Theme.of(context);
    final page = _currentPage;

    return SizedBox(
      width: _leftPanelWidth,
      child: Container(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: theme.dividerColor)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 页面操作区 ──
              _buildPageOpsSection(theme),
              const Divider(height: 1),
              // ── 布局选择 ──
              if (page != null) _buildLayoutSelector(page),
              if (page != null) const Divider(height: 1),
              // ── Slot 操作区 ──
              if (page != null) _buildSlotOpsSection(theme, page),
              if (page != null) const Divider(height: 1),
              // ── 组件选择 + 属性编辑（有选中 Slot 时）──
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 120),
                child: _selectedSlot != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildComponentPickerSection(theme),
                          const Divider(height: 1),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 150),
                            child: _buildPropertySection(),
                          ),
                        ],
                      )
                    : _buildSlotEmptyHint(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageOpsSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.pages, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text('${_doc!.pages.length} 页',
              style: theme.textTheme.labelMedium),
          const Spacer(),
          _MiniIconBtn(icon: Icons.add, tooltip: '添加页面', onTap: _addPage),
          if (_doc!.pages.length > 1)
            _MiniIconBtn(
                icon: Icons.delete_outline,
                tooltip: '删除当前页',
                onTap: () => _removePage(_selectedPageIndex)),
        ],
      ),
    );
  }

  Widget _buildLayoutSelector(DesignPage page) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('页面布局', style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          // ── 可视化布局卡片选择器 ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: DesignPageLayout.values.map((preset) {
                final isActive = page.layoutPreset == preset;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _LayoutCard(
                    label: _layoutLabel(preset),
                    icon: _layoutIcon(preset),
                    desc: _layoutDesc(preset),
                    active: isActive,
                    onTap: () {
                      setState(() {
                        page.layoutPreset = preset;
                        _maybeResetRegions(page);
                        _doc!.touch();
                      });
                      _syncService?.sync(_doc!);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          // ── Flex 布局参数 ──
          if (page.layoutPreset == DesignPageLayout.flex) ...[
            const SizedBox(height: 8),
            _buildFlexParams(page, theme),
          ],
          // ── Grid 布局参数 ──
          if (page.layoutPreset == DesignPageLayout.grid) ...[
            const SizedBox(height: 8),
            _buildGridParams(page, theme),
          ],
          // ── Dock 布局区域提示 ──
          if (page.layoutPreset == DesignPageLayout.dock) ...[
            const SizedBox(height: 8),
            _buildDockRegionHint(page, theme),
          ],
        ],
      ),
    );
  }

  IconData _layoutIcon(DesignPageLayout p) => switch (p) {
    DesignPageLayout.fullscreen => Icons.crop_square,
    DesignPageLayout.grid => Icons.grid_view,
    DesignPageLayout.dock => Icons.dock,
    DesignPageLayout.flex => Icons.view_column,
    DesignPageLayout.absolute => Icons.move_down,
  };

  String _layoutDesc(DesignPageLayout p) => switch (p) {
    DesignPageLayout.fullscreen => '撑满全屏',
    DesignPageLayout.grid => '多列网格',
    DesignPageLayout.dock => '停靠分区',
    DesignPageLayout.flex => '弹性盒子',
    DesignPageLayout.absolute => '自由定位',
  };

  /// 弹性布局参数编辑。
  Widget _buildFlexParams(DesignPage page, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('弹性参数', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          // 方向 + Wrap
          Row(
            children: [
              Expanded(
                child: _buildFlexDropdown(
                  label: '方向',
                  value: page.flexDirection,
                  items: const [
                    ('column', '纵向'),
                    ('row', '横向'),
                  ],
                  onChanged: (v) {
                    setState(() { page.flexDirection = v; _doc!.touch(); });
                    _syncService?.sync(_doc!);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildFlexDropdown(
                  label: '间距',
                  value: page.flexGap.toStringAsFixed(0),
                  items: const [
                    ('0', '0px'), ('4', '4px'), ('8', '8px'), ('12', '12px'),
                    ('16', '16px'), ('24', '24px'),
                  ],
                  onChanged: (v) {
                    setState(() { page.flexGap = double.tryParse(v) ?? 8; _doc!.touch(); });
                    _syncService?.sync(_doc!);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 主轴对齐 + 交叉轴对齐
          Row(
            children: [
              Expanded(
                child: _buildFlexDropdown(
                  label: '主轴对齐',
                  value: page.flexJustify,
                  items: const [
                    ('start', '左/上'), ('center', '居中'), ('end', '右/下'),
                    ('between', '两端'), ('around', '环绕'), ('evenly', '均布'),
                  ],
                  onChanged: (v) {
                    setState(() { page.flexJustify = v; _doc!.touch(); });
                    _syncService?.sync(_doc!);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildFlexDropdown(
                  label: '交叉轴',
                  value: page.flexAlign,
                  items: const [
                    ('start', '左/上'), ('center', '居中'), ('end', '右/下'), ('stretch', '拉伸'),
                  ],
                  onChanged: (v) {
                    setState(() { page.flexAlign = v; _doc!.touch(); });
                    _syncService?.sync(_doc!);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 换行开关
          Row(
            children: [
              Text('自动换行', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const Spacer(),
              Switch(
                value: page.flexWrap,
                onChanged: (v) {
                  setState(() { page.flexWrap = v; _doc!.touch(); });
                  _syncService?.sync(_doc!);
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 网格布局参数编辑。
  Widget _buildGridParams(DesignPage page, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('网格参数', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildFlexDropdown(
                  label: '列数',
                  value: page.gridColumns.toString(),
                  items: List.generate(12, (i) => ('${i + 1}', '${i + 1} 列')),
                  onChanged: (v) {
                    setState(() { page.gridColumns = int.tryParse(v) ?? 1; _doc!.touch(); });
                    _syncService?.sync(_doc!);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildFlexDropdown(
                  label: '间距',
                  value: page.gridGap.toStringAsFixed(0),
                  items: const [
                    ('0', '0px'), ('8', '8px'), ('12', '12px'), ('16', '16px'),
                    ('24', '24px'), ('32', '32px'),
                  ],
                  onChanged: (v) {
                    setState(() { page.gridGap = double.tryParse(v) ?? 16; _doc!.touch(); });
                    _syncService?.sync(_doc!);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 紧凑下拉选择器（用于 flex/grid 参数编辑）。
  Widget _buildFlexDropdown({
    required String label,
    required String value,
    required List<(String, String)> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: items.any((e) => e.$1 == value) ? value : items.first.$1,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 10),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      ),
      style: const TextStyle(fontSize: 11),
      items: items.map((e) => DropdownMenuItem(
        value: e.$1,
        child: Text(e.$2, style: const TextStyle(fontSize: 11)),
      )).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }

  /// Dock 布局区域占用提示。
  Widget _buildDockRegionHint(DesignPage page, ThemeData theme) {
    // 统计每个区域的 slot 数量
    final occupied = <String, int>{};
    for (final s in page.slots) {
      occupied[s.region.name] = (occupied[s.region.name] ?? 0) + 1;
    }
    final regions = ['top', 'left', 'center', 'right', 'bottom'];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('停靠区域', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          // 可视化 mini Dock 面板
          SizedBox(
            height: 64,
            child: Column(
              children: [
                // top
                _dockRegionBar(regions[0], occupied[regions[0]] ?? 0, theme),
                Expanded(
                  child: Row(
                    children: [
                      // left
                      _dockRegionBar(regions[1], occupied[regions[1]] ?? 0, theme,
                          vertical: true),
                      // center
                      Expanded(
                        child: _dockRegionBar(regions[2], occupied[regions[2]] ?? 0, theme,
                            isCenter: true),
                      ),
                      // right
                      _dockRegionBar(regions[3], occupied[regions[3]] ?? 0, theme,
                          vertical: true),
                    ],
                  ),
                ),
                // bottom
                _dockRegionBar(regions[4], occupied[regions[4]] ?? 0, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dockRegionBar(String name, int count, ThemeData theme, {
    bool vertical = false,
    bool isCenter = false,
  }) {
    final hasSlot = count > 0;
    final color = hasSlot
        ? theme.colorScheme.primary.withValues(alpha: 0.6)
        : Colors.grey.shade300;
    return Tooltip(
      message: '$name: ${hasSlot ? "$count 个 Slot" : "空"}',
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
        width: vertical ? 16 : null,
        height: vertical ? null : 10,
        alignment: Alignment.center,
        child: hasSlot
            ? Text('$count',
                style: TextStyle(
                  fontSize: 8,
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ))
            : null,
      ),
    );
  }

  /// 切换布局预设时重置 slot 区域为合理默认值。
  void _maybeResetRegions(DesignPage page) {
    for (var i = 0; i < page.slots.length; i++) {
      page.slots[i].region = _defaultRegionForLayout(page.layoutPreset, i);
    }
  }

  String _layoutLabel(DesignPageLayout p) => switch (p) {
    DesignPageLayout.fullscreen => '全屏',
    DesignPageLayout.grid => '网格',
    DesignPageLayout.dock => '停靠',
    DesignPageLayout.flex => '弹性',
    DesignPageLayout.absolute => '自由',
  };

  Widget _buildSlotOpsSection(ThemeData theme, DesignPage page) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.widgets, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('${page.slots.length} 个 Slot',
                  style: theme.textTheme.labelMedium),
              const Spacer(),
              _MiniIconBtn(icon: Icons.add, tooltip: '添加 Slot', onTap: _addSlot),
              if (_selectedSlotIndex >= 0)
                _MiniIconBtn(
                    icon: Icons.delete_outline,
                    tooltip: '删除选中 Slot',
                    onTap: _removeSlot),
            ],
          ),
          if (page.slots.isNotEmpty) ...[
            const SizedBox(height: 4),
            // Slot 快速选择列表
            SizedBox(
              height: 32 * page.slots.length.clamp(1, 5).toDouble(),
              child: ListView.builder(
                itemCount: page.slots.length,
                itemExtent: 32,
                itemBuilder: (_, i) {
                  final slot = page.slots[i];
                  final isSelected = i == _selectedSlotIndex;
                  final hasComponent = slot.component != null;
                  return InkWell(
                    onTap: () => _selectSlot(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                            : null,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hasComponent ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 14,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              hasComponent
                                  ? '${slot.label} [${slot.region.name}]'
                                  : '${slot.id} [${slot.region.name}]',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSlotEmptyHint() {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_circle_outline, size: 36, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            const Text('点击 "+" 添加 Slot\n然后选择组件类型',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildComponentPickerSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.extension, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('选择组件类型', style: theme.textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: DropdownButtonFormField<String>(
              value: _selectedSlot?.component?.type ?? '',
              isExpanded: true,
              decoration: InputDecoration(
                hintText: '点击选择组件...',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              style: const TextStyle(fontSize: 12),
              items: [
                const DropdownMenuItem(value: '', child: Text('(未绑定)')),
                ...allDesignerComponents.map((c) => DropdownMenuItem(
                      value: c.type,
                      child: Row(
                        children: [
                          Icon(c.icon, size: 14),
                          const SizedBox(width: 6),
                          Text(c.label, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    )),
              ],
              onChanged: (v) {
                if (v != null && v.isNotEmpty) {
                  _setSlotComponent(v);
                } else if (v != null && v.isEmpty) {
                  _onComponentConfigChanged(null, {});
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _onSelectDataSource(String type) {
    final slot = _selectedSlot;
    if (slot?.component == null) return;
    setState(() {
      slot!.component!.config['dataSource'] = {'endpoint': 'orch://$type'};
      _doc!.touch();
      _statusText = '已嵌入数据源: orch://$type';
    });
    _syncService?.sync(_doc!);
    debugPrint('[PluginDesignerView] 📡 嵌入数据源: orch://$type → ${slot!.id}');
  }

  /// 更新 dataSource.dataPath —— 指定 JSON 键路径。
  ///
  /// 空字符串或 null 时移除 dataPath，即使用全量数据。
  void _onUpdateDataPath(String path) {
    final slot = _selectedSlot;
    if (slot?.component == null) return;
    final ds = slot!.component!.config['dataSource'] as Map<String, dynamic>?;
    if (ds == null) return;
    if (path.isEmpty) {
      ds.remove('dataPath');
      debugPrint('[PluginDesignerView] 🗑 移除 dataPath → 使用全量数据');
    } else {
      ds['dataPath'] = path;
      debugPrint('[PluginDesignerView] 📍 dataPath = $path');
    }
    _doc!.touch();
    _syncService?.sync(_doc!);
    setState(() {}); // 重建 PropertyPanel 以同步 _dataPathCtrl
  }

  /// 获取 orch 类型的缓存数据格式描述用于预览弹窗。
  ///
  /// 调用 DataOrchestrator.dumpDataFormat(name) 生成树状结构描述。
  /// 返回 String（格式文本），或 Map（错误信息）。
  Future<dynamic> _fetchDataPreview(String type) async {
    final orch = ref.read(dataOrchestratorProvider);
    try {
      final formatText = orch.dumpDataFormat(type);
      if (formatText == null) {
        return {'_empty': true, 'message': '该数据源暂无缓存数据'};
      }
      return formatText;
    } catch (e) {
      return {'_error': '$e'};
    }
  }

  /// 获取 orch 类型的原始 decoded JSON（结构树点选 dataPath 用）。
  ///
  /// 走 `DataOrchestrator.getByName`（缓存优先，无缓存才触发拉取）。
  /// 错误时返回 `{'_error': ...}` 哨兵 Map；无数据返回 null。
  Future<dynamic> _fetchRawData(String type) async {
    final orch = ref.read(dataOrchestratorProvider);
    try {
      final raw = await orch.getByName(type);
      debugPrint('[PluginDesignerView] 原始数据拉取: orch://$type → '
          '${raw == null ? 'null' : raw.runtimeType}');
      return raw;
    } catch (e) {
      debugPrint('[PluginDesignerView] ⚠️ 原始数据拉取失败: orch://$type → $e');
      return {'_error': '$e'};
    }
  }

  void _openDataCollectionWizardFromPanel() {
    final String pluginsDir = widget.pluginsDir ?? ref.read(pluginsDirProvider);
    final orch = ref.read(dataOrchestratorProvider);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DataCollectionWizard(
          pluginsDir: pluginsDir,
          orch: orch,
          projectRoot: _findProjectRoot(),
          onCompleted: (result) {
            final registered = registerDataSourcesFromManifest(
              orch: orch,
              pluginDir: result.outputDir,
              projectRoot: _findProjectRoot(),
              onlyType: result.typeName,
            );
            if (registered.contains(result.typeName)) {
              debugPrint('[PluginDesignerView] ✅ 采集完成 orch://${result.typeName}');
              // 自动嵌入当前选中 slot
              _onSelectDataSource(result.typeName);
            }
            if (mounted) {
              setState(() => _statusText = '数据采集完成: orch://${result.typeName}');
            }
          },
        ),
      ),
    );
  }

  Widget _buildPropertySection() {
    return PropertyPanel(
      selectedSlot: _selectedSlot,
      onSlotPropChanged: _onSlotPropChanged,
      onComponentConfigChanged: _onComponentConfigChanged,
      onSlotDeleted: _removeSlot,
      isTypeRegistered: (type) =>
          ref.read(dataOrchestratorProvider).registeredTypes.contains(type),
      onAutoGenerateDataSource: _openAutoDataSourceCapture,
      registeredTypes:
          ref.read(dataOrchestratorProvider).registeredTypes.toList(),
      onSelectDataSource: _onSelectDataSource,
      onOpenDataCollectionWizard: _openDataCollectionWizardFromPanel,
      onFetchDataPreview: _fetchDataPreview,
      onFetchRawData: _fetchRawData,
      onUpdateDataPath: _onUpdateDataPath,
      layoutPreset: _currentPage?.layoutPreset,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 右面板：实时预览
  // ═══════════════════════════════════════════════════════════

  Widget _buildPreviewPanel() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
          children: [
            // 预览标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility, size: 16,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('实时预览',
                        style: Theme.of(context).textTheme.labelMedium),
                    if (_isSyncing) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      _doc != null ? 'Dart 渲染 · ${_doc!.pages.length} 页' : '',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ),
            // 真实 CompositeView 渲染预览
            Expanded(
              child: CompositePreviewFrame(document: _doc),
            ),
          ],
        ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 底部状态栏
  // ═══════════════════════════════════════════════════════════

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
            'v3 按钮式 · 实时 Dart 渲染预览',
            style: TextStyle(fontSize: 10, color: Theme.of(context).disabledColor),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 内部组件
// ═══════════════════════════════════════════════════════════

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

/// 可视化布局选择卡片。
class _LayoutCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String desc;
  final bool active;
  final VoidCallback onTap;

  const _LayoutCard({
    required this.label,
    required this.icon,
    required this.desc,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: desc,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary
                  : Colors.grey.shade300,
              width: active ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18,
                  color: active ? theme.colorScheme.primary : Colors.grey.shade500),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    color: active ? theme.colorScheme.primary : Colors.grey.shade600,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// 插件元数据编辑对话框。
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

  static const _kIconMap = <String, IconData>{
    'home': Icons.home, 'dashboard': Icons.dashboard, 'settings': Icons.settings,
    'star': Icons.star, 'favorite': Icons.favorite, 'extension': Icons.extension,
    'widgets': Icons.widgets, 'apps': Icons.apps, 'store': Icons.store,
    'cloud': Icons.cloud, 'school': Icons.school, 'psychology': Icons.psychology,
    'science': Icons.science, 'description': Icons.description, 'code': Icons.code,
    'brush': Icons.brush, 'bar_chart': Icons.bar_chart, 'calendar_month': Icons.calendar_month,
    'map': Icons.map, 'chat': Icons.chat, 'computer': Icons.computer,
    'folder': Icons.folder, 'build': Icons.build, 'rocket_launch': Icons.rocket_launch,
    'lightbulb': Icons.lightbulb,
  };
}
