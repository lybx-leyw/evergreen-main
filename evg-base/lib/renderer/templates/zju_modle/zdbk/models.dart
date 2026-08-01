/// ZDBK 数据模型——解析数据中心（orch://zdbk_*）返回的教务 JSON。
///
/// 与 v5P 架构（§3）及 classroom-modle 一致：**字段提取走 bindings**。
/// 每个模型 `fromJson(item, bindings)` 经 [extractPath] 按「语义键 → 数据 JSON 键路径」
/// 提取字段；manifest 的 `dataSources.<name>.bindings` 可覆盖任意键，未声明的键
/// 回退到本文件的 `_default*Bindings`（与 scraper 直出中文键对齐）。
///
/// 因此渲染层**不再写死**数据源字段名：数据源换了键名，只需改 manifest 的 bindings，
/// 无需动模板代码。以下三类结构性变换仍留在模板内（bindings 只覆盖标量字段提取）：
///  1. 课表 `kcb` 是 `<br>` 拼接的 blob 字符串，需 [_Kcb.parse] 启发式拆分；
///  2. 列表根信封（`items` / `kbList`）由 [ZdbkData] 按 `bindings['items']` 解析；
///  3. `pt2/pt3/pt4` 带「分」后缀的数值清洗、按学期/周几的分组展示。
library;

import 'package:evergreen_base/renderer/atomic/json_path.dart';

/// 安全转字符串（trim + 空串归 null）。
String? _asString(dynamic v) {
  if (v == null) return null;
  final t = v.toString().trim();
  return t.isEmpty ? null : t;
}

/// 按 binding 取某语义字段：manifest 声明优先，否则默认键路径。
String? _field(Map m, Map<String, String>? b, String field, String defKey) =>
    _asString(extractPath(m, (b != null && b[field] != null) ? b[field]! : defKey));

/// 列表根提取：manifest 可用 `bindings['items']` 覆盖根键（默认 [defaultKey]），
/// 非 Map 视为裸 List（兼容历史缓存形态）。
dynamic _itemsRaw(dynamic raw, Map<String, String>? b, String defaultKey) {
  if (raw is! Map) return raw;
  final key = (b != null && b['items'] != null) ? b['items']! : defaultKey;
  return raw[key];
}

/// 解析列表为强类型模型（每项套用 [ctor]，ctor 接收 item 与 bindings）。
List<T> _parseList<T>(
  dynamic raw,
  T Function(Map, Map<String, String>?) ctor,
  Map<String, String>? b,
) {
  if (raw is! List) return [];
  return raw.whereType<Map>().map((m) => ctor(m, b)).toList();
}

/// 解析教务课表单元格 blob（`kcb` 字段）：形如
/// `课程名<br>学期{周次}<br>教师A/教师B<br>地点zwf考试时间zwf`
/// 拆出 课程名 / 教师 / 地点 / 考试时间。
class _Kcb {
  static Map<String, String> parse(String? kcb) {
    final out = {'name': '', 'teacher': '', 'location': '', 'exam': ''};
    if (kcb == null || kcb.isEmpty) return out;
    final parts = kcb.split(RegExp(r'<br\s*/?>'));
    if (parts.isNotEmpty) out['name'] = parts[0].trim();
    for (final raw in parts.skip(1)) {
      final p = raw.replaceAll('zwf', ' ').trim();
      if (p.isEmpty) continue;
      if (p.contains('/') && (out['teacher'] ?? '').isEmpty) {
        out['teacher'] = p;
      } else if ((p.contains('校区') ||
              p.contains('楼') ||
              p.contains('室') ||
              p.contains('东') ||
              p.contains('西') ||
              p.contains('紫金港')) &&
          (out['location'] ?? '').isEmpty) {
        out['location'] = p;
      } else if (p.contains('年') && p.contains('日') && (out['exam'] ?? '').isEmpty) {
        out['exam'] = p;
      }
    }
    return out;
  }
}

