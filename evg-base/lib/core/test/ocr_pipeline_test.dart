/// OcrPipeline 测试——覆盖两级降级、文件不存在、parsePageOutput。
library;

import 'package:test/test.dart';

import 'package:dio/dio.dart';

import '../services/ocr_pipeline.dart';

void main() {
  group('OcrPipeline', () {
    late OcrPipeline pipeline;

    setUp(() {
      pipeline = OcrPipeline(Dio());
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
    test('解析有效的 JSON 输出（单页）', () {
      const stdout = '{"pages": [{"page": 1, "text": "高等数学 期末成绩 95分"}]}';
      final result = OcrPipeline.parsePageOutput(stdout);
      expect(result, contains('高等数学'));
    });

    test('解析有效的 JSON 输出（多页）', () {
      const stdout = '{"pages": ['
          '{"page": 1, "text": "高等数学 期末成绩 95分"},'
          '{"page": 2, "text": "大学英语 期末成绩 88分"}'
          ']}';
      final result = OcrPipeline.parsePageOutput(stdout);
      expect(result, contains('高等数学'));
      expect(result, contains('大学英语'));
      expect(result, contains('--- 第 1 页 ---'));
      expect(result, contains('--- 第 2 页 ---'));
    });

    test('无效 JSON 返回 null', () {
      final result = OcrPipeline.parsePageOutput('this is not json');
      expect(result, isNull);
    });

    test('缺少 pages 字段返回 null', () {
      const stdout = '{"status": "ok"}';
      final result = OcrPipeline.parsePageOutput(stdout);
      expect(result, isNull);
    });

    test('空 pages 数组返回 null', () {
      const stdout = '{"pages": []}';
      final result = OcrPipeline.parsePageOutput(stdout);
      expect(result, isNull);
    });

    test('pages 中空 text 被跳过', () {
      const stdout = '{"pages": [{"page": 1, "text": ""}]}';
      final result = OcrPipeline.parsePageOutput(stdout);
      expect(result, isNull);
    });

    test('空字符串返回 null', () {
      final result = OcrPipeline.parsePageOutput('');
      expect(result, isNull);
    });
  });
}
