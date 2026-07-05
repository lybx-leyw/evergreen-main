/// 根据 scope 路由到对应 MemoryStore 后端。
import 'scope.dart';
import 'store_interface.dart';
import 'in_memory_store.dart';
import 'file_memory_store.dart' show FileMemoryStore;

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