/// ── 课表 ──
class ZdbkTimetableEntry {
  final String courseName;
  final String teacher;
  final String location;
  final String examTime;
  final String weekday; // xqj: 1..7
  final String term; // xxq: 秋冬/春夏...
  final String courseNo;

  const ZdbkTimetableEntry({
    required this.courseName,
    this.teacher = '',
    this.location = '',
    this.examTime = '',
    this.weekday = '',
    this.term = '',
    this.courseNo = '',
  });

  static const _def = {
    'kcb': 'kcb',
    'courseName': 'kcmc',
    'weekday': 'xqj',
    'term': 'xxq',
    'courseNo': 'xkkh',
  };

  static ZdbkTimetableEntry fromJson(Map m, Map<String, String>? b) {
    final bd = b ?? _def;
    final k = _Kcb.parse(_field(m, bd, 'kcb', 'kcb'));
    final nameKey = bd['courseName'] ?? 'kcmc';
    final courseName = k['name']!.isNotEmpty
        ? k['name']!
        : (_asString(extractPath(m, nameKey)) ?? '未命名课程');
    return ZdbkTimetableEntry(
      courseName: courseName,
      teacher: k['teacher']!,
      location: k['location']!,
      examTime: k['exam']!,
      weekday: _field(m, bd, 'weekday', 'xqj') ?? '',
      term: _field(m, bd, 'term', 'xxq') ?? '',
      courseNo: _field(m, bd, 'courseNo', 'xkkh') ?? '',
    );
  }

  /// 星期中文（xqj: 1=周一 ... 7=周日）。
  String get weekdayLabel {
    final n = int.tryParse(weekday) ?? 0;
    const names = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return n >= 1 && n <= 7 ? names[n] : '未知';
  }
}

/// ── 成绩单 / 主修成绩 ──
class ZdbkGradeItem {
  final String courseName;
  final String score; // cj
  final String gpa; // jd
  final String credit; // xf
  final String courseNo;

  const ZdbkGradeItem({
    required this.courseName,
    this.score = '',
    this.gpa = '',
    this.credit = '',
    this.courseNo = '',
  });

  static const _def = {
    'courseName': 'kcmc',
    'score': 'cj',
    'gpa': 'jd',
    'credit': 'xf',
    'courseNo': 'xkkh',
  };

  static ZdbkGradeItem fromJson(Map m, Map<String, String>? b) {
    final bd = b ?? _def;
    return ZdbkGradeItem(
      courseName: _field(m, bd, 'courseName', 'kcmc') ?? '未命名课程',
      score: _field(m, bd, 'score', 'cj') ?? '',
      gpa: _field(m, bd, 'gpa', 'jd') ?? '',
      credit: _field(m, bd, 'credit', 'xf') ?? '',
      courseNo: _field(m, bd, 'courseNo', 'xkkh') ?? '',
    );
  }
}

/// ── 考试安排 ──
class ZdbkExamItem {
  final String courseName;
  final String location; // jsmc
  final String time; // kssj
  final String teacher; // xm
  final String term; // xxq
  final String seatNo; // zwxh
  final String credit;

  const ZdbkExamItem({
    required this.courseName,
    this.location = '',
    this.time = '',
    this.teacher = '',
    this.term = '',
    this.seatNo = '',
    this.credit = '',
  });

  static const _def = {
    'courseName': 'kcmc',
    'location': 'jsmc',
    'time': 'kssj',
    'teacher': 'xm',
    'term': 'xxq',
    'seatNo': 'zwxh',
    'credit': 'xf',
  };

  static ZdbkExamItem fromJson(Map m, Map<String, String>? b) {
    final bd = b ?? _def;
    return ZdbkExamItem(
      courseName: _field(m, bd, 'courseName', 'kcmc') ?? '未命名考试',
      location: _field(m, bd, 'location', 'jsmc') ?? '',
      time: _field(m, bd, 'time', 'kssj') ?? '',
      teacher: _field(m, bd, 'teacher', 'xm') ?? '',
      term: _field(m, bd, 'term', 'xxq') ?? '',
      seatNo: _field(m, bd, 'seatNo', 'zwxh') ?? '',
      credit: _field(m, bd, 'credit', 'xf') ?? '',
    );
  }
}

