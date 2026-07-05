/// 设置视图——渲染内置/插件配置项。
///
/// 从 [sharedPreferencesProvider] 读取 [getAllSettings]，
/// 按类型渲染对应输入控件（文本/开关/路径选择）。
///
/// 公开类：[SettingsView]
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/config/settings.dart' as cfg;
import 'package:evergreen_base/providers.dart';

/// 设置列表视图。
///
/// 由 [ModuleDispatch] 在 `ui == 'settings'` 时创建。
class SettingsView extends ConsumerStatefulWidget {
  final ModuleDescriptor descriptor;

  const SettingsView({super.key, required this.descriptor});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final settings = cfg.getAllSettings(prefs);
    final theme = Theme.of(context);

    if (settings.isEmpty) {
      return const Center(
        child: Text('暂无设置项\n请在 config.json 中声明设置',
            textAlign: TextAlign.center),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: settings.length + 1, // +1 for header
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildHeader(theme);
        }
        final entry = settings[index - 1];
        return _buildSettingTile(entry.decl, entry.value, theme);
      },
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.descriptor.name,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(widget.descriptor.description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildSettingTile(
      cfg.SettingDecl decl, String currentValue, ThemeData theme) {
    final isSecure = decl.isSecure;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // 标签区
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(decl.label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500)),
                if (decl.hint != null && decl.hint!.isNotEmpty)
                  Text(decl.hint!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 控件区
          Expanded(child: _buildControl(decl, currentValue, isSecure, isDark)),
        ],
      ),
    );
  }

  Widget _buildControl(
      cfg.SettingDecl decl, String currentValue, bool isSecure, bool isDark) {
    final prefs = ref.read(sharedPreferencesProvider);

    switch (decl.type) {
      case cfg.SettingType.bool_:
        return Switch(
          value: currentValue == 'true',
          onChanged: (v) {
            cfg.setSetting(prefs, decl.key, v.toString());
            setState(() {}); // 刷新 UI
          },
        );

      case cfg.SettingType.option:
        if (decl.options == null || decl.options!.isEmpty) {
          return _buildTextField(decl, currentValue, isSecure, prefs);
        }
        return DropdownButtonFormField<String>(
          value: decl.options!.any((o) => o.value == currentValue)
              ? currentValue
              : decl.options!.first.value,
          isExpanded: true,
          decoration: _inputDecoration(decl.key, isDark),
          items: decl.options!
              .map((o) => DropdownMenuItem(value: o.value, child: Text(o.label)))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              cfg.setSetting(prefs, decl.key, v);
              setState(() {});
            }
          },
        );

      case cfg.SettingType.string:
      case cfg.SettingType.path:
      default:
        return _buildTextField(decl, currentValue, isSecure, prefs);
    }
  }

  Widget _buildTextField(cfg.SettingDecl decl, String currentValue,
      bool isSecure, dynamic prefs) {
    if (!_controllers.containsKey(decl.key)) {
      _controllers[decl.key] = TextEditingController(text: currentValue);
    }

    return TextField(
      controller: _controllers[decl.key],
      obscureText: isSecure,
      decoration: _inputDecoration(decl.key, true).copyWith(
        suffixIcon: isSecure
            ? IconButton(
                icon: const Icon(Icons.visibility_off, size: 20),
                onPressed: () {
                  // toggle visibility via rebuild
                  setState(() {});
                },
              )
            : null,
      ),
      style: TextStyle(fontSize: 14, fontFamily: isSecure ? 'monospace' : null),
      onChanged: (v) {
        cfg.setSetting(prefs, decl.key, v);
      },
    );
  }

  InputDecoration _inputDecoration(String key, bool isDark) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300)),
      filled: true,
      fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
    );
  }
}
