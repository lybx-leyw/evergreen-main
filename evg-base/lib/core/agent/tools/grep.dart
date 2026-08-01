/// Agent 工具：在工作区内按正则搜索文件内容（类 grep）。
///
/// 所有搜索限定在 [workspaceDir] 沙箱内（复用 [PathSandbox]），逐文件逐行匹配，
/// 只回命中行 + 行号，避免整文件回灌上下文。带 max_matches 上限、单文件大小上限、
/// 二进制文件跳过三重防护，与 read_file 的安全思路一致。
///
/// # [GrepTool]
///
/// | 方法 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `GrepTool({workspaceDir, maxMatches, maxFileBytes})` | 工作区路径 + 上限 | `GrepTool` | 构造 |
/// | `execute(args)` | `Map` | `Future<String>` | 按正则搜索文件内容 |

import 'dart:io';

import '../../utils/path_sandbox.dart';
import '../tool.dart';
import 'package:path/path.dart' as p;

// ═══════ GrepTool ═══════

/// 在工作区内按正则搜索文件内容。
///
/// 路径相对于 [workspaceDir]，使用 [PathSandbox] 确保不越界。
class GrepTool extends Tool {
  final String _workspaceDir;
  final PathSandbox _sandbox;
  final int _maxMatches;
  final int _maxFileBytes;

  GrepTool({
    required String workspaceDir,
    int maxMatches = 200,
    int maxFileBytes = 5 * 1024 * 1024,
  })  : _workspaceDir = workspaceDir,
        _sandbox = PathSandbox(workspaceDir),
        _maxMatches = maxMatches,
        _maxFileBytes = maxFileBytes;

  @override
  String get name => 'grep';

