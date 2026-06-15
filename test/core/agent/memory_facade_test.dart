import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/memory/memory.dart';
import 'package:evergreen_multi_tools/core/agent/memory/facade.dart';
import 'package:evergreen_multi_tools/core/agent/memory/router.dart';
import 'package:evergreen_multi_tools/core/agent/memory/scope.dart';
import 'package:evergreen_multi_tools/core/agent/memory/in_memory_store.dart';
import 'package:evergreen_multi_tools/core/agent/memory/file_memory_store.dart';

void main() {
  group('MemoryFacade', () {
    late MemoryFacade facade;

    setUp(() async {
      final router = MemoryRouter(global: FileMemoryStore('.test_memories'));
      facade = MemoryFacade(router);
    });

    test('remember → recall 往返', () async {
      final mem = Memory(
        name: 'prefer-chinese',
        title: '用中文回答',
        type: MemoryType.user,
        body: '用户偏好简体中文。',
      );
      await facade.remember(MemoryScope.global, mem);

      final recalled = await facade.recall(MemoryScope.global, 'prefer-chinese');
      expect(recalled, isNotNull);
      expect(recalled!.title, '用中文回答');
      expect(recalled.body, '用户偏好简体中文。');
    });

    test('search 关键词匹配', () async {
      await facade.remember(MemoryScope.global, Memory(
        name: 'test-1',
        title: '成绩查询',
        type: MemoryType.user,
        body: '上次查询了微积分成绩',
      ));
      await facade.remember(MemoryScope.global, Memory(
        name: 'test-2',
        title: '课表',
        type: MemoryType.user,
        body: '周一有早课',
      ));

      final results = await facade.search(MemoryScope.global, '成绩');
      expect(results.any((m) => m.title.contains('成绩')), true);
    });

    test('forget 删除记忆', () async {
      await facade.remember(MemoryScope.global, Memory(
        name: 'to-delete',
        title: '删除测试',
        type: MemoryType.user,
        body: 'should be gone',
      ));
      await facade.forget(MemoryScope.global, 'to-delete');

      final gone = await facade.recall(MemoryScope.global, 'to-delete');
      expect(gone, isNull);
    });
  });
}
