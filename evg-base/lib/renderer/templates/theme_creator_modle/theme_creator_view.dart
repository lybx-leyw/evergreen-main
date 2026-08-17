/// 主题创作中心主视图——三栏 IDE 编排。
///
/// 布局（参照 html-creator，宽屏 ≥900px）：
/// - 左栏：草稿列表（新建/选择/删除）
/// - 中栏：编辑区（id/name + 8 个语义色）
/// - 右栏：Dart 实时预览（草稿即时换肤）
///
/// 窄屏（<900px）自动退化为上下堆叠（编辑在上、预览在下）。
/// 数据流：草稿就地编辑 → 保存到 workspace JSON → 导出为主题插件
/// （plugins/<id>/theme/theme.json）+ ThemeStore 热注册 → 设置页立即可切换。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/config/settings.dart'
    show getSetting, setSetting;
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/theme/builtin_themes.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

import 'models/theme_draft.dart';
import 'services/theme_draft_store.dart';
import 'services/theme_exporter.dart';
import 'services/theme_ai_service.dart';
import 'services/theme_chat_store.dart';
import 'widgets/theme_toolbar.dart';
import 'widgets/theme_draft_list.dart';
import 'widgets/color_field.dart';
import 'widgets/theme_preview.dart';

/// 主题创作中心视图。
class ThemeCreatorView extends ConsumerStatefulWidget {
  final dynamic descriptor;

  const ThemeCreatorView({super.key, this.descriptor});

  @override
  ConsumerState<ThemeCreatorView> createState() => _ThemeCreatorViewState();
}

class _ThemeCreatorViewState extends ConsumerState<ThemeCreatorView> {
  late final ThemeDraftStore _store;
  late final ThemeExporter _exporter;

  List<ThemeDraft> _drafts = [];
  ThemeDraft? _current;
  bool _dirty = false;
  bool _aiBusy = false;

  // 防抖自动保存
  Timer? _autoSaveTimer;

  /// 竖版窄屏：当前激活的 Tab（0=草稿 1=编辑 2=预览）。默认编辑。
  int _narrowTab = 1;

  @override
  void initState() {
    super.initState();
    _store = ThemeDraftStore();
    _exporter = ThemeExporter(resolvePluginsRoot());
    _reloadDrafts();
    if (_drafts.isEmpty) {
      // 首次进入：从内置 dark 复制一个起点草稿
      final seed = builtinThemes.firstWhere(
        (t) => t.id == 'dark',
        orElse: () => builtinThemes.first,
      );
      _current = ThemeDraft.fromDescriptor(seed);
      _drafts = [_current!];
      _saveNow();
    } else {
      _current = _drafts.first;
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  // ═══════ 草稿操作 ═══════

  void _reloadDrafts() {
    _drafts = _store.list();
  }

  void _saveNow() {
    final c = _current;
    if (c == null) return;
    _store.save(c);
    _dirty = false;
  }

  void _scheduleAutoSave() {
    _dirty = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 1200), _saveNow);
  }

  void _newDraft() {
    final c = _current;
    // 新草稿以当前草稿为底（快速迭代），id 加序号防冲突
    var n = 1;
    String id;
    do {
      id = 'my_theme${n == 1 ? '' : '_$n'}';
      n++;
    } while (_drafts.any((d) => d.id == id));
    final base = c ?? ThemeDraft.fromDescriptor(builtinThemes.first);
    final draft = ThemeDraft(
      id: id,
      name: '我的主题$n',
      colors: Map.of(base.colors),
    );
    setState(() {
      _current = draft;
      _drafts.add(draft);
    });
    _saveNow();
  }

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
                    _drafts = [draft, ..._drafts.where((d) => d.id != draft.id)];
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

  void _selectDraft(String id) {
    final d = _store.load(id);
    if (d == null) return;
    setState(() => _current = d);
  }

