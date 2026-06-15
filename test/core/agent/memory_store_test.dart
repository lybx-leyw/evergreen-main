import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/memory/in_memory_store.dart';
import 'package:evergreen_multi_tools/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_multi_tools/core/agent/memory/memory.dart';
import 'package:evergreen_multi_tools/core/agent/memory/router.dart';
import 'package:evergreen_multi_tools/core/agent/memory/scope.dart';

void main() {
  group('InMemoryStore', () {
    late InMemoryStore store;

    setUp(() => store = InMemoryStore());

    test('save + get 往返', () async {
      final m = Memory(name: 't1', title: '测试', type: MemoryType.user, body: '正文');
      await store.save(m);
      final got = await store.get('t1');
      expect(got, isNotNull);
      expect(got!.title, '测试');
      expect(got.body, '正文');
    });

    test('get 不存在的 key 返回 null', () async {
      expect(await store.get('nonexistent'), isNull);
    });

    test('save 同名覆盖', () async {
      await store.save(Memory(name: 'dup', title: '旧', type: MemoryType.user, body: 'old'));
      await store.save(Memory(name: 'dup', title: '新', type: MemoryType.user, body: 'new'));
      final got = await store.get('dup');
      expect(got!.title, '新');
    });

    test('delete 移除', () async {
      await store.save(Memory(name: 'd1', title: 'x', type: MemoryType.user, body: 'x'));
      await store.delete('d1');
      expect(await store.get('d1'), isNull);
    });

    test('all 返回全部', () async {
      await store.save(Memory(name: 'a', title: 'A', type: MemoryType.user, body: 'a'));
      await store.save(Memory(name: 'b', title: 'B', type: MemoryType.user, body: 'b'));
      final all = await store.all();
      expect(all.length, 2);
    });

    test('search 关键词匹配 title', () async {
      await store.save(Memory(name: 's1', title: '成绩', type: MemoryType.user, body: ''));
      final results = await store.search('成绩');
      expect(results.length, 1);
    });

    test('search 关键词匹配 body', () async {
      await store.save(Memory(name: 's2', title: 'X', type: MemoryType.user, body: '关于选课'));
      final results = await store.search('选课');
      expect(results.length, 1);
    });

    test('search 不区分大小写', () async {
      await store.save(Memory(name: 's3', title: 'GPA', type: MemoryType.user, body: ''));
      expect((await store.search('gpa')).length, 1);
      expect((await store.search('GPA')).length, 1);
    });

    test('search 无匹配返回空', () async {
      final results = await store.search('不存在');
      expect(results, isEmpty);
    });

    test('buildContextString 高优先级在前', () async {
      await store.save(Memory(name: 'lo', title: '低优', priority: 'low',
          type: MemoryType.user, body: '', description: ''));
      await store.save(Memory(name: 'hi', title: '高优', priority: 'high',
          type: MemoryType.user, body: '', description: ''));
      final ctx = await store.buildContextString();
      expect(ctx, contains('🔴'));
      expect(ctx.indexOf('🔴'), lessThan(ctx.indexOf('低优')));
    });

    test('buildContextString 空时返回空字符串', () async {
      expect(await store.buildContextString(), '');
    });
  });

  group('FileMemoryStore', () {
    test('构造函数不抛异常', () {
      expect(() => FileMemoryStore('.test_mem'), returnsNormally);
    });

    test('all 返回空（新目录）', () async {
      final store = FileMemoryStore('.test_mem_fresh');
      final all = await store.all();
      expect(all, isEmpty);
    });
  });

  group('MemoryRouter', () {
    late MemoryRouter router;
    late InMemoryStore conv;

    setUp(() {
      conv = InMemoryStore();
      router = MemoryRouter(
        conversation: conv,
        global: FileMemoryStore('.test_mem_router'),
      );
    });

    test('conversation scope → InMemoryStore', () {
      expect(router.backend(MemoryScope.conversation), same(conv));
    });

    test('feature scope → InMemoryStore', () {
      expect(router.backend(MemoryScope.feature), isA<InMemoryStore>());
    });

    test('global scope → FileMemoryStore', () {
      expect(router.backend(MemoryScope.global), isA<FileMemoryStore>());
    });
  });
}
