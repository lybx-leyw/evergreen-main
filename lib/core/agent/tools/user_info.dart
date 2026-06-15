/// Agent 工具：获取用户个人信息（年级、主修、培养方案 OCR）。
///
/// 数据来自设置页填入的个人信息，存储于 SharedPreferences。
library;

import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/agent/tool.dart';

/// 获取用户个人信息的工具。
class GetUserInfoTool extends Tool {
  @override
  String get name => 'get_user_info';

  @override
  String get description =>
      '获取用户的个人信息，包括年级、主修专业、辅修信息。'
      '以及用户通过设置页导入的「个人主修培养方案」和「其他培养方案」OCR 文本。'
      '若用户填写，可用于回答培养方案相关问题，无需额外请求教务系统。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final prefs = await SharedPreferences.getInstance();
    final grade = prefs.getString('STUDENT_GRADE') ?? '';
    final major = prefs.getString('STUDENT_MAJOR') ?? '';
    final minor = prefs.getString('STUDENT_MINOR') ?? '';
    final personalPlan = prefs.getString('PERSONAL_TRAINING_PLAN_OCR') ?? '';
    final otherPlan = prefs.getString('OTHER_TRAINING_PLAN_OCR') ?? '';

    final buf = StringBuffer();
    buf.writeln('## 用户个人信息\n');

    if (grade.isNotEmpty) {
      buf.writeln('- **年级**: ${grade}级');
    }
    if (major.isNotEmpty) {
      buf.writeln('- **主修**: $major');
    }
    if (minor.isNotEmpty) {
      buf.writeln('- **其他**: $minor');
    }

    if (grade.isEmpty && major.isEmpty && minor.isEmpty) {
      buf.writeln('用户暂未填写基本个人信息。');
    }

    if (personalPlan.isNotEmpty) {
      buf.writeln('\n### 个人主修培养方案\n');
      buf.writeln(personalPlan);
    }
    if (otherPlan.isNotEmpty) {
      buf.writeln('\n### 其他培养方案\n');
      buf.writeln(otherPlan);
    }

    buf.writeln('\n---\n_数据来源：设置页个人信息_');
    return buf.toString();
  }

  @override
  bool get readOnly => true;
}
