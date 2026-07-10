/// HTML render: renderTree
import 'dart:convert';
import '../shared/html_helpers.dart';

String renderTree(Map<String, dynamic> comp) {
  final cfg = comp['config'] as Map<String, dynamic>? ?? {};
  final root = cfg['root'] as Map<String, dynamic>? ?? {
    'label': '根节点',
    'children': [
      {'label': '子节点 A', 'children': [{'label': '叶子 A1'}, {'label': '叶子 A2'}]},
      {'label': '子节点 B'},
      {'label': '子节点 C', 'children': [{'label': '叶子 C1'}]},
    ],
  };

  String _renderNode(Map<String, dynamic> node, int depth) {
    final label = node['label'] as String? ?? '';
    final children = (node['children'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final hasChildren = children.isNotEmpty;
    final indent = depth * 20;
    final icon = node['icon'] as String? ?? (hasChildren ? '📁' : '📄');

    final childrenHtml = children.map((c) => _renderNode(c, depth + 1)).join('');

    return '''
<div class="evg-tree-node" style="padding-left:${indent}px">
  <div class="evg-tree-row">
    <span class="evg-tree-toggle">${hasChildren ? '▶' : '  '}</span>
    <span class="evg-tree-icon">$icon</span>
    <span class="evg-tree-label">${esc(label)}</span>
  </div>
  $childrenHtml
</div>''';
  }

  return '''
<div class="evg-comp evg-comp-tree">
  <div class="evg-comp-title">🌳 树形视图</div>
  <div class="evg-tree-container">${_renderNode(root, 0)}</div>
</div>''';
}
