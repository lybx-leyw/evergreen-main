/// 记忆合并测试：直接拼接 + 同 id 跳过 + 索引重建。
library;

import 'dart:io';

import 'package:test/test.dart';

import '../memory/memory.dart' show Memory, MemoryType;
import '../memory/file_memory_store.dart';
import '../memory/memory_merge.dart';

Memory _mem(String name, String body) => Memory(
      name: name,
      title: name,
      description: '测试记忆',
      type: MemoryType.user,
      body: body,
      priority: 'medium',
    );

void main() {
  group('mergeMemories · 直接拼接', () {
    test('不同 name → 全量拼接', () {
      final local = [_mem('fact-a', 'A'), _mem('fact-b', 'B')];
      final imported = [_mem('fact-c', 'C')];

      final r = mergeMemories(local, imported);

      expect(r.merged.length, 3);
      expect(r.merged.map((m) => m.name).toSet(), {'fact-a', 'fact-b', 'fact-c'});
      expect(r.skippedDuplicates, isEmpty);
    });

    test('同 name → 导入跳过（保留本地版本），计入 skippedDuplicates', () {
      final local = [_mem('fact-a', '本地版本')];
      final imported = [_mem('fact-a', '导入版本'), _mem('fact-b', 'B')];

      final r = mergeMemories(local, imported);

      expect(r.merged.length, 2);
      expect(r.merged.firstWhere((m) => m.name == 'fact-a').body, '本地版本');
      expect(r.skippedDuplicates.single.name, 'fact-a');
    });

    test('本地为空 → 导入全量进入', () {
      final r = mergeMemories([], [_mem('fact-a', 'A')]);

      expect(r.merged.length, 1);
      expect(r.skippedDuplicates, isEmpty);
    });
  });

  group('mergeMemoriesIntoStore · 落盘 + 索引重建', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('evg_mem_merge_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('写入新增记忆并重建 MEMORY.md 索引', () async {
      final store = FileMemoryStore(tmp.path);
      await store.save(_mem('fact-local', '本地'));

      final r = await mergeMemoriesIntoStore(store, [
        _mem('fact-imported', '导入'),
        _mem('fact-local', '重复导入'), // 同 id 跳过
      ]);

      // 两个文件落盘
      expect(File('${tmp.path}/fact-local.md').existsSync(), isTrue);
      expect(File('${tmp.path}/fact-imported.md').existsSync(), isTrue);
      // 索引重建且包含两条
      final index = File('${tmp.path}/MEMORY.md').readAsStringSync();
      expect(index, contains('fact-local'));
      expect(index, contains('fact-imported'));
      // 重复导入被跳过且未覆盖本地
      expect(r.skippedDuplicates.single.name, 'fact-local');
      final localReload = await store.get('fact-local');
      expect(localReload!.body, '本地');
    });
  });
}
