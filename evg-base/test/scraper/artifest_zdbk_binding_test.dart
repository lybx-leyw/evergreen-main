/// ZDBK bindings 真实性验证（以源码为准，v5P）。
///
/// 目的：验证 zdbk-modle 渲染层（[ZdbkData]）的字段提取**确实走 bindings**，
/// 而非写死数据源键名。验证方式：
///
///  A. 单元层：用一套**字段名完全自定义、与 zdbk 真实键（kcmc/cj/jd...）毫不相同**
///     的假数据 + 自定义 bindings 映射，证明 [ZdbkData] 按 `语义键 → 数据键路径`
///     提取（lesson → courseName、mark → score …）。
///
/// 本测试不依赖任何外部 scraper / 插件 manifest，纯 Dart 数据，
/// 以源码（models.dart + module_descriptor.dart）为唯一真相来源。
///
/// ⚠️ 2026-08-02：原 B 层（真实 zdbk-* 插件 manifest 契约验证）已删除——
/// zdbk-* 插件不在 plugins/（历史遗留，zdbk 功能已内置于 renderer 的 zdbk_modle，
/// 数据由 data-zdbk 插件提供），无 manifest 可读；bindings 机制已由 A 层覆盖。
library;
import 'dart:convert';

import 'package:evergreen_base/renderer/templates/zju_modle/zdbk/models.dart';
import 'package:flutter_test/flutter_test.dart';

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
    // ⚠️ 2026-08-02 删除：zdbk-* 插件已不在 plugins/（历史遗留），
    // 无真实 manifest 可读。bindings 机制已由 A 层（自定义键）覆盖。
  });
}
