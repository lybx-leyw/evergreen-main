/// OCR 内置工具（Task 四决策 4.2）——迁移自 skill_creator 的
/// `OcrFileTool` / `CheckOcrReadyTool`，注册到 AI 助手全局工具集。
///
/// 真实 OCR 能力由 `core/services/ocr_pipeline.dart` 的 [OcrPipeline]
/// （DeepSeek 云端 → Tesseract 本地两级降级）提供。本工具通过构造函数注入
/// `recognize` / `readiness` 回调，**不直接依赖 OcrPipeline 类型**——
/// 与 `ocr_attachment_handler.dart` 的注入风格一致，使 core/agent 子包可
/// 独立编译与测试（子包无 core/services 依赖）。
///
/// 插件化说明：spec 决策 4.2 要求「把 OCR 工具转成内置 agent tool 插件」。
/// 由于 OCR 管线（OcrPipeline）是 Dart 侧实现，无法纯 .py 复刻，本实现
/// 采取「Dart 内置工具为主 + `plugins/ocr/agent/` 标准插件格式文档示例」：
/// 真实能力注册为内置 `ocr_file` / `check_ocr_ready` 工具；`plugins/ocr/`
/// 目录提供 manifest.json + tool.py 作为插件形态示例（运行期因同名内置工具
/// 已注册而被 PluginBridge 跳过，未来若 OCR 引擎 Python 化即为真实实现）。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/path_sandbox.dart';
import '../tool.dart';

// ═══════ 扩展名常量 ═══════

/// OCR 目标图片扩展名（与 OcrPipeline._deepseekOcr 的 imageExts 对齐）。
const Set<String> kOcrImageExts = {'jpg', 'jpeg', 'png', 'bmp', 'tiff', 'webp'};

/// 文本扩展名（read_file 可直读，不需要 OCR）。
const Set<String> kTextFileExts = {'txt', 'md', 'json', 'csv', 'py', 'dart'};

/// 判断路径是否属于 OCR 目标（图片 / PDF）。
bool isOcrTargetPath(String filePath) {
  final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');
  return kOcrImageExts.contains(ext) || ext == 'pdf';
}

// ═══════ OcrFileTool ═══════

/// 对扫描版 PDF / 图片运行 OCR（只读；DeepSeek 云端 → Tesseract 本地降级）。
class OcrFileTool extends Tool {
  final Future<String?> Function(String filePath) _recognize;
  final PathSandbox _sandbox;

  OcrFileTool({
    required Future<String?> Function(String filePath) recognize,
    required String workspaceDir,
  })  : _recognize = recognize,
        _sandbox = PathSandbox(workspaceDir);

  @override
  String get name => 'ocr_file';

  @override
  String get description => '对扫描版 PDF / 图片文件运行 OCR（只读）。'
      '参数 file_path 为工作区相对路径（推荐）或绝对路径。'
      '内部走两级降级：DeepSeek-OCR 云端 → Tesseract 本地；'
      '返回识别文本预览（前 6000 字）。'
      '文本文件请使用 read_file 工具；OCR 环境诊断请使用 check_ocr_ready。'
      '\n\nRun OCR on a scanned PDF or image file (read-only). '
      'Input: file_path (workspace-relative path preferred, absolute allowed). '
      'Returns recognized text (first ~6000 chars). Two-level fallback: '
      'DeepSeek-OCR cloud → local Tesseract.';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'file_path': {
            'type': 'string',
            'description': '工作区相对路径或绝对路径（扫描版 PDF / 图片文件）',
          },
        },
        'required': ['file_path'],
      };

  @override
  bool get readOnly => true;

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final rawPath = args['file_path']?.toString().trim() ?? '';
    if (rawPath.isEmpty) return '[error: file_path 必填]';

    // 文本文件引导走 read_file（避免浪费 OCR 时间）。
    final ext = p.extension(rawPath).toLowerCase().replaceFirst('.', '');
    if (kTextFileExts.contains(ext)) {
      return '[error: $rawPath 是文本文件，请用 read_file 工具读取]';
    }

    // 相对路径 → 沙箱限定工作区；绝对路径 → 原样使用。
    final absPath = p.isAbsolute(rawPath) ? rawPath : _sandbox.confine(rawPath);
    if (absPath == null) {
      return '[error: 路径 "$rawPath" 不在工作区内（仅允许工作区相对路径或绝对路径）]';
    }
    if (!File(absPath).existsSync()) {
      return '[error: 文件不存在: $rawPath]';
    }

    try {
      final text = await _recognize(absPath);
      if (text == null || text.isEmpty) {
        return '[error: OCR 未识别到任何文本（检查 OCR 环境，见 check_ocr_ready）]';
      }
      final preview = text.length > 6000 ? text.substring(0, 6000) : text;
      return '[ok] OCR 完成（总字数=${text.length}）\n'
          '--- 内容预览（前 ${preview.length} 字）---\n$preview';
    } catch (e) {
      return '[error: OCR 失败: $e]';
    }
  }
}

// ═══════ CheckOcrReadyTool ═══════

/// OCR 环境就绪诊断（只读）。
class CheckOcrReadyTool extends Tool {
  final Future<Map<String, dynamic>> Function() _readiness;

  CheckOcrReadyTool({
    required Future<Map<String, dynamic>> Function() readiness,
  }) : _readiness = readiness;

  @override
  String get name => 'check_ocr_ready';

  @override
  String get description => '诊断本地 OCR 环境（只读）：Python、OCR 脚本、DeepSeek OCR Key、'
      'Tesseract 可用性。在依赖 ocr_file 识别扫描件前可先调用。'
      '\n\nDiagnose the local OCR environment: python, scripts, OCR API key, '
      'tesseract. Call before relying on ocr_file for scanned PDFs.';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {},
        'required': <String>[],
      };

  @override
  bool get readOnly => true;

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final data = await _readiness();
    return formatReadiness(data);
  }

  /// 把 OcrReadinessReport 的快照字段压平为工具可消费的 Map（供注册点闭包使用）。
  ///
  /// [summarize] 来自 `OcrReadinessReport.summarize()`；其余为报告布尔字段。
  static Map<String, dynamic> readinessMap({
    required String summarize,
    required bool python,
    required bool pdfScript,
    required bool ocrScript,
    required bool ocrKey,
    required bool tesseract,
  }) {
    return {
      'summarize': summarize,
      'python': python,
      'pdf_script': pdfScript,
      'ocr_script': ocrScript,
      'ocr_key': ocrKey,
      'tesseract': tesseract,
    };
  }

  /// 格式化就绪诊断文本（纯函数，可单测）。
  static String formatReadiness(Map<String, dynamic> data) {
    final buf = StringBuffer()
      ..writeln(data['summarize']?.toString() ?? 'OCR 就绪状态未知')
      ..writeln('python: ${data['python'] == true ? "可用" : "不可用"}')
      ..writeln('pdf_to_images.py: ${data['pdf_script'] == true ? "存在" : "缺失"}')
      ..writeln('ocr_file.py: ${data['ocr_script'] == true ? "存在" : "缺失"}')
      ..writeln('DeepSeek OCR Key: ${data['ocr_key'] == true ? "已配置" : "未配置"}')
      ..writeln('Tesseract: ${data['tesseract'] == true ? "可用" : "不可用"}');
    return buf.toString();
  }
}
