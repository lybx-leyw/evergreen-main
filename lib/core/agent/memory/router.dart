import 'scope.dart';
import 'store_interface.dart';
import 'in_memory_store.dart';
import 'file_memory_store.dart' show FileMemoryStore;

/// 根据 [MemoryScope] 路由到对应的 [MemoryStore] 后端。
///
/// 无状态——只负责查表，不持有业务逻辑。
class MemoryRouter {
  final InMemoryStore _conversation;
  final InMemoryStore _feature; // TODO: 阶段四-B 替换为 DriftMemoryStore
  final FileMemoryStore _global;

  MemoryRouter({
    InMemoryStore? conversation,
    InMemoryStore? feature,
    required FileMemoryStore global,
  })  : _conversation = conversation ?? InMemoryStore(),
        _feature = feature ?? InMemoryStore(),
        _global = global;

  /// 根据 scope 返回对应的 store。
  IMemoryStore backend(MemoryScope scope) {
    switch (scope) {
      case MemoryScope.conversation:
        return _conversation;
      case MemoryScope.feature:
        return _feature;
      case MemoryScope.global:
        return _global;
    }
  }
}
