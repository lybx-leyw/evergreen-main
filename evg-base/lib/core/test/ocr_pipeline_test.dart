/// OcrPipeline 测试——覆盖两级降级、文件不存在、parsePageOutput。
library;

import 'dart:io';

import 'package:test/test.dart';

import '../services/ocr_pipeline.dart';

void main() {
  group('OcrPipeline', () {
    late OcrPipeline pipeline;

    setUp(() {
      pipeline = OcrPipeline();
    });

    test('recognizeFile 文件不存在返回 null', () async {
      final result = await pipeline.recognizeFile('/nonexistent/image_12345.png');
      expect(result, isNull);
    });

    test('recognizeFile 空字符串路径返回 null', () async {
      final result = await pipeline.recognizeFile('');
      expect(result, isNull);
    });

    test('recognizeUrl 无效 URL 返回空字符串', () async {
      final result = await pipeline.recognizeUrl('not_a_valid_url');
      expect(result, '');
    });
  });

  group('parsePageOutput', () {
    test('解析有效的 JSON 输出', () {
      const stdout = '''
{"page": 1, "text": "高等数学 期末成绩 95分"}
{"page": 2, "text": "大学英语 期末成绩 88分"}
''';
      final result = OcrPipeline.parsePageOutput(stdout);
      expect(result, contains('高等数学'));
      expect(result, contains('大学英语'));
    });

    test('无效 JSON 行返回 null', () {
      final result = OcrPipeline.parsePageOutput('this is not json');
      expect(result, isNull);
    });

    test('混合输出跳过无效行', () {
      const stdout = '''
some log output
{"page": 1, "text": "有效内容"}
more noise
''';
      final result = OcrPipeline.parsePageOutput(stdout);
      expect(result, contains('有效内容'));
      expect(result, isNot(contains('noise')));
    });

    test('空字符串返回 null', () {
      final result = OcrPipeline.parsePageOutput('');
      expect(result, isNull);
    });
  });
}
