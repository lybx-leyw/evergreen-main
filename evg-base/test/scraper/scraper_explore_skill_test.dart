/// 探索 Skill（scraperExploreSkillBody）内容测试 —— P1-A 探索策略启发式。
///
/// 纯 Dart，无 Flutter 依赖，验证探索 Skill 提示词包含深度探索所需的
/// 策略章节：体量预估 / 骨架扫描 → 目标下钻 / 噪音链接甄别 / 导航后回读 /
/// 目标缺失先 ask。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_base/renderer/templates/scraper_modle/scraper_skill_const.dart'
    show scraperExploreSkillBody;

void main() {
  final skill = scraperExploreSkillBody;

  group('scraperExploreSkillBody 探索策略启发式（P1-A）', () {
    test('包含「探索策略启发式」章节', () {
      expect(skill, contains('探索策略启发式'));
    });

    test('包含体量预估（栏目门户/列表分页/SPA）指引', () {
      expect(skill, contains('体量预估'));
      expect(skill, contains('栏目门户'));
      expect(skill, contains('列表+分页'));
      expect(skill, contains('SPA'));
    });

    test('包含「广度扫骨架 → 按目标深度下钻」节奏', () {
      expect(skill, contains('广度扫骨架'));
      expect(skill, contains('下钻'));
      expect(skill, contains('只对**相关栏目**逐层下钻'));
    });

    test('包含噪音链接甄别（不导航清单 + 优先导航清单）', () {
      expect(skill, contains('噪音链接甄别'));
      expect(skill, contains('href="#"'));
      expect(skill, contains('javascript:'));
      expect(skill, contains('登录/注册/关于/帮助/联系/隐私/条款'));
      expect(skill, contains('`?page=`'));
      expect(skill, contains('/api/'));
      expect(skill, contains('.json'));
    });

    test('包含「导航后必须回读」要求（防失明）', () {
      expect(skill, contains('导航后必须回读'));
      expect(skill, contains('list_captured_requests()'));
      expect(skill, contains('read_request_by_id'));
      expect(skill, contains('禁止连续盲导航'));
    });

    test('目标缺失时先 ask 确认（放宽少问问题）', () {
      expect(skill, contains('ask()'));
      expect(skill, contains('目标缺失先 ask'));
      expect(skill, contains('不要为了"少问问题"而猜测目标乱扫'));
    });
  });
}
