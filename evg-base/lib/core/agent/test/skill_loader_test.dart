/// SkillLoader 单元测试：插件形态路径（plugins/<id>/skill/*.md）+ 禁用过滤。
///
/// 覆盖：
/// 1. 平铺 .md（.greenix/skills 旧布局）与插件布局 B（<plugin>/skill/*.md）都能加载；
/// 2. disabledSkillIds 按 Skill 名归一化与插件目录段两种规则过滤；
/// 3. disabledIdsFromPluginStates 读取 .plugin_states.json 的停用集合。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../skill/skill.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('evg_skill_loader_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String write(String rel, String content) {
    final f = File(p.join(tmp.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    return f.path;
  }

  String skillMd(String name, String description, [String body = '# body']) {
    return '---\nname: $name\ndescription: $description\n---\n$body';
  }

  group('路径统一（Skill 即插件）', () {
    test('同时加载 .greenix/skills 平铺与 plugins/<id>/skill 布局 B', () {
      final legacyPath = p.join(tmp.path, '.greenix', 'skills');
      write(p.join('.greenix', 'skills', 'legacy.md'), skillMd('legacy', '旧路径技能'));
      write(p.join('plugins', 'my-skill', 'skill', 'my-skill.md'),
          skillMd('my-skill', '插件形态技能'));

      final loader = SkillLoader([legacyPath, p.join(tmp.path, 'plugins')]);
      final names = loader.loadAll().map((s) => s.name).toSet();

      expect(names, contains('legacy'));
      expect(names, contains('my-skill'));
    });
  });

  group('禁用过滤', () {
    test('按 Skill 名归一化匹配禁用（大小写/空白归一）', () {
      final plugins = p.join(tmp.path, 'plugins');
      write(p.join('plugins', 'my-skill', 'skill', 'my-skill.md'),
          skillMd('My Skill', '被禁用的技能'));
      write(p.join('plugins', 'ok-skill', 'skill', 'ok-skill.md'),
          skillMd('ok-skill', '保留的技能'));

      final loader = SkillLoader([plugins], disabledSkillIds: {'my-skill'});
      final names = loader.loadAll().map((s) => s.name).toSet();

      expect(names, isNot(contains('My Skill')));
      expect(names, contains('ok-skill'));
    });

    test('按插件目录段匹配禁用（plugins/<id>/skill/ 命中）', () {
      final plugins = p.join(tmp.path, 'plugins');
      write(p.join('plugins', 'blocked-plugin', 'skill', 'a.md'),
          skillMd('a', '目录被禁用的技能'));
      write(p.join('plugins', 'ok-plugin', 'skill', 'b.md'),
          skillMd('b', '正常技能'));

      final loader = SkillLoader([plugins], disabledSkillIds: {'blocked-plugin'});
      final names = loader.loadAll().map((s) => s.name).toSet();

      expect(names, isNot(contains('a')));
      expect(names, contains('b'));
    });
  });

  group('disabledIdsFromPluginStates', () {
    test('读取 enabled=false 的插件 id；忽略 _config 与启用项', () {
      write(p.join('plugins', '.plugin_states.json'),
          '{ "_config": {"sortMode": "group"}, "off-skill": {"enabled": false}, "on-skill": {"enabled": true} }');

      final disabled = SkillLoader.disabledIdsFromPluginStates(p.join(tmp.path, 'plugins'));
      expect(disabled, {'off-skill'});
    });

    test('文件缺失返回空集合', () {
      expect(SkillLoader.disabledIdsFromPluginStates(p.join(tmp.path, 'plugins')), isEmpty);
    });
  });

  group('pluginsRootForDisabled 热生效', () {
    test('市场停用后无需重启，loadAll 即时过滤', () {
      final plugins = p.join(tmp.path, 'plugins');
      write(p.join('plugins', 'toggle-skill', 'skill', 'toggle-skill.md'),
          skillMd('toggle-skill', '可停用的技能'));
      final loader = SkillLoader([plugins], pluginsRootForDisabled: plugins);

      // 未停用：可加载
      expect(loader.loadAll().map((s) => s.name), contains('toggle-skill'));

      // 市场中心写入停用状态后：下次 loadAll 即被过滤
      write(p.join('plugins', '.plugin_states.json'),
          '{ "toggle-skill": {"enabled": false} }');
      expect(
          loader.loadAll().map((s) => s.name), isNot(contains('toggle-skill')));

      // 重新启用：恢复加载
      write(p.join('plugins', '.plugin_states.json'),
          '{ "toggle-skill": {"enabled": true} }');
      expect(loader.loadAll().map((s) => s.name), contains('toggle-skill'));
    });
  });
}
