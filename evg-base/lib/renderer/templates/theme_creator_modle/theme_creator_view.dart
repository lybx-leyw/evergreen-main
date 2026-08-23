/// 主题创作中心主视图——三栏 IDE 编排 + 显式 AI 面板。
///
/// 布局（参照 html-creator，宽屏 ≥900px）：
/// - 左栏：面板列表（新建/选择/重命名/删除，一面板一实例一草稿）
/// - 中栏：编辑区（id/name + 8 个语义色）
/// - 右栏：Dart 实时预览（草稿即时换肤）
/// - 底部：显式 AI 面板（消息历史 + 绑定态徽标 + 断点续做）
///
/// 窄屏（<900px）自动退化为 Tab 堆叠（面板/编辑/预览/AI）。
///
/// 数据流（会话-面板双向绑定，对齐 scraper / html-creator）：
/// - 一面板一实例：加载/新建面板时 [ThemePanelManager.ensureInstance] 幂等分配
///   固定实例（实例 ID == 主题 ID），实例 ID 永不变；
/// - 一会话一固定历史按实例隔离：切换面板时先保存当前会话，再恢复新实例历史；
/// - 会话文件内 panelId + instanceId 双向校验，孤儿会话不恢复；
/// - 删除面板时先切走再删，避免自动保存把已删目录重建。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/config/settings.dart'
    show getSetting, setSetting;
import 'package:evergreen_base/core/theme/builtin_themes.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/providers.dart';

import 'models/theme_draft.dart';
import 'services/theme_ai_service.dart';
import 'services/theme_exporter.dart';
import 'services/theme_panel_manager.dart';
import 'view/theme_ai_panel.dart';
import 'widgets/color_field.dart';
import 'widgets/theme_preview.dart';
import 'widgets/theme_toolbar.dart';

/// 主题创作中心视图。
class ThemeCreatorView extends ConsumerStatefulWidget {
  final dynamic descriptor;

  const ThemeCreatorView({super.key, this.descriptor});

  @override
  ConsumerState<ThemeCreatorView> createState() => _ThemeCreatorViewState();
}

class _ThemeCreatorViewState extends ConsumerState<ThemeCreatorView> {
  late final ThemePanelManager _panelMgr;
  late final ThemeExporter _exporter;
  late final ThemeAiService _aiService;
  final FocusNode _aiFocusNode = FocusNode();

  List<ThemePanelMeta> _panels = [];
  String? _currentPanelId;
  ThemeDraft? _current;

  /// 当前实例（AI 面板绑定态徽标：实例名 / 实例 ID / 会话恢复态）。
  String? _currentInstanceId;
  String? _currentInstanceName;

  // 防抖自动保存
  Timer? _autoSaveTimer;

  /// 竖版窄屏：当前激活的 Tab（0=面板 1=编辑 2=预览 3=AI）。默认编辑。
  int _narrowTab = 1;

  @override
  void initState() {
    super.initState();
    _panelMgr = ThemePanelManager();
    // 旧数据一次性迁移：老草稿 → 面板，老单例聊天 → 实例会话
    _panelMgr.migrateLegacyIfNeeded();
    _exporter = ThemeExporter(resolvePluginsRoot());

    _aiService = ThemeAiService(
      apiKey: _readApiKey(),
      baseUrl: _readBaseUrl(),
    );
    // 会话文件按实例隔离（panels/{panelId}/instances/{instanceId}/session.json），
    // 生命周期随面板——删除面板即删除实例与会话，不留孤儿文件。
    _aiService.resolveSessionsPath = instanceSessionsPath;
    // 未配置 API Key 时弹窗引导填写并保存。
    _aiService.ensureApiKey = _promptApiKey;
    // 会话落盘时写入当前草稿快照（断点续做恢复 UI 状态）。
    _aiService.currentDraftProvider = () => _current;
    // AI 生成成功 → 应用到当前面板草稿。
    _aiService.onDraftGenerated = _applyAiDraft;

    _panels = _panelMgr.listPanels();
    if (_panels.isEmpty) {
      // 首次进入：创建默认面板（从内置 dark 复制起点草稿）
      final seed = _seedDraft();
      final data = _panelMgr.createPanel(name: '我的主题', seedDraft: seed);
      _panels = [data.meta];
    }
    _loadPanel(_panels.first.id);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _aiFocusNode.dispose();
    _aiService.dispose();
    super.dispose();
  }