  void _deleteDraft(String id) {
    if (_current?.id == id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('不能删除当前编辑中的草稿')),
      );
      return;
    }
    _store.delete(id);
    setState(() => _reloadDrafts());
  }

  void _setColor(String key, String value) {
    final c = _current;
    if (c == null) return;
    setState(() {
      c.colors[key] = value.trim();
      _dirty = true;
    });
    _scheduleAutoSave();
  }

  void _setName(String v) {
    final c = _current;
    if (c == null) return;
    setState(() {
      c.name = v;
      _dirty = true;
    });
    _scheduleAutoSave();
  }

  void _setId(String v) {
    final c = _current;
    if (c == null) return;
    setState(() {
      c.id = v.trim();
      _dirty = true;
    });
    _scheduleAutoSave();
  }

  // ═══════ 导出 / AI ═══════

  void _export() {
    final c = _current;
    if (c == null) return;
    _saveNow();
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

  Future<void> _aiGenerate() async {
    final c = _current;
    if (c == null || _aiBusy) return;

    final prefs = ref.read(sharedPreferencesProvider);
    var apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY');
    // 未配置 key：弹窗引导直接填写并保存（按钮不降级为禁用）。
    if (apiKey.isEmpty) {
      final input = await _promptApiKey();
      if (input == null || !mounted) return;
      apiKey = input;
    }
    final baseUrl = getSetting(prefs, 'DEEPSEEK_BASE_URL');
    if (apiKey.isEmpty) return;

    // 输入描述
    final desc = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('🎨 AI 生成主题'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '描述你的主题',
              hintText: '例如：温暖的学习书房，柔和的暖黄灯光',
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final v = ctrl.text.trim();
                if (v.isNotEmpty) Navigator.pop(ctx, v);
              },
              child: const Text('生成'),
            ),
          ],
        );
      },
    );
    if (desc == null || desc.isEmpty || !mounted) return;

    setState(() => _aiBusy = true);
    try {
      final service = ThemeAiService(
        apiKey: apiKey,
        baseUrl: baseUrl.isNotEmpty ? baseUrl : 'https://api.deepseek.com/v1',
      );
      // 断点续作：携带持久化历史（重启后返工不丢上下文）
      final history = ThemeChatStore().toAgentMessages();
      final draft = await service.generate(desc, history: history);
      if (!mounted) return;
      if (draft == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 生成失败，请重试或检查 API Key')),
        );
        return;
      }
      setState(() {
        _current = draft;
        _drafts = [draft, ..._drafts.where((d) => d.id != draft.id)];
      });
      _saveNow();
      // 记录本轮对话（用户指令 + 结果摘要），供下次迭代返工
      ThemeChatStore().appendRound(
        userPrompt: desc,
        assistantSummary:
            '已生成主题「${draft.name}」：' + jsonEncode(draft.toJson()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✨ 已生成主题「${draft.name}」，可微调后导出')),
      );
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThemeToolbar(
          onNew: _newDraft,
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
          // 避免按钮凭空消失让用户困惑。
          onAiGenerate: _aiGenerate,
          exportEnabled: c?.canExport ?? false,
          aiEnabled: _aiEnabled,
          aiBusy: _aiBusy,
        ),
        Expanded(
          child: c == null
              ? const Center(child: Text('无草稿，点击「新建」开始'))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 900) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 210,
                            child: _buildListPanel(),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            flex: 2,
                            child: _buildEditorPanel(c),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            flex: 3,
                            child: _buildPreviewPanel(c),
                          ),
                        ],
                      );
                    }
                    // 窄屏：Tab 切换 + 全宽渲染（草稿/编辑/预览），
                    // IndexedStack 保活——编辑内容与滚动位置不丢失，
                    // 草稿列表不再因窄屏而消失。
                    return _buildNarrowBody(c);
                  },
                ),
        ),
      ],
    );
  }

  // ── 竖版窄屏 Tab 导航 ──

  /// 竖版 Tab 顺序：草稿 / 编辑 / 预览。
  static const _narrowTabs = <(IconData, String)>[
    (Icons.folder_open, '草稿'),
    (Icons.palette_outlined, '编辑'),
    (Icons.visibility_outlined, '预览'),
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

  Widget _buildListPanel() {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Text('草稿 (${_drafts.length})',
                style: theme.textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ThemeDraftList(
              drafts: _drafts,
              selectedId: _current?.id,
              onSelect: _selectDraft,
              onDelete: _deleteDraft,
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
