/// 设置视图——通过 Config 模块直接读写 SharedPreferences。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/config/settings.dart' show initSettings, getAllSettings, setSetting, SettingType, SettingDecl;
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
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

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
    _controllers.forEach((key, ctrl) {
      setSetting(prefs, key, ctrl.text);
      saved++;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存 $saved 项'), backgroundColor: Colors.green, duration: const Duration(seconds: 2)),
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
    final isDark = theme.brightness == Brightness.dark;
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final e in items) _buildTile(e, isDark),
      ],
    );
  }

  Widget _buildTile(({SettingDecl decl, String value}) item, bool isDark) {
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
          Expanded(child: _buildControl(item, isDark)),
        ],
      ),
    );
  }

  Widget _buildControl(({SettingDecl decl, String value}) item, bool isDark) {
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
        if (opts.isEmpty) return _buildTextField(item, isDark);
        final cur = opts.any((o) => o.value == item.value) ? item.value : opts.first.value;
        return DropdownButtonFormField<String>(
          value: cur,
          isExpanded: true,
          decoration: _decoration(isDark),
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
        return _buildTextField(item, isDark);
    }
  }

  Widget _buildTextField(({SettingDecl decl, String value}) item, bool isDark) {
    final d = item.decl;
    final isMasked = d.isSecure && (_obscured[d.key] ?? true);
    return TextFormField(
      controller: _controllers[d.key],
      obscureText: isMasked,
      decoration: _decoration(isDark).copyWith(
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

  InputDecoration _decoration(bool isDark) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      filled: true,
      fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
    );
  }
}
