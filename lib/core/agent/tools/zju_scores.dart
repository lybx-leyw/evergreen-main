/// ZJU 成绩工具——获取 GPA / 成绩单。
library;

import '../tool.dart';
import 'zju_data_source.dart';

class ZjuScoresTool extends Tool {
  final ZjuDataSource _dataSource;

  ZjuScoresTool(this._dataSource);

  @override
  String get name => 'get_scores';

  @override
  String get description => '获取当前用户的 GPA 和成绩概览，包括五分制、四分制 GPA、总学分、课程门数。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    try {
      final result = await _dataSource.getScores();
      if (result == null) return '暂未获取到成绩数据，请确认是否已登录教务网。';

      return '📊 成绩概览\n'
          '- 五分制: ${result.fivePointGpa.toStringAsFixed(2)}  / 5.0\n'
          '- 四分制(4.3): ${result.fourPointThreeGpa.toStringAsFixed(2)}  / 4.3\n'
          '- 四分制(4.0): ${result.fourPointGpa.toStringAsFixed(2)}  / 4.0\n'
          '- 百分制: ${result.hundredPointGpa.toStringAsFixed(1)}  / 100\n'
          '- 总学分: ${result.totalCredits.toStringAsFixed(1)}\n'
          '- 课程门数: ${result.courseCount}';
    } catch (e) {
      return '[查询失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}
