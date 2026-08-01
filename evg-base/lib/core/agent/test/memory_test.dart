/// Memory 系统测试 — 覆盖 Memory CRUD 三 scope、MemoryStore 持久化、MemoryFact 矛盾检测。
library;

import 'dart:io';

import 'package:test/test.dart';

import '../memory/memory.dart';
import '../memory/in_memory_store.dart';
import '../memory/file_memory_store.dart';
import '../memory/scope.dart';
import '../memory/router.dart';
import '../memory/fact.dart';

void main() {
  // ═══════ Memory model ═══════

  group('Memory model', () {
    test('filename derives from name', () {
      final m = Memory(name: 'my-fact', description: 'test');
      expect(m.filename, 'my-fact.md');
    });

    test('title defaults to de-kebab name', () {
      final m = Memory(name: 'user-preference');
      expect(m.title, 'User Preference');
    });

    test('toYamlFrontmatter includes all fields', () {
      final m = Memory(
        name: 'fact-1',
        description: 'a fact',
        type: MemoryType.user,
        priority: 'high',
      );
      final fm = m.toYamlFrontmatter();
      expect(fm['name'], 'fact-1');
      expect(fm['type'], 'user');
      expect(fm['priority'], 'high');
    });

    test('MemoryType fromString', () {
      expect(MemoryType.fromString('user'), MemoryType.user);
      expect(MemoryType.fromString('feedback'), MemoryType.feedback);
      expect(MemoryType.fromString('project'), MemoryType.project);
      expect(MemoryType.fromString('reference'), MemoryType.reference);
      expect(MemoryType.fromString('unknown'), MemoryType.project); // fallback
    });
  });

  // ═══════ InMemoryStore ═══════

  group('InMemoryStore', () {
    late InMemoryStore store;

    setUp(() async {
      store = InMemoryStore();
    });

    test('save and get', () async {
      final m = Memory(name: 'test', description: 'desc', body: 'body');
      await store.save(m);
      final got = await store.get('test');
      expect(got, isNotNull);
      expect(got!.description, 'desc');
    });

    test('save overwrites same name', () async {
      await store.save(Memory(name: 'x', description: 'first'));
      await store.save(Memory(name: 'x', description: 'second'));
      final got = await store.get('x');
      expect(got!.description, 'second');
    });

    test('all returns all memories', () async {
      await store.save(Memory(name: 'a', description: 'a'));
      await store.save(Memory(name: 'b', description: 'b'));
      final all = await store.all();
      expect(all.length, 2);
    });

    test('delete removes memory', () async {
      await store.save(Memory(name: 'x', description: 'x'));
      await store.delete('x');
      expect(await store.get('x'), isNull);
    });

    test('search matches title and body', () async {
      await store.save(Memory(name: 'a', title: 'Python', body: 'django'));
      await store.save(Memory(name: 'b', title: 'Dart', body: 'flutter'));
      final results = await store.search('python');
      expect(results.length, 1);
      expect(results.first.name, 'a');
    });

    test('search empty returns empty', () async {
      final results = await store.search('');
      expect(results, isEmpty);
    });

    test('buildContextString returns formatted context', () async {
      await store.save(Memory(name: 'key', description: 'important'));
      final ctx = await store.buildContextString();
      expect(ctx, contains('Key')); // title is de-kebab'd from name
      expect(ctx, contains('important'));
    });

    test('buildContextString empty when no memories', () async {
      final ctx = await store.buildContextString();
      expect(ctx, '');
    });
  });

  // ═══════ FileMemoryStore ═══════

  group('FileMemoryStore', () {
    late String tmpDir;
    late FileMemoryStore store;

    setUp(() {
      tmpDir = '${Directory.systemTemp.path}${Platform.pathSeparator}agent_test_memory_${DateTime.now().millisecondsSinceEpoch}';
      store = FileMemoryStore(tmpDir);
    });

    tearDown(() {
      final dir = Directory(tmpDir);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('save writes file to disk', () async {
      final m = Memory(name: 'disk-test', description: 'a disk fact', body: 'hello');
      await store.save(m);

      final file = File('$tmpDir${Platform.pathSeparator}disk-test.md');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('name: disk-test'));
      expect(content, contains('hello'));
    });

    test('get reads from disk', () async {
      await store.save(Memory(name: 'fact', description: 'desc', body: 'body'));
      final got = await store.get('fact');
      expect(got, isNotNull);
      expect(got!.body, 'body');
    });

    test('delete removes file', () async {
      await store.save(Memory(name: 'tmp', description: 'tmp'));
      await store.delete('tmp');
      expect(await store.get('tmp'), isNull);
      expect(File('$tmpDir/tmp.md').existsSync(), isFalse);
    });

    test('all returns sorted memories', () async {
      await store.save(Memory(name: 'b', description: 'B'));
      await store.save(Memory(name: 'a', description: 'A'));
      final all = await store.all();
      expect(all.length, 2);
      expect(all[0].name, 'a');
      expect(all[1].name, 'b');
    });

    test('handles non-existent directory gracefully', () async {
      final s = FileMemoryStore('$tmpDir${Platform.pathSeparator}nonexistent');
      final all = await s.all();
      expect(all, isEmpty);
    });
  });

  // ═══════ MemoryScope + Router ═══════

  group('MemoryScope + Router', () {
    late MemoryRouter router;
    late InMemoryStore conv;
    late InMemoryStore feat;

    setUp(() async {
      conv = InMemoryStore();
      feat = InMemoryStore();
      router = MemoryRouter(
        conversation: conv,
        feature: feat,
        global: FileMemoryStore(
          '${Directory.systemTemp.path}${Platform.pathSeparator}agent_test_router_${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
    });

    tearDown(() async {
      // FileMemoryStore wraps a MemoryStore — cleanup handled by FileMemoryStore group
    });

    test('router routes to correct backend by scope', () async {
      final globalStore = router.backend(MemoryScope.global);
      final convStore = router.backend(MemoryScope.conversation);
      final featStore = router.backend(MemoryScope.feature);

      expect(convStore, isA<InMemoryStore>());
      expect(featStore, isA<InMemoryStore>());
      expect(globalStore, isA<FileMemoryStore>());
    });

    test('three scopes isolate memories', () async {
      await router.backend(MemoryScope.conversation)
          .save(Memory(name: 'c', description: 'conv'));
      await router.backend(MemoryScope.global)
          .save(Memory(name: 'g', description: 'global'));

      expect(await router.backend(MemoryScope.conversation).get('c'), isNotNull);
      expect(await router.backend(MemoryScope.conversation).get('g'), isNull);
    });
  });

  // ═══════ MemoryFact ═══════

  group('MemoryFact', () {
    test('toPrompt formats fact with time anchor', () {
      final f = MemoryFact(
        fact: '用户主修计算机科学',
        timeAnchor: '2026年6月',
        confidence: 0.9,
        recordedAt: DateTime(2026, 6),
      );
      expect(f.toPrompt(), '[2026年6月] 用户主修计算机科学');
    });

    test('contradiction detection: grade change', () {
      final a = MemoryFact(
        fact: '用户是大二学生',
        timeAnchor: '2025',
        confidence: 0.9,
        recordedAt: DateTime(2025),
      );
      final b = MemoryFact(
        fact: '用户是大三学生',
        timeAnchor: '2026',
        confidence: 0.9,
        recordedAt: DateTime(2026),
      );
      expect(a.contradicts(b), isTrue);
    });

    test('contradiction detection: major change', () {
      final a = MemoryFact(
        fact: '用户主修计算机科学',
        timeAnchor: '2025',
        confidence: 0.9,
        recordedAt: DateTime(2025),
      );
      final b = MemoryFact(
        fact: '用户主修数学',
        timeAnchor: '2026',
        confidence: 0.9,
        recordedAt: DateTime(2026),
      );
      expect(a.contradicts(b), isTrue);
    });

    test('no contradiction for compatible facts', () {
      final a = MemoryFact(
        fact: '用户喜欢Python',
        timeAnchor: '2025',
        confidence: 0.9,
        recordedAt: DateTime(2025),
      );
      final b = MemoryFact(
        fact: '用户喜欢Dart',
        timeAnchor: '2026',
        confidence: 0.9,
        recordedAt: DateTime(2026),
      );
      expect(a.contradicts(b), isFalse);
    });

    test('toJson/fromJson roundtrip', () {
      final original = MemoryFact(
        fact: 'test fact',
        timeAnchor: '2026-07',
        confidence: 0.85,
        isStyleFact: true,
        recordedAt: DateTime(2026, 7, 2),
        source: '用户说喜欢简洁代码',
      );
      final json = original.toJson();
      final restored = MemoryFact.fromJson(json);
      expect(restored.fact, original.fact);
      expect(restored.confidence, original.confidence);
      expect(restored.isStyleFact, isTrue);
      expect(restored.source, original.source);
    });
  });
}
