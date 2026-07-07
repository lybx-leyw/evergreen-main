/// Agent 工具：获取当前学年学期信息。
/// 让 AI 知道现在是哪个学年、哪个学期。
library;

import '../../../core/agent/tool.dart';

/// 获取当前学年学期的工具。
class GetCurrentSemesterTool extends Tool {
  @override
  String get name => 'get_current_semester';

  @override
  String get description =>
      '获取当前的学年和学期信息。当用户没有明确指定学年学期时，先调用此工具确定当前时间。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final now = DateTime.now();
    final month = now.month;
    final year = now.year;

    // ZJU 学期划分：
    // 秋冬学期（9月-2月）→ xqm=3, 学年为当前年
    // 春夏学期（3月-8月）→ xqm=12, 学年为前一年
    final isAutumnWinter = month >= 9 || month <= 2;
    final academicYearStart = isAutumnWinter ? year : year - 1;
    final semester = isAutumnWinter ? 3 : 12;
    final semesterName = isAutumnWinter ? '秋冬学期' : '春夏学期';
    final semesterCode = isAutumnWinter ? '1' : '2';

    // 下一学期
    final nextIsAutumnWinter = !isAutumnWinter;
    final nextYear = nextIsAutumnWinter ? academicYearStart : academicYearStart + 1;
    final nextSemester = nextIsAutumnWinter ? 3 : 12;
    final nextSemesterName = nextIsAutumnWinter ? '秋冬学期' : '春夏学期';

    return '''
当前时间: ${now.year}年${now.month}月${now.day}日

当前学期:
  学年: $academicYearStart-${academicYearStart + 1}
  学期: $semesterName (代码: $semester, ZJU码: $semesterCode)
  说明: 用于开课情况查询的 tjksxq 值为 ${academicYearStart}-${academicYearStart + 1}$semesterCode

下一学期:
  学年: $nextYear-${nextYear + 1}
  学期: $nextSemesterName (代码: $nextSemester)

注意：查询开课情况时，请用当前学期的学年和学期参数。
''';
  }

  @override
  bool get readOnly => true;
}
