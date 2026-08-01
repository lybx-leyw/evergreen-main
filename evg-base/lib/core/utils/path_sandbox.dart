/// 路径沙箱——防止 Agent 工具越界读写文件。
///
/// 所有文件操作工具（read_file / write_file / workspace）统一使用此类
/// 确保操作限定在指定沙箱根目录内。
///
/// ## 用法
/// ```dart
/// final sandbox = PathSandbox('/workspace/ai-assistant');
/// final safe = sandbox.confine('../../../etc/passwd'); // → null (被拒绝)
/// final ok   = sandbox.confine('output/report.md');    // → '/workspace/ai-assistant/output/report.md'
/// ```
library;

import 'dart:io';

/// 路径越界异常。
class PathSandboxException implements Exception {
  final String message;
  const PathSandboxException(this.message);
  @override
  String toString() => 'PathSandboxException: $message';
}

/// 路径沙箱——确保所有文件操作限定在指定根目录内。
///
/// 功能：
/// - 规范化路径（解析 `..` 和 `.`）
/// - 拒绝沙箱外的路径（返回 null）
class PathSandbox {
  final String _root;

  /// 创建以 [root] 为边界的沙箱。root 会自动转为绝对路径。
  PathSandbox(String root) : _root = Directory(root).absolute.path;

  /// 沙箱根目录（已规范化的绝对路径）。
  String get root => _root;

  /// 将用户提供的 [path] 约束在沙箱内。
  ///
  /// - 相对路径会相对于沙箱根目录拼接
  /// - 规范化后仍在沙箱内的返回绝对路径
  /// - 越界则返回 null
  String? confine(String path) {
    try {
      // 将相对路径转为基于沙箱根的绝对路径
      final abs = _toAbsolute(path);
      final resolved = _canonical(abs);
      final rootCanonical = _canonical(_root);
      final sep = Platform.pathSeparator;
      if (resolved == rootCanonical || resolved.startsWith('$rootCanonical$sep')) {
        return resolved;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 将路径转为基于沙箱根的绝对路径。
  String _toAbsolute(String path) {
    if (Platform.isWindows && path.length >= 2 && path[1] == ':') {
      // Windows 绝对路径（C:\...）
      return path;
    }
    if (path.startsWith('/') || (Platform.isWindows && path.startsWith('\\'))) {
      // Unix 绝对路径 / Windows UNC
      return path;
    }
    // 相对路径 → 拼接沙箱根
    final sep = Platform.pathSeparator;
    return '$_root$sep$path';
  }

  /// 规范化路径，解析 `..` 和 `.`（不要求路径已存在）。
  static String _canonical(String path) {
    final sep = Platform.pathSeparator;
    // 用户常传 Unix 风格 /，需先统一为平台分隔符，否则 split(sep) 会把
    // "C:\root\../../escape" 整体当作一个 part，".." 永远不被识别 → 越界绕过。
    final normalized = path.replaceAll('/', sep).replaceAll('\\', sep);
    final abs = Directory(normalized).absolute.path;
    final parts = abs.split(sep);
    final out = <String>[];
    for (final part in parts) {
      if (part == '.' || part.isEmpty) continue;
      if (part == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(part);
    }
    // Windows 盘符保留
    if (Platform.isWindows && out.isNotEmpty && !out.first.endsWith(':')) {
      // 尝试从原始路径提取盘符
      final driveMatch = RegExp(r'^([A-Za-z]:)').firstMatch(abs);
      if (driveMatch != null) {
        out.insert(0, driveMatch.group(1)!);
      }
    }
    final result = '${out.join(sep)}${abs.endsWith(sep) ? sep : ''}'.replaceAll('$sep$sep', sep);
    return result;
  }

  @override
  String toString() => 'PathSandbox($_root)';
}
