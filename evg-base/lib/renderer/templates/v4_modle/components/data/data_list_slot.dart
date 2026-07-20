/// DataList slot — 数据驱动的 ListView.separated 列表组件。
///
/// 不同于 card-list 的固定 2 列 GridView，本组件渲染为线性列表，
/// 每个数据项映射为 ListTile（title/subtitle/leading/trailing 均可配置），
/// 数据条目数与拉取数据量一一对应——课程越多卡片越多。
///
/// 特性：
/// - 可选搜索栏（关键字过滤，支持多字段搜索）
/// - ListView.separated 线性列表
/// - 每项 ListTile 的 title/subtitle/leading/trailing 由 item template 控制
/// - 尾部操作按钮支持 4 种 action：
///   - `navigate`（默认）：发出 `slot:navigate:{target}` 事件
///   - `link`：url_launcher 打开外置浏览器
///   - `switch_page`：发出 `slot:switch_page:{target}` 切换 Tab 页
///   - `custom`：发出 `slot:data_action:{target}` 自定义事件
/// - 优雅空态（数据源无数据/搜索无匹配时）
///
/// 继承 DataSourceSlot，自动处理数据加载、autoRefresh、优雅降级。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/slot/data_source_slot.dart';

// ═══════ DataListSlot ═══════

/// 数据驱动列表组件——读取 dataSource 拉取的数据，渲染为 ListView.separated。
class DataListSlot extends DataSourceSlot {
  final PageEventBus? pageEventBus;

  const DataListSlot({super.key, required super.config, this.pageEventBus});

  @override
  DataSourceSlotState<DataListSlot> createState() => _DataListSlotState();
}

