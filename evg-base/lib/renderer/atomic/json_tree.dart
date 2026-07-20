/// JSON 结构树模型 —— 供插件设计器「点选数据路径 (dataPath)」使用。
///
/// 将任意 decoded JSON（`Map`/`List`/标量）构建为 [JsonTreeNode] 树，
/// 每个节点携带与 [extractPath]（`json_path.dart`）完全兼容的 [JsonTreeNode.path]。
///
/// 纯 Dart、无 Flutter 依赖，便于单元测试。
library;

import 'package:evergreen_base/renderer/atomic/json_path.dart';

/// 键名能否被 [extractPath] 的 token 语法（`[a-zA-Z_][a-zA-Z0-9_]*`）完整表达。
///
/// 含 `-`、空格、数字开头等字符的键无法生成合法点路径（extractPath 的
/// `RegExp.allMatches` 会静默跳过非法片段，导致解析错位），此类键在 UI 上
/// 必须禁止点选。
bool isExpressibleKey(String key) {
  return RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(key);
}

/// 由路径段序列生成 [extractPath] 兼容的点路径字符串。
///
/// 段为 [String]（字段名）或 [int]（数组下标）：
///   `['a', 'b']`      → `a.b`
///   `['a', 'b', 0, 'c']` → `a.b[0].c`
///   `[]`              → `''`（根 = 全量数据）
String jsonPathOf(List<dynamic> segments) {
  final buf = StringBuffer();
  for (final seg in segments) {
    if (seg is int) {
      buf.write('[$seg]');
    } else {
      if (buf.isNotEmpty) buf.write('.');
      buf.write(seg);
    }
  }
  return buf.toString();
}

/// JSON 树节点类别。
enum JsonNodeKind { map, list, value }

/// JSON 结构树节点（不可变）。
class JsonTreeNode {
  /// 展示名：Map 节点为键名，List 元素为 `[i]`，根节点为 [label] 入参。
  final String label;

  /// 从根到本节点的 [extractPath] 兼容路径；根为 `''`。
  final String path;

  final JsonNodeKind kind;

  /// 叶子节点的值摘要（截断）；容器节点为 `{n 键}` / `[n 项]`。
  final String summary;

  /// 子节点（容器才有；可能因截断少于实际子项数）。
  final List<JsonTreeNode> children;

  /// 本节点路径是否可被 [extractPath] 表达（链路上所有键均合法）。
  final bool pathValid;

  /// 容器实际子项总数（截断前）。
  final int totalChildren;

  const JsonTreeNode({
    required this.label,
    required this.path,
    required this.kind,
    required this.summary,
    this.children = const [],
    this.pathValid = true,
    this.totalChildren = 0,
  });

  bool get isContainer => kind != JsonNodeKind.value;
}

/// 值摘要最大长度。
const int kMaxSummaryLength = 40;

/// 构建 JSON 结构树。
///
/// - [label]：根节点展示名（默认 `root`）。
/// - [maxListItems]：每个 List 最多展开的子项数，超出计入 [JsonTreeNode.totalChildren]。
/// - [maxDepth]：最大递归深度，防御深层嵌套（超出按值摘要处理）。
JsonTreeNode buildJsonTree(
  dynamic root, {
  String label = 'root',
  int maxListItems = 50,
  int maxDepth = 12,
}) {
  return _build(root, label, const [], true, 0, maxListItems, maxDepth);
}

