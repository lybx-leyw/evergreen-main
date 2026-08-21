/// html-creator 主视图 —— 三栏 IDE 编排。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/app/service/providers/renderer_providers.dart';
import 'models/html_project.dart';
import 'services/html_export_service.dart';
import 'services/data_preview_service.dart';
import 'services/canvas_manager.dart';
import 'view/data_panel.dart';
import 'view/editor_panel.dart';
import 'view/preview_panel.dart';
import 'view/ai_panel.dart';
import 'widgets/html_toolbar.dart';
import 'widgets/html_view_switch.dart';
import 'widgets/html_sidebar.dart';
import 'services/html_ai_service.dart';

class HtmlCreatorView extends ConsumerStatefulWidget {
  final ModuleDescriptor? descriptor;
  final ComponentDescriptor? component;
  final String? pluginsDir;

  const HtmlCreatorView({
    super.key,
    this.descriptor,
    this.component,
    this.pluginsDir,
  });

  @override
  ConsumerState<HtmlCreatorView> createState() => _HtmlCreatorViewState();
}

class _HtmlCreatorViewState extends ConsumerState<HtmlCreatorView> {
  late HtmlProject _project;
  late DataPreviewService _dataService;
  late HtmlAiService _aiService;
  late CanvasManager _canvasMgr;
  final _htmlController = TextEditingController();
  final _cssController = TextEditingController();
  final _jsController = TextEditingController();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  String? _selectedDataSource;

  String _previewHtml = '';
  bool _useExportedPreview = false;
  String? _pluginsRoot;

  String? _currentCanvasId;
  List<CanvasMeta> _canvases = [];

  /// 当前画板绑定的实例 ID（I1：画板 ↔ 实例 1:1，实例 ID == 插件 ID）。
  String? _currentInstanceId;

  /// 各画板当前实例快照（key = 画板 id；左侧栏「画板树/实例」视图用，
  /// 列表/加载/改名后显式刷新，避免每次 build 读盘）。
  final Map<String, InstanceMeta> _instancesByBoard = {};

  /// 自动保存 debounce Timer。
  Timer? _autoSaveTimer;

  /// 竖版窄屏：当前激活的 Tab（0=数据 1=编辑 2=预览 3=AI）。默认编辑。
  int _narrowTab = 1;

  // ═══════ T2 · 布局重排状态 ═══════

  /// 宽屏布局模式（三栏 / 双栏 / 全宽预览），持久化到 SharedPreferences。
  HtmlLayoutMode _layoutMode = HtmlLayoutMode.ide;

  /// 编辑器占（编辑+预览）合计宽度的比例（可拖拽，0.3~0.7，默认 0.5）。
  double _editorRatio = 0.5;

  /// I2：统一左栏宽度（可拖拽，180~320dp，默认 220）。
  double _sidebarWidth = 220;

  /// PreviewPanel 全局保活 key：跨布局模式/宽窄屏切换不销毁 WebView。
  /// 强制刷新预览时换新 key（销毁旧 State → 重建加载）。
  GlobalKey _previewGlobalKey = GlobalKey();

  /// EditorPanel / DataPanel 保活 key（保留编辑 tab 与数据缓存）。
  final GlobalKey _editorGlobalKey = GlobalKey();
  final GlobalKey _dataPanelGlobalKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _canvasMgr = CanvasManager();

    final orch = ref.read(dataOrchestratorProvider);
    _dataService = DataPreviewService(orch);
    // 始终用 pluginsDirProvider 获取正确的 plugins/ 目录（如 d:/evg-workplace/plugins/）
    _pluginsRoot = (() { try { return ref.read(pluginsDirProvider); } catch (_) { return 'plugins/'; } })();

    _initAiService(orch);

