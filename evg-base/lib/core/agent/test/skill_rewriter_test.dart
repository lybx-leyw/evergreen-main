/// SkillRewriter 纯函数解析/校验测试——不涉文件系统、不调用 LLM。
///
/// 覆盖：
/// - [SkillRewriter.normalizeName] 名称规范化（不改语义、仅 kebab-case）；
/// - [SkillRewriter.parseOutput] AI 输出解析（frontmatter 拆分、字段缺失、
///   run_as 回退、代码块去包裹、引号去除、名称规范化）。
library;

import 'package:test/test.dart';

import '../skill/skill_rewriter.dart';

void main() {
  // ═══════ normalizeName（纯函数） ═══════

  group('normalizeName', () {
    test('空格 → kebab-case', () {
      expect(SkillRewriter.normalizeName('My Skill'), 'my-skill');
    });

    test('下划线 → kebab-case', () {
      expect(SkillRewriter.normalizeName('my_skill'), 'my-skill');
    });

    test('多空格 + 大小写混合 → 合并连字符', () {
      expect(SkillRewriter.normalizeName('  Summarize   Code  '),
          'summarize-code');
    });

    test('驼峰分隔 → kebab-case', () {
      expect(SkillRewriter.normalizeName('summarizeCode'), 'summarize-code');
    });

    test('已是 kebab-case 保持不变', () {
      expect(SkillRewriter.normalizeName('already-kebab'), 'already-kebab');
    });

    test('数字保留', () {
      expect(SkillRewriter.normalizeName('Skill v2'), 'skill-v2');
    });

    test('全中文名原样保留（小写化，不为空）', () {
      expect(SkillRewriter.normalizeName('总结代码'), '总结代码');
    });

    test('空输入 → 空串', () {
      expect(SkillRewriter.normalizeName(''), '');
      expect(SkillRewriter.normalizeName('   '), '');
    });
  });

  // ═══════ parseOutput（纯函数） ═══════

  group('parseOutput', () {
    test('完整 frontmatter → 拆分 name/description/body/runAs', () {
      const raw = '''
---
name: summarize-code
description: 总结代码仓库的核心逻辑
run_as: inline
---
# 总结代码

## 适用场景
当需要快速理解一个代码库时使用。

## 执行步骤
1. 扫描目录结构
2. 提炼核心模块
''';
      final data = SkillRewriter.parseOutput(raw);
      expect(data, isNotNull);
      expect(data!.name, 'summarize-code');
      expect(data.description, '总结代码仓库的核心逻辑');
      expect(data.runAs, 'inline');
      expect(data.body, contains('# 总结代码'));
      expect(data.body, contains('## 执行步骤'));
    });

    test('runAs 别名 runAs 也支持', () {
      const raw = '''
---
name: my-skill
description: 描述
runAs: subagent
---
正文
''';
      final data = SkillRewriter.parseOutput(raw);
      expect(data, isNotNull);
      expect(data!.runAs, 'subagent');
    });

    test('run_as 缺失 → 回退 fallbackRunAs', () {
      const raw = '''
---
name: my-skill
description: 描述
---
正文
''';
      final data = SkillRewriter.parseOutput(raw, fallbackRunAs: 'subagent');
      expect(data, isNotNull);
      expect(data!.runAs, 'subagent');
    });

    test('run_as 非法值 → 回退 fallbackRunAs', () {
      const raw = '''
---
name: my-skill
description: 描述
run_as: agent
---
正文
''';
      final data = SkillRewriter.parseOutput(raw, fallbackRunAs: 'inline');
      expect(data, isNotNull);
      expect(data!.runAs, 'inline');
    });

    test('description 缺失 → null（格式不正确，可重试）', () {
      const raw = '''
---
name: my-skill
---
正文
''';
      expect(SkillRewriter.parseOutput(raw), isNull);
    });

    test('body 缺失 → null', () {
      const raw = '''
---
name: my-skill
description: 描述
---
''';
      expect(SkillRewriter.parseOutput(raw), isNull);
    });

    test('无 frontmatter → null', () {
      const raw = '只有一段正文，没有 frontmatter';
      expect(SkillRewriter.parseOutput(raw), isNull);
    });

    test('代码块包裹 → 去包裹后正常解析', () {
      const raw = '''```markdown
---
name: my-skill
description: 描述
run_as: inline
---
正文内容
```''';
      final data = SkillRewriter.parseOutput(raw);
      expect(data, isNotNull);
      expect(data!.name, 'my-skill');
      expect(data.body, '正文内容');
    });

    test('name 缺失 → 回退 fallbackName 并规范化', () {
      const raw = '''
---
description: 描述
run_as: inline
---
正文
''';
      final data =
          SkillRewriter.parseOutput(raw, fallbackName: 'My Skill');
      expect(data, isNotNull);
      expect(data!.name, 'my-skill');
    });

    test('name 规范化：AI 输出非 kebab 形式 → 规范化', () {
      const raw = '''
---
name: My Skill
description: 描述
run_as: inline
---
正文
''';
      final data = SkillRewriter.parseOutput(raw);
      expect(data, isNotNull);
      expect(data!.name, 'my-skill');
    });

    test('frontmatter 值带引号 → 去引号', () {
      const raw = '''
---
name: "my-skill"
description: '描述文字'
run_as: inline
---
正文
''';
      final data = SkillRewriter.parseOutput(raw);
      expect(data, isNotNull);
      expect(data!.name, 'my-skill');
      expect(data.description, '描述文字');
    });

    test('name 全中文且无 fallback → 保留中文名（非空）', () {
      const raw = '''
---
name: 总结代码
description: 描述
run_as: inline
---
正文
''';
      final data = SkillRewriter.parseOutput(raw);
      expect(data, isNotNull);
      expect(data!.name, '总结代码');
    });

    test('body 保留多行 Markdown 结构', () {
      const raw = '''
---
name: my-skill
description: 描述
run_as: inline
---
## 步骤

1. 第一步
2. 第二步

> 注意：不要删除历史。
''';
      final data = SkillRewriter.parseOutput(raw);
      expect(data, isNotNull);
      expect(data!.body, contains('1. 第一步'));
      expect(data.body, contains('> 注意'));
    });
  });
}
