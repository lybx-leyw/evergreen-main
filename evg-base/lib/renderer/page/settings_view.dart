/// 设置视图——通过 Config 模块直接读写 SharedPreferences。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/config/settings.dart' show initSettings, getAllSettings, setSetting, SettingType, SettingDecl;
import 'package:evergreen_base/core/config/config_http_server.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';

class SettingsView extends ConsumerStatefulWidget {
  final ModuleDescriptor descriptor;
  const SettingsView({super.key, required this.descriptor});
  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  final _controllers = <String, TextEditingController>{};
  final _obscured = <String, bool>{};

  @override
  void dispose() {
    for (final c in _controllers.values) { c.dispose(); }
    super.dispose();
  }

  void _initControllers(List<({SettingDecl decl, String value})> items) {
    for (final e in items) {
      if (e.decl.type == SettingType.string || e.decl.type == SettingType.path) {
        _controllers.putIfAbsent(e.decl.key, () => TextEditingController(text: e.value));
      }
    }
  }

  Future<void> _saveAll() async {
    final prefs = ref.read(sharedPreferencesProvider);
    var saved = 0;
    // ⚠️ 必须 await 每个 setSetting：SharedPreferences 在 Android 底层用 apply()
    // 异步刷盘，若 fire-and-forget → 进程重启前未刷盘 → 数据丢失。
    for (final entry in _controllers.entries) {
      final v = entry.value.text;
      final masked = (entry.key.contains('PASSWORD') || entry.key.contains('SECRET'))
          ? (v.isNotEmpty ? '***(${v.length}字符)' : '(空)')
          : v;
      debugPrint('[SettingsView] 保存 ${entry.key} = $masked');
      await setSetting(prefs, entry.key, v);
      saved++;
    }
    // 保存后验证
    debugPrint('[SettingsView] 保存完成, 验证: ZJU_USERNAME in prefs=${prefs.containsKey("ZJU_USERNAME")}, val="${prefs.getString("ZJU_USERNAME")}"');
    // 保存后立即同步到 .greenix/config.json，确保同一 session 内 Python scraper
    // 能直接读到最新凭证（Tier 1 本地文件路径，而非等下次启动的 sync）。
    try {
      final configServer = ref.read(configHttpServerProvider);
      configServer.syncConfigToGreenix();
    } catch (e) {
      debugPrint('[SettingsView] syncConfigToGreenix 失败: $e');
    }
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已保存 $saved 项'),
        backgroundColor: scheme.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _rescan() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final pluginsDir = ref.read(pluginsDirProvider);
    await initSettings(prefs, pluginDirs: [pluginsDir]);
    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已刷新设置项'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.read(sharedPreferencesProvider);
    final items = getAllSettings(prefs);
    _initControllers(items);

    if (items.isEmpty) {
      return const Center(
        child: Text('暂无设置项\n请在 config.json 中声明设置', textAlign: TextAlign.center),
      );
    }

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.descriptor.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(widget.descriptor.description, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton(onPressed: _rescan, icon: const Icon(Icons.refresh, size: 20), tooltip: '重新扫描配置'),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _saveAll,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('保存所有'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildThemeSection(theme),
        const SizedBox(height: 16),
        _buildInterfaceSection(theme),
        const SizedBox(height: 16),
        for (final e in items) _buildTile(e, theme.colorScheme),
      ],
    );
  }

