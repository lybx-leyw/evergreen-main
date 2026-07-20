/// ZDBK bindings 真实性验证（以源码为准，v5P）。
///
/// 目的：验证 zdbk-modle 渲染层（[ZdbkData]）的字段提取**确实走 bindings**，
/// 而非写死数据源键名。两层验证：
///
///  A. 单元层：用一套**字段名完全自定义、与 zdbk 真实键（kcmc/cj/jd...）毫不相同**
///     的假数据 + 自定义 bindings 映射，证明 [ZdbkData] 按 `语义键 → 数据键路径`
///     提取（lesson → courseName、mark → score …）。
///
///  B. 契约层：读取**真实** `plugins/zdbk-*` 模块 manifest，断言其
///     `dataSources.<name>.bindings` 声明了字段映射，并用该 bindings 构造标准键
///     数据验证 [ZdbkData] 正确提取——证明真实插件与源码 bindings 机制对齐。
///
/// 本测试不依赖任何外部 scraper / 不存在的测试插件，纯 Dart 数据 + 真实 manifest
/// 静态契约，以源码（models.dart + module_descriptor.dart）为唯一真相来源。
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/zdbk_modle/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// ── 工作区定位：向上找到真实插件 plugins/zdbk-scores（契约层用）──
String _workspaceRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final probe =
        p.join(dir.path, 'plugins', 'zdbk-scores', 'module', 'manifest.json');
    if (File(probe).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('找不到 plugins/zdbk-scores（当前: ${Directory.current.path}）');
}

ModuleDescriptor _loadModule(String ws, String id) {
  final f = File(p.join(ws, 'plugins', id, 'module', 'manifest.json'));
  final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return ModuleDescriptor.fromJson(json);
}

/// 自定义键假数据（字段名与 zdbk 真实键毫不相同）——单元层演示 bindings 不写死键名。
final Map<String, Map<String, dynamic>> _fake = {
  'transcript': {
    'rows': [
      {'lesson': '高等数学(虚构)', 'mark': '92', 'gp': '3.8', 'hours': '4.0', 'code': 'MATH1001'},
      {'lesson': '大学英语(虚构)', 'mark': '88', 'gp': '3.6', 'hours': '3.0', 'code': 'ENG1002'},
      {'lesson': '数据结构(虚构)', 'mark': '95', 'gp': '4.0', 'hours': '4.0', 'code': 'CS1003'},
    ],
  },
  'major_grade': {
    'rows': [
      {'lesson': '主修-数学分析(虚构)', 'mark': '90', 'gp': '3.7', 'hours': '5.0', 'code': 'MAJOR01'},
      {'lesson': '主修-离散数学(虚构)', 'mark': '93', 'gp': '3.9', 'hours': '4.0', 'code': 'MAJOR02'},
    ],
  },
  'practice_scores': {
    'second': '12分',
    'third': '8分',
    'fourth': '5分',
  },
  'exams': {
    'events': [
      {
        'subject': '高等数学(虚构)',
        'room': '紫金港东1A-305',
        'when': '2026-01-15 09:00',
        'proctor': '王伟',
        'sem': '秋冬',
        'seat': 'A12',
        'credit': '4.0',
      },
      {
        'subject': '大学英语(虚构)',
        'room': '紫金港东2B-110',
        'when': '2026-01-16 14:00',
        'proctor': '李娜',
        'sem': '秋冬',
        'seat': 'B07',
        'credit': '3.0',
      },
    ],
  },
  'timetable': {
    'grid': [
      {
        'cell': '高等数学(虚构)<br>王伟/李娜<br>紫金港东1A-305<br>2026年1月15日 09:00',
        'title': '高等数学(虚构)',
        'dow': '1',
        'season': '秋冬',
        'cno': 'MATH1001',
      },
      {
        'cell': '<br>张三/李四<br>紫金港西2B-201<br>2026年1月16日 14:00',
        'title': '线性代数(虚构)',
        'dow': '3',
        'season': '秋冬',
        'cno': 'MATH1002',
      },
    ],
  },
  'course_offerings': {
    'list': [
      {
        'lesson_name': '机器学习(虚构)',
        'instructor': '陈强',
        'venue': '紫金港东4-201',
        'slot': '周一第3-4节',
        'credit': '3.0',
        'kind': '必修',
        'nature': '专业课',
        'school': '计算机学院',
        'major': '计算机科学',
        'year': '2025-2026',
        'term': '秋冬',
      },
      {
        'lesson_name': '操作系统(虚构)',
        'instructor': '赵敏',
        'venue': '紫金港西3-105',
        'slot': '周三第1-2节',
        'credit': '4.0',
        'kind': '必修',
        'nature': '专业课',
        'school': '计算机学院',
        'major': '计算机科学',
        'year': '2025-2026',
        'term': '秋冬',
      },
    ],
  },
  'training_plans': {
    'plans': [
      {
        'program': '计算机科学培养方案(虚构)',
        'major': '计算机科学',
        'faculty': '计算机学院',
        'entry_year': '2023',
        'duration': '4',
        'min_credit': '150',
        'total_credit': '160',
        'discipline': '工学',
        'campus': '紫金港',
        'goal': '培养系统能力与工程素养',
      },
    ],
  },
  'notifications': {
    'bulletins': [
      {
        'uid': 'n001',
        'headline': '关于期末考试安排的通知(虚构)',
        'author': '教务处',
        'issued': '2026-01-10',
        'views': '120',
        'body': '请同学们及时查看个人考试安排。',
      },
      {
        'uid': 'n002',
        'headline': '寒假放假通知(虚构)',
        'author': '学工办',
        'issued': '2026-01-12',
        'views': '88',
        'body': '寒假自1月20日起至2月20日。',
      },
    ],
  },
};

