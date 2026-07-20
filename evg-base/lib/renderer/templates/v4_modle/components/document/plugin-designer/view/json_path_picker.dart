/// 可交互 JSON 结构树 —— 点击节点生成 dataPath 键路径。
///
/// 用于插件设计器「数据预览与路径选择」弹窗：
/// - 懒展开：仅渲染展开集合内的可见节点（大 JSON 安全）
/// - 点击任意节点 → 生成与 `extractPath` 兼容的点路径（如 `a.b[0].c`）
/// - 键名含特殊字符（无法被 extractPath 表达）的节点禁止点选并置灰
/// - 按 [initialPath] 自动展开祖先链并高亮当前路径
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/atomic/json_tree.dart';

/// 点击节点选路径的树选择器。
class JsonPathPicker extends StatefulWidget {
  /// 已 decode 的 JSON 数据（Map/List/标量）。
  final dynamic data;

  /// 当前已配置的 dataPath（用于初始高亮 + 自动展开祖先链）。
  final String? initialPath;

  /// 点选节点回调（根节点 path 为 ''，表示使用全量数据）。
  final ValueChanged<String> onPathSelected;

  const JsonPathPicker({
    super.key,
    required this.data,
    this.initialPath,
    required this.onPathSelected,
  });

  @override
  State<JsonPathPicker> createState() => _JsonPathPickerState();
}

class _JsonPathPickerState extends State<JsonPathPicker> {
  late final JsonTreeNode _root;
  late final Set<String> _expanded;
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    _root = buildJsonTree(widget.data, label: '全部数据');
    final init = widget.initialPath;
    _selectedPath = (init != null && init.isNotEmpty) ? init : null;
    _expanded = ancestorPaths(init);
    debugPrint('[JsonPathPicker] 初始化: initialPath=$init, 自动展开 ${_expanded.length} 层');
  }

  void _toggle(String path) {
    setState(() {
      if (!_expanded.remove(path)) _expanded.add(path);
    });
  }

  void _select(JsonTreeNode node) {
    setState(() => _selectedPath = node.path);
    debugPrint('[JsonPathPicker] 选中路径: "${node.path}"');
    widget.onPathSelected(node.path);
  }

  @override
  Widget build(BuildContext context) {
    final visible = flattenVisible(_root, _expanded);
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (_, i) => _buildRow(visible[i]),
    );
  }

  Widget _buildRow(FlatJsonNode flat) {
    final theme = Theme.of(context);
    final node = flat.node;
    final selected = _selectedPath != null && _selectedPath == node.path;
    final expandable = node.isContainer && node.children.isNotEmpty;
    final isOpen = node.path.isEmpty || _expanded.contains(node.path);
    final enabled = node.pathValid;

    final row = InkWell(
      onTap: enabled ? () => _select(node) : null,
      child: Container(
        height: 28,
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : null,
        padding: EdgeInsets.only(left: 4 + flat.depth * 14.0, right: 8),
        child: Row(
          children: [
            // 展开/折叠箭头
            SizedBox(
              width: 20,
              child: expandable
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _toggle(node.path),
                      child: Icon(
                        isOpen ? Icons.expand_more : Icons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
            ),
            Icon(
              switch (node.kind) {
                JsonNodeKind.map => Icons.data_object,
                JsonNodeKind.list => Icons.view_list,
                JsonNodeKind.value => Icons.label_outline,
              },
              size: 13,
              color: enabled
                  ? theme.colorScheme.primary.withValues(alpha: 0.8)
                  : theme.disabledColor,
            ),
            const SizedBox(width: 4),
            Flexible(
              flex: 2,
              child: Text(
                node.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: enabled
                      ? theme.colorScheme.onSurface
                      : theme.disabledColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              flex: 3,
              child: Text(
                node.summary,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.75),
                ),
              ),
            ),
            if (!enabled)
              Icon(Icons.block, size: 12, color: theme.disabledColor),
            if (selected)
              Icon(Icons.check_circle,
                  size: 14, color: theme.colorScheme.primary),
            // 截断提示
            if (node.isContainer && node.totalChildren > node.children.length)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '+${node.totalChildren - node.children.length}',
                  style: TextStyle(fontSize: 10, color: theme.disabledColor),
                ),
              ),
          ],
        ),
      ),
    );

    if (!enabled) {
      return Tooltip(
        message: '键名含特殊字符，无法生成 dataPath（仅支持字母/数字/下划线，且不以数字开头）',
        child: row,
      );
    }
    return row;
  }
}
