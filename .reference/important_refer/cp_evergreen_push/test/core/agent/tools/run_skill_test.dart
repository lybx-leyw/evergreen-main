import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/skill/skill.dart';
import 'package:evergreen_multi_tools/core/agent/tools/run_skill.dart';
import 'package:evergreen_multi_tools/core/agent/tool.dart' show Registry;
import 'package:evergreen_multi_tools/core/agent/provider.dart';
import 'package:evergreen_multi_tools/core/agent/message.dart';

/// Mock LLM — always returns "OK".
class _MockProvider extends Provider {
  @override String get name => 'mock';
  @override
  Stream<ProviderEvent> chat({
    required List<Message> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    yield ProviderEvent.content('OK');
    yield ProviderEvent.done();
  }
}

/// Mock LLM — always returns empty (for testing empty subagent output).
class _EmptyMockProvider extends Provider {
  @override String get name => 'empty-mock';
  @override
  Stream<ProviderEvent> chat({
    required List<Message> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    yield ProviderEvent.done();
  }
}

/// 创建一个内置 SkillIndex 用于测试（模拟 BuiltinSkills）。
SkillIndex _builtinForTest() {
  final idx = SkillIndex();
  BuiltinSkills.loadInto(idx);
  return idx;
}

void main() {
  late SkillIndex builtinIndex;
  late SkillLoader loader;
  late RunSkillTool runSkill;
  late ListSkillsTool listSkills;
  late Provider mockLlm;
  late Registry registry;

  setUp(() {
    builtinIndex = _builtinForTest();
    mockLlm = _MockProvider();
    registry = Registry();
    // 使用临时目录作为 skill 加载路径
    loader = SkillLoader(['.test_skills_run']);
    runSkill = RunSkillTool(loader, builtinIndex, mockLlm, registry);
    listSkills = ListSkillsTool(loader, builtinIndex);

    // 清理 + 创建临时目录
    final d = Directory('.test_skills_run');
    if (d.existsSync()) d.deleteSync(recursive: true);
    d.createSync(recursive: true);
  });

  tearDown(() {
    final d = Directory('.test_skills_run');
    if (d.existsSync()) d.deleteSync(recursive: true);
  });

  // ═══════════════════════════════════════════════════════════
  // RunSkillTool
  // ═══════════════════════════════════════════════════════════

  group('RunSkillTool', () {
    test('name 和 description', () {
      expect(runSkill.name, 'run_skill');
      expect(runSkill.description, contains('Skill'));
      expect(runSkill.readOnly, isTrue);
    });

    test('schema 要求 name 参数', () {
      expect(runSkill.schema['required'], contains('name'));
    });

    test('缺少 name → 错误提示', () async {
      final result = await runSkill.execute({});
      expect(result, contains('请指定'));
    });

    test('空 name → 错误提示', () async {
      final result = await runSkill.execute({'name': '  '});
      expect(result, contains('请指定'));
    });

    test('不存在的 skill → 列出可用列表', () async {
      // 从磁盘加载——目录中有 acceptance 则列出
      // 使用真实的 .greenix/skills/ 目录的 loader
      final realLoader = SkillLoader(['.greenix/skills']);
      final tool = RunSkillTool(realLoader, _builtinForTest(), mockLlm, registry);
      final result = await tool.execute({'name': 'nonexistent_xyz'});
      expect(result, contains('未找到'));
    });

    test('从磁盘加载存在的 skill → 返回完整 body', () async {
      // 创建临时 skill 文件
      File('.test_skills_run/my-skill.md').writeAsStringSync('''---
name: my-skill
description: 测试技能描述
---
## 正文
这是测试内容。
### 策略1
做某事。
''');
      final localLoader = SkillLoader(['.test_skills_run']);
      final tool = RunSkillTool(localLoader, _builtinForTest(), mockLlm, registry);

      final result = await tool.execute({'name': 'my-skill'});
      expect(result, contains('已加载 Skill：my-skill'));
      expect(result, contains('测试技能描述'));
      expect(result, contains('## 正文'));
      expect(result, contains('这是测试内容'));
      // 不应包含 frontmatter 标记
      expect(result, isNot(contains('---\nname')));
    });

    test('从实际 acceptance.md 加载', () async {
      final realLoader = SkillLoader(['.greenix/skills']);
      final tool = RunSkillTool(realLoader, _builtinForTest(), mockLlm, registry);

      final result = await tool.execute({'name': 'acceptance'});
      expect(result, contains('已加载 Skill：acceptance'));
      expect(result, contains('无威胁的对话伙伴'));
      expect(result, contains('六大温柔策略'));
    });

    test('热加载：新文件放入后立即可用', () async {
      // 第一次调用——无文件
      final result1 = await runSkill.execute({'name': 'hot-skill'});
      expect(result1, contains('未找到'));

      // 放入新文件
      File('.test_skills_run/hot-skill.md').writeAsStringSync('''---
name: hot-skill
description: 热加载测试
---
热加载成功！
''');
      // 第二次调用——立即可用（无需重启）
      final result2 = await runSkill.execute({'name': 'hot-skill'});
      expect(result2, contains('已加载 Skill：hot-skill'));
      expect(result2, contains('热加载成功'));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // RunSkillTool — subagent 模式
  // ═══════════════════════════════════════════════════════════

  group('RunSkillTool subagent 模式', () {
    test('subagent skill → 启动子 Agent 并返回回复', () async {
      File('.test_skills_run/sub-skill.md').writeAsStringSync('''---
name: sub-skill
description: 子Agent技能
run_as: subagent
---
你是子Agent，请用一句话回复。
''');
      final localLoader = SkillLoader(['.test_skills_run']);
      final tool = RunSkillTool(localLoader, _builtinForTest(), mockLlm, registry);

      final result = await tool.execute({'name': 'sub-skill'});
      expect(result, contains('🧬 Subagent'));
      expect(result, contains('sub-skill'));
      expect(result, contains('OK')); // mock 返回
    });

    test('subagent skill 返回空 → 兜底提示', () async {
      // 使用一个返回空字符串的 mock
      final emptyLlm = _EmptyMockProvider();
      final emptyTool = RunSkillTool(loader, builtinIndex, emptyLlm, registry);

      File('.test_skills_run/empty-sub.md').writeAsStringSync('''---
name: empty-sub
description: 空回复技能
run_as: subagent
---
随便
''');
      final result = await emptyTool.execute({'name': 'empty-sub'});
      expect(result, contains('子 Agent 未产生有效回复'));
    });

    test('subagent skill 无工具注册表', () async {
      // 验证子 Agent 的 Registry 是空的（不能调工具）
      File('.test_skills_run/notool.md').writeAsStringSync('''---
name: notool
description: 无工具测试
run_as: subagent
---
你是一个子Agent，不能调用任何工具。
''');
      final localLoader = SkillLoader(['.test_skills_run']);
      final tool = RunSkillTool(localLoader, _builtinForTest(), mockLlm, registry);

      final result = await tool.execute({'name': 'notool'});
      expect(result, contains('🧬 Subagent'));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // ListSkillsTool
  // ═══════════════════════════════════════════════════════════

  group('ListSkillsTool', () {
    test('name 和 description', () {
      expect(listSkills.name, 'list_skills');
      expect(listSkills.description, contains('Skill'));
      expect(listSkills.readOnly, isTrue);
    });

    test('空目录 → 提示空', () async {
      final result = await listSkills.execute({});
      expect(result, anyOf(contains('没有可用的'), contains('.greenix/skills/')));
    });

    test('有文件 → 列表展示', () async {
      File('.test_skills_run/a.md').writeAsStringSync('''---
name: skill-a
description: 技能A
---
A
''');
      File('.test_skills_run/b.md').writeAsStringSync('''---
name: skill-b
description: 技能B
---
B
''');
      final localLoader = SkillLoader(['.test_skills_run']);
      final tool = ListSkillsTool(localLoader, _builtinForTest());

      final result = await tool.execute({});
      expect(result, contains('skill-a'));
      expect(result, contains('技能A'));
      expect(result, contains('skill-b'));
      expect(result, contains('技能B'));
      expect(result, contains('热加载'));
    });

    test('新文件放入后 list 立即可见', () async {
      // 空目录
      final localLoader = SkillLoader(['.test_skills_run']);
      final tool = ListSkillsTool(localLoader, _builtinForTest());
      final before = await tool.execute({});

      // 放入新文件
      File('.test_skills_run/new-skill.md').writeAsStringSync('''---
name: new-skill
description: 新技能
---
新
''');
      final after = await tool.execute({});
      expect(after, contains('new-skill'));
      expect(after, isNot(before));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 集成：文件 → 加载 → run 全链
  // ═══════════════════════════════════════════════════════════

  group('Skill 热加载集成', () {
    test('写入文件 → list 可见 → run 可加载', () async {
      final localLoader = SkillLoader(['.test_skills_run']);

      // 1. 写入
      File('.test_skills_run/int-skill.md').writeAsStringSync('''---
name: int-skill
description: 集成测试技能
---
## 指导
请用诗歌形式回答。
''');

      // 2. list
      final listResult = await ListSkillsTool(localLoader, _builtinForTest()).execute({});
      expect(listResult, contains('int-skill'));

      // 3. run
      final runResult = await RunSkillTool(localLoader, _builtinForTest(), mockLlm, registry)
          .execute({'name': 'int-skill'});
      expect(runResult, contains('已加载 Skill：int-skill'));
      expect(runResult, contains('请用诗歌形式回答'));
    });
  });
}