void main() {
  group('A. 单元层：自定义键经 bindings 提取（渲染层不写死键名）', () {
    test('scores/transcript：自定义字段经 bindings 解析', () {
      final b = {
        'items': 'rows',
        'courseName': 'lesson',
        'score': 'mark',
        'gpa': 'gp',
        'credit': 'hours',
        'courseNo': 'code',
      };
      final raw = _fake['transcript']!;
      final list = ZdbkData.grades(raw, b);
      expect(list.length, 3);
      expect(list[0].courseName, '高等数学(虚构)'); // lesson → courseName
      expect(list[0].score, '92'); // mark → score
      expect(list[0].gpa, '3.8'); // gp → gpa
      expect(list[0].credit, '4.0'); // hours → credit
      expect(list[0].courseNo, 'MATH1001'); // code → courseNo
    });

    test('scores/major_grade：自定义字段经 bindings 解析', () {
      final b = {
        'items': 'rows',
        'courseName': 'lesson',
        'score': 'mark',
        'gpa': 'gp',
        'credit': 'hours',
        'courseNo': 'code',
      };
      final raw = _fake['major_grade']!;
      final list = ZdbkData.grades(raw, b);
      expect(list.length, 2);
      expect(list[1].courseName, '主修-离散数学(虚构)');
      expect(list[1].score, '93');
      expect(list[1].courseNo, 'MAJOR02');
    });

    test('scores/practice_scores：二三课堂 自定义键 + 去「分」', () {
      final b = {
        'pt2': 'second',
        'pt3': 'third',
        'pt4': 'fourth',
      };
      final raw = _fake['practice_scores']!;
      final p = ZdbkData.practice(raw, b);
      expect(p.pt2, 12.0); // second → pt2，去「分」
      expect(p.pt3, 8.0); // third → pt3
      expect(p.pt4, 5.0); // fourth → pt4
    });

    test('exams：自定义字段经 bindings 解析', () {
      final b = {
        'items': 'events',
        'courseName': 'subject',
        'location': 'room',
        'time': 'when',
        'teacher': 'proctor',
        'term': 'sem',
        'seatNo': 'seat',
        'credit': 'credit',
      };
      final raw = _fake['exams']!;
      final list = ZdbkData.exams(raw, b);
      expect(list.length, 2);
      expect(list[0].courseName, '高等数学(虚构)'); // subject → courseName
      expect(list[0].location, '紫金港东1A-305'); // room → location
      expect(list[0].time, '2026-01-15 09:00'); // when → time
      expect(list[0].teacher, '王伟'); // proctor → teacher
      expect(list[0].term, '秋冬'); // sem → term
      expect(list[0].seatNo, 'A12'); // seat → seatNo
      expect(list[0].credit, '4.0'); // credit → credit
    });

    test('timetable：grid 列表根 + cell blob + 字段 全部经 bindings', () {
      final b = {
        'items': 'grid',
        'kcb': 'cell',
        'courseName': 'title', // cell blob 名为空时回退到此键
        'weekday': 'dow',
        'term': 'season',
        'courseNo': 'cno',
      };
      final raw = _fake['timetable']!;
      final list = ZdbkData.timetable(raw, b);
      expect(list.length, 2);
      // 条目1：cell blob 解析 + dow/season/cno 绑定
      expect(list[0].courseName, '高等数学(虚构)'); // blob name
      expect(list[0].teacher, '王伟/李娜');
      expect(list[0].location, '紫金港东1A-305');
      expect(list[0].examTime, '2026年1月15日 09:00');
      expect(list[0].weekday, '1'); // dow → weekday
      expect(list[0].term, '秋冬'); // season → term
      expect(list[0].courseNo, 'MATH1001'); // cno → courseNo
      // 条目2：cell blob 名为空 → courseName 回退到 title 绑定
      expect(list[1].courseName, '线性代数(虚构)'); // title → courseName
      expect(list[1].teacher, '张三/李四');
      expect(list[1].courseNo, 'MATH1002');
    });

    test('courses/course_offerings：全字段自定义键经 bindings', () {
      final b = {
        'items': 'list',
        'courseName': 'lesson_name',
        'teacher': 'instructor',
        'location': 'venue',
        'schedule': 'slot',
        'credit': 'credit',
        'type': 'kind',
        'property': 'nature',
        'college': 'school',
        'major': 'major',
        'year': 'year',
        'term': 'term',
      };
      final raw = _fake['course_offerings']!;
      final list = ZdbkData.offerings(raw, b);
      expect(list.length, 2);
      expect(list[0].courseName, '机器学习(虚构)'); // lesson_name → courseName
      expect(list[0].teacher, '陈强'); // instructor → teacher
      expect(list[0].location, '紫金港东4-201'); // venue → location
      expect(list[0].schedule, '周一第3-4节'); // slot → schedule
      expect(list[0].credit, '3.0');
      expect(list[0].type, '必修'); // kind → type
      expect(list[0].property, '专业课'); // nature → property
      expect(list[0].college, '计算机学院'); // school → college
      expect(list[0].major, '计算机科学');
      expect(list[0].year, '2025-2026');
      expect(list[0].term, '秋冬');
    });

    test('courses/training_plans：全字段自定义键经 bindings', () {
      final b = {
        'items': 'plans',
        'planName': 'program',
        'major': 'major',
        'college': 'faculty',
        'grade': 'entry_year',
        'lengthYears': 'duration',
        'minCredits': 'min_credit',
        'totalCredits': 'total_credit',
        'category': 'discipline',
        'campus': 'campus',
        'remarks': 'goal',
      };
      final raw = _fake['training_plans']!;
      final list = ZdbkData.plans(raw, b);
      expect(list.length, 1);
      expect(list[0].planName, '计算机科学培养方案(虚构)'); // program → planName
      expect(list[0].major, '计算机科学');
      expect(list[0].college, '计算机学院'); // faculty → college
      expect(list[0].grade, '2023'); // entry_year → grade
      expect(list[0].lengthYears, '4'); // duration → lengthYears
      expect(list[0].minCredits, '150'); // min_credit → minCredits
      expect(list[0].totalCredits, '160'); // total_credit → totalCredits
      expect(list[0].category, '工学'); // discipline → category
      expect(list[0].campus, '紫金港'); // campus → campus
      expect(list[0].remarks, '培养系统能力与工程素养'); // goal → remarks
    });

    test('notifications：自定义键经 bindings 解析', () {
      final b = {
        'items': 'bulletins',
        'id': 'uid',
        'title': 'headline',
        'publisher': 'author',
        'publishDate': 'issued',
        'viewCount': 'views',
        'content': 'body',
      };
      final raw = _fake['notifications']!;
      final list = ZdbkData.notifications(raw, b);
      expect(list.length, 2);
      expect(list[0].id, 'n001'); // uid → id
      expect(list[0].title, '关于期末考试安排的通知(虚构)'); // headline → title
      expect(list[0].publisher, '教务处'); // author → publisher
      expect(list[0].publishDate, '2026-01-10'); // issued → publishDate
      expect(list[0].viewCount, 120); // views → viewCount（int）
      expect(list[0].content, '请同学们及时查看个人考试安排。'); // body → content
    });

    test('控制：无 bindings 时自定义字段提取不到（证明 bindings 不可或缺）', () {
      final raw = _fake['transcript']!;
      // 不传 bindings → 模型回退到默认键（items/kcmc/cj...），而数据根是 rows、
      // 字段是 lesson/mark... → 列表根找不到 → 空列表；字段也找不到。
      final list = ZdbkData.grades(raw, null);
      expect(list, isEmpty);
    });
  });

  group('B. 契约层：真实 zdbk-* 插件 manifest 的 bindings', () {
    final ws = _workspaceRoot();

    test('zdbk-scores 声明 transcript/major_grade/practice_scores 且 bindings 正确', () {
      final m = _loadModule(ws, 'zdbk-scores');
      expect(m.template, 'zdbk');
      expect(m.modleRoute, 'score');
      expect(m.dataSources, isNotNull);

      // transcript
      final t = m.dataSources!['transcript']!;
      expect(t.bindings, isNotNull);
      expect(t.bindings!['courseName'], 'kcmc');
      expect(t.bindings!['score'], 'cj');
      expect(t.bindings!['gpa'], 'jd');
      expect(t.bindings!['credit'], 'xf');
      expect(t.bindings!['courseNo'], 'xkkh');
      // 用真实 bindings 构造标准键数据，验证 ZdbkData 能正确提取
      final raw = {
        'items': [
          {'kcmc': '数学分析', 'cj': '90', 'jd': '3.7', 'xf': '5.0', 'xkkh': 'MA001'},
        ],
      };
      final list = ZdbkData.grades(raw, t.bindings);
      expect(list.length, 1);
      expect(list[0].courseName, '数学分析');
      expect(list[0].score, '90');
      expect(list[0].gpa, '3.7');
      expect(list[0].credit, '5.0');
      expect(list[0].courseNo, 'MA001');

      // practice_scores 的 pt 字段映射
      final p = m.dataSources!['practice_scores']!;
      expect(p.bindings!['pt2'], 'pt2');
      expect(p.bindings!['pt3'], 'pt3');
      expect(p.bindings!['pt4'], 'pt4');
    });

    test('zdbk-exams 声明 exams.bindings（含 kssj/zwxh 等真实键）', () {
      final m = _loadModule(ws, 'zdbk-exams');
      final e = m.dataSources!['exams']!;
      expect(e.bindings, isNotNull);
      expect(e.bindings!['courseName'], 'kcmc');
      expect(e.bindings!['location'], 'jsmc');
      expect(e.bindings!['time'], 'kssj');
      expect(e.bindings!['teacher'], 'xm');
      expect(e.bindings!['seatNo'], 'zwxh');
      final raw = {
        'items': [
          {'kcmc': '高等数学', 'jsmc': '东1A', 'kssj': '2026-01-15', 'xm': '王伟', 'xxq': '秋冬', 'zwxh': 'A12', 'xf': '4.0'},
        ],
      };
      final list = ZdbkData.exams(raw, e.bindings);
      expect(list[0].courseName, '高等数学');
      expect(list[0].location, '东1A');
      expect(list[0].time, '2026-01-15');
      expect(list[0].teacher, '王伟');
      expect(list[0].seatNo, 'A12');
    });

    test('zdbk-timetable 声明 timetable.bindings（含 kcb blob 与 kbList 列表根）', () {
      final m = _loadModule(ws, 'zdbk-timetable');
      final t = m.dataSources!['timetable']!;
      expect(t.bindings!['items'], 'kbList'); // 课表列表根是 kbList
      expect(t.bindings!['kcb'], 'kcb'); // blob 字段
      expect(t.bindings!['courseName'], 'kcmc');
      expect(t.bindings!['weekday'], 'xqj');
      final raw = {
        'kbList': [
          {'kcb': '线性代数<br>张三/李四<br>紫金港西2B<br>2026年1月16日', 'kcmc': '线性代数', 'xqj': '3', 'xxq': '秋冬', 'xkkh': 'MATH2'},
        ],
      };
      final list = ZdbkData.timetable(raw, t.bindings);
      expect(list.length, 1);
      expect(list[0].courseName, '线性代数');
      expect(list[0].teacher, '张三/李四'); // kcb blob 中教师以 "/" 分隔
      expect(list[0].weekday, '3');
      expect(list[0].courseNo, 'MATH2');
    });

    test('zdbk-courses 声明 course_offerings/training_plans.bindings', () {
      final m = _loadModule(ws, 'zdbk-courses');
      final o = m.dataSources!['course_offerings']!;
      expect(o.bindings!['courseName'], 'kcmc');
      expect(o.bindings!['teacher'], 'jsxm');
      expect(o.bindings!['location'], 'skdd');
      final p = m.dataSources!['training_plans']!;
      expect(p.bindings!['planName'], 'zymc');
      expect(p.bindings!['grade'], 'synj');
      expect(p.bindings!['lengthYears'], 'xz');
    });

    test('zdbk-notifications 声明 notifications.bindings', () {
      final m = _loadModule(ws, 'zdbk-notifications');
      final n = m.dataSources!['notifications']!;
      expect(n.bindings!['id'], 'id');
      expect(n.bindings!['title'], 'title');
      expect(n.bindings!['publisher'], 'publisher');
      expect(n.bindings!['viewCount'], 'viewCount');
    });
  });
}
