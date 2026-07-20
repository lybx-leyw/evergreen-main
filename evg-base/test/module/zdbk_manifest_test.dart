/// zdbk-modle 契约单元测试（v5P）。
///
/// 验证 [ModuleDescriptor] 对 v5P 新增字段的解析与序列化：
/// - 模块级 `modle_route`（选择 modle 内子 UI，按参考粒度拆多个独立 module）
/// - 模块级多数据源 `dataSources`（命名 source → DataSourceDescriptor）
/// - `dataSources.*.bindings`（字段→键路径，v5P 数据解耦核心）
/// 以及 zdbk 各独立模块 manifest 的真实契约形状 + [ZdbkData] 的 bindings 驱动解析。
import 'dart:convert';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/zdbk_modle/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _scoresManifestJson = '''
{
  "type": "module",
  "id": "zdbk-scores",
  "name": "成绩",
  "template": "zdbk",
  "modle_route": "score",
  "dataSources": {
    "transcript": {
      "endpoint": "orch://zdbk_transcript",
      "bindings": {
        "items": "items",
        "courseName": "kcmc",
        "score": "cj",
        "gpa": "jd",
        "credit": "xf",
        "courseNo": "xkkh"
      }
    },
    "major_grade": { "endpoint": "orch://zdbk_major_grade" },
    "practice_scores": { "endpoint": "orch://zdbk_practice_scores" }
  }
}
''';

const _examsManifestJson = '''
{
  "type": "module",
  "id": "zdbk-exams",
  "name": "考试安排",
  "template": "zdbk",
  "modle_route": "exams",
  "dataSources": {
    "exams": { "endpoint": "orch://zdbk_exams" }
  }
}
''';

