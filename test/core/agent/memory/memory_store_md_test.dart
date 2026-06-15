import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/memory/memory.dart';

/// 测试 MemoryStore 对 .md 文件（frontmatter 格式）的读写解析。
/// 这直接覆盖了人类用户通过侧栏「全局记忆」读取记忆的路径。
void main() {
  const testDir = '.test_md_memories';

  setUp(() {
    final dir = Directory(testDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  tearDown(() {
    final dir = Directory(testDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  // ═══════════════════════════════════════════════════════════
  // MemoryStore — .md frontmatter 解析
  // ═══════════════════════════════════════════════════════════

  group('MemoryStore .md 文件写入与解析', () {
    test('save → load → 字段完整保留', () {
      final store = MemoryStore(testDir);
      final mem = Memory(
        name: 'cardinal-perfectionist',
        title: '完美主义者',
        description: '首要特质',
        type: MemoryType.user,
        body: '完美主义者',
        priority: 'cardinal',
      );
      store.save(mem);

      // 重新加载
      final store2 = MemoryStore(testDir);
      store2.load();
      final all = store2.all();
      expect(all.length, 1);

      final loaded = all.first;
      expect(loaded.name, 'cardinal-perfectionist');
      expect(loaded.title, '完美主义者');
      expect(loaded.description, '首要特质');
      expect(loaded.type, MemoryType.user);
      expect(loaded.body, '完美主义者');
      expect(loaded.priority, 'cardinal');
    });

    test('save 多个不同优先级的记忆 → 全部可读', () {
      final store = MemoryStore(testDir);
      store.save(Memory(
        name: 'central-diligent', title: '勤奋', description: '中心特质',
        type: MemoryType.user, body: '勤奋', priority: 'central',
      ));
      store.save(Memory(
        name: 'fact-abc123', title: '用户是大三学生', description: '关键事实',
        type: MemoryType.user,
        body: '[2026年6月] 用户是大三学生', priority: 'high',
      ));
      store.save(Memory(
        name: 'secondary-pref', title: '偏好简洁回答', description: '次要特质',
        type: MemoryType.user, body: '偏好简洁回答', priority: 'secondary',
      ));

      final store2 = MemoryStore(testDir);
      store2.load();
      final all = store2.all();
      expect(all.length, 3);

      // 按优先级验证
      expect(all.any((m) => m.priority == 'cardinal'), isFalse);
      expect(all.any((m) => m.priority == 'central' && m.title == '勤奋'), isTrue);
      expect(all.any((m) => m.priority == 'high' && m.body.contains('大三')), isTrue);
      expect(all.any((m) => m.priority == 'secondary'), isTrue);
    });

    test('delete 删除后重新 load → 不存在', () {
      final store = MemoryStore(testDir);
      store.save(Memory(
        name: 'to-delete', title: '待删除', type: MemoryType.user,
        body: '应该被删除', priority: 'high',
      ));
      expect(store.all().length, 1);

      store.delete('to-delete');

      final store2 = MemoryStore(testDir);
      store2.load();
      expect(store2.all().length, 0);
    });

    test('中文特质名作为 name → 文件名正确', () {
      final store = MemoryStore(testDir);
      store.save(Memory(
        name: 'central-INFJ（提倡者型人格）',
        title: 'INFJ（提倡者型人格）',
        description: '中心特质',
        type: MemoryType.user,
        body: 'INFJ（提倡者型人格）',
        priority: 'central',
      ));

      final store2 = MemoryStore(testDir);
      store2.load();
      final all = store2.all();
      expect(all.length, 1);
      expect(all.first.title, 'INFJ（提倡者型人格）');

      // 验证文件确实存在
      final file = File('$testDir/central-INFJ（提倡者型人格）.md');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('INFJ'));
      expect(content, contains('提倡者型人格'));
    });

    test('body 含多行文本 → 完整保留', () {
      final store = MemoryStore(testDir);
      store.save(Memory(
        name: 'fact-multiline',
        title: '多行事实',
        type: MemoryType.user,
        body: '第一行\n第二行\n第三行',
        priority: 'high',
      ));

      final store2 = MemoryStore(testDir);
      store2.load();
      final loaded = store2.all().first;
      expect(loaded.body, '第一行\n第二行\n第三行');
    });

    test('frontmatter 含冒号的字段 → 正确解析', () {
      final store = MemoryStore(testDir);
      store.save(Memory(
        name: 'fact-colon',
        title: '带冒号的标题',
        description: '描述: 包含冒号',
        type: MemoryType.feedback,
        body: '内容也有: 冒号',
        priority: 'medium',
      ));

      final store2 = MemoryStore(testDir);
      store2.load();
      final loaded = store2.all().first;
      // 冒号只在第一个出现处分割 key:value
      expect(loaded.description, contains('描述'));
      expect(loaded.type, MemoryType.feedback);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // MemoryStore 与全局记忆写入工具的集成
  // ═══════════════════════════════════════════════════════════

  group('MemoryStore 写入→重读 往返 (模拟人类 UI 读写)', () {
    test('人类写入关键事实 → load 后可读', () {
      // 模拟 _AddMemoryButton 写入流程
      final store = MemoryStore(testDir);
      final content = '用户偏好简洁回答';
      store.save(Memory(
        name: 'key_fact-${content.hashCode.toRadixString(16)}',
        title: content,
        description: '关键事实',
        type: MemoryType.user,
        body: content,
        priority: 'high',
      ));

      // 模拟 UI 重新加载
      final store2 = MemoryStore(testDir);
      store2.load();
      final all = store2.all();
      expect(all.length, 1);
      expect(all.first.title, content);
    });

    test('人类写入首要特质（覆盖旧值）→ 只保留最新', () {
      final store = MemoryStore(testDir);

      // 旧首要特质
      store.save(Memory(
        name: 'cardinal-old', title: '探索者', description: '首要特质',
        type: MemoryType.user, body: '探索者', priority: 'cardinal',
      ));

      // 新用户想覆盖：先删再写
      store.load();
      for (final old in store.all().where((m) => m.priority == 'cardinal')) {
        store.delete(old.name);
      }
      store.save(Memory(
        name: 'cardinal-new', title: '实干家', description: '首要特质',
        type: MemoryType.user, body: '实干家', priority: 'cardinal',
      ));

      final store2 = MemoryStore(testDir);
      store2.load();
      final cardinals = store2.all().where((m) => m.priority == 'cardinal');
      expect(cardinals.length, 1);
      expect(cardinals.first.title, '实干家');
    });

    test('人类清空所有记忆 → load 为空', () {
      final store = MemoryStore(testDir);
      store.save(Memory(
        name: 'c1', title: '特质1', type: MemoryType.user,
        body: 't1', priority: 'central',
      ));
      store.save(Memory(
        name: 'c2', title: '特质2', type: MemoryType.user,
        body: 't2', priority: 'central',
      ));

      // 清空（模拟 _clearAll）
      store.load();
      for (final m in store.all()) {
        store.delete(m.name);
      }

      final store2 = MemoryStore(testDir);
      store2.load();
      expect(store2.all().length, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // MEMORY.md 索引
  // ═══════════════════════════════════════════════════════════

  group('MEMORY.md 索引', () {
    test('写入记忆后 MEMORY.md 自动生成', () {
      final store = MemoryStore(testDir);
      store.save(Memory(
        name: 'idx-test', title: '索引测试', description: '测试索引生成',
        type: MemoryType.user, body: '测试', priority: 'high',
      ));

      final idxFile = File('$testDir/MEMORY.md');
      expect(idxFile.existsSync(), isTrue);
      final idx = idxFile.readAsStringSync();
      expect(idx, contains('idx-test'));
      expect(idx, contains('测试索引生成')); // buildIndex 显示 description，非 title
    });

    test('删除所有记忆后 MEMORY.md 为空', () {
      final store = MemoryStore(testDir);
      store.save(Memory(
        name: 'idx-del', title: '待删', type: MemoryType.user,
        body: 'x', priority: 'high',
      ));
      store.delete('idx-del');

      final store2 = MemoryStore(testDir);
      expect(store2.buildIndex(), isEmpty);
    });
  });
}
