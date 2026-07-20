/// ARTIFEST 虚假数据 × bindings 真实性验证（v5P）。
///
/// 目的：用一套**字段名完全自定义、与 zdbk 真实键（kcmc/cj/jd...）毫不相同**的虚假
/// 数据源（plugins/artifest-data），配合 artifest-zdbk-* 模块 manifest 中显式声明的
/// bindings，证明 zdbk-modle 渲染层的字段提取**确实走 bindings**，而非写死数据源键名。
///
/// 验证链路：scraper（自定义键 JSON） → manifest.bindings（自定义键 → 语义键）
///          → [ZdbkData]（按 bindings 提取） → 正确模型。
///
/// 若本机有 Python 解释器，测试会真实运行 scraper.py 取数；否则回退到与 scraper.py
/// 完全一致的嵌入镜像（见 [_mirror]），两者必须保持同步。
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/zdbk_modle/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// ── 工作区定位：向上找到 plugins/artifest-data ──
String _workspaceRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final probe = p.join(dir.path, 'plugins', 'artifest-data', 'data', 'scraper.py');
    if (File(probe).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('找不到 plugins/artifest-data（当前: ${Directory.current.path}）');
}

ModuleDescriptor _loadModule(String ws, String id) {
  final f = File(p.join(ws, 'plugins', id, 'module', 'manifest.json'));
  final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return ModuleDescriptor.fromJson(json);
}

/// 尝试用本机 Python 运行真实 scraper.py（最强验证）；不可用则返回 null。
Future<Map<String, dynamic>?> _tryRunScraper(String ws, String typeArg) async {
  final script = p.join(ws, 'plugins', 'artifest-data', 'data', 'scraper.py');
  const candidates = ['py', 'python', 'python3', r'.greenix\python\python.exe'];
  for (final c in candidates) {
    try {
      final r = await Process.run(
        c,
        [script, '--type', typeArg],
        workingDirectory: p.dirname(script),
      );
      if (r.exitCode == 0) {
        return jsonDecode(r.stdout as String) as Map<String, dynamic>;
      }
    } on ProcessException {
      // 该候选不存在，尝试下一个
    }
  }
  return null;
}

/// 与 scraper.py 的 FAKE 完全一致的嵌入镜像（无 Python 时回退用）。
Map<String, dynamic> _mirror(String typeArg) => _fake[typeArg]!;