void main() {
  group('ModuleDescriptor v5P 多数据源契约', () {
    test('成绩模块：解析 modle_route=score 与 3 个 dataSources', () {
      final d = ModuleDescriptor.fromJson(
          jsonDecode(_scoresManifestJson) as Map<String, dynamic>);

      expect(d.template, 'zdbk');
      expect(d.modleRoute, 'score');
      expect(d.dataSources, isNotNull);
      expect(d.dataSources!.length, 3);
      expect(d.dataSources!['transcript']!.endpoint, 'orch://zdbk_transcript');
      expect(d.dataSources!['major_grade']!.endpoint, 'orch://zdbk_major_grade');
      expect(
          d.dataSources!['practice_scores']!.endpoint, 'orch://zdbk_practice_scores');
    });

    test('考试模块：解析 modle_route=exams 与单 dataSources', () {
      final d = ModuleDescriptor.fromJson(
          jsonDecode(_examsManifestJson) as Map<String, dynamic>);
      expect(d.modleRoute, 'exams');
      expect(d.dataSources!.length, 1);
      expect(d.dataSources!['exams']!.endpoint, 'orch://zdbk_exams');
    });

    test('无 modle_route / dataSources 时回退默认且不报错', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'plain',
        'name': '普通模块',
        'template': 'v4',
      });
      expect(d.modleRoute, isNull);
      expect(d.dataSources, isNull);
      expect(d.template, 'v4');
    });

    test('toJson 序列化包含 modle_route 与 dataSources（往返一致）', () {
      final d = ModuleDescriptor.fromJson(
          jsonDecode(_scoresManifestJson) as Map<String, dynamic>);
      final out = d.toJson();
      expect(out['modle_route'], 'score');
      expect(out['dataSources'], isA<Map>());
      final ds = out['dataSources'] as Map;
      expect(ds['transcript']['endpoint'], 'orch://zdbk_transcript');

      final round = ModuleDescriptor.fromJson(out);
      expect(round.modleRoute, 'score');
      expect(round.dataSources!.length, 3);
    });

    test('classroom 单数据源契约不受影响', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'classroom-demo',
        'name': '智云课堂',
        'template': 'classroom',
        'dataSource': {
          'endpoint': 'orch://classroom',
          'bindings': {'courses': 'courses'}
        }
      });
      expect(d.modleRoute, isNull);
      expect(d.dataSources, isNull);
      expect(d.dataSource!.endpoint, 'orch://classroom');
      expect(d.dataSource!.bindings!['courses'], 'courses');
    });

    test('成绩模块 manifest 含 bindings 且能被解析', () {
      final d = ModuleDescriptor.fromJson(
          jsonDecode(_scoresManifestJson) as Map<String, dynamic>);
      expect(d.dataSources!['transcript']!.bindings, isNotNull);
      expect(d.dataSources!['transcript']!.bindings!['courseName'], 'kcmc');
      expect(d.dataSources!['transcript']!.bindings!['items'], 'items');
    });
  });

  group('zdbk-modle bindings 驱动解析', () {
    test('成绩：无 bindings 时按默认键解析 scraper 形状数据', () {
      final raw = [
        {
          'kcmc': '高等数学',
          'cj': '92',
          'jd': '4.0',
          'xf': '4',
          'xkkh': 'MATH01'
        }
      ];
      final list = ZdbkData.grades(raw, null);
      expect(list.length, 1);
      expect(list.first.courseName, '高等数学');
      expect(list.first.score, '92');
      expect(list.first.gpa, '4.0');
      expect(list.first.courseNo, 'MATH01');
    });

    test('成绩：自定义 bindings 覆盖键名（数据用非标准键也能解析）', () {
      final raw = [
        {
          'name': '线性代数',
          'point': '88',
          'gp': '3.7',
          'credit': '3',
          'no': 'LA01'
        }
      ];
      final b = {
        'courseName': 'name',
        'score': 'point',
        'gpa': 'gp',
        'credit': 'credit',
        'courseNo': 'no',
      };
      final list = ZdbkData.grades(raw, b);
      expect(list.first.courseName, '线性代数');
      expect(list.first.score, '88');
      expect(list.first.gpa, '3.7');
      expect(list.first.courseNo, 'LA01');
    });

    test('成绩：bindings 部分覆盖，未声明键回退默认', () {
      final raw = [
        {'kcmc': '物理', 'cj': '85', 'jd': '3.7', 'xf': '4', 'xkkh': 'PHY01'}
      ];
      // 只覆盖 score 键，其余回退默认 kcmc/jd/xf/xkkh
      final b = {'score': 'point'};
      final list = ZdbkData.grades(raw, b);
      // score 找不到 'point' → 空串；courseName 等按默认键正常解析
      expect(list.first.courseName, '物理');
      expect(list.first.gpa, '3.7');
      expect(list.first.score, '');
    });

    test('课表：bindings 覆盖 items 列表根键（kbList）与 kcb blob 拆分', () {
      final raw = {
        'kbList': [
          {
            'kcb': '大学物理<br>张老师/李老师<br>紫金港西1-301<br>2026年1月8日',
            'xqj': '1',
            'xxq': '秋冬',
            'xkkh': 'PHY'
          }
        ]
      };
      final b = {
        'items': 'kbList',
        'kcb': 'kcb',
        'courseName': 'kcmc',
        'weekday': 'xqj',
        'term': 'xxq',
        'courseNo': 'xkkh'
      };
      final list = ZdbkData.timetable(raw, b);
      expect(list.length, 1);
      expect(list.first.courseName, '大学物理');
      expect(list.first.teacher, '张老师/李老师');
      expect(list.first.location, '紫金港西1-301');
      expect(list.first.examTime, '2026年1月8日');
      expect(list.first.weekdayLabel, '周一');
    });

    test('二三四课堂：bindings 覆盖 pt2/pt3/pt4 并去「分」后缀', () {
      final b = {'pt2': 'a', 'pt3': 'b', 'pt4': 'c'};
      final p = ZdbkData.practice(
          {'a': '12分', 'b': '8分', 'c': '5分'}, b);
      expect(p.pt2, 12.0);
      expect(p.pt3, 8.0);
      expect(p.pt4, 5.0);
    });
  });
}