    // T2：恢复布局偏好（模式 / 分栏比例），SharedPreferences 全局持久化
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final mode = HtmlLayoutMode.values.asNameMap()[prefs.getString('html_creator_layout_mode')];
      if (mode != null) _layoutMode = mode;
      _sidebarWidth = (prefs.getDouble('html_creator_sidebar_width') ?? 220).clamp(180, 320).toDouble();
      _editorRatio = (prefs.getDouble('html_creator_editor_ratio') ?? 0.5).clamp(0.3, 0.7).toDouble();
    } catch (_) {
      // 偏好读取失败不阻塞启动
    }

    _canvases = _canvasMgr.listCanvases();
    if (_canvases.isNotEmpty) {
      _loadCanvas(_canvases.first.id);
    } else {
      // 首次使用：自动创建默认数据面板画布
      final t = _templates[0];
      final data = _canvasMgr.createCanvas(
        name: '我的数据面板',
        htmlContent: t.html, cssContent: t.css, jsContent: t.js,
      );
      // I1：首板也分配固定实例（一会话一份历史记忆从第一板生效）
      final instance = _canvasMgr.ensureInstance(data.meta.id);
      _aiService.switchCanvas(data.meta.id, instanceId: instance.id);
      _applyCanvasData(data);
      _refreshCanvasList();
      _refreshInstances();
    }

    // 监听编辑器变化 → 3 秒后自动保存
    _htmlController.addListener(_onEditorChanged);
    _cssController.addListener(_onEditorChanged);
    _jsController.addListener(_onEditorChanged);
  }

  void _initAiService(DataOrchestrator orch) {
    final wsDir = '${greenixWorkspaceDir('html-creator')}/editor';
    _aiService = HtmlAiService(ref, widget.descriptor?.id ?? 'html-creator', orch,
      workspaceDir: wsDir,
      pluginsDir: _pluginsRoot!,
    );
    // I1：会话文件按实例隔离（canvases/{boardId}/instances/{instanceId}/session.json），
    // 生命周期随画板——删除画板即删除实例与会话，不留孤儿文件。
    _aiService.resolveSessionsPath = (boardId, instanceId) =>
        instanceSessionsPath(boardId, instanceId);
    _aiService.onFileChanged = _syncFilesFromWorkspace;
    _aiService.onPluginExported = (pluginId) {
      setState(() {
        _useExportedPreview = true;
        // 换新 GlobalKey → 销毁旧 PreviewPanel State → 重载最新导出
        _previewGlobalKey = GlobalKey();
      });
    };
    // 画布 ↔ 插件 ID 绑定：首次导出确定后强制复用，避免重复导出生成多个插件
    _aiService.resolveCanvasPluginId = () {
      final cid = _currentCanvasId;
      if (cid == null) return null;
      return _canvasMgr.loadCanvas(cid)?.meta.pluginId;
    };
    _aiService.bindCanvasPluginId = (pluginId) {
      final cid = _currentCanvasId;
      if (cid == null) return;
      _canvasMgr.bindPluginId(cid, pluginId);
      // 插件 ID 即实例 ID：AI 首次导出确定插件 ID 后，同步当前实例身份。
      _aiService.rebindInstanceId(pluginId);
      _currentInstanceId = pluginId;
      _refreshInstances();
      if (mounted) setState(() {});
    };
    _aiService.resolveNavSection = () => _project.navSection;
    _aiService.awaitReview = _awaitHumanReview;
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    // dispose 期间禁止 setState / 触碰 context（mounted 此时仍为 true，
    // ScaffoldMessenger.of 会抛 "deactivated widget's ancestor"）
    _saveCanvasToDisk(notify: false, silent: true); // 最后保存一次
    _htmlController.dispose();
    _cssController.dispose();
    _jsController.dispose();
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// 编辑器内容变化 → 3 秒后自动保存。
  void _onEditorChanged() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 3), () {
      if (_currentCanvasId != null && mounted) {
        _saveCanvasToDisk(silent: true);
      }
    });
  }

  void _rebuildPreview() {
    final css = _cssController.text;
    final js = _jsController.text;
    String html = _htmlController.text;

    if (css.isNotEmpty && !html.contains('<style>')) {
      html = html.replaceFirst('</head>', '<style>\n$css\n</style>\n</head>');
    } else if (css.isEmpty && html.contains('<style>')) {
      html = html.replaceAll(RegExp(r'<style>.*?</style>', dotAll: true), '');
    }
    if (js.isNotEmpty && !html.contains('<script>')) {
      html = html.replaceFirst('</body>', '<script>\n$js\n</script>\n</body>');
    }

    setState(() {
      _previewHtml = html;
      _project.htmlContent = html;
    });
  }

  // ═══════ 画布操作 ═══════

  /// 新建画布（弹出模板选择）。
  void _newCanvas() {
    showDialog(
      context: context,
      builder: (ctx) => _NewCanvasDialog(
        onSelect: (template) {
          Navigator.pop(ctx);
          _saveCanvasToDisk(silent: true);
          final data = _canvasMgr.createCanvas(
            name: '画布 ${_canvases.length + 1}',
            htmlContent: template.html,
            cssContent: template.css,
            jsContent: template.js,
          );
          // I1：新画板创作之处即分配固定实例（实例 ID == 插件 ID）
          final instance = _canvasMgr.ensureInstance(data.meta.id);
          _aiService.switchCanvas(data.meta.id, instanceId: instance.id); // 新画板 = 新实例 = 新 AI 会话
          _applyCanvasData(data);
          _refreshCanvasList();
          _refreshInstances();
        },
      ),
    );
  }

  /// 加载画布。
  void _loadCanvas(String canvasId) {
    _saveCanvasToDisk(); // 先保存当前画布
    // I1：确保画板有固定实例（幂等；老画板首次加载自动创建实例 + 迁移旧会话）
    final instance = _ensureInstanceFor(canvasId);
    _aiService.switchCanvas(canvasId, instanceId: instance.id); // 切换 AI 会话持久化（绑定随板走）

    final data = _canvasMgr.loadCanvas(canvasId);
    if (data != null) {
      _applyCanvasData(data);
      _refreshInstances();
      // T1：切板提示——画板名 + 会话恢复态（断点续作 / 新会话）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final resumed = _aiService.restoredFromSession;
        final count = _aiService.sessionMessageCount;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            resumed
                ? '已切换到画板「${data.meta.name}」，恢复历史会话 $count 条'
                : '已切换到画板「${data.meta.name}」（新会话）',
          ),
          duration: const Duration(seconds: 1),
        ));
      });
    }
  }

  /// 保存当前画布到磁盘。
  /// [silent] 为 true 时不弹 SnackBar（自动保存用）。
  /// [notify] 为 false 时不调 setState（dispose 期间调用必须跳过，
  /// 否则触发 `_lifecycleState != defunct` 断言并污染框架状态机）。
  void _saveCanvasToDisk({bool silent = false, bool notify = true}) {
    if (_currentCanvasId == null) return;
    // 画布已被删除（删除流程先切走再删，此守卫兜底自动保存竞态），
    // 跳过保存以免 saveCanvas 重建已删目录。
    if (!_canvasMgr.hasCanvas(_currentCanvasId!)) return;
    _canvasMgr.saveCanvas(
      _currentCanvasId!,
      name: _nameController.text,
      htmlContent: _htmlController.text,
      cssContent: _cssController.text,
      jsContent: _jsController.text,
      navSection: _project.navSection,
    );
    if (notify) {
      setState(() {});
    }
    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('画布已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  /// 导出插件到 plugins/ + assets/plugins_bundle/，并热注册到侧边栏。
  void _exportPlugin() async {
    _saveCanvasToDisk();

    _project.pluginId = _idController.text;
    _project.pluginName = _nameController.text;

    final service = HtmlExportService(_pluginsRoot!, assetsBundleDir: _findAssetsBundle());
    final result = await service.export(_project);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? null : Colors.red,
      ));
      if (result.success) {
        // 绑定画布 ↔ 插件 ID：后续手动/AI 导出均复用同一插件。
        // 插件 ID 即实例 ID，绑定后同步当前实例身份与会话路径。
        final cid = _currentCanvasId;
        if (cid != null) {
          _canvasMgr.bindPluginId(cid, _project.pluginId);
          _aiService.rebindInstanceId(_project.pluginId);
          _currentInstanceId = _project.pluginId;
          _refreshInstances();
        }
        _registerToSidebar();
        setState(() {
          _useExportedPreview = true;
          // 换新 GlobalKey → 强制重载预览（加载最新导出产物）
          _previewGlobalKey = GlobalKey();
        });
      }
    }
  }

  /// 从 _pluginsRoot 向上找到 evg-base 项目根，再拼出 assets/plugins_bundle/。
  /// 不硬编码路径层级，通过向上查找 pubspec.yaml 定位。
  String? _findAssetsBundle() {
    var dir = Directory(_pluginsRoot!).parent; // plugins/ 的父目录
    while (true) {
      final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final bundle = p.join(dir.path, 'assets', 'plugins_bundle');
        debugPrint('[HtmlCreator] 📦 assetsBundle: $bundle');
        return bundle;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    debugPrint('[HtmlCreator] ⚠ 未找到 pubspec.yaml，跳过 assets_bundle');
    return null;
  }

  /// 将刚导出的插件热注册到 moduleRegistryProvider，侧边栏和路由实时可见。
  ///
  /// B1 重构：走 [ModuleRegistry.reloadModule] 正规 API（seal 后仍可用，
  /// 幂等替换同 id 模块），消除此前「重建 ModuleRegistry」的 workaround——
  /// 重建会丢失 _capabilities 能力维度，且重复导出同 id 时 register 抛
  /// 重复异常被静默吞掉，导致侧边栏不刷新。
  void _registerToSidebar() {
    try {
      final manifestPath = p.join(_pluginsRoot!, _project.pluginId, 'module', 'manifest.json');
      final manifestFile = File(manifestPath);
      if (!manifestFile.existsSync()) return;

      final manifestJson = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;

      // 1. 更新 v2ManifestProvider（manifest 快照，供外部查询）
      ref.read(v2ManifestProvider.notifier).update((current) {
        final updated = Map<String, Map<String, dynamic>>.from(current);
        updated[_project.pluginId] = manifestJson;
        return updated;
      });

      // 2. reloadModule 正规 API：同 id 移除旧 + 追加新（保持 seal 状态，
      //    能力维度不受影响）；StateProvider 赋值无条件通知监听方重建。
      final descriptor = ModuleDescriptor.fromJson(manifestJson);
      final registry = ref.read(moduleRegistryProvider);
      final ok = registry.reloadModule(descriptor);
      if (ok) {
        ref.read(moduleRegistryProvider.notifier).state = registry;
        debugPrint('[HtmlCreator] 🔗 热注册到侧边栏: ${_project.pluginId} (reloadModule)');
      } else {
        debugPrint('[HtmlCreator] ⚠ 热注册被拒绝（依赖缺失）: ${_project.pluginId}');
      }
    } catch (e) {
      debugPrint('[HtmlCreator] ⚠ 热注册失败: $e');
    }
  }

  /// 删除当前画布。
  void _deleteCurrentCanvas() {
    if (_currentCanvasId == null) return;
    _deleteCanvas(_currentCanvasId!);
  }

  /// 删除画布（I2 统一入口：工具栏 / 左栏删除按钮共用）。
  ///
  /// 顺序保证：若删除的是当前画板，**先切到别的画板再删**——
  /// 避免删除后 _loadCanvas 内的 _saveCanvasToDisk 重建已删目录
  /// （saveCanvas 会自动 createSync 目录，会把刚删的画板复活）。
  void _deleteCanvas(String canvasId) {
    if (_canvases.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少保留一个画布')),
      );
      return;
    }
    if (_currentCanvasId == canvasId) {
      final target = _canvases.firstWhere((c) => c.id != canvasId).id;
      _loadCanvas(target);
    }
    _canvasMgr.deleteCanvas(canvasId); // 删画板目录 = 实例 + 会话一并清理
    _refreshCanvasList();
    _refreshInstances();
  }

  /// 重命名画布。
  void _renameCanvas(String newName) {
    if (_currentCanvasId == null || newName.trim().isEmpty) return;
    _canvasMgr.renameCanvas(_currentCanvasId!, newName.trim());
    _nameController.text = newName.trim();
    _refreshCanvasList();
  }

  /// 重命名画布（左栏回调：画板 id + 新名，可重命名非当前画板）。
  void _renameCanvasById(String canvasId, String newName) {
    if (newName.trim().isEmpty) return;
    _canvasMgr.renameCanvas(canvasId, newName.trim());
    if (canvasId == _currentCanvasId) {
      _nameController.text = newName.trim();
    }
    _refreshCanvasList();
    setState(() {});
  }

  /// 重命名实例（左栏回调：实例 id + 新名；实例 ID == 插件 ID，改名不丢会话）。
  void _renameInstance(String instanceId, String newName) {
    String? boardId;
    for (final e in _instancesByBoard.entries) {
      if (e.value.id == instanceId) {
        boardId = e.key;
        break;
      }
    }
    if (boardId == null) return;
    _canvasMgr.renameInstance(boardId, instanceId, newName);
    _refreshInstances();
    setState(() {});
  }

  /// 确保画板有固定实例（幂等；返回当前实例并同步视图状态）。
  InstanceMeta _ensureInstanceFor(String boardId) {
    final instance = _canvasMgr.ensureInstance(boardId);
    _currentInstanceId = instance.id;
    return instance;
  }

  /// 刷新各画板实例快照（列表/加载/改名/删除后调用）。
  void _refreshInstances() {
    _instancesByBoard.clear();
    for (final c in _canvases) {
      final instance = _canvasMgr.tryLoadInstanceOf(c.id);
      if (instance != null) {
        _instancesByBoard[c.id] = instance;
      }
    }
    final cur = _currentCanvasId;
    if (cur != null) {
      _currentInstanceId = _instancesByBoard[cur]?.id;
    }
  }

  void _applyCanvasData(CanvasData data) {
    _currentCanvasId = data.meta.id;
    // I1：画板 ↔ 实例 1:1——实例 id 从 meta 锚点读回（实例 ID == 插件 ID）
    _currentInstanceId = data.meta.instanceId;
    _nameController.text = data.meta.name;
    // T1：恢复画布绑定的数据源（切板后 AI 上下文/数据面板随板恢复）
    _selectedDataSource = data.meta.selectedDataSource;
    // 画布已绑定插件 ID 时复用绑定值，否则由画布名派生
    _idController.text = data.meta.pluginId ?? _sanitizeId(data.meta.name);
    _htmlController.text = data.htmlContent;
    _cssController.text = data.cssContent;
    _jsController.text = data.jsContent;
    _project = HtmlProject(
      pluginId: _idController.text,
      pluginName: data.meta.name,
      htmlContent: data.htmlContent,
      navSection: data.meta.navSection,
    );
    _useExportedPreview = false;
    _rebuildPreview();
  }

  void _refreshCanvasList() {
    _canvases = _canvasMgr.listCanvases();
  }

  String _sanitizeId(String name) {
    final id = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-]'), '-').replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return id.isEmpty ? 'my-plugin' : id;
  }

  void _loadDataIntoEditor(String sourceName) {
    _selectedDataSource = sourceName;
    // T1：绑定随板走——写入画布 meta.json，切板/重启后自动恢复
    final cid = _currentCanvasId;
    if (cid != null) _canvasMgr.bindDataSource(cid, sourceName);
    final current = _htmlController.text;
    if (current.contains('REPLACE_WITH_SOURCE_NAME')) {
      _htmlController.text = current.replaceAll('REPLACE_WITH_SOURCE_NAME', sourceName);
      _rebuildPreview();
    }
  }

  /// 当前活跃的评判 Completer（非 null 表示正在等待评判）。
  Completer<String>? _reviewCompleter;

  /// 等待人类评判（用于 view_html_result 工具）。
  /// 非模态：在 AI 面板上方显示评判栏，用户可同时查看预览面板。
  Future<String> _awaitHumanReview() async {
    final completer = Completer<String>();
    if (!mounted) return 'PASS';
    setState(() => _reviewCompleter = completer);
    return completer.future;
  }

  void _submitReview(bool pass, String reason) {
    final c = _reviewCompleter;
    if (c == null || c.isCompleted) return;
    setState(() => _reviewCompleter = null);
    if (pass) {
      c.complete('PASS ✅ 视觉效果通过');
    } else {
      final detail = reason.trim().isNotEmpty ? reason.trim() : '视觉效果不理想';
      c.complete('FAIL ❌ $detail');
    }
  }

  /// Agent 写文件后从工作区同步回编辑器。
  void _syncFilesFromWorkspace() {
    final wsDir = '${greenixWorkspaceDir('html-creator')}/editor';
    try {
      final htmlFile = File(p.join(wsDir, 'index.html'));
      final cssFile = File(p.join(wsDir, 'style.css'));
      final jsFile = File(p.join(wsDir, 'script.js'));

      if (htmlFile.existsSync()) {
        final html = htmlFile.readAsStringSync();
        if (html != _htmlController.text) {
          _htmlController.text = html;
        }
      }
      if (cssFile.existsSync()) {
        final css = cssFile.readAsStringSync();
        if (css != _cssController.text) {
          _cssController.text = css;
        }
      }
      if (jsFile.existsSync()) {
        final js = jsFile.readAsStringSync();
        if (js != _jsController.text) {
          _jsController.text = js;
        }
      }
      _rebuildPreview();
    } catch (e) {
      debugPrint('[HtmlCreator] 同步工作区失败: $e');
    }
  }

  /// AI 生成回调（文本模式兼容）。
  void _onAiGenerated({String? html, String? css, String? js}) {
    if (html != null) _htmlController.text = html;
    if (css != null) _cssController.text = css;
    if (js != null) _jsController.text = js;
    _rebuildPreview();
  }

  @override
  Widget build(BuildContext context) {
    // 窄屏（手机/小窗）：三栏放不下 → 数据/编辑/预览单栏 Tab 切换，避免 RenderFlex 溢出。
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    return Scaffold(
      body: Column(
        children: [
          HtmlToolbar(
            project: _project,
            canvases: _canvases,
            currentCanvasId: _currentCanvasId,
            onPluginIdChanged: (v) => _project.pluginId = v,
            onPluginNameChanged: (v) => _project.pluginName = v,
            onNavSectionChanged: (v) {
              _project.navSection = v;
              _saveCanvasToDisk(silent: true); // 持久化到画布 meta.json
            },
            onSave: _saveCanvasToDisk,
            onExport: _exportPlugin,
            onNewCanvas: _newCanvas,
            onLoadCanvas: _loadCanvas,
            onDeleteCanvas: _deleteCurrentCanvas,
            onRenameCanvas: _renameCanvas,
            onPreviewRefresh: () {
              if (!isWide) setState(() => _narrowTab = 2);
              _rebuildPreview();
            },
            onAIGenerate: () {
              if (!isWide) setState(() => _narrowTab = 3);
            },
          ),
          // T2：宽屏布局模式切换（三栏 / 双栏 / 全宽预览，仿 scraper 视图切换）
          if (isWide)
            HtmlViewSwitch(current: _layoutMode, onChanged: _setLayoutMode),
          Expanded(
            child: isWide ? _buildWideBody() : _buildNarrowBody(),
          ),
          // 宽屏：底部 AI 面板 + 评判栏（窄屏已内置于 Tab 路线/评判分屏）
          if (isWide) ...[
            if (_reviewCompleter != null)
              _ReviewBar(
                onSubmit: _submitReview,
                onSkip: () => _submitReview(true, ''),
              ),
            SizedBox(
              height: 250,
              child: AiPanel(
                aiService: _aiService,
                htmlContent: _htmlController.text,
                cssContent: _cssController.text,
                jsContent: _jsController.text,
                selectedDataSource: _selectedDataSource,
                onGenerated: _onAiGenerated,
                instanceName: _currentInstanceName,
                instanceId: _currentInstanceId,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════ T2 · 布局模式与分栏 ═══════

  /// 当前实例（AI 面板绑定态徽标用，I1）。
  InstanceMeta? get _currentInstance {
    final cid = _currentCanvasId;
    if (cid == null) return null;
    return _instancesByBoard[cid];
  }

  /// 当前实例名（AI 面板绑定态徽标用，I1）。
  String? get _currentInstanceName => _currentInstance?.name;

  /// 切换宽屏布局模式并持久化。
  void _setLayoutMode(HtmlLayoutMode mode) {
    if (mode == _layoutMode) return;
    setState(() => _layoutMode = mode);
    try {
      ref.read(sharedPreferencesProvider).setString('html_creator_layout_mode', mode.name);
    } catch (_) {}
  }

  /// 分栏比例持久化（拖拽结束后调用）。
  void _persistLayoutPrefs() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      prefs.setDouble('html_creator_sidebar_width', _sidebarWidth);
      prefs.setDouble('html_creator_editor_ratio', _editorRatio);
    } catch (_) {}
  }

  /// 宽屏（≥700dp）：统一左栏 / 编辑 / 预览 三栏 IDE 布局（I2）。
  Widget _buildWideBody() {
    // I2：数据中枢收编进统一左栏「数据源」视图（保活 key 不变）
    final sidebar = HtmlSidebar(
      canvases: _canvases,
      currentCanvasId: _currentCanvasId,
      currentInstanceId: _currentInstanceId,
      instancesByBoard: _instancesByBoard,
      onSelectCanvas: _loadCanvas,
      onNewCanvas: _newCanvas,
      onDeleteCanvas: _deleteCanvas,
      onRenameCanvas: _renameCanvasById,
      onRenameInstance: _renameInstance,
      dataPanel: DataPanel(
        key: _dataPanelGlobalKey,
        dataService: _dataService,
        onSelectSource: _loadDataIntoEditor,
        selectedSource: _selectedDataSource,
      ),
    );
    final editor = EditorPanel(
      key: _editorGlobalKey,
      htmlController: _htmlController,
      cssController: _cssController,
      jsController: _jsController,
      onChanged: _rebuildPreview,
    );
    final preview = PreviewPanel(
      key: _previewGlobalKey,
      htmlContent: _previewHtml,
      pluginId: _useExportedPreview ? _project.pluginId : null,
      pluginsDir: _useExportedPreview ? _pluginsRoot : null,
    );

    return LayoutBuilder(builder: (ctx, constraints) {
      final totalW = constraints.maxWidth;
      final editorFlex = (_editorRatio * 100).round().clamp(1, 99).toInt();
      final previewFlex = ((1 - _editorRatio) * 100).round().clamp(1, 99).toInt();

      // 可拖拽分隔条（调整相邻栏比例）
      Widget divider(void Function(double dx) onDrag) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
            onHorizontalDragEnd: (_) => _persistLayoutPrefs(),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: Container(
                width: 8,
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 1,
                    height: double.infinity,
                    color: Theme.of(ctx).dividerColor,
                  ),
                ),
              ),
            ),
          );

      switch (_layoutMode) {
        case HtmlLayoutMode.ide:
          return Row(children: [
            SizedBox(width: _sidebarWidth, child: sidebar),
            divider((dx) => setState(() {
              _sidebarWidth = (_sidebarWidth + dx).clamp(180, 320).toDouble();
            })),
            Expanded(flex: editorFlex, child: editor),
            divider((dx) => setState(() {
              _editorRatio = (_editorRatio + dx / totalW).clamp(0.3, 0.7).toDouble();
            })),
            Expanded(flex: previewFlex, child: preview),
          ]);
        case HtmlLayoutMode.split:
          return Row(children: [
            Expanded(flex: editorFlex, child: editor),
            divider((dx) => setState(() {
              _editorRatio = (_editorRatio + dx / totalW).clamp(0.3, 0.7).toDouble();
            })),
            Expanded(flex: previewFlex, child: preview),
          ]);
        case HtmlLayoutMode.preview:
          return preview;
      }
    });
  }

  /// 窄屏（<700dp）：数据 / 编辑 / 预览 / AI 单栏 Tab 切换。
  /// IndexedStack 保活：切换不销毁面板——预览 WebView 不重载、
  /// 编辑器光标/内容保留、AI 会话保留。
  ///
  /// T2 增强：AI 评判中（_reviewCompleter != null）自动切为上下分屏——
  /// 上预览、下评判栏 + AI 面板，修复「评判栏提示看右侧预览但窄屏看不到」
  /// 的体验断点。
  Widget _buildNarrowBody() {
    if (_reviewCompleter != null) {
      return Column(children: [
        Expanded(
          flex: 3,
          child: PreviewPanel(
            key: _previewGlobalKey,
            htmlContent: _previewHtml,
            pluginId: _useExportedPreview ? _project.pluginId : null,
            pluginsDir: _useExportedPreview ? _pluginsRoot : null,
          ),
        ),
        _ReviewBar(
          previewHint: '上方预览',
          onSubmit: _submitReview,
          onSkip: () => _submitReview(true, ''),
        ),
        SizedBox(
          height: 200,
          child: AiPanel(
            aiService: _aiService,
            htmlContent: _htmlController.text,
            cssContent: _cssController.text,
            jsContent: _jsController.text,
            selectedDataSource: _selectedDataSource,
            onGenerated: _onAiGenerated,
            instanceName: _currentInstanceName,
            instanceId: _currentInstanceId,
          ),
        ),
      ]);
    }
    return Column(
      children: [
        _buildNarrowTabBar(),
        Expanded(
          child: IndexedStack(
            index: _narrowTab,
            children: [
              DataPanel(
                key: _dataPanelGlobalKey,
                dataService: _dataService,
                onSelectSource: _loadDataIntoEditor,
                selectedSource: _selectedDataSource,
              ),
              EditorPanel(
                key: _editorGlobalKey,
                htmlController: _htmlController,
                cssController: _cssController,
                jsController: _jsController,
                onChanged: _rebuildPreview,
              ),
              PreviewPanel(
                key: _previewGlobalKey,
                htmlContent: _previewHtml,
                pluginId: _useExportedPreview ? _project.pluginId : null,
                pluginsDir: _useExportedPreview ? _pluginsRoot : null,
              ),
              AiPanel(
                aiService: _aiService,
                htmlContent: _htmlController.text,
                cssContent: _cssController.text,
                jsContent: _jsController.text,
                selectedDataSource: _selectedDataSource,
                onGenerated: _onAiGenerated,
                instanceName: _currentInstanceName,
                instanceId: _currentInstanceId,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 竖版窄屏 Tab 导航 ──

  /// 竖版 Tab 顺序：数据 / 编辑 / 预览 / AI。
  static const _narrowTabs = <(IconData, String)>[
    (Icons.storage, '数据'),
    (Icons.code, '编辑'),
    (Icons.visibility, '预览'),
    (Icons.auto_awesome, 'AI'),
  ];

  Widget _buildNarrowTabBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border:
            Border(bottom: BorderSide(color: scheme.outlineVariant, width: 0.5)),
      ),
      child: Row(children: [
        for (var i = 0; i < _narrowTabs.length; i++) ...[if (i > 0) const SizedBox(width: 3), Expanded(child: _buildNarrowTabItem(i))],
      ]),
    );
  }

  Widget _buildNarrowTabItem(int index) {
    final (icon, label) = _narrowTabs[index];
    final active = _narrowTab == index;
    final scheme = Theme.of(context).colorScheme;
    final fg = active ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: () => setState(() => _narrowTab = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: active ? scheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  color: fg,
                  fontWeight: active ? FontWeight.w600 : null)),
        ]),
      ),
    );
  }

  // 模板定义已移至文件末尾的 _templates / _NewCanvasDialog。

}

