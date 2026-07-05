import 'dart:io';

/// 路径越界异常。
class PathSandboxException implements Exception {
  final String message;
  const PathSandboxException(this.message);
  @override
  String toString() => 'PathSandboxException: $message';
}

/// 路径沙箱——防止路径遍历逃逸。
///
/// 确保所有文件操作限定在项目根目录内。
class PathSandbox {
  static String? _root;

  /// 初始化沙箱根目录（首次访问时自动检测）。
  static String get _projectRoot {
    if (_root != null) return _root!;
    // 沿目录树向上查找 pubspec.yaml 作为项目根
    var dir = Directory.current;
    while (true) {
      if (File('${dir.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) {
        _root = dir.path;
        return _root!;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        // 到达文件系统根，回退到当前目录
        _root = Directory.current.path;
        return _root!;
      }
      dir = parent;
    }
  }

  /// 规范化路径，解析 `..` 和 `.`（不要求路径已存在）。
  static String _canonical(String path) {
    final abs = Directory(path).absolute.path;
    final sep = Platform.pathSeparator;
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
      out.insert(0, 'C:');
    }
    return '${out.join(sep)}${abs.endsWith(sep) ? sep : ''}'.replaceAll('$sep$sep', sep);
  }

  /// 检查路径是否在项目根目录内。
  static bool isWithin(String path) {
    try {
      final resolved = _canonical(path);
      final root = _canonical(_projectRoot);
      final s = Platform.pathSeparator;
      return resolved == root || resolved.startsWith('$root$s');
    } catch (_) {
      return false;
    }
  }

  /// 将路径约束在沙箱内。
  ///
  /// 规范化后仍在项目根内的返回规范化路径，否则返回 null。
  static String? confineOrNull(String path) {
    try {
      final resolved = _canonical(path);
      final root = _canonical(_projectRoot);
      final s = Platform.pathSeparator;
      if (resolved == root || resolved.startsWith('$root$s')) {
        return resolved;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