/// ── 二三课堂成绩 ──
class ZdbkPracticeScore {
  final double pt2;
  final double pt3;
  final double pt4;

  const ZdbkPracticeScore({
    this.pt2 = 0.0,
    this.pt3 = 0.0,
    this.pt4 = 0.0,
  });

  static const _def = {
    'pt2': 'pt2',
    'pt3': 'pt3',
    'pt4': 'pt4',
  };

  static ZdbkPracticeScore fromJson(Map m, Map<String, String>? b) {
    final bd = b ?? _def;
    double v(String field) => double.tryParse(
            _field(m, bd, field, field)?.replaceAll('分', '') ?? '') ??
        0.0;
    return ZdbkPracticeScore(pt2: v('pt2'), pt3: v('pt3'), pt4: v('pt4'));
  }
}

/// ── 开课情况 ──
class ZdbkCourseOffering {
  final String courseName;
  final String teacher; // jsxm
  final String location; // skdd
  final String schedule; // sksj
  final String credit; // xf
  final String type; // kclb
  final String property; // kcxz
  final String college; // kkxy
  final String major; // zymc
  final String year; // xn
  final String term; // xxq

  const ZdbkCourseOffering({
    required this.courseName,
    this.teacher = '',
    this.location = '',
    this.schedule = '',
    this.credit = '',
    this.type = '',
    this.property = '',
    this.college = '',
    this.major = '',
    this.year = '',
    this.term = '',
  });

  static const _def = {
    'courseName': 'kcmc',
    'teacher': 'jsxm',
    'location': 'skdd',
    'schedule': 'sksj',
    'credit': 'xf',
    'type': 'kclb',
    'property': 'kcxz',
    'college': 'kkxy',
    'major': 'zymc',
    'year': 'xn',
    'term': 'xxq',
  };

  static ZdbkCourseOffering fromJson(Map m, Map<String, String>? b) {
    final bd = b ?? _def;
    return ZdbkCourseOffering(
      courseName: _field(m, bd, 'courseName', 'kcmc') ?? '未命名课程',
      teacher: _field(m, bd, 'teacher', 'jsxm') ?? '',
      location: _field(m, bd, 'location', 'skdd') ?? '',
      schedule: _field(m, bd, 'schedule', 'sksj') ?? '',
      credit: _field(m, bd, 'credit', 'xf') ?? '',
      type: _field(m, bd, 'type', 'kclb') ?? '其他',
      property: _field(m, bd, 'property', 'kcxz') ?? '',
      college: _field(m, bd, 'college', 'kkxy') ?? '',
      major: _field(m, bd, 'major', 'zymc') ?? '',
      year: _field(m, bd, 'year', 'xn') ?? '',
      term: _field(m, bd, 'term', 'xxq') ?? '',
    );
  }
}

/// ── 培养方案 ──
class ZdbkTrainingPlan {
  final String planName; // zymc
  final String major; // zymc
  final String college; // xymc
  final String grade; // synj（入学年）
  final String lengthYears; // xz
  final String minCredits; // zdbyxf
  final String totalCredits; // kcdlxfyq
  final String category; // zydlmc
  final String campus; // xqmc
  final String remarks; // pymb

  const ZdbkTrainingPlan({
    required this.planName,
    this.major = '',
    this.college = '',
    this.grade = '',
    this.lengthYears = '',
    this.minCredits = '',
    this.totalCredits = '',
    this.category = '',
    this.campus = '',
    this.remarks = '',
  });

  static const _def = {
    'planName': 'zymc',
    'major': 'zymc',
    'college': 'xymc',
    'grade': 'synj',
    'lengthYears': 'xz',
    'minCredits': 'zdbyxf',
    'totalCredits': 'kcdlxfyq',
    'category': 'zydlmc',
    'campus': 'xqmc',
    'remarks': 'pymb',
  };

