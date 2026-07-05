/// 设置视图——通过 settings 模块 HTTP 接口获取/保存配置项。
///
/// 从 [modulePortsProvider] 获取 settings 模块端口，
/// 请求 `GET /api/settings` 获取所有设置声明及当前值，
/// 通过 `POST /api/settings/:key` 保存更改。
///
/// 公开类：[SettingsView]
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 数据模型（不依赖 cfg.SettingDecl，完全由 HTTP 响应驱动）
// ═══════════════════════════════════════════════════════════════════════════

/// 单个设置项（来自 `GET /settings` 的 `settings` 数组）。
class _SettingItem {
  final String key;
  final String label;
  final String type; // "string" | "bool" | "option" | "path"
  final String value;
  final String? defaultValue;
  final bool isSecure;
  final String? hint;
  final List<_OptionItem>? options;

  const _SettingItem({
    required this.key,
    required this.label,
    required this.type,
    required this.value,
    this.defaultValue,
    this.isSecure = false,
    this.hint,
    this.options,
  });

  factory _SettingItem.fromJson(Map<String, dynamic> json) {
    return _SettingItem(
      key: json['key'] as String,
      label: json['label'] as String? ?? json['key'] as String,
      type: json['type'] as String? ?? 'string',
      value: json['value'] as String? ?? '',
      defaultValue: json['defaultValue'] as String?,
      isSecure: json['isSecure'] == true,
      hint: json['hint'] as String?,
      options: (json['options'] as List<dynamic>?)
          ?.map((o) => _OptionItem.fromJson(o as Map<String, dynamic>))
          .toList(),
    );
  }

  _SettingItem copyWith({String? value}) {
    return _SettingItem(
      key: key,
      label: label,
      type: type,
      value: value ?? this.value,
      defaultValue: defaultValue,
      isSecure: isSecure,
      hint: hint,
      options: options,
    );
  }
}

class _OptionItem {
  final String value;
  final String label;

  const _OptionItem({required this.value, required this.label});

