import 'memory.dart' show Memory;
import 'store_interface.dart';

/// Conversation 级记忆——存储在内存 Map 中，会话结束即丢弃。
///
/// 注意：`search` 使用简单的 `body.contains(query)` 全文匹配。
class InMemoryStore implements IMemoryStore {
  final Map<String, Memory> _store = {};

  @override
  Future<void> save(Memory memory) async {
    _store[memory.name] = memory;
  }

  @override
  Future<Memory?> get(String name) async => _store[name];

  @override
  Future<List<Memory>> all() async => _store.values.toList();

  @override
  Future<List<Memory>> search(String query) async {
    final q = query.toLowerCase();
    return _store.values
        .where((m) =>
            m.title.toLowerCase().contains(q) ||
            m.body.toLowerCase().contains(q) ||
            m.description.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<void> delete(String name) async {
    _store.remove(name);
  }

  @override
  Future<String> buildContextString() async {
    if (_store.isEmpty) return '';
    final buf = StringBuffer();
    final highPriority = _store.values.where((m) => m.priority == 'high');
    final rest = _store.values.where((m) => m.priority != 'high');

    for (final m in highPriority) {
      buf.writeln('🔴 ${m.title}: ${m.description}');
    }
    for (final m in rest) {
      buf.writeln('- ${m.title}: ${m.description}');
    }
    return buf.toString();
  }
}
