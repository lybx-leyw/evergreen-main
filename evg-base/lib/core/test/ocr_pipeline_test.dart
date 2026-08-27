/// OcrPipeline 测试——覆盖两级降级、文件不存在、parsePageOutput。
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

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

  group('安卓降级链（fake pythonRunOnce + forceAndroid: true）', () {
    late Directory tmp;
    late String scriptsDir;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('ocr_pipeline_android_');
      // `greenixScriptsDir` 默认 = cwd/.greenix/scripts（greenix_path 无测试绑定），
      // 在测试 cwd（lib/core）下放置 ocr_file.py 占位，tearDown 清理。
      scriptsDir = p.join(Directory.current.path, '.greenix', 'scripts');
      Directory(scriptsDir).createSync(recursive: true);
      File(p.join(scriptsDir, 'ocr_file.py')).writeAsStringSync('placeholder');
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
      // 仅清理测试写入的 ocr_file.py 与因此创建的空目录（不动其他内容）。
      try {
        File(p.join(scriptsDir, 'ocr_file.py')).deleteSync();
      } catch (_) {}
      try {
        Directory(scriptsDir).deleteSync();
      } catch (_) {}
      try {
        Directory(p.join(Directory.current.path, '.greenix')).deleteSync();
      } catch (_) {}
    });

    OcrPipeline buildPipeline(
      PythonRunOnce runOnce, {
      String? apiKey,
    }) {
      return OcrPipeline(Dio(), null, apiKey, runOnce, true);
    }

    test('Level1 跳过（无 Key）→ Chaquopy ocr_file 被调用，parsePageOutput 复用', () async {
      final calls = <({String entry, List<String> args, Duration? timeout})>[];
      final pipeline = buildPipeline(
        (entry, args, {timeout, workingDirectory}) async {
          calls.add((entry: entry, args: List.of(args), timeout: timeout));
          return (
            stdout: '{"pages": [{"page": 1, "text": "安卓OCR文本"}]}',
            stderr: '',
            exitCode: 0,
          );
        },
      );

      final imgPath = p.join(tmp.path, 'scan.png');
      File(imgPath).writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]); // 占位图片字节
      final result = await pipeline.recognizeFile(imgPath);

      expect(calls, hasLength(1));
      expect(p.basename(calls.single.entry), 'ocr_file.py');
      expect(calls.single.args, ['--path', imgPath]);
      expect(calls.single.timeout, const Duration(seconds: 120));
      // parsePageOutput 复用：JSON pages → 合并文本
      expect(result, contains('安卓OCR文本'));
    });

    test('Level1 失败（有 Key 但扩展名不支持）→ Chaquopy ocr_file 被调用', () async {
      final calls = <String>[];
      final pipeline = buildPipeline(
        (entry, args, {timeout, workingDirectory}) async {
          calls.add(entry);
          return (
            stdout: '{"pages": [{"page": 1, "text": "fallback text"}]}',
            stderr: '',
            exitCode: 0,
          );
        },
        apiKey: 'sk-test',
      );

      // .xyz 非图片/PDF → Level1（DeepSeek）直接返回 null → Level2 Chaquopy。
      final weirdPath = p.join(tmp.path, 'doc.xyz');
      File(weirdPath).writeAsStringSync('x');
      final result = await pipeline.recognizeFile(weirdPath);

      expect(calls, hasLength(1));
      expect(p.basename(calls.single), 'ocr_file.py');
      expect(result, contains('fallback text'));
    });

    test('stderr JSON 错误 → 可读降级文案（Pillow/DEEPSEEK_OCR_API_KEY）', () async {
      final pipeline = buildPipeline(
        (entry, args, {timeout, workingDirectory}) async {
          return (
            stdout: '',
            stderr: '{"error": "请安装 Pillow 与 pytesseract"}',
            exitCode: 1,
          );
        },
      );

      final imgPath = p.join(tmp.path, 'scan.png');
      File(imgPath).writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
      final result = await pipeline.recognizeFile(imgPath);

      expect(result, isNotNull);
      expect(result, contains('安卓本地 OCR 缺依赖'));
      expect(result, contains('Pillow'));
      expect(result, contains('DEEPSEEK_OCR_API_KEY'));
      expect(result, contains('请安装 Pillow 与 pytesseract'));
    });

    test('安卓 PDF：返回明确提示（缺 poppler 渲染），不触 python 执行', () async {
      final calls = <String>[];
      final pipeline = buildPipeline(
        (entry, args, {timeout, workingDirectory}) async {
          calls.add(entry);
          return (stdout: '', stderr: '', exitCode: 1);
        },
        apiKey: 'sk-test',
      );

      final pdfPath = p.join(tmp.path, 'doc.pdf');
      File(pdfPath).writeAsStringSync('%PDF-1.4 fake');
      final result = await pipeline.recognizeFile(pdfPath);

      expect(result, contains('安卓 PDF OCR 暂不支持'));
      expect(result, contains('poppler'));
      expect(calls, isEmpty);
    });

    test('recognizeUrl 安卓：返回空串不抛异常', () async {
      final pipeline = buildPipeline(
        (entry, args, {timeout, workingDirectory}) async =>
            (stdout: '', stderr: '', exitCode: 1),
      );

      final result = await pipeline.recognizeUrl('http://example.com/slide.png');
      expect(result, '');
    });
  });
}