/// 人类评判对话框 —— 用于 view_html_result 工具。
/// 非模态评判栏 —— 嵌入 AI 面板上方，不遮挡预览。
///
/// Agent 调用 view_html_result 时显示此栏，
/// 用户可同时查看右侧预览面板后点击 PASS/FAIL。
class _ReviewBar extends StatefulWidget {
  final void Function(bool pass, String reason) onSubmit;
  final VoidCallback onSkip;

  /// 预览位置提示（宽屏「右侧预览」/ 窄屏评判分屏「上方预览」）。
  final String previewHint;

  const _ReviewBar({
    required this.onSubmit,
    required this.onSkip,
    this.previewHint = '右侧预览',
  });

  @override
  State<_ReviewBar> createState() => _ReviewBarState();
}

class _ReviewBarState extends State<_ReviewBar> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border(top: BorderSide(color: Colors.amber.shade200)),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text('👀 请查看${widget.previewHint}的渲染效果，然后评判是否通过',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 600 ? 110 : 200,
            child: TextField(
              controller: _reasonController,
              maxLines: 1,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                hintText: '不通过时填写原因...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => widget.onSubmit(true, _reasonController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: const Text('✅ 通过', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          OutlinedButton(
            onPressed: () => widget.onSubmit(false, _reasonController.text),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: const Text('❌ 不通过', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: widget.onSkip,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
            child: const Text('跳过', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

// ═══════ 模板库 ═══════

class _CanvasTemplate {
  final String name;
  final String icon;
  final String description;
  final String html;
  final String css;
  final String js;
  const _CanvasTemplate(this.name, this.icon, this.description, this.html, this.css, this.js);
}

final _templates = [
  _CanvasTemplate(
    '数据面板', '📊', '渐变紫色 Dashboard + 统计卡片 + 数据网格',
    '''<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><title>数据面板</title></head><body>
<header class="header"><div class="header-inner"><h1>📊 数据面板</h1><p>自动加载数据中枢数据</p></div></header>
<main class="container"><div class="stats-row" id="stats"></div><div id="content"><p class="loading">加载中...</p></div></main>
<footer class="footer"><span>Powered by Evergreen</span></footer></body></html>''',
    _defaultDashboardCss(),
    _defaultDataJs(),
  ),
  _CanvasTemplate(
    '卡片列表', '🃏', '简洁白底卡片布局，适合展示条目列表',
    '''<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><title>卡片列表</title></head><body>
<div class="container"><h1>📋 数据列表</h1><div id="content"><p class="loading">加载中...</p></div></div></body></html>''',
    _defaultCardCss(),
    _defaultDataJs(),
  ),
  _CanvasTemplate(
    '数据表格', '📋', '传统表格布局 + 搜索过滤，适合密集数据展示',
    '''<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><title>数据表格</title></head><body>
<div class="container"><h1>📋 数据表格</h1>
<div class="toolbar"><input type="text" id="search" placeholder="🔍 搜索..." oninput="filterTable()"></div>
<div class="table-wrap"><table id="data-table"><thead><tr id="table-head"></tr></thead><tbody id="table-body"><tr><td colspan="10" class="loading">加载中...</td></tr></tbody></table></div>
</div></body></html>''',
    _defaultTableCss(),
    _defaultTableJs(),
  ),
  _CanvasTemplate(
    '空白画布', '📄', '从零开始，完全自由的创作空间',
    '''<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><title>空白画布</title></head><body>
<div id="app"></div></body></html>''',
    '''body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 20px; background: #fff; color: #333; }''',
    '''// 在这里编写你的 JavaScript 代码
console.log('Hello Evergreen!');''',
  ),
];

class _NewCanvasDialog extends StatelessWidget {
  final void Function(_CanvasTemplate template) onSelect;
  const _NewCanvasDialog({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择模板'),
      content: SizedBox(
        width: 520,
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.4,
          ),
          itemCount: _templates.length,
          itemBuilder: (ctx, i) {
            final t = _templates[i];
            return InkWell(
              onTap: () => onSelect(t),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.icon, style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 6),
                    Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(t.description, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      ],
    );
  }
}

String _defaultDashboardCss() => '''* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; color: #333; }
.header { background: rgba(255,255,255,0.95); backdrop-filter: blur(10px); box-shadow: 0 2px 20px rgba(0,0,0,0.08); }
.header-inner { max-width: 1100px; margin: 0 auto; padding: 28px 32px; }
.header h1 { font-size: 26px; font-weight: 700; color: #1a1a2e; margin-bottom: 6px; }
.header p { font-size: 14px; color: #666; }
.container { max-width: 1100px; margin: 0 auto; padding: 24px 32px 60px; }
.stats-row { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 16px; margin-bottom: 24px; }
.stat-card { background: rgba(255,255,255,0.95); border-radius: 12px; padding: 20px; box-shadow: 0 2px 12px rgba(0,0,0,0.06); transition: transform 0.2s, box-shadow 0.2s; }
.stat-card:hover { transform: translateY(-2px); box-shadow: 0 6px 24px rgba(0,0,0,0.1); }
.stat-label { font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; color: #999; margin-bottom: 6px; }
.stat-value { font-size: 28px; font-weight: 700; color: #667eea; }
.data-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 16px; }
.data-card { background: rgba(255,255,255,0.95); border-radius: 12px; padding: 20px; box-shadow: 0 2px 12px rgba(0,0,0,0.06); border-left: 4px solid #667eea; transition: transform 0.2s; }
.data-card:hover { transform: translateY(-2px); box-shadow: 0 8px 30px rgba(0,0,0,0.1); }
.data-card h3 { font-size: 16px; font-weight: 600; color: #1a1a2e; margin-bottom: 10px; }
.data-field { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid #f0f0f0; font-size: 13px; }
.data-field:last-child { border-bottom: none; }
.data-field .label { color: #888; font-weight: 500; }
.data-field .value { color: #333; font-weight: 500; text-align: right; max-width: 60%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.loading { text-align: center; color: rgba(255,255,255,0.8); font-size: 15px; padding: 40px 0; }
.empty-state { text-align: center; padding: 60px 20px; color: rgba(255,255,255,0.7); }
.empty-state .icon { font-size: 48px; margin-bottom: 12px; }
.footer { text-align: center; padding: 20px; color: rgba(255,255,255,0.5); font-size: 12px; }''';

String _defaultCardCss() => '''* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f5f7fa; min-height: 100vh; color: #333; }
.container { max-width: 900px; margin: 0 auto; padding: 32px 20px; }
h1 { font-size: 22px; font-weight: 700; color: #1a1a2e; margin-bottom: 20px; }
.card-list { display: flex; flex-direction: column; gap: 12px; }
.card { background: #fff; border-radius: 10px; padding: 16px 20px; box-shadow: 0 1px 4px rgba(0,0,0,0.06); border-left: 4px solid #4f8cff; transition: transform 0.15s, box-shadow 0.15s; }
.card:hover { transform: translateX(4px); box-shadow: 0 4px 16px rgba(0,0,0,0.08); }
.card h3 { font-size: 15px; font-weight: 600; color: #1a1a2e; margin-bottom: 6px; }
.card p { font-size: 13px; color: #666; line-height: 1.5; }
.card .meta { font-size: 11px; color: #aaa; margin-top: 6px; }
.loading { text-align: center; color: #999; font-size: 14px; padding: 40px 0; }''';

String _defaultTableCss() => '''* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f5f7fa; min-height: 100vh; color: #333; }
.container { max-width: 1100px; margin: 0 auto; padding: 32px 20px; }
h1 { font-size: 22px; font-weight: 700; color: #1a1a2e; margin-bottom: 16px; }
.toolbar { margin-bottom: 12px; }
.toolbar input { width: 100%; max-width: 300px; padding: 8px 12px; border: 1px solid #ddd; border-radius: 6px; font-size: 13px; outline: none; }
.toolbar input:focus { border-color: #4f8cff; }
.table-wrap { background: #fff; border-radius: 10px; box-shadow: 0 1px 4px rgba(0,0,0,0.06); overflow-x: auto; }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
thead { background: #f8f9fb; }
th { padding: 10px 14px; text-align: left; font-weight: 600; color: #555; border-bottom: 2px solid #eee; white-space: nowrap; }
td { padding: 10px 14px; border-bottom: 1px solid #f0f0f0; }
tr:hover td { background: #f8f9ff; }
.loading { text-align: center; color: #999; padding: 30px 0; }''';

String _defaultDataJs() => '''async function init() {
  try { var d = await platform.data.get('REPLACE_WITH_SOURCE_NAME'); var c = document.getElementById('content');
  if (!d) { c.innerHTML = '<div class="empty-state"><div class="icon">📭</div><p>暂无数据</p></div>'; return; }
  if (Array.isArray(d) && d.length > 0) {
    var s = document.getElementById('stats'); if (s) s.innerHTML = '<div class="stat-card"><div class="stat-label">总记录</div><div class="stat-value">' + d.length + '</div></div>';
    var h = '<div class="data-grid">';
    d.forEach(function(item, i) { h += '<div class="data-card"><h3>#' + (i+1) + '</h3>';
      if (typeof item === 'object') Object.keys(item).slice(0,6).forEach(function(k) { var v = item[k]; h += '<div class="data-field"><span class="label">' + k + '</span><span class="value">' + (v===null?'—':String(v).slice(0,60)) + '</span></div>'; });
      h += '</div>'; });
    c.innerHTML = h + '</div>';
  } else if (d && typeof d === 'object') {
    var k = Object.keys(d); var s = document.getElementById('stats'); if (s) s.innerHTML = '<div class="stat-card"><div class="stat-label">字段数</div><div class="stat-value">' + k.length + '</div></div>';
    var h = '<div class="data-card"><h3>数据详情</h3>'; k.slice(0,12).forEach(function(kk) { h += '<div class="data-field"><span class="label">' + kk + '</span><span class="value">' + (d[kk]===null?'—':String(d[kk]).slice(0,80)) + '</span></div>'; });
    c.innerHTML = h + '</div>';
  }} catch(e) { c.innerHTML = '<div class="empty-state"><div class="icon">⚠️</div><p>加载失败: ' + e.message + '</p></div>'; }
} init();''';

String _defaultTableJs() => '''async function init() {
  try { var d = await platform.data.get('REPLACE_WITH_SOURCE_NAME');
  if (!d || !Array.isArray(d) || d.length === 0) { document.getElementById('table-body').innerHTML = '<tr><td colspan="10" style="text-align:center;color:#999;padding:30px">暂无数据</td></tr>'; return; }
  var keys = Object.keys(d[0]).slice(0, 8);
  document.getElementById('table-head').innerHTML = '<th>#</th>' + keys.map(function(k) { return '<th>' + k + '</th>'; }).join('');
  document.getElementById('table-body').innerHTML = d.map(function(item, i) {
    return '<tr><td>' + (i+1) + '</td>' + keys.map(function(k) { var v = item[k]; return '<td>' + (v === null ? '—' : String(v).slice(0, 80)) + '</td>'; }).join('') + '</tr>';
  }).join('');
  } catch(e) { document.getElementById('table-body').innerHTML = '<tr><td colspan="10" style="text-align:center;color:red;padding:20px">加载失败: ' + e.message + '</td></tr>'; }
} init();
function filterTable() { var q = document.getElementById('search').value.toLowerCase(); var rows = document.querySelectorAll('#table-body tr');
  rows.forEach(function(r) { r.style.display = r.textContent.toLowerCase().includes(q) ? '' : 'none'; }); }''';