  @override
  String get description =>
      '在工作区内按正则表达式搜索文件内容，返回命中行及其行号。'
      '用于快速定位大文件（如 data_query 落盘的数据文件）中的字段或错误信息，'
      '无需整文件读取。搜索范围限定在工作区内，越界路径会被拒绝。'
      '\n\n参数：'
      '- pattern: 正则表达式（必填）\n'
      '- path: 搜索的文件或目录相对路径（可选，默认整个工作区）\n'
      '- file_filter: 文件名 glob 过滤，如 "*.json"（可选，仅递归搜索时生效）\n'
      '- case_sensitive: 是否区分大小写（可选，默认 false）\n'
      '- max_matches: 返回的最大命中数（可选，默认 200）\n'
      '- context: 命中行前后各回的上下文行数（可选，默认 0）\n'
      '- context_before: 仅命中行之前的上下文行数（可选，覆盖 context）\n'
      '- context_after: 仅命中行之后的上下文行数（可选，覆盖 context）';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'pattern': {
            'type': 'string',
            'description': '正则表达式，如 "error|失败"、"course_\\d+"',
          },
          'path': {
            'type': 'string',
            'description': '搜索的文件或目录相对路径（相对于工作区根）。不传则搜索整个工作区。',
          },
          'file_filter': {
            'type': 'string',
            'description': '文件名 glob 过滤，如 "*.json"、"grades*.txt"。仅递归搜索时生效。',
          },
          'case_sensitive': {
            'type': 'boolean',
            'description': '是否区分大小写，默认 false（不区分）。',
          },
          'max_matches': {
            'type': 'integer',
            'description': '最多返回的命中数，默认 200，范围 1-5000。',
          },
          'context': {
            'type': 'integer',
            'description': '命中行前后各回的上下文行数，默认 0。',
          },
          'context_before': {
            'type': 'integer',
            'description': '仅命中行之前的上下文行数，覆盖 context。',
          },
          'context_after': {
            'type': 'integer',
            'description': '仅命中行之后的上下文行数，覆盖 context。',
          },
        },
        'required': ['pattern'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final rawPattern = args['pattern']?.toString() ?? '';
    if (rawPattern.isEmpty) return '请提供 pattern（正则表达式）参数。';

    // 编译正则
    final caseSensitive = (args['case_sensitive'] as bool?) ?? false;
    late final RegExp regex;
    try {
      regex = RegExp(rawPattern, caseSensitive: caseSensitive);
    } on FormatException catch (e) {
      return '[grep 错误] 非法正则表达式 "$rawPattern"：$e';
    }

    // 解析 max_matches（clamp 防滥用）
    final requested = (args['max_matches'] as int?) ?? _maxMatches;
    final maxMatches = requested.clamp(1, 5000);

    // 解析上下文行数（命中行前后各回 N 行，clamp 防滥用）
    final ctxArg = (args['context'] as int?) ?? 0;
    final ctxBefore = ((args['context_before'] as int?) ?? ctxArg).clamp(0, 100);
    final ctxAfter = ((args['context_after'] as int?) ?? ctxArg).clamp(0, 100);

    // 解析搜索范围
    final rawPath = args['path']?.toString().trim() ?? '';
    final fileFilter = args['file_filter']?.toString().trim();
    final List<File> files;
    String scopeLabel;
    File? singleFile;

    if (rawPath.isNotEmpty) {
      final safe = _sandbox.confine(rawPath);
      if (safe == null) {
        return '[越界拒绝] 路径 "$rawPath" 不在工作区内。搜索仅限工作区内。';
      }
      if (FileSystemEntity.typeSync(safe) == FileSystemEntityType.file) {
        singleFile = File(safe);
        files = [singleFile];
        scopeLabel = p.relative(safe, from: _workspaceDir);
      } else if (FileSystemEntity.typeSync(safe) ==
          FileSystemEntityType.directory) {
        final dir = Directory(safe);
        files = _collectFiles(dir, fileFilter);
        scopeLabel = p.relative(safe, from: _workspaceDir);
      } else {
        return '路径不存在：$rawPath';
      }
    } else {
      final dir = Directory(_workspaceDir);
      files = _collectFiles(dir, fileFilter);
      scopeLabel = '整个工作区';
    }

    if (files.isEmpty) {
      final filterHint =
          fileFilter != null ? '（file_filter="$fileFilter"）' : '';
      return '在 $scopeLabel$filterHint 中未找到可搜索的文件。';
    }

    // 逐文件匹配（支持上下文行）
    final blocks = <String>[];
    var matchCount = 0;
    var skippedLarge = 0;
    var skippedBinary = 0;
    var scannedFiles = 0;

    for (final file in files) {
      if (matchCount >= maxMatches) break;
      final size = file.lengthSync();
      if (size > _maxFileBytes) {
        skippedLarge++;
        continue;
      }
      // 尝试按文本读取；二进制文件读取会抛异常，跳过
      String content;
      try {
        content = await file.readAsString();
      } catch (_) {
        skippedBinary++;
        continue;
      }
      final lines = content.split('\n');
      // 收集命中行索引（受 max_matches 上限约束，只计命中行）
      final matched = <int>[];
      for (var i = 0; i < lines.length; i++) {
        if (regex.hasMatch(lines[i])) {
          matched.add(i);
          if (matched.length >= maxMatches - matchCount) break;
        }
      }
      if (matched.isEmpty) continue;
      scannedFiles++;
      matchCount += matched.length;

      // 合并命中行 ± 上下文，得到需展示的行集合（按行号排序）
      final showSet = <int>{};
      for (final m in matched) {
        for (var k = m - ctxBefore; k <= m + ctxAfter; k++) {
          if (k >= 0 && k < lines.length) showSet.add(k);
        }
      }
      final showList = showSet.toList()..sort();
      final rel = p.relative(file.path, from: _workspaceDir);
      final b = StringBuffer();
      b.writeln('`$rel`:');
      for (final idx in showList) {
        final isMatch = matched.contains(idx);
        final tag = isMatch ? '>' : ' ';
        b.writeln('$tag L${idx + 1}: ${lines[idx].trim()}');
      }
      b.writeln();
      blocks.add(b.toString());
    }

    if (matchCount == 0) {
      final filterHint =
          fileFilter != null ? '（file_filter="$fileFilter"）' : '';
      final skipHint = <String>[];
      if (skippedLarge > 0) {
        skipHint.add('$skippedLarge 个大文件(>${_fmtSize(_maxFileBytes)})');
      }
      if (skippedBinary > 0) skipHint.add('$skippedBinary 个二进制文件');
      final skipText = skipHint.isNotEmpty
          ? '（已跳过 ${skipHint.join('、')}，可用 read_file 分段读取）'
          : '';
      return '未在 $scopeLabel$filterHint 中找到匹配 "$rawPattern" 的内容。$skipText';
    }

    final header = StringBuffer();
    header.writeln('## grep 结果 — 正则 `$rawPattern`');
    header.writeln(
        '命中 $matchCount 处（搜索 $scannedFiles 个文件，范围：$scopeLabel）');
    if (ctxBefore > 0 || ctxAfter > 0) {
      header.writeln('_（上下文：命中行前后各 +$ctxBefore/-$ctxAfter 行，'
          '以 `>` 标记命中行）_');
    }
    if (matchCount >= maxMatches) {
      header.writeln('_（已达 max_matches=$maxMatches 上限，更多命中未显示）_');
    }
    if (skippedLarge > 0) {
      header.writeln(
          '_（跳过 $skippedLarge 个大文件 > ${_fmtSize(_maxFileBytes)}，可用 read_file 分段读取）_');
    }
    if (skippedBinary > 0) {
      header.writeln('_（跳过 $skippedBinary 个二进制文件）_');
    }
    header.writeln();
    return '$header${blocks.join('')}';
  }

  /// 递归收集目录下的文件，按 [fileFilter] glob 过滤（null 表示不过滤）。
  List<File> _collectFiles(Directory dir, String? fileFilter) {
    final files = <File>[];
    if (!dir.existsSync()) return files;
    for (final entity
        in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (fileFilter != null && !_matchGlob(p.basename(entity.path), fileFilter)) {
        continue;
      }
      files.add(entity);
    }
    return files;
  }

  /// 需要正则转义的特殊字符集合。
  static final Set<String> _regexSpecials = {
    r'\', '^', r'$', '.', '|', '?', '*', '+', '(', ')', '[', ']', '{', '}'
  };

  /// 简单 glob 匹配：支持 `*` 和 `?`，大小写不敏感。
  static bool _matchGlob(String name, String pattern) {
    final sb = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == '*') {
        sb.write('.*');
      } else if (c == '?') {
        sb.write('.');
      } else if (_regexSpecials.contains(c)) {
        sb.write('\\$c');
      } else {
        sb.write(c);
      }
    }
    sb.write(r'$');
    final re = RegExp(sb.toString(), caseSensitive: false);
    return re.hasMatch(name);
  }

  @override
  bool get readOnly => true;

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
