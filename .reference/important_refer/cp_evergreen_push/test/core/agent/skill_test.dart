import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/skill/skill.dart';

void main() {
  group('Skill', () {
    test('Skill 对象创建', () {
      final skill = Skill(
        name: 'test-skill',
        description: 'A test skill',
        body: 'This is the body',
        path: '',
        scope: SkillScope.builtin,
        runAs: SkillRunAs.inline,
      );

      expect(skill.name, 'test-skill');
      expect(skill.description, 'A test skill');
      expect(skill.body, 'This is the body');
      expect(skill.scope, SkillScope.builtin);
      expect(skill.runAs, SkillRunAs.inline);
    });

    test('SkillScope 优先级排序', () {
      final scopes = SkillScope.values.toList()..sort((a, b) => a.priority.compareTo(b.priority));
      expect(scopes.first, SkillScope.builtin);
      expect(scopes.last, SkillScope.project);
    });

    test('SkillRunAs 枚举', () {
      expect(SkillRunAs.inline, isNotNull);
      expect(SkillRunAs.subagent, isNotNull);
      expect(SkillRunAs.values.length, 2);
    });
  });
}
