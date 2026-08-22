/// 回归测试：市场中心扫描 Skill 能力目录（Skill 即插件）。
///
/// 覆盖：
/// 1. plugins/<id>/skill/*.md 无 manifest 也能生成 type='skill' 卡片；
/// 2. 卡片 name/description 取自 frontmatter，id 回退文件夹名；
/// 3. 与 module manifest 同目录时 id 不碰撞（追加 -skill 后缀）；
/// 4. dirs 映射指向真实文件夹（卸载定位用）。
library;

import 'dart:io';

import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/marketplace_scan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('scanPluginManifests Skill 扫描', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('mp_skill_scan_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    void writeSkill(String pluginDirName, String mdName, String name, String desc) {
      final dir = Directory(p.join(tmp.path, pluginDirName, 'skill'))..createSync(recursive: true);
      File(p.join(dir.path, mdName)).writeAsStringSync(
          '---\nname: $name\ndescription: $desc\n---\n# body');
    }

    test('无 manifest 的纯 skill 插件生成 type=skill 卡片', () {
      writeSkill('summarize-code', 'summarize-code.md', 'summarize-code', '总结代码');

      final (descriptors, dirs) = scanPluginManifests(tmp.path);

      expect(descriptors.length, 1);
      final info = descriptors.first;
      expect(info.type, 'skill');
      expect(info.isSkill, isTrue);
      expect(info.name, 'summarize-code');
      expect(info.description, '总结代码');
      expect(info.id, 'summarize-code');
      expect(dirs[info.id], p.join(tmp.path, 'summarize-code'));
    });

    test('同目录既有 module manifest 时 skill 卡 id 追加 -skill 后缀', () {
      // 无 id 的 module manifest → module 卡 id=文件夹名
      final dir = Directory(p.join(tmp.path, 'multi'))..createSync();
      Directory(p.join(dir.path, 'module')).createSync();
      File(p.join(dir.path, 'module', 'manifest.json')).writeAsStringSync(
          '{"type": "module", "name": "Multi"}');
      writeSkill('multi', 'a.md', 'a', '技能 A');

      final (descriptors, _) = scanPluginManifests(tmp.path);
      final ids = descriptors.map((d) => d.id).toSet();
      final skills = descriptors.where((d) => d.type == 'skill').toList();

      expect(ids, contains('multi')); // module 卡占用了文件夹名
      expect(skills.length, 1);
      expect(skills.first.id, 'multi-skill');
      expect(skills.first.name, 'a');
    });

    test('空的 skill 目录不生成卡片', () {
      Directory(p.join(tmp.path, 'empty-skill', 'skill')).createSync(recursive: true);

      final (descriptors, _) = scanPluginManifests(tmp.path);
      expect(descriptors, isEmpty);
    });
  });
}