  factory _OptionItem.fromJson(Map<String, dynamic> json) {
    return _OptionItem(
      value: json['value'] as String,
      label: json['label'] as String? ?? json['value'] as String,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SettingsView
// ═══════════════════════════════════════════════════════════════════════════

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
  final Map<String, TextEditingController> _controllers = {};

  /// 从 HTTP 获取的所有设置项。
  List<_SettingItem> _items = [];

  /// 加载错误信息。
  String? _error;

  /// 是否正在加载。
  bool _loading = true;

  /// settings 模块的 base URL。
  String? get _baseUrl {
    final ports = ref.read(modulePortsProvider);
    final port = ports['settings'];
    if (port == null || port == 0) return null;
    return 'http://127.0.0.1:$port';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── HTTP 请求 ──

  Future<void> _loadSettings() async {
    final base = _baseUrl;
    if (base == null) {
      setState(() {
        _error = 'settings 模块未启动（端口未知）';
        _loading = false;
      });
      return;
    }

    try {
      final client =
          HttpClient()..connectionTimeout = const Duration(seconds: 5);
      try {
        final req = await client.getUrl(Uri.parse('$base/api/settings'));
        final resp = await req.close().timeout(const Duration(seconds: 5));
        if (resp.statusCode != 200) {
          setState(() {
            _error = 'HTTP ${resp.statusCode}';
            _loading = false;
          });
          return;
        }
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final list = data['settings'] as List<dynamic>?;
        if (list == null) {
          setState(() {
            _error = '响应缺少 settings 字段';
            _loading = false;
          });
          return;
        }
        final items = list
            .map((e) => _SettingItem.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _items = items;
          _error = null;
          _loading = false;
        });
        _syncControllers(items);
      } finally {
        client.close();
      }
    } catch (e) {
      setState(() {
        _error = '加载失败: $e';
        _loading = false;
      });
    }
  }

  Future<void> _saveSetting(String key, String value) async {
    final base = _baseUrl;
    if (base == null) return;

    try {
      final client =
          HttpClient()..connectionTimeout = const Duration(seconds: 5);
      try {
        final req = await client.postUrl(Uri.parse('$base/api/settings/$key'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'value': value}));
        final resp = await req.close().timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          debugPrint('[settings] 已保存 $key = $value');
          // 本地更新值以即时反映 UI 变化
          _updateLocalValue(key, value);
        } else {
          debugPrint('[settings] 保存 $key 失败: HTTP ${resp.statusCode}');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[settings] 保存 $key 异常: $e');
    }
  }

  void _updateLocalValue(String key, String newValue) {
    setState(() {
      _items = _items.map((item) {
        if (item.key == key) return item.copyWith(value: newValue);
        return item;
      }).toList();
    });
  }

  void _syncControllers(List<_SettingItem> items) {
    // 清理不再存在的 controller
    final currentKeys = items.map((i) => i.key).toSet();
    for (final k in _controllers.keys.where((k) => !currentKeys.contains(k))) {
      _controllers.remove(k)?.dispose();
    }
    // 更新/创建 controller
    for (final item in items) {
      if (item.type == 'string' || item.type == 'path') {
        if (_controllers.containsKey(item.key)) {
          _controllers[item.key]!.text = item.value;
        } else {
          _controllers[item.key] = TextEditingController(text: item.value);
        }
      }
    }
  }

  // ── 渲染 ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadSettings();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Text('暂无设置项\n请在 config.json 中声明设置',
            textAlign: TextAlign.center),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSettings,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + 1, // +1 for header
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == 0) return _buildHeader(theme);
          return _buildSettingTile(_items[index - 1], theme);
        },
      ),
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

  Widget _buildSettingTile(_SettingItem item, ThemeData theme) {
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
                Text(item.label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500)),
                if (item.hint != null && item.hint!.isNotEmpty)
                  Text(item.hint!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 控件区
          Expanded(child: _buildControl(item, isDark)),
        ],
      ),
    );
  }

  Widget _buildControl(_SettingItem item, bool isDark) {
    switch (item.type) {
      case 'bool':
        return Switch(
          value: item.value == 'true',
          onChanged: (v) {
            _saveSetting(item.key, v.toString());
          },
        );

      case 'option':
        if (item.options == null || item.options!.isEmpty) {
          return _buildTextField(item, isDark);
        }
        final currentValue = item.options!.any((o) => o.value == item.value)
            ? item.value
            : item.options!.first.value;
        return DropdownButtonFormField<String>(
          value: currentValue,
          isExpanded: true,
          decoration: _inputDecoration(item.key, isDark),
          items: item.options!
              .map((o) =>
                  DropdownMenuItem(value: o.value, child: Text(o.label)))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              _saveSetting(item.key, v);
            }
          },
        );

      case 'string':
      case 'path':
      default:
        return _buildTextField(item, isDark);
    }
  }

  Widget _buildTextField(_SettingItem item, bool isDark) {
    if (!_controllers.containsKey(item.key)) {
      _controllers[item.key] = TextEditingController(text: item.value);
    }

    return TextField(
      controller: _controllers[item.key],
      obscureText: item.isSecure,
      decoration: _inputDecoration(item.key, isDark).copyWith(
        suffixIcon: item.isSecure
            ? IconButton(
                icon: const Icon(Icons.visibility_off, size: 20),
                onPressed: () => setState(() {}),
              )
            : null,
      ),
      style: TextStyle(
          fontSize: 14, fontFamily: item.isSecure ? 'monospace' : null),
      onChanged: (v) {
        _saveSetting(item.key, v);
      },
    );
  }

  InputDecoration _inputDecoration(String key, bool isDark) {
    return InputDecoration(
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300)),
      filled: true,
      fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
    );
  }
}
