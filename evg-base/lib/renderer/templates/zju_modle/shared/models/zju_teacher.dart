/// 查老师（teachers）模型——chalaoshi.top 教师评分数据集。
///
/// B3-teachers（2026-08-13）自参考工程
/// `cp_evergreen_push/lib/features/teachers/services/chalaoshi_service.dart`
/// 内部模型提取，前缀 `Zju` 防冲突（规划 §5.6），并补齐 JSON 桥接：
/// 数据集走数据中枢 `zju_teachers` 缓存统计，模型 toJson/fromJson 对齐。
library;

/// 数据集内一条教师记录（本地完整数据集，来自 chalaoshi.top 抓取）。
class ZjuTeacherRecord {
  final int id;
  final String name;

  /// 拼音全拼（搜索匹配用）。
  final String py;

  /// 拼音首字母缩写（搜索匹配用）。
  final String sx;
  final int collegeId;
  final int hot;

  /// 本地缓存的评分字符串（可为空 = 暂无评分）。
  final String rate;

  const ZjuTeacherRecord({
    required this.id,
    required this.name,
    this.py = '',
    this.sx = '',
    this.collegeId = 0,
    this.hot = 0,
    this.rate = '',
  });

  factory ZjuTeacherRecord.fromJson(Map<String, dynamic> json) {
    return ZjuTeacherRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      py: json['py'] as String? ?? '',
      sx: json['sx'] as String? ?? '',
      collegeId: (json['xy'] as num?)?.toInt() ?? 0,
      hot: (json['hot'] as num?)?.toInt() ?? 0,
      rate: json['rate']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'py': py,
        'sx': sx,
        'xy': collegeId,
        'hot': hot,
        'rate': rate,
      };
}

/// 搜索结果条目（含来源标识：online = 实时抓取 / local = 本地缓存）。
class ZjuTeacherResult {
  final int id;
  final String name;
  final double? score;
  final String? college;
  final String url;

  /// "online" = 从 chalaoshi.top 实时抓取；"local" = 本地缓存数据。
  final String dataSource;

  const ZjuTeacherResult({
    required this.id,
    required this.name,
    this.score,
    this.college,
    required this.url,
    this.dataSource = 'local',
  });

  factory ZjuTeacherResult.fromJson(Map<String, dynamic> json) {
    return ZjuTeacherResult(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble(),
      college: json['college'] as String?,
      url: json['url'] as String? ?? '',
      dataSource: json['dataSource'] as String? ?? 'local',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (score != null) 'score': score,
        if (college != null) 'college': college,
        'url': url,
        'dataSource': dataSource,
      };
}

/// 教师详情（详情对话框用）。
class ZjuTeacherDetail {
  final int id;
  final String name;
  final double? score;
  final int raters;
  final String? college;

  const ZjuTeacherDetail({
    required this.id,
    required this.name,
    this.score,
    this.raters = 0,
    this.college,
  });

  factory ZjuTeacherDetail.fromJson(Map<String, dynamic> json) {
    return ZjuTeacherDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble(),
      raters: (json['raters'] as num?)?.toInt() ?? 0,
      college: json['college'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (score != null) 'score': score,
        'raters': raters,
        if (college != null) 'college': college,
      };
}

/// 完整数据集（colleges 索引 + teachers 列表）。
///
/// 数据中枢 `zju_teachers` fetcher 只缓存统计（完整 1.5MB 数据集作为
/// asset 内置 + 文档目录增量缓存，不进 JSON 缓存），故本类保留
/// fromJson/toJson 供测试与可能的完整缓存复用。
class ZjuTeacherDataset {
  final Map<int, String> colleges;
  final List<ZjuTeacherRecord> teachers;

  const ZjuTeacherDataset({required this.colleges, required this.teachers});

  factory ZjuTeacherDataset.fromJson(Map<String, dynamic> json) {
    final colleges = <int, String>{};
    for (final c in (json['colleges'] as List<dynamic>?) ?? []) {
      final m = c as Map<String, dynamic>;
      colleges[(m['id'] as num).toInt()] = m['name'] as String;
    }
    final teachers = ((json['teachers'] as List<dynamic>?) ?? [])
        .map((t) => ZjuTeacherRecord.fromJson(t as Map<String, dynamic>))
        .toList();
    return ZjuTeacherDataset(colleges: colleges, teachers: teachers);
  }

  Map<String, dynamic> toJson() => {
        'colleges': colleges.entries
            .map((e) => {'id': e.key, 'name': e.value})
            .toList(),
        'teachers': teachers.map((t) => t.toJson()).toList(),
      };

  /// 数据集规模统计（数据中枢缓存/状态面板展示）。
  Map<String, dynamic> toStatsJson() => {
        'loaded': true,
        'teachers': teachers.length,
        'colleges': colleges.length,
      };

  String? collegeName(int collegeId) => colleges[collegeId];
}
