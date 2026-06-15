/// Agent 工具：查老师——基于 Lazuli 完整数据集的本地搜索。
/// 一次拉取，全本地搜索，无频率限制。
library;

import 'package:dio/dio.dart';

import '../../../core/agent/tool.dart';
import '../../teachers/services/chalaoshi_service.dart';

class SearchTeacherTool extends Tool {
  final Dio _dio;
  late final ChalaoshiService _service;

  SearchTeacherTool(this._dio) {
    _service = ChalaoshiService(_dio);
  }

  @override
  String get name => 'search_teacher';

  @override
  String get description =>
      '搜索浙江大学教师的评分和评价信息。数据来自本地完整数据集，毫秒级返回，'
      '没有频率限制。不要自己访问 chalaoshi.top 或其他查老师网站——用这个工具就行。'
      '支持按姓名、拼音、拼音缩写搜索。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': '教师姓名、拼音或拼音缩写',
          },
        },
        'required': ['name'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final name = args['name']?.toString() ?? '';
    if (name.isEmpty) return '无此老师的评分';

    try {
      final results = await _service.search(name);

      if (results.isEmpty) {
        return '无此老师的评分';
      }

      final buf = StringBuffer();
      buf.writeln('🔍 搜索 "$name" 找到 ${results.length} 位教师：\n');
      for (var i = 0; i < results.length && i < 15; i++) {
        final t = results[i];
        buf.writeln('${i + 1}. **${t.name}**'
            '${t.score != null ? "  ⭐ ${t.score!.toStringAsFixed(1)}分" : " 暂无评分"}');
        if (t.college != null) buf.writeln('   学院: ${t.college}');
        buf.writeln();
      }

      return buf.toString().trim();
    } catch (e) {
      print('[search_teacher] ⚠️ 查询失败: $e');
      return '无此老师的评分';
    }
  }

  @override
  bool get readOnly => true;
}
