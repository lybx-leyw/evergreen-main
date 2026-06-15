import 'memory.dart' show Memory;
import 'scope.dart';
import 'router.dart';

/// 记忆系统统一入口。
///
/// 所有记忆操作通过此 Facade 进行——消费者无需知道
/// 记忆存储在哪个后端、如何序列化、如何注入 system prompt。
///
/// ```dart
/// final facade = MemoryFacade(router);
///
/// // 写入全局偏好
/// await facade.remember(MemoryScope.global, Memory(
///   name: 'prefer-chinese', title: '用中文回答',
///   type: MemoryType.user, body: '用户偏好简体中文。',
/// ));
///
/// // 搜索功能级记忆
/// final results = await facade.search(MemoryScope.feature, '成绩');
///
/// // 构建 system prompt 上下文（三 scope 自动合并）
/// final context = await facade.buildContext();
/// ```
class MemoryFacade {
  final MemoryRouter _router;

  MemoryFacade(this._router);

  /// 写入记忆到指定 scope。
  Future<void> remember(MemoryScope scope, Memory memory) async {
    await _router.backend(scope).save(memory);
  }

  /// 召回单条记忆。
  Future<Memory?> recall(MemoryScope scope, String name) async {
    return _router.backend(scope).get(name);
  }

  /// 搜索记忆（关键词匹配 title + body）。
  Future<List<Memory>> search(MemoryScope scope, String query) async {
    return _router.backend(scope).search(query);
  }

  /// 删除记忆。
  Future<void> forget(MemoryScope scope, String name) async {
    await _router.backend(scope).delete(name);
  }

  /// 构建 system prompt 注入块——合并三个 scope 的记忆。
  ///
  /// 格式：
  /// ```
  /// ## 对话上下文 (Conversation Memory)
  /// ...
  ///
  /// ## 功能记忆 (Feature Memory)
  /// ...
  ///
  /// ## 项目记忆 (Global Memory)
  /// ...
  /// ```
  Future<String> buildContext() async {
    final buf = StringBuffer();
    for (final scope in MemoryScope.values) {
      final ctx = await _router.backend(scope).buildContextString();
      if (ctx.isNotEmpty) {
        final label = switch (scope) {
          MemoryScope.conversation => '对话上下文 (Conversation Memory)',
          MemoryScope.feature => '功能记忆 (Feature Memory)',
          MemoryScope.global => '项目记忆 (Global Memory)',
        };
        buf.writeln('## $label');
        buf.writeln(ctx);
        buf.writeln();
      }
    }
    return buf.toString().trimRight();
  }
}
