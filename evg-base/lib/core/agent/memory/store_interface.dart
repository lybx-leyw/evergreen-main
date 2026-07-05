/// 记忆存储抽象接口。

import 'memory.dart' show Memory;

// ═══════ IMemoryStore ═══════

/// 记忆存储抽象接口。
abstract class IMemoryStore {
  /// 保存一条记忆。
  Future<void> save(Memory memory);

  /// 按名称获取记忆。
  Future<Memory?> get(String name);

  /// 列出所有记忆。
  Future<List<Memory>> all();

  /// 按关键词搜索（匹配 title + body）。
  Future<List<Memory>> search(String query);

  /// 删除一条记忆。
  Future<void> delete(String name);

  /// 构建可注入 system prompt 的上下文字符串。
  Future<String> buildContextString();
}
