import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_multi_tools/core/agent/memory/memory.dart';
import 'package:evergreen_multi_tools/core/agent/tools/read_global_memory.dart';
import 'package:evergreen_multi_tools/core/agent/tools/write_global_memory.dart';

/// 测试用 store（.greenix 风格临时目录，避免污染真实数据）。
const _testDir = '.test_global_mem';

void main() {
  late FileMemoryStore store;
  late ReadGlobalMemoryTool readTool;
  late WriteGlobalMemoryTool writeTool;

  setUp(() {
    store = FileMemoryStore(_testDir);
    readTool = ReadGlobalMemoryTool(store);
    writeTool = WriteGlobalMemoryTool(store);
  });

  tearDown(() async {
    // 清理所有测试记忆
    final all = await store.all();
    for (final m in all) {
      await store.delete(m.name);
    }
  });

  // ═══════════════════════════════════════════════════════════
  // WriteGlobalMemoryTool
  // ═══════════════════════════════════════════════════════════

  group('WriteGlobalMemoryTool set_cardinal', () {
    test('设置首要特质形容词', () async {
      final result = await writeTool
          .execute({'action': 'set_cardinal', 'trait': '实干家'});
      expect(result, contains('✅'));
      expect(result, contains('实干家'));

      final all = await store.all();
      final cardinals = all.where((m) => m.priority == 'cardinal');
      expect(cardinals.length, 1);
      expect(cardinals.first.title, '实干家');
    });

    test('覆盖旧的首要特质', () async {
      await writeTool.execute({'action': 'set_cardinal', 'trait': '探索者'});
      await writeTool.execute({'action': 'set_cardinal', 'trait': '实干家'});

      final all = await store.all();
      final cardinals = all.where((m) => m.priority == 'cardinal');
      expect(cardinals.length, 1);
      expect(cardinals.first.title, '实干家');
    });

    test('缺少 trait 参数 → 错误提示', () async {
      final result = await writeTool.execute({'action': 'set_cardinal'});
      expect(result, contains('请提供 trait'));
    });
  });

  group('WriteGlobalMemoryTool add_central', () {
    test('添加单个中心特质', () async {
      final result = await writeTool
          .execute({'action': 'add_central', 'trait': '严谨'});
      expect(result, contains('✅'));
      expect(result, contains('严谨'));

      final all = await store.all();
      final centrals = all.where((m) => m.priority == 'central');
      expect(centrals.length, 1);
    });

    test('批量添加多个中心特质', () async {
      final result = await writeTool.execute({
        'action': 'add_central',
        'traits': ['勤奋', '严谨', '好奇'],
      });
      expect(result, contains('勤奋'));
      expect(result, contains('严谨'));
      expect(result, contains('好奇'));

      final all = await store.all();
      expect(all.where((m) => m.priority == 'central').length, 3);
    });

    test('缺少参数 → 错误提示', () async {
      final result = await writeTool.execute({'action': 'add_central'});
      expect(result, contains('请提供 trait'));
    });
  });

  group('WriteGlobalMemoryTool add_secondary', () {
    test('添加次要特质（情境性偏好）', () async {
      final result = await writeTool.execute({
        'action': 'add_secondary',
        'trait': '写代码时偏好简洁风格',
      });
      expect(result, contains('✅'));
      expect(result, contains('写代码时偏好简洁风格'));

      final all = await store.all();
      expect(all.where((m) => m.priority == 'secondary').length, 1);
    });

    test('缺少 trait → 错误提示', () async {
      final result = await writeTool.execute({'action': 'add_secondary'});
      expect(result, contains('请提供 trait'));
    });
  });

  group('WriteGlobalMemoryTool set_requirement', () {
    test('设置用户需求', () async {
      final result = await writeTool.execute({
        'action': 'set_requirement',
        'trait': '用中文回答',
      });
      expect(result, contains('✅'));
      expect(result, contains('用中文回答'));
      expect(result, contains('AI 将在后续对话中遵循'));

      final all = await store.all();
      final reqs = all.where((m) => m.priority == 'requirement');
      expect(reqs.length, 1);
      expect(reqs.first.title, '用中文回答');
    });

    test('多条用户需求共存', () async {
      await writeTool.execute({'action': 'set_requirement', 'trait': '用中文回答'});
      await writeTool.execute({'action': 'set_requirement', 'trait': '代码示例用 Rust'});

      final all = await store.all();
      final reqs = all.where((m) => m.priority == 'requirement');
      expect(reqs.length, 2);
    });

    test('缺少 trait → 错误提示', () async {
      final result = await writeTool.execute({'action': 'set_requirement'});
      expect(result, contains('请提供 trait'));
    });
  });

  group('WriteGlobalMemoryTool remember', () {
    test('记录关键事实（带时间锚定）', () async {
      final fact = '[2026年6月] 用户是大三学生，主修计算机科学';
      final result = await writeTool.execute({
        'action': 'remember',
        'fact': fact,
      });
      expect(result, contains('✅'));
      expect(result, contains('大三学生'));

      final all = await store.all();
      final facts = all.where((m) =>
          m.priority == 'high' &&
          !['cardinal', 'central', 'secondary', 'requirement'].contains(m.priority));
      expect(facts.length, 1);
      expect(facts.first.body, fact);
    });

    test('记录带指定优先级的关键事实', () async {
      await writeTool.execute({
        'action': 'remember',
        'fact': '次要信息',
        'priority': 'low',
      });
      final all = await store.all();
      expect(all.any((m) => m.body == '次要信息'), isTrue);
    });

    test('超长事实自动截断标题', () async {
      final longFact = 'A' * 120;
      final result = await writeTool.execute({
        'action': 'remember',
        'fact': longFact,
      });
      expect(result, contains('✅'));
      // 标题不应超过 83 字符（80 + '...'）
      final all = await store.all();
      final mem = all.firstWhere((m) => m.body == longFact);
      expect(mem.title.length, lessThanOrEqualTo(83));
    });

    test('缺少 fact → 错误提示', () async {
      final result = await writeTool.execute({'action': 'remember'});
      expect(result, contains('请提供 fact'));
    });
  });

  group('WriteGlobalMemoryTool forget', () {
    test('按关键词删除匹配的记忆', () async {
      // 先写入两条
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] 用户主修数学',
      });
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] 用户辅修物理',
      });

      // 删除"数学"相关的
      final result = await writeTool.execute({
        'action': 'forget',
        'fact': '数学',
      });
      expect(result, contains('✅'));
      expect(result, contains('数学'));

      // 验证只剩一条
      final all = await store.all();
      final facts = all.where((m) =>
          m.priority == 'high' &&
          !['cardinal', 'central', 'secondary', 'requirement'].contains(m.priority));
      expect(facts.length, 1);
      expect(facts.first.body, contains('物理'));
    });

    test('删除不存在的记忆 → 提示无需删除', () async {
      final result = await writeTool.execute({
        'action': 'forget',
        'fact': '不存在的内容',
      });
      expect(result, contains('未找到'));
    });

    test('缺少 fact → 错误提示', () async {
      final result = await writeTool.execute({'action': 'forget'});
      expect(result, contains('请提供 fact'));
    });
  });

  group('WriteGlobalMemoryTool 边界', () {
    test('未知 action → 错误提示', () async {
      final result = await writeTool.execute({'action': 'invalid_action'});
      expect(result, contains('未知操作'));
      expect(result, contains('set_cardinal'));
    });

    test('多次写入同一事实不重复', () async {
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] 用户是大三学生',
      });
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] 用户是大三学生',
      });
      final all = await store.all();
      final facts = all.where((m) =>
          m.priority == 'high' &&
          !['cardinal', 'central', 'secondary', 'requirement'].contains(m.priority));
      // 同一事实 hash 相同 → save 会覆盖，不重复
      expect(facts.length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // ReadGlobalMemoryTool
  // ═══════════════════════════════════════════════════════════

  group('ReadGlobalMemoryTool 读空记忆', () {
    test('空 store → 返回空提示', () async {
      final result = await readTool.execute({});
      expect(result, contains('全局记忆为空'));
    });

    test('搜索无匹配 → 返回无匹配提示', () async {
      final result = await readTool.execute({'query': '不存在'});
      expect(result, contains('未找到'));
    });
  });

  group('ReadGlobalMemoryTool 读已写入记忆', () {
    test('读取全部记忆 → Allport 格式四层结构', () async {
      await writeTool.execute({'action': 'set_cardinal', 'trait': '实干家'});
      await writeTool.execute({
        'action': 'add_central',
        'traits': ['勤奋', '严谨'],
      });
      await writeTool.execute({
        'action': 'add_secondary',
        'trait': '写代码时偏好简洁风格',
      });
      await writeTool.execute({
        'action': 'set_requirement',
        'trait': '用中文回答',
      });
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] 用户是大三学生',
      });

      final result = await readTool.execute({});
      // 五层结构
      expect(result, contains('首要特质'));
      expect(result, contains('实干家'));
      expect(result, contains('中心特质'));
      expect(result, contains('勤奋'));
      expect(result, contains('严谨'));
      expect(result, contains('次要特质'));
      expect(result, contains('写代码时偏好简洁风格'));
      expect(result, contains('用户需求'));
      expect(result, contains('用中文回答'));
      expect(result, contains('关键事实'));
      expect(result, contains('大三学生'));
    });

    test('按关键词搜索', () async {
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] 用户主修计算机科学',
      });
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] 用户辅修数学',
      });

      final result = await readTool.execute({'query': '计算机'});
      expect(result, contains('计算机科学'));
      expect(result, isNot(contains('数学')));
    });

    test('仅首要有值时正确显示', () async {
      await writeTool.execute({'action': 'set_cardinal', 'trait': '完美主义者'});

      final result = await readTool.execute({});
      expect(result, contains('首要特质'));
      expect(result, contains('完美主义者'));
      // 其他层应不显示
      expect(result, isNot(contains('中心特质')));
      expect(result, isNot(contains('次要特质')));
      expect(result, isNot(contains('关键事实')));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // ReadGlobalMemoryTool — 写后读一致性（BUG-16 修复验证）
  // ═══════════════════════════════════════════════════════════

  group('ReadGlobalMemoryTool 写后读一致性', () {
    test('写入后立即读取 → 读到最新内容', () async {
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] 用户是大三学生',
      });

      // 写入后立即读取 → 应看到新内容
      final result = await readTool.execute({});
      expect(result, contains('大三学生'));
    });

    test('写入 → 读取 → 再写入 → 再读取：始终读最新', () async {
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] 第一批数据',
      });

      final r1 = await readTool.execute({});
      expect(r1, contains('第一批数据'));

      // 写入新内容
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] 第二批数据',
      });

      // 再读取 → 应同时包含新旧内容
      final r2 = await readTool.execute({});
      expect(r2, contains('第一批数据'));
      expect(r2, contains('第二批数据'));
    });

    test('同回合内 AI 多次带不同 query 搜索 → 每次执行精确搜索', () async {
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] 用户偏好简洁回答',
      });
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] 用户是浙大学生',
      });

      // 多次搜索不同关键词
      final r1 = await readTool.execute({'query': '简洁'});
      final r2 = await readTool.execute({'query': '浙大'});

      expect(r1, contains('简洁回答'));
      expect(r1, isNot(contains('浙大')));
      expect(r2, contains('浙大学生'));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 往返集成测试
  // ═══════════════════════════════════════════════════════════

  group('写入 → 读取 往返', () {
    test('完整奥尔波特四条线往返', () async {
      // 写入
      await writeTool.execute({'action': 'set_cardinal', 'trait': '创新者'});
      await writeTool.execute({
        'action': 'add_central',
        'traits': ['开放', '好奇', '坚韧'],
      });
      await writeTool.execute({
        'action': 'add_secondary',
        'trait': '讨论哲学时特别兴奋',
      });
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] 用户就读于浙江大学',
      });

      // 读取
      final readResult = await readTool.execute({});

      // 验证所有内容可读
      expect(readResult, contains('创新者'));
      expect(readResult, contains('开放'));
      expect(readResult, contains('好奇'));
      expect(readResult, contains('坚韧'));
      expect(readResult, contains('讨论哲学时特别兴奋'));
      expect(readResult, contains('浙江大学'));
    });

    test('写入 → 删除 → 读取为空', () async {
      await writeTool.execute({
        'action': 'remember',
        'fact': '临时测试数据',
      });

      // 确认存在
      var read = await readTool.execute({});
      expect(read, contains('临时测试数据'));

      // 删除
      await writeTool.execute({'action': 'forget', 'fact': '临时'});

      // 确认删除
      read = await readTool.execute({});
      expect(read, isNot(contains('临时测试数据')));
    });

    test('覆盖首要特质 → 读到的已更新', () async {
      await writeTool.execute({'action': 'set_cardinal', 'trait': '探索者'});
      await writeTool.execute({'action': 'set_cardinal', 'trait': '关怀者'});

      final read = await readTool.execute({});
      expect(read, isNot(contains('探索者')));
      expect(read, contains('关怀者'));
    });

    test('AI 写入后用户可通过搜 forget 删除', () async {
      // 模拟 AI 写入
      await writeTool.execute({
        'action': 'remember',
        'fact': '[2026年6月] AI自动记录的偏好',
      });

      // 模拟用户（或 AI）搜索并删除
      final searchResult = await readTool.execute({'query': '偏好'});
      expect(searchResult, contains('AI自动记录的偏好'));

      await writeTool.execute({'action': 'forget', 'fact': '偏好'});

      // 确认已删除
      final afterDelete = await readTool.execute({});
      expect(afterDelete, isNot(contains('AI自动记录的偏好')));
    });
  });
}