JsonTreeNode _build(
  dynamic value,
  String label,
  List<dynamic> segments,
  bool ancestorValid,
  int depth,
  int maxListItems,
  int maxDepth,
) {
  final path = jsonPathOf(segments);
  if (value is Map && depth < maxDepth) {
    final entries = value.entries.toList();
    final children = <JsonTreeNode>[];
    for (final e in entries) {
      final key = e.key.toString();
      final valid = ancestorValid && isExpressibleKey(key);
      children.add(_build(
          e.value, key, [...segments, key], valid, depth + 1, maxListItems, maxDepth));
    }
    return JsonTreeNode(
      label: label,
      path: path,
      kind: JsonNodeKind.map,
      summary: '{${entries.length} 键}',
      children: children,
      pathValid: ancestorValid,
      totalChildren: entries.length,
    );
  }
  if (value is List && depth < maxDepth) {
    final shown = value.length > maxListItems ? maxListItems : value.length;
    final children = <JsonTreeNode>[];
    for (var i = 0; i < shown; i++) {
      children.add(_build(
          value[i], '[$i]', [...segments, i], ancestorValid, depth + 1, maxListItems, maxDepth));
    }
    return JsonTreeNode(
      label: label,
      path: path,
      kind: JsonNodeKind.list,
      summary: '[${value.length} 项]',
      children: children,
      pathValid: ancestorValid,
      totalChildren: value.length,
    );
  }
  return JsonTreeNode(
    label: label,
    path: path,
    kind: JsonNodeKind.value,
    summary: _summarizeValue(value),
    pathValid: ancestorValid,
  );
}

String _summarizeValue(dynamic v) {
  final String raw;
  if (v == null) {
    raw = 'null';
  } else if (v is String) {
    raw = '"$v"';
  } else if (v is Map) {
    // 超过 maxDepth 的容器按摘要展示
    raw = '{${v.length} 键}';
  } else if (v is List) {
    raw = '[${v.length} 项]';
  } else {
    raw = v.toString();
  }
  return raw.length > kMaxSummaryLength
      ? '${raw.substring(0, kMaxSummaryLength)}…'
      : raw;
}

/// 带深度的可见节点（供扁平化列表渲染）。
class FlatJsonNode {
  final JsonTreeNode node;
  final int depth;
  const FlatJsonNode(this.node, this.depth);
}

/// 将树按展开集合扁平化为可见节点序列（DFS 先序）。
///
/// [expanded] 中存放已展开节点的 path；根（`''`）始终可见并视为已展开。
/// 仅容器节点可展开；未展开的容器不输出其子树。
List<FlatJsonNode> flattenVisible(JsonTreeNode root, Set<String> expanded) {
  final out = <FlatJsonNode>[];
  void walk(JsonTreeNode node, int depth) {
    out.add(FlatJsonNode(node, depth));
    if (!node.isContainer) return;
    if (node.path.isNotEmpty && !expanded.contains(node.path)) return;
    for (final c in node.children) {
      walk(c, depth + 1);
    }
  }

  walk(root, 0);
  return out;
}

/// 找出树中 path 与 [extractPath] 往返一致性的快捷校验（测试用）。
///
/// 返回 true 表示 `extractPath(root, node.path)` 能取到非 null（路径有效）。
bool pathRoundTrip(dynamic root, JsonTreeNode node) {
  if (node.path.isEmpty) return true;
  return extractPath(root, node.path) != null;
}

/// 提取 [path] 的全部祖先路径（不含自身），用于按已配置路径自动展开树。
///
/// 例：`a.b[0].c` → `{'a', 'a.b', 'a.b[0]'}`；空路径 → 空集合。
/// 使用与 [extractPath] 完全相同的 token 正则，保证前缀链一致。
Set<String> ancestorPaths(String? path) {
  final out = <String>{};
  if (path == null || path.trim().isEmpty) return out;
  final re = RegExp(r'([a-zA-Z_][a-zA-Z0-9_]*)|\s*\[(\d+)\]\s*');
  final segments = <dynamic>[];
  for (final m in re.allMatches(path.trim())) {
    if (m.group(1) != null) {
      segments.add(m.group(1)!);
    } else if (m.group(2) != null) {
      segments.add(int.parse(m.group(2)!));
    }
  }
  for (var i = 1; i < segments.length; i++) {
    out.add(jsonPathOf(segments.sublist(0, i)));
  }
  return out;
}