class _DataListSlotState extends DataSourceSlotState<DataListSlot> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── mergeData ───

  @override
  Map<String, dynamic> mergeData(Map<String, dynamic> base, dynamic resolved) {
    final merged = <String, dynamic>{...base};
    if (resolved is List) {
      merged['items'] = resolved; // 行列表直接作为 items
    } else if (resolved is Map<String, dynamic>) {
      if (resolved.containsKey('items')) {
        merged['items'] = resolved['items'];
      } else {
        merged.addAll(resolved);
      }
    }
    return merged;
  }

  // ─── buildStatic ───

  @override
  Widget buildStatic(Map<String, dynamic> cfg) {
    final title = cfg['title'] as String?;
    final rawItems = (cfg['items'] as List<dynamic>?) ?? <dynamic>[];
    final itemTemplate = cfg['item'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final searchable = cfg['searchable'] == true;
    final searchPlaceholder = cfg['searchPlaceholder'] as String? ?? '搜索...';
    final searchFields = (cfg['searchFields'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
    final separatorCfg = cfg['separator'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final emptyCfg = cfg['emptyState'] as Map<String, dynamic>? ?? const <String, dynamic>{};

    // 搜索过滤
    final filtered = _filterItems(rawItems, searchFields);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        if (title != null && title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        // 搜索栏
        if (searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: searchPlaceholder,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        // 列表
        Expanded(
          child: filtered.isEmpty
              ? _emptyState(emptyCfg, colorScheme)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      _buildSeparator(separatorCfg, colorScheme),
                  itemBuilder: (ctx, i) =>
                      _buildItem(ctx, filtered[i], itemTemplate, colorScheme),
                ),
        ),
      ],
    );
  }

  // ─── 搜索过滤 ───

  List<dynamic> _filterItems(List<dynamic> items, List<String> fields) {
    if (_query.isEmpty) return items;
    final q = _query.toLowerCase();
    return items.where((item) {
      if (item is! Map) return false;
      // 若配置了 searchFields，只搜索指定字段
      if (fields.isNotEmpty) {
        return fields.any((f) {
          final v = _fieldValue(item, f);
          return v.toLowerCase().contains(q);
        });
      }
      // 否则搜索所有字符串字段
      return item.values.any((v) {
        if (v is String) return v.toLowerCase().contains(q);
        if (v is num) return v.toString().contains(q);
        return false;
      });
    }).toList();
  }

  // ─── 分隔线 ───

  Widget _buildSeparator(Map<String, dynamic> sep, ColorScheme cs) {
    final type = sep['type'] as String? ?? 'divider';
    final height = (sep['height'] as num?)?.toDouble() ?? 1.0;
    if (type == 'none') return const SizedBox.shrink();
    return Divider(
      height: height,
      indent: sep['indent'] as double? ?? 16,
      endIndent: sep['endIndent'] as double? ?? 16,
      color: cs.outlineVariant.withAlpha(120),
    );
  }

  // ─── 列表项 ───

  Widget _buildItem(BuildContext context, dynamic raw,
      Map<String, dynamic> tmpl, ColorScheme cs) {
    if (raw is! Map) {
      return ListTile(title: Text(raw.toString()));
    }
    final item = raw as Map<String, dynamic>;

    final titleField = tmpl['titleField'] as String? ?? '';
    final subtitleCfg = tmpl['subtitle'] as Map<String, dynamic>?;
    final leadingCfg = tmpl['leading'] as Map<String, dynamic>?;
    final trailingActions =
        (tmpl['trailingActions'] as List<dynamic>?) ?? <dynamic>[];

    // Title
    final titleText =
        titleField.isNotEmpty ? _fieldValue(item, titleField) : '';

    // Subtitle: 多字段拼接
    String? subtitleText;
    if (subtitleCfg != null) {
      final fields = (subtitleCfg['fields'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          <String>[];
      final sep = subtitleCfg['separator'] as String? ?? ' · ';
      final parts = fields
          .map((f) => _fieldValue(item, f))
          .where((v) => v.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) subtitleText = parts.join(sep);
    }

    // Leading
    Widget? leading;
    if (leadingCfg != null) {
      final iconField = leadingCfg['iconField'] as String?;
      final colorField = leadingCfg['colorField'] as String?;
      if (iconField != null) {
        final iconCode = _fieldValue(item, iconField);
        final icon = _resolveIcon(iconCode);
        Color? color;
        if (colorField != null) {
          final colorStr = _fieldValue(item, colorField);
          color = _parseColor(colorStr);
        }
        leading = Icon(icon, size: 28, color: color ?? cs.primary);
      }
    }

    // Trailing actions
    List<Widget>? trailing;
    if (trailingActions.isNotEmpty) {
      trailing = trailingActions.map<Widget>((act) {
        final a = act as Map<String, dynamic>;
        final icon = _resolveIcon(a['icon'] as String? ?? '');
        final tooltip = a['tooltip'] as String? ?? '';
        final action = a['action'] as String? ?? 'navigate';
        final target = a['target'] as String? ?? '';
        return IconButton(
          icon: Icon(icon, size: 20),
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          onPressed: () {
            _dispatchAction(action, target, item);
          },
        );
      }).toList();
    }

    return ListTile(
      title: Text(titleText,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(fontWeight: FontWeight.w500)),
      subtitle: subtitleText != null
          ? Text(subtitleText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis)
          : null,
      leading: leading,
      trailing: trailing != null
          ? Row(mainAxisSize: MainAxisSize.min, children: trailing)
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }

  // ─── 空态 ───

  Widget _emptyState(Map<String, dynamic> emptyCfg, ColorScheme cs) {
    final icon = _resolveIcon(emptyCfg['icon'] as String? ?? 'inbox');
    final message = emptyCfg['message'] as String? ?? '暂无数据';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant.withAlpha(120)),
            const SizedBox(height: 12),
            Text(message,
                style: TextStyle(
                    color: cs.onSurfaceVariant.withAlpha(180), fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ─── 工具方法 ───

  /// 从数据项中安全取字段值。
  String _fieldValue(Map map, String field) {
    final v = map[field];
    if (v == null) return '';
    return v.toString();
  }

  /// 字符串 → Material Icon（通过 IconData 字面量匹配）。
  IconData _resolveIcon(String code) {
    // 从常见 Material Icons 中查找 —— 支持 25+ 常用图标名
    switch (code) {
      case 'person_search': return Icons.person_search;
      case 'download': return Icons.download;
      case 'grade': return Icons.grade;
      case 'school': return Icons.school;
      case 'person': return Icons.person;
      case 'star': return Icons.star;
      case 'favorite': return Icons.favorite;
      case 'info': return Icons.info;
      case 'settings': return Icons.settings;
      case 'edit': return Icons.edit;
      case 'delete': return Icons.delete;
      case 'share': return Icons.share;
      case 'bookmark': return Icons.bookmark;
      case 'flag': return Icons.flag;
      case 'check': return Icons.check;
      case 'close': return Icons.close;
      case 'refresh': return Icons.refresh;
      case 'search': return Icons.search;
      case 'mail': return Icons.mail;
      case 'phone': return Icons.phone;
      case 'map': return Icons.map;
      case 'calendar_today': return Icons.calendar_today;
      case 'article': return Icons.article;
      case 'description': return Icons.description;
      case 'inbox': return Icons.inbox;
      default: return Icons.circle;
    }
  }

  /// 字符串颜色 → Color。
  Color? _parseColor(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final hex = s.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return null;
    }
  }

  /// 根据 action 类型分发尾部操作按钮事件。
  ///
  /// 支持四种 action：
  /// - `navigate`（默认）：发出 `slot:navigate:{target}` 事件
  /// - `link`：用 url_launcher 打开外置浏览器
  /// - `switch_page`：发出 `slot:switch_page:{target}` 事件
  /// - `custom`：发出 `slot:data_action:{target}` 自定义事件
  void _dispatchAction(String action, String target, Map<String, dynamic> item) {
    // 替换 target 中的 {fieldName} 占位符
    var resolved = target;
    if (resolved.contains('{')) {
      item.forEach((k, v) {
        resolved = resolved.replaceAll('{$k}', v.toString());
      });
    }

    switch (action) {
      case 'link':
        _openLink(resolved);
        return;
      case 'switch_page':
        widget.pageEventBus?.emit(
          'slot:switch_page:$resolved',
          sourceSlot: 'data-list',
          data: {'item': item, 'target': resolved},
        );
        return;
      case 'custom':
        widget.pageEventBus?.emit(
          'slot:data_action:$resolved',
          sourceSlot: 'data-list',
          data: {'item': item, 'target': resolved},
        );
        return;
      default: // 'navigate' 或未知
        widget.pageEventBus?.emit(
          'slot:navigate:$resolved',
          sourceSlot: 'data-list',
          data: {'item': item, 'target': resolved},
        );
    }
  }

  /// 用 [url_launcher] 打开外置浏览器。
  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 静默失败：无法打开链接
    }
  }
}