  static ZdbkTrainingPlan fromJson(Map m, Map<String, String>? b) {
    final bd = b ?? _def;
    return ZdbkTrainingPlan(
      planName: _field(m, bd, 'planName', 'zymc') ?? '未命名方案',
      major: _field(m, bd, 'major', 'zymc') ?? '',
      college: _field(m, bd, 'college', 'xymc') ?? '',
      grade: _field(m, bd, 'grade', 'synj') ?? '',
      lengthYears: _field(m, bd, 'lengthYears', 'xz') ?? '',
      minCredits: _field(m, bd, 'minCredits', 'zdbyxf') ?? '',
      totalCredits: _field(m, bd, 'totalCredits', 'kcdlxfyq') ?? '',
      category: _field(m, bd, 'category', 'zydlmc') ?? '',
      campus: _field(m, bd, 'campus', 'xqmc') ?? '',
      remarks: _field(m, bd, 'remarks', 'pymb') ?? '',
    );
  }
}

/// ── 通知公告 ──
class ZdbkNotification {
  final String id;
  final String title;
  final String? publisher;
  final String? publishDate;
  final int? viewCount;
  final String? content;

  const ZdbkNotification({
    required this.id,
    required this.title,
    this.publisher,
    this.publishDate,
    this.viewCount,
    this.content,
  });

  static const _def = {
    'id': 'id',
    'title': 'title',
    'publisher': 'publisher',
    'publishDate': 'publishDate',
    'viewCount': 'viewCount',
    'content': 'content',
  };

  static ZdbkNotification fromJson(Map m, Map<String, String>? b) {
    final bd = b ?? _def;
    return ZdbkNotification(
      id: _field(m, bd, 'id', 'id') ?? '',
      title: _field(m, bd, 'title', 'title') ?? '无标题',
      publisher: _field(m, bd, 'publisher', 'publisher'),
      publishDate: _field(m, bd, 'publishDate', 'publishDate'),
      viewCount: int.tryParse(_field(m, bd, 'viewCount', 'viewCount') ?? ''),
      content: _field(m, bd, 'content', 'content'),
    );
  }
}

/// 把[orch]返回的任意原始数据解析为模型列表的通用入口。
///
/// [b] 为对应数据源的 manifest `bindings`：传入后字段提取与列表根键均按声明路径，
/// 未传/null 则回退各模型的默认键（与 scraper 输出对齐）。
class ZdbkData {
  static List<ZdbkTimetableEntry> timetable(dynamic raw, Map<String, String>? b) =>
      _parseList(_itemsRaw(raw, b, 'kbList'), ZdbkTimetableEntry.fromJson, b);

  static List<ZdbkGradeItem> grades(dynamic raw, Map<String, String>? b) =>
      _parseList(_itemsRaw(raw, b, 'items'), ZdbkGradeItem.fromJson, b);

  static List<ZdbkExamItem> exams(dynamic raw, Map<String, String>? b) =>
      _parseList(_itemsRaw(raw, b, 'items'), ZdbkExamItem.fromJson, b);

  static ZdbkPracticeScore practice(dynamic raw, Map<String, String>? b) {
    if (raw is! Map) return const ZdbkPracticeScore();
    return ZdbkPracticeScore.fromJson(raw, b);
  }

  static List<ZdbkCourseOffering> offerings(dynamic raw, Map<String, String>? b) =>
      _parseList(_itemsRaw(raw, b, 'items'), ZdbkCourseOffering.fromJson, b);

  static List<ZdbkTrainingPlan> plans(dynamic raw, Map<String, String>? b) =>
      _parseList(_itemsRaw(raw, b, 'items'), ZdbkTrainingPlan.fromJson, b);

  static List<ZdbkNotification> notifications(dynamic raw, Map<String, String>? b) =>
      _parseList(_itemsRaw(raw, b, 'items'), ZdbkNotification.fromJson, b);
}
