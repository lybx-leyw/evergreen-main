/// ocr_file / check_ocr_ready 工具测试（Task 四决策 4.2）。
///
/// 覆盖：
/// - 空参数 / 缺 file_path → `[error: file_path 必填]`
/// - 文本扩展名（txt/md/json/csv/py/dart）→ 引导使用 read_file
/// - 相对路径 → 沙箱解析到工作区绝对路径并传给 recognize
/// - 绝对路径 → 原样传给 recognize
/// - `../` 越界 → 拒绝（不在工作区内）
/// - 文件不存在 → `[error: 文件不存在]`
/// - recognize 返回 null → `[error: OCR 未识别到任何文本]`
/// - recognize 抛异常 → `[error: OCR 失败]`
/// - 长文本截断 6000 字预览
/// - isOcrTargetPath 扩展名判定
/// - CheckOcrReadyTool 返回格式化诊断；readinessMap / formatReadiness 纯函数
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../tools/ocr_file_tool.dart';
import '../tool.dart';
import '../tools/plugin_bridge.dart';

void main() {
  late Directory tmp;
  late String ws;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ocr_file_tool_');
    ws = tmp.path;
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  OcrFileTool tool({Future<String?> Function(String path)? recognize}) =>
      OcrFileTool(
        recognize: recognize ?? (path) async => 'OCR text of $path',
        workspaceDir: ws,
      );

  group('OcrFileTool — 参数', () {
    test('空参数 → [error: file_path 必填]', () async {
      final out = await tool().execute({});
      expect(out, contains('[error:'));
      expect(out, contains('file_path 必填'));
    });

    test('file_path 空白 → 同空参数', () async {
      final out = await tool().execute({'file_path': '   '});
      expect(out, contains('file_path 必填'));
    });
  });

  group('OcrFileTool — 文本文件引导', () {
    test('文本扩展名 → 提示用 read_file（不触发 OCR）', () async {
      var called = false;
      final t = OcrFileTool(
        recognize: (path) async {
          called = true;
          return 'x';
        },
        workspaceDir: ws,
      );
      for (final ext in ['txt', 'md', 'json', 'csv', 'py', 'dart']) {
        called = false;
        final out = await t.execute({'file_path': 'a.$ext'});
        expect(called, isFalse, reason: '$ext 不应触发 recognize');
        expect(out, contains('read_file'), reason: '$ext');
        expect(out, contains('[error:'));
      }
    });
  });

  group('OcrFileTool — 路径解析', () {
    test('相对路径 → 沙箱解析到工作区绝对路径并调用 recognize', () async {
      File(p.join(ws, 'scan.png')).writeAsBytesSync([1, 2, 3]);
      String? received;
      final t = OcrFileTool(
        recognize: (path) async {
          received = path;
          return '识别结果 ABC';
        },
        workspaceDir: ws,
      );
      final out = await t.execute({'file_path': 'scan.png'});
      expect(received, File(p.join(ws, 'scan.png')).absolute.path);
      expect(out, contains('[ok]'));
      expect(out, contains('识别结果 ABC'));
    });

    test('绝对路径 → 原样传给 recognize', () async {
      final abs = p.join(ws, 'doc.pdf');
      File(abs).writeAsBytesSync([1]);
      String? received;
      final t = OcrFileTool(
        recognize: (path) async {
          received = path;
          return 'x';
        },
        workspaceDir: ws,
      );
      final out = await t.execute({'file_path': abs});
      expect(received, abs);
      expect(out, contains('[ok]'));
    });

    test('`../` 越界 → 拒绝', () async {
      final out = await tool().execute({'file_path': '../secret.png'});
      expect(out, contains('[error:'));
      expect(out, contains('不在工作区内'));
    });

    test('深层 `../../..` 越界 → 拒绝', () async {
      final out =
          await tool().execute({'file_path': '../../../../etc/passwd.png'});
      expect(out, contains('[error:'));
      expect(out, contains('不在工作区内'));
    });

    test('文件不存在 → [error: 文件不存在]', () async {
      final out = await tool().execute({'file_path': 'ghost.png'});
      expect(out, contains('文件不存在: ghost.png'));
    });
  });

  group('OcrFileTool — recognize 结果', () {
    test('recognize 返回 null → OCR 未识别到任何文本', () async {
      File(p.join(ws, 'a.png')).writeAsBytesSync([1]);
      final t = OcrFileTool(recognize: (_) async => null, workspaceDir: ws);
      final out = await t.execute({'file_path': 'a.png'});
      expect(out, contains('OCR 未识别到任何文本'));
    });

    test('recognize 抛异常 → [error: OCR 失败]', () async {
      File(p.join(ws, 'a.png')).writeAsBytesSync([1]);
      final t = OcrFileTool(
          recognize: (_) async => throw Exception('boom'), workspaceDir: ws);
      final out = await t.execute({'file_path': 'a.png'});
      expect(out, contains('[error: OCR 失败'));
      expect(out, contains('boom'));
    });

    test('长文本 → 截断 6000 字预览', () async {
      File(p.join(ws, 'a.png')).writeAsBytesSync([1]);
      final long = '字' * 8000;
      final t = OcrFileTool(recognize: (_) async => long, workspaceDir: ws);
      final out = await t.execute({'file_path': 'a.png'});
      expect(out, contains('总字数=8000'));
      expect(out, contains('前 6000 字'));
    });
  });

  group('isOcrTargetPath', () {
    test('图片/PDF → true；文本 → false', () {
      for (final f in [
        'a.png',
        'a.jpg',
        'a.jpeg',
        'a.bmp',
        'a.tiff',
        'a.webp',
        'a.PDF',
        'a.pdf'
      ]) {
        expect(isOcrTargetPath(f), isTrue, reason: f);
      }
      for (final f in ['a.txt', 'a.md', 'a.json', 'a.py', 'a.csv', 'a.dart']) {
        expect(isOcrTargetPath(f), isFalse, reason: f);
      }
    });
  });

  group('plugins/ocr 文档示例（与内置同名）', () {
    test('PluginBridge.registerAll 同名跳过 → 不产生重复工具、不干扰内置', () async {
      // 构造临时插件目录 plugins/ocr/agent/{manifest.json, ocr_file.py}
      // （与仓库 evg-base/plugins/ocr/ 同形态的文档示例）。
      final pluginsRoot = Directory(p.join(tmp.path, 'plugins'));
      final agentDir = Directory(p.join(pluginsRoot.path, 'ocr', 'agent'));
      agentDir.createSync(recursive: true);
      File(p.join(agentDir.path, 'manifest.json')).writeAsStringSync('''
{
  "name": "ocr_file",
  "description": "对扫描版 PDF / 图片文件运行 OCR（只读）",
  "schema": {
    "type": "object",
    "properties": {
      "file_path": {"type": "string", "description": "工作区相对路径或绝对路径"}
    }
  },
  "readOnly": true,
  "runtime": "python",
  "argMode": "stdin",
  "lifetime": "once"
}
''');
      File(p.join(agentDir.path, 'ocr_file.py'))
          .writeAsStringSync('print("format example")');

      final registry = Registry();
      var builtinCalled = false;
      registry.register(SimpleTool(
        name: 'ocr_file',
        description: '内置 OCR 工具',
        schema: const {'type': 'object', 'properties': {}},
        execute: (args) async {
          builtinCalled = true;
          return 'builtin result';
        },
      ));

      PluginBridge.registerAll(registry, pluginsRoot);

      // 插件未被注册（同名跳过），内置工具仍可正常调用。
      expect(registry.all().length, 1);
      final out = await registry.call('ocr_file', '{}');
      expect(out, 'builtin result');
      expect(builtinCalled, isTrue);
    });
  });

  group('CheckOcrReadyTool', () {
    test('返回格式化诊断文本', () async {
      final t = CheckOcrReadyTool(
        readiness: () async => CheckOcrReadyTool.readinessMap(
          summarize: 'OCR 就绪（DeepSeek-OCR 已配置，Tesseract 可用）',
          python: true,
          pdfScript: true,
          ocrScript: true,
          ocrKey: true,
          tesseract: true,
        ),
      );
      final out = await t.execute({});
      expect(out, contains('OCR 就绪'));
      expect(out, contains('python: 可用'));
      expect(out, contains('pdf_to_images.py: 存在'));
      expect(out, contains('ocr_file.py: 存在'));
      expect(out, contains('DeepSeek OCR Key: 已配置'));
      expect(out, contains('Tesseract: 可用'));
    });

    test('formatReadiness 纯函数：缺失键安全回退', () {
      final out = CheckOcrReadyTool.formatReadiness({'summarize': 'OCR 未就绪'});
      expect(out, contains('OCR 未就绪'));
      expect(out, contains('python: 不可用'));
      expect(out, contains('pdf_to_images.py: 缺失'));
      expect(out, contains('Tesseract: 不可用'));
    });

    test('readOnly = true（可并行）', () {
      expect(
          CheckOcrReadyTool(
            readiness: () async => <String, dynamic>{},
          ).readOnly,
          isTrue);
      expect(
          OcrFileTool(recognize: (_) async => null, workspaceDir: ws).readOnly,
          isTrue);
    });
  });
}
