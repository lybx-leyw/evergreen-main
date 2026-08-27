/// Skill 创作「深寻 agents」采集工具集。
///
/// 在标准工具（web_search / web_fetch / workspace 读写）之上追加：
/// - `download_file` — 下载 URL 到工作区（PDF 等，写工具）；
/// - `pdf_extract_text` — pymupdf 提取 PDF 文本预览（数字型 PDF 文本层）。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/agent/tool.dart';
import 'package:evergreen_base/renderer/templates/skill_creator_modle/tools/pymupdf_tool.dart';

// ═══════ DownloadFileTool ═══════

/// 下载远程文件（PDF/图片等）到工作区指定路径（写工具，串行）。
class DownloadFileTool extends Tool {
  final Dio _dio;

  /// 允许写入的根目录（Agent 工作区）。
  final String workspaceDir;

  DownloadFileTool(this._dio, {required this.workspaceDir});

  @override
  String get name => 'download_file';

  @override
  String get description =>
      'Download a remote file (PDF/image/HTML) to the workspace. '
      'Input: url (remote file URL) and save_path (relative path under workspace, e.g. materials/paper1.pdf). '
      'Use this to fetch paper/PDF files found via web search or page links.';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': 'Remote file URL to download',
          },
          'save_path': {
            'type': 'string',
            'description':
                'Relative save path under workspace, e.g. materials/paper1.pdf',
          },
        },
        'required': ['url', 'save_path'],
      };

  @override
  bool get readOnly => false;

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final url = args['url']?.toString() ?? '';
    final savePath = args['save_path']?.toString() ?? '';
    if (url.isEmpty || savePath.isEmpty) {
      return '[error: url 与 save_path 必填]';
    }
    if (url.length > 8192) return '[error: URL 超过 8192 字符上限]';
    if (savePath.length > 1024 || p.isAbsolute(savePath)) return '[error: save_path 必须是 1024 字符内的相对路径]';
    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null || parsedUrl.host.isEmpty || parsedUrl.userInfo.isNotEmpty || !{'http', 'https'}.contains(parsedUrl.scheme.toLowerCase())) {
      return '[error: 仅允许 http/https 下载地址]';
    }
    final host = parsedUrl.host.toLowerCase();
    final privateIpv4 = RegExp(r'^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)').hasMatch(host);
    final privateIpv6 = host.startsWith('fc') || host.startsWith('fd') || host.startsWith('fe80:');
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1' || host == '0.0.0.0' || host == '169.254.169.254' || privateIpv4 || privateIpv6) {
      return '[error: 禁止访问本机或云元数据地址]';
    }
    try {
      final resolved = await InternetAddress.lookup(host);
      if (resolved.any((a) => a.isLoopback || a.isLinkLocal || RegExp(r'^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)').hasMatch(a.address) || a.address.startsWith('fc') || a.address.startsWith('fd'))) {
        return '[error: DNS 解析到受限内网地址]';
      }
    } catch (_) { return '[error: 无法解析目标主机]'; }

    // 路径沙箱：仅允许写入 workspace 内
    final target = p.normalize(p.join(workspaceDir, savePath));
    final root = p.normalize(workspaceDir);
    final rootPrefix = root.endsWith(Platform.pathSeparator) ? root : '$root${Platform.pathSeparator}';
    if (target != root && !target.startsWith(rootPrefix)) {
      return '[error: save_path 越界，必须位于工作区内]';
    }

    try {
      final existing = File(target);
      final sourceFile = File('$target.source');
      String? cachedSource;
      try { if (sourceFile.existsSync()) cachedSource = sourceFile.readAsStringSync(); } catch (_) {}
      if (existing.existsSync() && await existing.length() > 0 && cachedSource == url) {
        return '[ok] 已命中下载缓存（${await existing.length()} 字节）→ $target';
      }
      Response<List<int>>? resp;
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          resp = await _dio.get<List<int>>(url, options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            receiveTimeout: const Duration(seconds: 60),
            headers: {'User-Agent': 'Evergreen-Research-Agent/1.0'},
          ));
          break;
        } catch (e) {
          lastError = e;
          if (attempt < 2) await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
        }
      }
      if (resp == null) return '[error: 下载失败 $url → $lastError]';
      if (resp.data == null || resp.data!.isEmpty) {
        return '[error: 下载内容为空: $url]';
      }
      // 研究资料单文件上限 100 MiB，避免误下载 HTML/压缩包耗尽工作区。
      if (resp.data!.length > 100 * 1024 * 1024) {
        return '[error: 文件超过 100MiB 上限]';
      }
      final bytes = resp.data!;
      final lower = url.toLowerCase();
      final looksPdf = lower.contains('.pdf') ||
          (bytes.length >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46);
      final ext = p.extension(target).toLowerCase();
      if (ext == '.pdf' && !looksPdf) return '[error: 下载内容不是有效 PDF]';
      final file = File(target);
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      final tmp = File('$target.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(target);
      try {
        sourceFile.writeAsStringSync(url, flush: true);
      } catch (_) {
        // 文件已原子落盘；缓存元数据写失败不应把成功下载报告成失败。
      }
      return '[ok] 已下载 ${bytes.length} 字节 → $target';
    } catch (e) {
      return '[error: 下载失败 $url → $e]';
    }
  }
}

// ═══════ PdfExtractTool ═══════

/// 用 pymupdf 提取本地 PDF 文本预览（只读）。
///
/// 返回前 [previewChars] 字符 + 总长度 + 分段数。
/// 完整文本由编排层落盘到 `materials/<id>.txt`，避免撑爆 Agent 上下文。
class PdfExtractTool extends Tool {
  final String? pythonPath;
  final String? scriptPath;
  final int previewChars;

  PdfExtractTool({this.pythonPath, this.scriptPath, this.previewChars = 6000});

  @override
  String get name => 'pdf_extract_text';

  @override
  String get description =>
      'Extract plain text preview from a local PDF using pymupdf. '
      'Input: file_path (absolute path). Returns first ~6000 chars + total length. '
      'For scanned/image PDFs the text layer is empty.';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'file_path': {
            'type': 'string',
            'description': 'Absolute path to the PDF file',
          },
        },
        'required': ['file_path'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final filePath = args['file_path']?.toString() ?? '';
    if (filePath.isEmpty) return '[error: file_path 必填]';
    try {
      final data = await PymupdfTool.extractSegments(
        filePath,
        pythonPath: pythonPath,
        scriptPath: scriptPath,
      );
      final fullText = (data['full_text'] as String? ?? '').trim();
      final segments = (data['segments'] as List?)?.length ?? 0;
      final pageCount = data['page_count'] as int? ?? 0;
      final preview = fullText.length > previewChars
          ? fullText.substring(0, previewChars)
          : fullText;
      return '[ok] 页数=$pageCount 分段=$segments 总字数=${fullText.length}\n'
          '--- 预览（前 ${preview.length} 字）---\n$preview';
    } catch (e) {
      return '[error: $e]';
    }
  }
}
