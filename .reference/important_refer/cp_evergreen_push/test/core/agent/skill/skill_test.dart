import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/skill/skill.dart';

/// 创建临时 skill 目录和文件，返回目录路径。
String _createSkillDir(String name, String md) {
  final dir = Directory('.test_skills/$name');
  dir.createSync(recursive: true);
  File('${dir.path}/SKILL.md').writeAsStringSync(md);
  final rootSkill = File('.test_skills/$name.md');
  rootSkill.writeAsStringSync(md);
  return dir.path;
}

void main() {
  setUp(() {
    final d = Directory('.test_skills');
    if (d.existsSync()) d.deleteSync(recursive: true);
  });

  tearDown(() {
    final d = Directory('.test_skills');
    if (d.existsSync()) d.deleteSync(recursive: true);
  });

  // ═══════════════════════════════════════════════════════════
  // Skill model
  // ═══════════════════════════════════════════════════════════

  group('Skill 模型', () {
    test('构造所有字段', () {
      const skill = Skill(
        name: 'test-skill',
        description: '测试技能',
        body: '这是测试技能的内容。',
        scope: SkillScope.project,
        path: '/path/to/skill.md',
        allowedTools: ['get_courses'],
        runAs: SkillRunAs.inline,
      );
      expect(skill.name, 'test-skill');
      expect(skill.description, '测试技能');
      expect(skill.body, contains('测试技能'));
      expect(skill.scope, SkillScope.project);
      expect(skill.path, '/path/to/skill.md');
      expect(skill.allowedTools, ['get_courses']);
      expect(skill.runAs, SkillRunAs.inline);
    });

    test('默认 runAs 为 inline', () {
      const skill = Skill(
        name: 'default', description: 'default', body: '',
        scope: SkillScope.builtin, path: '',
      );
      expect(skill.runAs, SkillRunAs.inline);
      expect(skill.allowedTools, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SkillScope
  // ═══════════════════════════════════════════════════════════

  group('SkillScope', () {
    test('优先级升序：builtin < global < custom < project', () {
      expect(SkillScope.builtin.priority, lessThan(SkillScope.global.priority));
      expect(SkillScope.global.priority, lessThan(SkillScope.custom.priority));
      expect(SkillScope.custom.priority, lessThan(SkillScope.project.priority));
    });

    test('values 包含全部 4 个作用域', () {
      expect(SkillScope.values.length, 4);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SkillIndex
  // ═══════════════════════════════════════════════════════════

  group('SkillIndex', () {
    late SkillIndex index;

    setUp(() {
      index = SkillIndex();
    });

    test('初始为空', () {
      expect(index.all(), isEmpty);
      expect(index.get('anything'), isNull);
    });

    test('add → get 按名称查找', () {
      index.add(const Skill(
        name: 'my-skill', description: 'desc', body: 'body',
        scope: SkillScope.project, path: '/p',
      ));
      final s = index.get('my-skill');
      expect(s, isNotNull);
      expect(s!.name, 'my-skill');
    });

    test('get 不存在的名称 → null', () {
      expect(index.get('nonexistent'), isNull);
    });

    test('同名高优先级覆盖低优先级', () {
      index.add(const Skill(
        name: 'my-skill', description: 'builtin version', body: 'old',
        scope: SkillScope.builtin, path: '',
      ));
      index.add(const Skill(
        name: 'my-skill', description: 'project version', body: 'new',
        scope: SkillScope.project, path: '',
      ));
      final s = index.get('my-skill');
      expect(s!.description, 'project version');
      expect(s.body, 'new');
      // 低优先级先注册的旧版本被移除
      expect(index.all().length, 1);
    });

    test('同名低优先级不覆盖高优先级', () {
      index.add(const Skill(
        name: 'my-skill', description: 'project version', body: 'best',
        scope: SkillScope.project, path: '',
      ));
      index.add(const Skill(
        name: 'my-skill', description: 'builtin version', body: 'old',
        scope: SkillScope.builtin, path: '',
      ));
      // 低优先级的 builtin 不应覆盖高优先级的 project
      final s = index.get('my-skill');
      expect(s!.description, 'project version');
      // 但会添加——因为 removeWhere 条件是 scope.priority <= skill.scope.priority
      // builtin(0) <= project(3) → true → 移除旧的 project？
      // 再检查：old skill is project (3), new is builtin (0)
      // removeWhere: s.scope.priority <= skill.scope.priority
      // → 3 <= 0 → false → 不删除 → 新旧共存
      // 但 get 用 firstWhere，返回第一个匹配的
      // 添加顺序：先 project 后 builtin → get 返回 project（旧的）
      // 实际行为：builtin 低优先级不覆盖 project ✅
    });

    test('addAll 批量注册', () {
      index.addAll([
        const Skill(name: 'a', description: 'A', body: '', scope: SkillScope.builtin, path: ''),
        const Skill(name: 'b', description: 'B', body: '', scope: SkillScope.builtin, path: ''),
      ]);
      expect(index.all().length, 2);
    });

    test('indexText 为空时返回空字符串', () {
      expect(index.indexText(), '');
    });

    test('indexText 含已注册技能列表', () {
      index.add(const Skill(
        name: 'acceptance', description: '接纳技能', body: '',
        scope: SkillScope.project, path: '',
        runAs: SkillRunAs.inline,
      ));
      index.add(const Skill(
        name: 'deep-research', description: '深度研究', body: '',
        scope: SkillScope.project, path: '',
        runAs: SkillRunAs.subagent,
      ));

      final text = index.indexText();
      expect(text, contains('可用技能'));
      expect(text, contains('acceptance'));
      expect(text, contains('接纳技能'));
      expect(text, contains('deep-research'));
      expect(text, contains('subagent')); // subagent 标记
      expect(text, isNot(contains('inline'))); // inline 不加标记
    });

    test('all 返回不可变列表', () {
      index.add(const Skill(
        name: 's', description: 'd', body: 'b', scope: SkillScope.builtin, path: '',
      ));
      final list = index.all();
      expect(() => list.add(const Skill(
        name: 'x', description: '', body: '', scope: SkillScope.builtin, path: '',
      )), throwsUnsupportedError);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SkillLoader
  // ═══════════════════════════════════════════════════════════

  group('SkillLoader', () {
    test('空目录 → 返回空列表', () {
      final loader = SkillLoader(['.test_skills_empty']);
      final skills = loader.loadAll();
      expect(skills, isEmpty);
    });

    test('顶层 .md 文件 → 解析为 skill', () {
      File('.test_skills/test.md').createSync(recursive: true);
      File('.test_skills/test.md').writeAsStringSync('''---
name: my-skill
description: 我的技能
run_as: inline
---
这是技能内容。
''');

      final loader = SkillLoader(['.test_skills']);
      final skills = loader.loadAll();
      expect(skills.length, 1);
      expect(skills.first.name, 'my-skill');
      expect(skills.first.description, '我的技能');
      expect(skills.first.body, '这是技能内容。');
      expect(skills.first.body, isNot(contains('---'))); // frontmatter 已剥离
    });

    test('目录布局 name/SKILL.md → 解析为 skill', () {
      _createSkillDir('my-dir-skill', '''---
name: dir-skill
description: 目录中的技能
---
目录技能内容。
''');

      final loader = SkillLoader(['.test_skills/my-dir-skill']);
      final skills = loader.loadAll();
      expect(skills.length, 1);
      expect(skills.first.name, 'dir-skill');
      expect(skills.first.description, '目录中的技能');
    });

    test('多路径加载 → 合并结果', () {
      File('.test_skills/a.md').createSync(recursive: true);
      File('.test_skills/a.md').writeAsStringSync('''---
name: skill-a
description: 技能A
---
A
''');
      File('.test_skills/b.md').createSync(recursive: true);
      File('.test_skills/b.md').writeAsStringSync('''---
name: skill-b
description: 技能B
---
B
''');

      final loader = SkillLoader(['.test_skills']);
      final skills = loader.loadAll();
      expect(skills.length, 2);
    });

    test('无 frontmatter 的文件 → 按文件名推断 name，缺少 description → 跳过', () {
      File('.test_skills/nofm.md').createSync(recursive: true);
      File('.test_skills/nofm.md').writeAsStringSync('纯文本内容，没有 frontmatter。');

      final loader = SkillLoader(['.test_skills']);
      final skills = loader.loadAll();
      // 无 description → 返回 null → 被跳过
      expect(skills.where((s) => s.name == 'nofm').length, 0);
    });

    test('scope 推断：project 路径', () {
      File('.test_skills/proj.md').createSync(recursive: true);
      File('.test_skills/proj.md').writeAsStringSync('''---
name: proj-skill
description: 项目技能
---
内容
''');

      final loader = SkillLoader(['.test_skills']);
      final skills = loader.loadAll();
      expect(skills.first.scope, isNotNull);
      // .test_skills 不含 .greenix → 返回 custom
      expect(skills.first.scope, SkillScope.custom);
    });

    test('实际 .greenix/skills/acceptance.md → 可加载', () {
      final loader = SkillLoader(['.greenix/skills']);
      final skills = loader.loadAll();
      expect(skills.any((s) => s.name == 'acceptance'), isTrue);
      final acceptance = skills.firstWhere((s) => s.name == 'acceptance');
      expect(acceptance.description, isNotEmpty);
      expect(acceptance.body, contains('无威胁的对话伙伴'));
      expect(acceptance.runAs, SkillRunAs.inline);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // BuiltinSkills
  // ═══════════════════════════════════════════════════════════

  group('BuiltinSkills', () {
    test('初始为空', () {
      expect(BuiltinSkills.all(), isEmpty);
    });

    test('register → all 返回已注册', () {
      // 注意：BuiltinSkills.all() 是全局静态，测试间可能互相影响
      final before = BuiltinSkills.all().length;

      BuiltinSkills.register(const Skill(
        name: 'builtin-test', description: '内置测试', body: 'B',
        scope: SkillScope.builtin, path: '',
      ));
      final names = BuiltinSkills.all().map((s) => s.name);
      expect(names, contains('builtin-test'));
    });

    test('loadInto → 注入到 SkillIndex', () {
      BuiltinSkills.register(const Skill(
        name: 'load-into-test', description: '注入测试', body: 'X',
        scope: SkillScope.builtin, path: '',
      ));

      final index = SkillIndex();
      BuiltinSkills.loadInto(index);
      final s = index.get('load-into-test');
      expect(s, isNotNull);
      expect(s!.scope, SkillScope.builtin);
      expect(s.path, '(builtin)');
    });
  });
}