final Map<String, Map<String, dynamic>> _fake = {
  'art_zdbk_timetable': {
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
  'art_zdbk_transcript': {
    'rows': [
      {'lesson': '高等数学(虚构)', 'mark': '92', 'gp': '3.8', 'hours': '4.0', 'code': 'MATH1001'},
      {'lesson': '大学英语(虚构)', 'mark': '88', 'gp': '3.6', 'hours': '3.0', 'code': 'ENG1002'},
      {'lesson': '数据结构(虚构)', 'mark': '95', 'gp': '4.0', 'hours': '4.0', 'code': 'CS1003'},
    ],
  },
  'art_zdbk_major_grade': {
    'rows': [
      {'lesson': '主修-数学分析(虚构)', 'mark': '90', 'gp': '3.7', 'hours': '5.0', 'code': 'MAJOR01'},
      {'lesson': '主修-离散数学(虚构)', 'mark': '93', 'gp': '3.9', 'hours': '4.0', 'code': 'MAJOR02'},
    ],
  },
  'art_zdbk_exams': {
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
  'art_zdbk_course_offerings': {
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
  'art_zdbk_training_plans': {
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
  'art_zdbk_practice_scores': {
    'second': '12分',
    'third': '8分',
    'fourth': '5分',
  },
  'art_zdbk_notifications': {
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
  final ws = _workspaceRoot();

  group('ARTIFEST × bindings 真实性', () {
    test('scraper 真实运行输出 与 嵌入镜像一致（Python 可用时）', () async {
      final live = await _tryRunScraper(ws, 'art_zdbk_transcript');
      if (live != null) {
        expect(live, _mirror('art_zdbk_transcript'));
      }
    });

    test('scores/transcript：自定义字段经 bindings 解析', () async {
      final m = _loadModule(ws, 'artifest-zdbk-scores');
      final b = m.dataSources!['transcript']!.bindings!;
      final raw = await _tryRunScraper(ws, 'art_zdbk_transcript') ?? _mirror('art_zdbk_transcript');
      final list = ZdbkData.grades(raw, b);
      expect(list.length, 3);
      expect(list[0].courseName, '高等数学(虚构)'); // lesson → courseName
      expect(list[0].score, '92'); // mark → score
      expect(list[0].gpa, '3.8'); // gp → gpa
      expect(list[0].credit, '4.0'); // hours → credit
      expect(list[0].courseNo, 'MATH1001'); // code → courseNo
    });

    test('scores/major_grade：自定义字段经 bindings 解析', () async {
      final m = _loadModule(ws, 'artifest-zdbk-scores');
      final b = m.dataSources!['major_grade']!.bindings!;
      final raw = await _tryRunScraper(ws, 'art_zdbk_major_grade') ?? _mirror('art_zdbk_major_grade');
      final list = ZdbkData.grades(raw, b);
      expect(list.length, 2);
      expect(list[1].courseName, '主修-离散数学(虚构)');
      expect(list[1].score, '93');
      expect(list[1].courseNo, 'MAJOR02');
    });

    test('scores/practice_scores：二三课堂 自定义键 + 去「分」', () async {
      final m = _loadModule(ws, 'artifest-zdbk-scores');
      final b = m.dataSources!['practice_scores']!.bindings!;
      final raw = await _tryRunScraper(ws, 'art_zdbk_practice_scores') ?? _mirror('art_zdbk_practice_scores');
      final p = ZdbkData.practice(raw, b);
      expect(p.pt2, 12.0); // second → pt2，去「分」
      expect(p.pt3, 8.0); // third → pt3
      expect(p.pt4, 5.0); // fourth → pt4
    });

    test('exams：自定义字段经 bindings 解析', () async {
      final m = _loadModule(ws, 'artifest-zdbk-exams');
      final b = m.dataSources!['exams']!.bindings!;
      final raw = await _tryRunScraper(ws, 'art_zdbk_exams') ?? _mirror('art_zdbk_exams');
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

    test('timetable：grid 列表根 + cell blob + 字段 全部经 bindings', () async {
      final m = _loadModule(ws, 'artifest-zdbk-timetable');
      final b = m.dataSources!['timetable']!.bindings!;
      final raw = await _tryRunScraper(ws, 'art_zdbk_timetable') ?? _mirror('art_zdbk_timetable');
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

    test('courses/course_offerings：全字段自定义键经 bindings', () async {
      final m = _loadModule(ws, 'artifest-zdbk-courses');
      final b = m.dataSources!['course_offerings']!.bindings!;
      final raw = await _tryRunScraper(ws, 'art_zdbk_course_offerings') ?? _mirror('art_zdbk_course_offerings');
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

    test('courses/training_plans：全字段自定义键经 bindings', () async {
      final m = _loadModule(ws, 'artifest-zdbk-courses');
      final b = m.dataSources!['training_plans']!.bindings!;
      final raw = await _tryRunScraper(ws, 'art_zdbk_training_plans') ?? _mirror('art_zdbk_training_plans');
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

    test('notifications：自定义键经 bindings 解析', () async {
      final m = _loadModule(ws, 'artifest-zdbk-notifications');
      final b = m.dataSources!['notifications']!.bindings!;
      final raw = await _tryRunScraper(ws, 'art_zdbk_notifications') ?? _mirror('art_zdbk_notifications');
      final list = ZdbkData.notifications(raw, b);
      expect(list.length, 2);
      expect(list[0].id, 'n001'); // uid → id
      expect(list[0].title, '关于期末考试安排的通知(虚构)'); // headline → title
      expect(list[0].publisher, '教务处'); // author → publisher
      expect(list[0].publishDate, '2026-01-10'); // issued → publishDate
      expect(list[0].viewCount, 120); // views → viewCount
      expect(list[0].content, '请同学们及时查看个人考试安排。'); // body → content
    });

    test('控制：无 bindings 时自定义字段提取不到（证明 bindings 不可或缺）', () async {
      final raw = _mirror('art_zdbk_transcript');
      // 不传 bindings → 模型回退到默认键（items/kcmc/cj...），而数据根是 rows、字段是
      // lesson/mark... → 列表根找不到 → 空列表；字段也找不到。
      final list = ZdbkData.grades(raw, null);
      expect(list, isEmpty);
    });
  });
}
