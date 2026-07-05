import 'memory.dart' show Memory, MemorySet, MemoryStore;
import 'store_interface.dart';

/// Global 级记忆——委托给现有的文件系统 [`MemoryStore`]。
///
/// 对应的物理存储：`{dir}/*.md` + `MEMORY.md` 索引文件。
/// 保留现有 `MemoryStore` 完全不动，仅通过适配器实现抽象接口。
class FileMemoryStore implements IMemoryStore {
  final MemoryStore _delegate;

  FileMemoryStore(String dir) : _delegate = MemoryStore(dir);

  @override
  Future<void> save(Memory memory) async => _delegate.save(memory);

  @override
  Future<Memory?> get(String name) async => _delegate.get(name);

  @override
  Future<List<Memory>> all() async => _delegate.all();

  @override
  Future<List<Memory>> search(String query) async {
    final all = _delegate.all();
    final q = query.toLowerCase();
    return all
        .where((m) =>
            m.title.toLowerCase().contains(q) ||
            m.body.toLowerCase().contains(q) ||
            m.description.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<void> delete(String name) async => _delegate.delete(name);

  @override
  Future<String> buildContextString() async {
    final set = MemorySet(store: _delegate);
    return set.toContextString();
  }
}
