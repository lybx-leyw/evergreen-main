/// pymupdf Agent Tool — PDF 文本提取。
///
/// 作为 Agent Tool 注册到 AgentAssembly，供 paper_service 调用。
/// 实际通过子进程调用 pymupdf CLI（pdf2zh_next 的 pymupdf 依赖）。
library;

/// pymupdf 文本提取工具。
///
/// TODO: 实现为 dart Tool 接口，注册到 AgentAssembly.fromConfig 的 seedTools。
/// 当前为骨架占位，说明需实现的接口和调用方式。
class PymupdfTool {
  /// 工具名称。
  static const String toolName = 'pymupdf_extract';

  /// 工具描述。
  static const String description =
      'Extract plain text from a PDF file using pymupdf. '
      'Input: PDF file path. '
      'Output: plain text content with layout preserved.';

  /// 调用 pymupdf 提取 PDF 文本。
  ///
  /// [filePath] PDF 文件绝对路径。
  /// 返回提取的纯文本。
  static Future<String> extractText(String filePath) async {
    // TODO: 实现子进程调用
    // import 'dart:io';
    // final result = await Process.run(
    //   'python',
    //   ['-c', '''
    //     import fitz
    //     doc = fitz.open("$filePath")
    //     text = ""
    //     for page in doc:
    //         text += page.get_text()
    //     print(text)
    //   '''],
    // );
    // if (result.exitCode != 0) {
    //   throw Exception('pymupdf extraction failed: ${result.stderr}');
    // }
    // return result.stdout as String;

    throw UnimplementedError(
        'pymupdf_tool: 子进程调用待实现。'
        '需安装 pymupdf (pip install pymupdf)');
  }

  /// 工具 schema（用于 Agent 工具注册）。
  static Map<String, dynamic> get schema => {
        'name': toolName,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': {
            'file_path': {
              'type': 'string',
              'description':
                  'Absolute path to the PDF file',
            },
          },
          'required': ['file_path'],
        },
      };
}