  String _readApiKey() {
    try {
      return getSetting(ref.read(sharedPreferencesProvider), 'DEEPSEEK_API_KEY');
    } catch (_) {
      return '';
    }
  }

  String _readBaseUrl() {
    try {
      final v = getSetting(ref.read(sharedPreferencesProvider), 'DEEPSEEK_BASE_URL');
      return v.isNotEmpty ? v : 'https://api.deepseek.com/v1';
    } catch (_) {
      return 'https://api.deepseek.com/v1';
    }
  }

  /// 内置 dark 起点草稿（首次进入 / 面板草稿缺失兜底）。
  ThemeDraft _seedDraft() {
    final seed = builtinThemes.firstWhere(
      (t) => t.id == 'dark',
      orElse: () => builtinThemes.first,
    );
    return ThemeDraft.fromDescriptor(seed);
  }

  // ═══════ 面板操作（一面板一实例） ═══════

  /// 加载面板：确保实例（幂等）→ 切换 AI 会话（保存旧/恢复新）→ 恢复面板状态。
  Future<void> _loadPanel(String panelId) async {
    if (_currentPanelId != null && _currentPanelId != panelId) {
      _saveNow(); // 先保存当前面板
    }
    final instance = _panelMgr.ensureInstance(panelId);
    await _aiService.switchPanel(panelId, instanceId: instance.id);
    final data = _panelMgr.loadPanel(panelId);
    if (data == null || !mounted) return;
    final metaName = data.meta.name;
    setState(() {
      _currentPanelId = panelId;
      _current = data.draft ?? _seedDraft();
      _syncInstance();
      _narrowTab = 1;
    });
    _refreshPanels();
    // 切板提示：面板名 + 会话恢复态（断点续作 / 新会话）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final resumed = _aiService.restoredFromSession;
      final count = _aiService.sessionMessageCount;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          resumed
              ? '已切换到面板「$metaName」，恢复历史会话 $count 条'
              : '已切换到面板「$metaName」（新会话）',
        ),
        duration: const Duration(seconds: 1),
      ));
    });
  }

  /// 新建面板：创建 → 确保实例 → 切换 AI 会话（新面板 = 新实例 = 新会话）。
  Future<void> _newPanel() async {
    _saveNow();
    var n = 1;
    final used = _panels.map((p) => p.instanceId ?? '').toSet();
    String id;
    do {
      id = 'my_theme${n == 1 ? '' : '_$n'}';
      n++;
    } while (used.contains(id));
    final name = '我的主题${n - 1}';
    final base = _current ?? _seedDraft();
    final seed = ThemeDraft(id: id, name: name, colors: Map.of(base.colors));
    final data = _panelMgr.createPanel(name: name, seedDraft: seed);
    final instance = _panelMgr.ensureInstance(data.meta.id);
    await _aiService.switchPanel(data.meta.id, instanceId: instance.id);
    if (!mounted) return;
    setState(() {
      _currentPanelId = data.meta.id;
      _current = data.draft;
      _syncInstance();
    });
    _refreshPanels();
  }

  /// 删除面板：先切到别的面板再删（避免自动保存把已删目录重建）。
  void _deletePanel(String panelId) {
    if (_panels.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少保留一个面板')),
      );
      return;
    }
    if (_currentPanelId == panelId) {
      final target = _panels.firstWhere((p) => p.id != panelId).id;
      _loadPanel(target);
    }
    _panelMgr.deletePanel(panelId); // 删面板目录 = 实例 + 会话一并清理
    _refreshPanels();
    setState(() => _syncInstance());
  }

  /// 重命名面板（改名不改变 id，不丢草稿/会话；实例名同步）。
  void _renamePanel(String panelId, String newName) {
    final name = newName.trim();
    if (name.isEmpty) return;
    _panelMgr.renamePanel(panelId, name);
    if (panelId == _currentPanelId) {
      setState(() => _syncInstance());
    }
    _refreshPanels();
    setState(() {});
  }

  /// 从内置主题复制为当前面板草稿（快速迭代起点）。
  void _copyFromBuiltin() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('从内置主题复制为起点',
                  style: Theme.of(ctx).textTheme.titleSmall),
            ),
            for (final t in builtinThemes)
              ListTile(
                leading: _MiniBar(colors: t.colors),
                title: Text(t.name),
                subtitle: Text(t.id,
                    style: const TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  final draft = ThemeDraft.fromDescriptor(t);
                  setState(() {
                    _current = draft;
                                });
                  _saveNow();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ═══════ 草稿操作（当前面板草稿） ═══════

  void _refreshPanels() {
    _panels = _panelMgr.listPanels();
  }

  /// 同步当前实例缓存（AI 面板绑定态徽标）。
  void _syncInstance() {
    final pid = _currentPanelId;
    final inst = pid == null ? null : _panelMgr.tryLoadInstanceOf(pid);
    _currentInstanceId = inst?.id;
    _currentInstanceName = inst?.name;
  }

  void _saveNow() {
    final c = _current;
    final pid = _currentPanelId;
    if (c == null || pid == null) return;
    _panelMgr.savePanel(pid, draft: c);
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 1200), _saveNow);
  }

  void _setColor(String key, String value) {
    final c = _current;
    if (c == null) return;
    setState(() {
      c.colors[key] = value.trim();
    });
    _scheduleAutoSave();
  }

  void _setName(String v) {
    final c = _current;
    if (c == null) return;
    setState(() {
      c.name = v;
    });
    _scheduleAutoSave();
  }

  void _setId(String v) {
    final c = _current;
    if (c == null) return;
    setState(() {
      c.id = v.trim();
    });
    _scheduleAutoSave();
  }

  // ═══════ 导出 / AI ═══════

  void _export() {
    final c = _current;
    final pid = _currentPanelId;
    if (c == null || pid == null) return;
    _saveNow();
    // 主题 ID 即实例 ID：导出时绑定，同步实例身份与会话路径（杜绝 ID 分叉）
    _panelMgr.bindThemeId(pid, c.id);
    _aiService.rebindInstanceId(c.id);
    setState(() => _syncInstance());
    final store = ref.read(themeStoreProvider);
    final r = _exporter.exportAndRegister(c, store);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.message),
        duration: const Duration(seconds: 3),
        action: r.success
            ? SnackBarAction(
                label: '立即应用',
                onPressed: () => store.setActiveById(c.id),
              )
            : null,
      ),
    );
  }

  bool get _aiEnabled {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      return getSetting(prefs, 'DEEPSEEK_API_KEY').isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// AI 生成成功 → 应用到当前面板草稿并持久化。
  void _applyAiDraft(ThemeDraft draft) {
    if (!mounted) return;
    setState(() {
      _current = draft;
    });
    _saveNow();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✨ 已生成主题「${draft.name}」，可微调后导出')),
    );
  }

  /// 工具栏「AI 助手」：窄屏切到 AI Tab，宽屏聚焦 AI 输入框。
  void _focusAi() {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    if (!isWide) setState(() => _narrowTab = 3);
    _aiFocusNode.requestFocus();
  }

  /// 未配置 DEEPSEEK_API_KEY 时弹窗引导填写并保存，保存后继续生成流程。
  Future<String?> _promptApiKey() async {
    final ctrl = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎨 AI 生成需要 API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('未配置 DEEPSEEK_API_KEY，可直接在此填写：',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'DEEPSEEK_API_KEY',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('保存并使用'),
          ),
        ],
      ),
    );
    if (input == null || input.isEmpty) return null;
    await setSetting(
        ref.read(sharedPreferencesProvider), 'DEEPSEEK_API_KEY', input);
    if (!mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ API Key 已保存，开始生成...')),
    );
    return input;
  }

  // ═══════ 布局 ═══════

  @override
  Widget build(BuildContext context) {
    final c = _current;
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThemeToolbar(
          onNew: _newPanel,
          onCopyBuiltin: _copyFromBuiltin,
          onSave: () {
            _saveNow();
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('已保存草稿'), duration: Duration(seconds: 1)),
            );
          },
          onExport: _export,
          // 始终显示 AI 按钮（未配置 API Key 时为禁用态并提示），
          // 点击聚焦底部 AI 面板输入框。
          onAiGenerate: _focusAi,
          exportEnabled: c?.canExport ?? false,
          aiEnabled: _aiEnabled,
          aiBusy: _aiService.busy,
        ),
        Expanded(
          child: c == null
              ? const Center(child: Text('无面板，点击「新建面板」开始'))
              : (isWide ? _buildWideBody(c) : _buildNarrowBody(c)),
        ),
        // 宽屏：底部显式 AI 面板（窄屏已内置于 Tab 路线）
        if (isWide)
          SizedBox(
            height: 250,
            child: ThemeAiPanel(
              aiService: _aiService,
              instanceName: _currentInstanceName,
              instanceId: _currentInstanceId,
              focusNode: _aiFocusNode,
            ),
          ),
      ],
    );
  }

  Widget _buildWideBody(ThemeDraft c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 210, child: _buildListPanel()),
        const VerticalDivider(width: 1),
        Expanded(flex: 2, child: _buildEditorPanel(c)),
        const VerticalDivider(width: 1),
        Expanded(flex: 3, child: _buildPreviewPanel(c)),
      ],
    );
  }

  // ── 竖版窄屏 Tab 导航 ──

  /// 竖版 Tab 顺序：面板 / 编辑 / 预览 / AI。
  static const _narrowTabs = <(IconData, String)>[
    (Icons.folder_open, '面板'),
    (Icons.palette_outlined, '编辑'),
    (Icons.visibility_outlined, '预览'),
    (Icons.auto_awesome, 'AI'),
  ];

  Widget _buildNarrowBody(ThemeDraft c) {
    return Column(
      children: [
        _buildNarrowTabBar(),
        Expanded(
          child: IndexedStack(
            index: _narrowTab,
            children: [
              _buildListPanel(),
              _buildEditorPanel(c),
              _buildPreviewPanel(c),
              ThemeAiPanel(
                aiService: _aiService,
                instanceName: _currentInstanceName,
                instanceId: _currentInstanceId,
                focusNode: _aiFocusNode,
              ),
            ],
          ),
        ),
      ],
    );
  }

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

  // ── 左栏：面板列表 ──

  Widget _buildListPanel() {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('面板 (${_panels.length})',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 16),
                  tooltip: '新建面板',
                  visualDensity: VisualDensity.compact,
                  onPressed: _newPanel,
                ),
              ],
            ),
          ),
          Expanded(
            child: _PanelList(
              panels: _panels,
              selectedId: _currentPanelId,
              messageCountOf: _panelMgr.sessionMessageCountOf,
              onSelect: _loadPanel,
              onRename: _renamePanel,
              onDelete: _deletePanel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorPanel(ThemeDraft c) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // id / name
          Row(
            children: [
              Expanded(
                child: _SyncedTextField(
                  initialValue: c.name,
                  onChanged: _setName,
                  decoration: const InputDecoration(
                    labelText: '主题名称',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SyncedTextField(
                  initialValue: c.id,
                  onChanged: _setId,
                  decoration: InputDecoration(
                    labelText: '主题 id（snake_case）',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: c.idValid
                        ? null
                        : '小写字母/数字/下划线，勿用内置 id',
                    errorStyle: const TextStyle(fontSize: 10),
                  ),
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 校验提示
          Text(
            c.canExport ? '✅ 可导出' : '⚠ 补全 8 色并修正 id 后可导出',
            style: TextStyle(
              fontSize: 11,
              color: c.canExport
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 6),
          // 8 色编辑
          Expanded(
            child: ListView(
              children: [
                for (final key in kThemeColorKeys)
                  ColorField(
                    semanticKey: key,
                    label: kThemeColorLabels[key] ?? key,
                    value: c.colors[key] ?? '',
                    presets: kThemeColorPresets[key] ?? const [],
                    onChanged: (v) => _setColor(key, v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPanel(ThemeDraft c) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Text('实时预览（Dart 渲染）',
                style: theme.textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ThemePreview(draft: c.toDescriptor()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 左栏面板列表——一面板一实例一草稿，支持选择 / 重命名 / 删除。
class _PanelList extends StatelessWidget {
  final List<ThemePanelMeta> panels;
  final String? selectedId;
  final int Function(String panelId) messageCountOf;
  final ValueChanged<String> onSelect;
  final void Function(String panelId, String newName) onRename;
  final ValueChanged<String> onDelete;

  const _PanelList({
    required this.panels,
    required this.selectedId,
    required this.messageCountOf,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (panels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('暂无面板\n点击顶部「新建面板」开始',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      itemCount: panels.length,
      itemBuilder: (ctx, i) {
        final p = panels[i];
        final selected = p.id == selectedId;
        final count = messageCountOf(p.id);
        final themeId = p.instanceId ?? p.themeId;
        return Material(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
              : Colors.transparent,
          child: InkWell(
            onTap: () => onSelect(p.id),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (count > 0) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('$count 条',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: theme.colorScheme.onPrimaryContainer)),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          themeId != null && themeId.isNotEmpty
                              ? '实例 #$themeId'
                              : '（未分配实例）',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                              fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    tooltip: '重命名面板',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _promptRename(ctx, p),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    tooltip: '删除面板（含实例与会话）',
                    onPressed: () => onDelete(p.id),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _promptRename(BuildContext ctx, ThemePanelMeta p) {
    final ctrl = TextEditingController(text: p.name);
    showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('重命名面板'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '面板名（不改变 ID，不丢历史）',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(dctx, v.trim());
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(dctx, v);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((v) {
      if (v is String && v.isNotEmpty) onRename(p.id, v);
    });
  }
}

/// 与外部值同步的文本输入框——控制器只建一次，外部值变化时同步文本。
class _SyncedTextField extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onChanged;
  final InputDecoration? decoration;
  final TextStyle? style;

  const _SyncedTextField({
    required this.initialValue,
    required this.onChanged,
    this.decoration,
    this.style,
  });

  @override
  State<_SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<_SyncedTextField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue);

  @override
  void didUpdateWidget(_SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue &&
        _ctrl.text != widget.initialValue) {
      _ctrl.text = widget.initialValue;
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      onChanged: widget.onChanged,
      decoration: widget.decoration,
      style: widget.style,
    );
  }
}

/// 内置主题色条（复制选择弹窗用）。
class _MiniBar extends StatelessWidget {
  final Map<String, String> colors;

  const _MiniBar({required this.colors});

  @override
  Widget build(BuildContext context) {
    const keys = ['background', 'accent', 'text'];
    return Container(
      width: 44,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final k in keys)
            Expanded(
              child: Container(
                color: Color(
                    int.tryParse(
                            (colors[k] ?? '#000000').replaceFirst('#', 'FF'),
                            radix: 16) ??
                        0xFF000000),
              ),
            ),
        ],
      ),
    );
  }
}
