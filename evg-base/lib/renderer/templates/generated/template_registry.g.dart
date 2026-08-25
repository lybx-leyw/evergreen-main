// GENERATED CODE - DO NOT MODIFY BY HAND
//
// 由 tool/gen_template_registry.dart 生成，勿手改。
//   profile    : release_full
//   说明        : 全量版：装入全部模板（含浙大 zju / classroom / zdbk 场景）。
//   模板清单    : lib/renderer/templates/templates_index.json
//   修改方式    : 编辑上述输入后重新运行生成器
library;

import 'package:evergreen_base/renderer/templates/template.dart';
import 'package:evergreen_base/renderer/templates/dsh_modle/dsh_modle_template.dart';
import 'package:evergreen_base/renderer/templates/html_modle/html_modle_template.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/scraper_template.dart';
import 'package:evergreen_base/renderer/templates/skill_creator_modle/skill_creator_modle_template.dart';
import 'package:evergreen_base/renderer/templates/theme_creator_modle/theme_creator_modle_template.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/v4_modle_template.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zju_modle_template.dart';

/// 模板注册表（生成物）：共 9 条路由，7 个入口文件。
Map<String, ModleRenderer> buildTemplateRegistry() {
  return <String, ModleRenderer>{
    'v4': const V4ModleTemplate(),
    'zju': const ZjuModleTemplate(),
    'classroom': const ZjuModleTemplate(),
    'zdbk': const ZjuModleTemplate(),
    'html': const HtmlModleTemplate(),
    'scraper': const ScraperTemplate(),
    'theme-creator': const ThemeCreatorModleTemplate(),
    'skill-creator': const SkillCreatorModleTemplate(),
    'dsh': const DshModleTemplate(),
  };
}
