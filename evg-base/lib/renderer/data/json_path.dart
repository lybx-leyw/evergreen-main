/// JSON 点路径提取工具——自写，覆盖 M2 展示组件所需的 `results` / `results.items` 等形态。
///
/// 支持点路径与数组下标：
///   'a.b'      → root['a']['b']
///   'a.b[0].c' → ((root['a'] ?? {})['b'] ?? [])[0]['c']
///   '' / null  段缺失 / 下标越界 → 返回 null（绝不直接抛，便于 R5 优雅降级）
dynamic extractPath(dynamic root, String path) {
  if (root == null) return null;
  final trimmed = path.trim();
  if (trimmed.isEmpty) return root;

  // 切分路径为「字段名」或「下标」两种 token。
  final tokens = <dynamic>[];
  final re = RegExp(r'([a-zA-Z_][a-zA-Z0-9_]*)|\s*\[(\d+)\]\s*');
  for (final m in re.allMatches(trimmed)) {
    if (m.group(1) != null) {
      tokens.add(m.group(1)!);
    } else if (m.group(2) != null) {
      tokens.add(int.parse(m.group(2)!));
    }
  }
  if (tokens.isEmpty) return null;

  var current = root;
  for (final token in tokens) {
    if (current == null) return null;
    if (token is int) {
      if (current is List && token >= 0 && token < current.length) {
        current = current[token];
      } else {
        return null; // 下标越界
      }
    } else {
      if (current is Map) {
        current = current[token];
      } else {
        return null; // 当前节点不是 Map，无法继续走字段
      }
    }
  }
  return current;
}