  /// 外观 · 主题——列出 ThemeStore 全部主题（内置 + 插件），
  /// 切换即全局换肤（ChangeNotifier 链路）并持久化到 prefs。
  Widget _buildThemeSection(ThemeData theme) {
    final store = ref.watch(themeStoreProvider);
    final all = store.all;
    final activeId = store.activeTheme?.id;
    final validActive =
        activeId != null && all.any((t) => t.id == activeId) ? activeId : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text('外观 · 主题',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: all.isEmpty
                ? Text('无可用主题',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant))
                : DropdownButtonFormField<String>(
                    value: validActive ?? all.first.id,
                    isExpanded: true,
                    decoration: _decoration(theme.colorScheme),
                    items: all
                        .map((t) =>
                            DropdownMenuItem(value: t.id, child: Text(t.name)))
                        .toList(),
                    onChanged: (id) async {
                      if (id == null || id == activeId) return;
                      store.setActiveById(id);
                      final prefs = ref.read(sharedPreferencesProvider);
                      await prefs.setString('active_theme_id', id);
                      debugPrint('[SettingsView] 主题切换 → $id');
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 界面 · 反馈浮珠——开关控制全局 🐛 FeedbackFab 的显示/隐藏。
  ///
  /// 单一真相源为 [showFeedbackFabProvider]，SharedPreferences 键
  /// `SHOW_FEEDBACK_FAB`（bool）仅作持久化，改值即实时同步 app_shell。
  Widget _buildInterfaceSection(ThemeData theme) {
    final show = ref.watch(showFeedbackFabProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('界面 · 反馈浮珠',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                Text('显示右下角 🐛 反馈入口浮珠',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Switch(
              value: show,
              onChanged: (v) async {
                final prefs = ref.read(sharedPreferencesProvider);
                await prefs.setBool('SHOW_FEEDBACK_FAB', v);
                ref.read(showFeedbackFabProvider.notifier).state = v;
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(({SettingDecl decl, String value}) item, ColorScheme scheme) {
    final d = item.decl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                if (d.hint != null && d.hint!.isNotEmpty)
                  Text(d.hint!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: _buildControl(item, scheme)),
        ],
      ),
    );
  }

  Widget _buildControl(({SettingDecl decl, String value}) item, ColorScheme scheme) {
    final d = item.decl;
    switch (d.type) {
      case SettingType.bool_:
        return Switch(
          value: item.value == 'true',
          onChanged: (v) async {
            final prefs = ref.read(sharedPreferencesProvider);
            await setSetting(prefs, d.key, v.toString());
            setState(() {});
          },
        );
      case SettingType.option:
        final opts = d.options ?? [];
        if (opts.isEmpty) return _buildTextWithSuggestions(item, scheme);
        final cur = opts.any((o) => o.value == item.value) ? item.value : opts.first.value;
        return DropdownButtonFormField<String>(
          value: cur,
          isExpanded: true,
          decoration: _decoration(scheme),
          items: opts.map((o) => DropdownMenuItem(value: o.value, child: Text(o.label))).toList(),
          onChanged: (v) async {
            if (v != null) {
              final prefs = ref.read(sharedPreferencesProvider);
              await setSetting(prefs, d.key, v);
              setState(() {});
            }
          },
        );
      default:
        // string / path：自由文本输入；带 suggestions 时额外渲染快捷填充 chips
        return _buildTextWithSuggestions(item, scheme);
    }
  }

  /// 自由文本输入。声明了 `suggestions` 时，下方渲染可点击的快捷填充建议
  /// （仅作提示，不限制输入——用户可填写任意 OpenAI 兼容模型 id）。
  Widget _buildTextWithSuggestions(({SettingDecl decl, String value}) item, ColorScheme scheme) {
    final d = item.decl;
    final suggestions = d.suggestions;
    if (suggestions == null || suggestions.isEmpty) {
      return _buildTextField(item, scheme);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(item, scheme),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final s in suggestions)
              ActionChip(
                label: Text(s.label, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () => setState(() {
                  _controllers[d.key]?.text = s.value;
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField(({SettingDecl decl, String value}) item, ColorScheme scheme) {
    final d = item.decl;
    final isMasked = d.isSecure && (_obscured[d.key] ?? true);
    return TextFormField(
      controller: _controllers[d.key],
      obscureText: isMasked,
      decoration: _decoration(scheme).copyWith(
        suffixIcon: d.isSecure
            ? IconButton(
                icon: Icon(isMasked ? Icons.visibility_off : Icons.visibility, size: 20),
                onPressed: () => setState(() => _obscured[d.key] = !(_obscured[d.key] ?? true)),
              )
            : null,
      ),
      style: TextStyle(fontSize: 14, fontFamily: d.isSecure ? 'monospace' : null),
    );
  }

  InputDecoration _decoration(ColorScheme scheme) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      filled: true,
      // 跟随主题：M3 填充输入框标准语义色（surfaceContainerHighest = 主题 surface/bgSecondary）
      fillColor: scheme.surfaceContainerHighest,
    );
  }
}
