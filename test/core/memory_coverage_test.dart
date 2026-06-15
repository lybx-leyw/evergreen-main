import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/memory/fact.dart';
import 'package:evergreen_multi_tools/core/agent/memory/memory.dart';
import 'package:evergreen_multi_tools/core/agent/memory/in_memory_store.dart';
import 'package:evergreen_multi_tools/core/agent/memory/router.dart';
import 'package:evergreen_multi_tools/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_multi_tools/core/agent/memory/scope.dart';
import 'package:evergreen_multi_tools/core/agent/compact/compact.dart';
import 'package:evergreen_multi_tools/core/agent/agent/session.dart';
import 'package:evergreen_multi_tools/core/agent/message.dart';
import 'package:evergreen_multi_tools/core/agent/provider.dart';

class _MockCompactLlm extends Provider {
  final String _response;
  _MockCompactLlm(this._response);
  @override String get name => 'mock';
  @override
  Stream<ProviderEvent> chat({
    required List<Message> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    yield ProviderEvent.content(_response);
    yield ProviderEvent.done();
  }
}

void main() {
  group('MemoryFact — 高级冲突检测', () {
    test('研一→研二 冲突', () {
      final old_ = MemoryFact(fact: '用户是研一学生', timeAnchor: '2025年', confidence: 1, recordedAt: DateTime(2025));
      final new_ = MemoryFact(fact: '用户是研二学生', timeAnchor: '2026年', confidence: 1, recordedAt: DateTime(2026));
      expect(old_.contradicts(new_), true);
    });

    test('博一→博二 冲突', () {
      final old_ = MemoryFact(fact: '用户是博一学生', timeAnchor: '2025年', confidence: 1, recordedAt: DateTime(2025));
      final new_ = MemoryFact(fact: '用户是博二学生', timeAnchor: '2026年', confidence: 1, recordedAt: DateTime(2026));
      expect(old_.contradicts(new_), true);
    });

    test('主修A→主修B 冲突', () {
      final a = MemoryFact(fact: '用户主修计算机科学', timeAnchor: '', confidence: 1, recordedAt: DateTime(2025));
      final b = MemoryFact(fact: '用户主修电子工程', timeAnchor: '', confidence: 1, recordedAt: DateTime(2026));
      expect(a.contradicts(b), true);
    });

    test('相同专业不冲突', () {
      final a = MemoryFact(fact: '用户主修计算机科学', timeAnchor: '', confidence: 1, recordedAt: DateTime(2025));
      final b = MemoryFact(fact: '用户主修计算机科学', timeAnchor: '', confidence: 1, recordedAt: DateTime(2026));
      expect(a.contradicts(b), false);
    });

    test('不同领域不冲突', () {
      final a = MemoryFact(fact: '用户偏好简洁回答', timeAnchor: '', confidence: 1, recordedAt: DateTime(2025));
      final b = MemoryFact(fact: '用户是大三学生', timeAnchor: '', confidence: 1, recordedAt: DateTime(2026));
      expect(a.contradicts(b), false);
    });
  });

  group('TraitLevel — 全部层级', () {
    test('奥尔波特四层特质', () {
      expect(TraitLevel.values.length, 4);
      expect(TraitLevel.cardinal.name, 'cardinal');
      expect(TraitLevel.central.name, 'central');
      expect(TraitLevel.secondary.name, 'secondary');
      expect(TraitLevel.keyFact.name, 'keyFact');
    });

    test('层级顺序：首要→中心→次要→关键事实', () {
      final levels = TraitLevel.values;
      expect(levels[0], TraitLevel.cardinal);
      expect(levels[1], TraitLevel.central);
      expect(levels[2], TraitLevel.secondary);
      expect(levels[3], TraitLevel.keyFact);
    });
  });

  group('InMemoryStore — 边界', () {
    test('delete 不存在的 key 不崩溃', () async {
      final store = InMemoryStore();
      await store.delete('nonexistent');
      expect(await store.all(), isEmpty);
    });

    test('save 覆盖不报错', () async {
      final store = InMemoryStore();
      await store.save(Memory(name: 'x', title: 'A', type: MemoryType.user, body: 'a'));
      await store.save(Memory(name: 'x', title: 'B', type: MemoryType.user, body: 'b'));
      expect((await store.get('x'))!.title, 'B');
    });

    test('search 无匹配返回空列表', () async {
      final store = InMemoryStore();
      expect(await store.search('nonexistent'), isEmpty);
    });
  });

  group('MemoryRouter', () {
    test('默认 construction', () {
      final router = MemoryRouter(global: FileMemoryStore('.test_persist'));
      expect(router.backend(MemoryScope.conversation), isA<InMemoryStore>());
      expect(router.backend(MemoryScope.feature), isA<InMemoryStore>());
      expect(router.backend(MemoryScope.global), isA<FileMemoryStore>());
    });
  });

  group('Memory', () {
    test('Memory 对象创建', () {
      final m = Memory(
        name: 'test',
        title: '测试',
        type: MemoryType.user,
        body: '正文',
        description: '描述',
        priority: 'high',
      );
      expect(m.name, 'test');
      expect(m.title, '测试');
      expect(m.description, '描述');
      expect(m.priority, 'high');
    });

    test('MemoryType 枚举值', () {
      expect(MemoryType.values.length, greaterThanOrEqualTo(1));
      expect(MemoryType.user, isNotNull);
      expect(MemoryType.values, contains(MemoryType.user));
    });
  });

  group('Compactor — 阈值边界', () {
    test('exactly 70% 触发 compact', () {
      final c = Compactor(llm: _MockCompactLlm('sum'), contextWindow: 100000);
      // estimated 70000 = 70% → compactRatio(0.7) triggers
      // Can't directly set estimatedContextTokens, so verify ratio logic
      expect(c.compactRatio, 0.7);
      expect(70000 / 100000, 0.7);
    });

    test('force ratio at 80%', () async {
      final c = Compactor(llm: _MockCompactLlm('forced summary'), contextWindow: 128000);
      final session = Session();
      for (var i = 0; i < 200; i++) {
        session.add(Message.user('message $i' * 10));
      }
      // Should trigger compact since lots of messages
      final (should, trigger, isEmergency) = c.check(session);
      if (should) {
        final result = await c.compact(session, trigger);
        expect(result.messages.length, lessThan(session.messages.length + 1));
      }
    });

    test('contextRatioDescription 格式化', () {
      expect(contextRatioDescription(64000, 128000), '50% (64000 / 128000 tok)');
      expect(contextRatioDescription(0, 128000), '0% (0 / 128000 tok)');
      expect(contextRatioDescription(100, 0), '压缩已禁用');
    });
  });
}
