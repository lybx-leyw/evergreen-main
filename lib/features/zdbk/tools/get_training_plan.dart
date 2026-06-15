/// Agent 工具：获取培养方案信息。
///
/// 根据年级和专业查询培养方案，返回 API 已有的详细文本内容。
library;

import '../../../core/agent/tool.dart';
import '../../../core/result.dart';
import '../../../core/models/training_plan.dart';
import '../../../core/log.dart';

/// 培养方案数据源接口。
abstract class TrainingPlanDataSource {
  /// 按年级查询培养方案列表。
  Future<Result<List<TrainingPlan>>> getTrainingPlans(int grade);

  /// 下载培养方案 PDF → 转图片 → OCR，返回完整文本。
  Future<Result<String>> getPlanOcrText(String planNo);
}

/// 获取培养方案信息的工具。
///
/// 1. 按年级和专业查询培养方案
/// 2. 返回方案的详细文本（bz 字段）+ 基本信息
class GetTrainingPlanTool extends Tool {
  final TrainingPlanDataSource _dataSource;

  GetTrainingPlanTool(this._dataSource);

  @override
  String get name => 'get_training_plan';

  @override
  String get description =>
      '获取指定年级和专业的培养方案详细内容。'
      '当用户询问培养方案、课程计划、毕业要求、学分要求等信息时使用。'
      '需要知道用户的年级和专业（可先调用 get_user_info 获取）。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'grade': {
            'type': 'integer',
            'description': '年级，如 2025。不传则搜索全部',
          },
          'major': {
            'type': 'string',
            'description': '专业名称，如 计算机科学与技术。支持模糊匹配',
          },
        },
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final int grade;
    if (args['grade'] is int) {
      grade = args['grade'] as int;
    } else if (args['grade'] is String) {
      grade = int.tryParse(args['grade'] as String) ?? 0;
    } else {
      grade = 0;
    }
    final major = args['major']?.toString() ?? '';

    if (grade <= 0 && major.isEmpty) {
      return '请指定年级（如 grade=2025）或专业名称（如 major="计算机科学与技术"）。';
    }

    try {
      // 1. 查询培养方案列表
      final listResult = await _dataSource.getTrainingPlans(grade);
      if (listResult.isErr) {
        return '[查询培养方案列表失败: ${(listResult as Err).error.userMessage}]';
      }
      final allPlans = (listResult as Ok<List<TrainingPlan>>).value;

      if (allPlans.isEmpty) {
        return '未找到${grade > 0 ? "$grade级" : ""}的培养方案。';
      }

      // 2. 按专业筛选
      var matched = allPlans;
      if (major.isNotEmpty) {
        final q = major.toLowerCase();
        matched = allPlans.where((p) =>
            p.planName.toLowerCase().contains(q) ||
            (p.major?.toLowerCase().contains(q) ?? false)).toList();
      }

      if (matched.isEmpty) {
        final available = allPlans.map((p) =>
            '  - ${p.planName}${p.major != null ? " (${p.major})" : ""}').join('\n');
        return '未找到匹配 "$major" 的培养方案。当前年级可用的方案：\n$available';
      }

      // 3. 取第一个匹配的方案
      final plan = matched.first;
      final planNo = plan.planNo ?? '';
      if (planNo.isEmpty) {
        return '方案 "${plan.planName}" 缺少方案编号。';
      }

      // 4. OCR 识别 PDF 内容
      final ocrResult = await _dataSource.getPlanOcrText(planNo);
      if (ocrResult.isErr) {
        return '[OCR 失败: ${(ocrResult as Err).error.userMessage}]';
      }
      final ocrText = (ocrResult as Ok<String>).value;

      // 5. 组装结果
      final buf = StringBuffer();
      buf.writeln('## ${plan.planName}\n');
      buf.writeln('### 基本信息');
      if (plan.major != null && plan.major!.isNotEmpty) {
        buf.writeln('- **专业**: ${plan.major}');
      }
      if (plan.grade != null && plan.grade!.isNotEmpty) {
        buf.writeln('- **年级**: ${plan.grade}级');
      }
      if (plan.college != null && plan.college!.isNotEmpty) {
        buf.writeln('- **学院**: ${plan.college}');
      }
      if (plan.level != null && plan.level!.isNotEmpty) {
        buf.writeln('- **培养层次**: ${plan.level}');
      }
      if (plan.duration != null && plan.duration!.isNotEmpty) {
        buf.writeln('- **学制**: ${plan.duration}年');
      }
      if (plan.minCredits > 0) {
        buf.writeln('- **最低毕业学分**: ${plan.minCredits}');
      }
      buf.writeln();

      // OCR 内容
      buf.writeln('### 培养方案原文（OCR 识别）\n');
      buf.writeln(ocrText);
      buf.writeln();

      // OCR 免责提示
      buf.writeln('---');
      buf.writeln('> ⚠️ **OCR 识别提示**：以上内容由光学字符识别自动生成，可能存在：');
      buf.writeln('> - 文字识别错误（特别是数字、英文缩写、标点符号）');
      buf.writeln('> - 表格结构丢失或错位');
      buf.writeln('> - 格式排版与原文不一致');
      buf.writeln('>');
      buf.writeln('> **建议**：对于关键信息（毕业学分要求、必修课程等），请以官方 PDF 为准。');

      return buf.toString().trim();
    } catch (e) {
      Log().error('GetTrainingPlanTool failed', error: e);
      return '[获取培养方案失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}
