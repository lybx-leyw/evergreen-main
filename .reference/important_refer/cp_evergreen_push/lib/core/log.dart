import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 日志级别。
enum LogLevel { debug, info, warn, error }

/// 应用日志单例。
///
/// - Debug 模式：输出到 `stderr`（同步，不丢日志）
/// - Release 模式：写入文件（`~/AppData/Local/evergreen/logs/` 或 `~/Library/Logs/evergreen/`）
/// - 文件轮转：单文件最大 5MB，保留最近 5 个文件
///
/// 使用示例：
/// ```dart
/// Log().info('User logged in', data: {'username': 'xxx'});
/// Log().error('Request failed', error: e, stack: stack);
/// ```
class Log {
  static final Log _instance = Log._();
  factory Log() => _instance;
  Log._();

  static const int _maxFileSize = 5 * 1024 * 1024; // 5MB
  static const int _maxFileCount = 5;

  IOSink? _fileSink;
  String? _logDir;
  int _currentFileIndex = 0;
  int _currentFileSize = 0;
  final List<String> _recentBuffer = [];
  static const int _recentBufferMax = 500;

  /// 初始化日志目录（首次写日志时延迟初始化）。
  Future<String> _getLogDir() async {
    if (_logDir != null) return _logDir!;
    if (kReleaseMode) {
      final appDir = await getApplicationSupportDirectory();
      _logDir = '${appDir.path}${Platform.pathSeparator}logs';
      await Directory(_logDir!).create(recursive: true);
    }
    return _logDir ?? '';
  }

  /// 获取当前日志文件路径。
  String _logFilePath(int index) {
    final prefix = _logDir!.endsWith(Platform.pathSeparator)
        ? _logDir!
        : '$_logDir${Platform.pathSeparator}';
    return '${prefix}evergreen_$index.log';
  }

  /// 打开或轮转日志文件。
  Future<IOSink?> _ensureFileSink() async {
    if (!kReleaseMode) return null;
    final dir = await _getLogDir();
    if (dir.isEmpty) return null;

    final path = _logFilePath(_currentFileIndex);
    final file = File(path);

    if (await file.exists()) {
      _currentFileSize = await file.length();
    }

    // 文件超限 → 轮转到下一个索引
    if (_currentFileSize >= _maxFileSize) {
      _currentFileIndex = (_currentFileIndex + 1) % _maxFileCount;
      final nextPath = _logFilePath(_currentFileIndex);
      final nextFile = File(nextPath);
      if (await nextFile.exists()) {
        await nextFile.delete(); // 覆盖最旧的日志
      }
      _currentFileSize = 0;
    }

    _fileSink = File(_logFilePath(_currentFileIndex))
        .openWrite(mode: FileMode.append);
    return _fileSink;
  }

  /// 写入一条日志。
  Future<void> _write(String level, String message,
      {Object? data, Object? error, StackTrace? stack}) async {
    final now = DateTime.now();
    final timestamp =
        '${now.year}-${_pad(now.month)}-${_pad(now.day)} '
        '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}.'
        '${now.millisecond.toString().padLeft(3, '0')}';

    // 模块标签：从调用栈提取
    final moduleTag = _extractModuleTag();

    final buffer = StringBuffer();
    buffer.writeln('[$timestamp] [$level] [$moduleTag] $message');
    if (data != null) {
      buffer.writeln('  data: $data');
    }
    if (error != null) {
      buffer.writeln('  error: $error');
    }
    if (stack != null) {
      buffer.writeln('  stack: $stack');
    }

    final line = buffer.toString();

    // Release 模式：写文件
    if (kReleaseMode) {
      try {
        var sink = _fileSink;
        if (sink == null) {
          sink = await _ensureFileSink();
        }
        if (sink != null) {
          sink.write(line);
          await sink.flush();
          _currentFileSize += line.length;
        }
      } catch (_) {
        // 文件写入失败时回退到 stderr
        stderr.write(line);
      }
    } else {
      // Debug 模式：直接输出到 stderr
      stderr.write(line);
    }

    // 维护内存中的最近日志缓冲区（供 exportRecent 使用）
    _recentBuffer.add(line);
    while (_recentBuffer.length > _recentBufferMax) {
      _recentBuffer.removeAt(0);
    }
  }

  /// 调试日志 —— 仅在 debug 模式输出。
  void debug(String message, {Object? data}) {
    if (!kReleaseMode) {
      _write('DEBUG', message, data: data);
    }
  }

  /// 信息日志。
  void info(String message, {Object? data}) {
    _write('INFO', message, data: data);
  }

  /// 警告日志。
  void warn(String message, {Object? data, Object? error}) {
    _write('WARN', message, data: data, error: error);
  }

  /// 错误日志 —— 记录错误 + 调用栈。
  void error(String message,
      {Object? data, Object? error, StackTrace? stack}) {
    _write('ERROR', message,
        data: data, error: error, stack: stack ?? StackTrace.current);
  }

  /// 导出最近 N 条日志（供用户反馈时附上到 GitHub Issue）。
  ///
  /// 优先从内存缓冲区取；如果缓冲区不足，会尝试读取日志文件。
  Future<String> exportRecent({int lines = 200}) async {
    final buffer = StringBuffer();

    // 先从内存缓冲取
    final recent = _recentBuffer.length > lines
        ? _recentBuffer.sublist(_recentBuffer.length - lines)
        : _recentBuffer;

    for (final line in recent) {
      buffer.write(line);
    }

    // 如果内存不足且有文件，从文件尾部补充
    if (recent.length < lines && kReleaseMode && _logDir != null) {
      buffer.writeln(
          '\n--- Additional from log file (memory buffer only had ${recent.length} lines) ---');
      try {
        final path = _logFilePath(_currentFileIndex);
        final file = File(path);
        if (await file.exists()) {
          final content = await file.readAsString();
          final allLines = content.split('\n');
          final tailLines = allLines.length > (lines - recent.length)
              ? allLines.sublist(allLines.length - (lines - recent.length))
              : allLines;
          for (final line in tailLines) {
            buffer.writeln(line);
          }
        }
      } catch (_) {
        buffer.writeln('(无法读取日志文件)');
      }
    }

    return buffer.toString();
  }

  /// 从调用栈提取模块标签（如 'AuthInterceptor'、'ZdbkService'）。
  String _extractModuleTag() {
    try {
      final stack = StackTrace.current;
      final frames = stack.toString().split('\n');
      for (final frame in frames) {
        final trimmed = frame.trim();
        if (trimmed.isEmpty) continue;
        // 跳过 Log 自身的帧
        if (trimmed.contains('log.dart')) continue;
        // 尝试提取类名.方法名
        final match =
            RegExp(r'(?:\d+\s+)?(\w+)\.(\w+)').firstMatch(trimmed);
        if (match != null) {
          return match.group(1)!;
        }
        // 回退：提取文件名
        final fileMatch = RegExp(r'(\w+)\.dart').firstMatch(trimmed);
        if (fileMatch != null) {
          return fileMatch.group(1)!;
        }
      }
    } catch (_) {
      // 栈解析失败静默忽略
    }
    return 'Unknown';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// 释放文件资源（应用退出时调用）。
  Future<void> dispose() async {
    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;
  }
}
