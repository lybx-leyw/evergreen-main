import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'errors.dart';

/// 日志级别。
enum LogLevel { debug, info, warn, error }

/// 日志条目（供 UIOperationLog 捕获 / 错误中心过滤）。
class LogEntry {
  final LogLevel level;
  final String msg;
  final Object? data;
  final DateTime timestamp;

  /// 调用方模块标签（如 'PluginInstaller'），由调用栈提取。
  final String? module;

  /// 错误标识（格式 EVG-xxxxxxxx），仅 ERROR 级自动生成。
  final String? errorId;

  LogEntry(this.level, this.msg,
      {this.data, this.module, this.errorId})
      : timestamp = DateTime.now();
}

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

  /// Release 模式是否同时镜像到 stderr。
  ///
  /// 安卓 release 构建无文件日志排查入口，logcat 是唯一通道；
  /// 置 true 后所有级别在写文件的同时镜像到 stderr（logcat 可见）。
  /// 由 main.dart 在启动时开启。
  static bool mirrorToStderr = false;

  /// errorId 去重窗口：相同 (模块, 消息) 在此窗口内复用同一 errorId，避免刷屏。
  static const Duration errorIdDedupeWindow = Duration(minutes: 10);
  final Map<String, ({String id, int at})> _errorIdState = {};

  /// 最近结构化日志条目（供错误中心/过滤检索，与文本缓冲同上限）。
  final List<LogEntry> _recentEntries = [];
  static const int _recentEntriesMax = 500;

  /// 日志流（UIOperationLog 订阅以捕获操作期间的日志）。
  final _logStreamController = StreamController<LogEntry>.broadcast();
  Stream<LogEntry> get logStream => _logStreamController.stream;

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
      {Object? data,
      Object? error,
      StackTrace? stack,
      String? errorId}) async {
    final now = DateTime.now();
    final timestamp =
        '${now.year}-${_pad(now.month)}-${_pad(now.day)} '
        '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}.'
        '${now.millisecond.toString().padLeft(3, '0')}';

    // 模块标签：从调用栈提取
    final moduleTag = _extractModuleTag();

    final buffer = StringBuffer();
    buffer.writeln('[$timestamp] [$level] [$moduleTag]'
        '${errorId != null ? ' [$errorId]' : ''} $message');
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
      // 安卓 release 排障：镜像到 stderr（logcat 可见）
      if (mirrorToStderr) {
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
    if (kReleaseMode) return;
    final tag = _extractModuleTag();
    _remember(LogEntry(LogLevel.debug, message, data: data, module: tag));
    _write('DEBUG', message, data: data);
  }

  /// 信息日志。
  void info(String message, {Object? data}) {
    final tag = _extractModuleTag();
    _remember(LogEntry(LogLevel.info, message, data: data, module: tag));
    _write('INFO', message, data: data);
  }

  /// 警告日志。
  void warn(String message, {Object? data, Object? error, String? errorId}) {
    final tag = _extractModuleTag();
    _remember(LogEntry(LogLevel.warn, message,
        data: data, module: tag, errorId: errorId));
    _write('WARN', message, data: data, error: error, errorId: errorId);
  }

  /// 错误日志 —— 记录错误 + 调用栈 + errorId。
  ///
  /// errorId 由 (模块, 消息) 哈希生成，格式 `EVG-xxxxxxxx`；
  /// 相同错误在 [errorIdDedupeWindow] 内复用同一 id，便于按 id 检索整条链路。
  void error(String message,
      {Object? data, Object? error, StackTrace? stack, String? errorId}) {
    final tag = _extractModuleTag();
    // AppError 自带 errorId（EVG-<模块>-<8hex>），优先使用，保证错误链路可检索
    final appErrId = error is AppError ? (error).errorId : null;
    final id = errorId ?? appErrId ?? _errorIdFor(tag, message);
    _remember(LogEntry(LogLevel.error, message,
        data: data, module: tag, errorId: id));
    _write('ERROR', message,
        data: data,
        error: error,
        stack: stack ?? StackTrace.current,
        errorId: id);
  }

  /// 结构化过滤最近日志条目（供错误中心/检索）。
  ///
  /// [module] 为空则不限模块；[minLevel] 为最低级别；结果按时间升序。
  List<LogEntry> entries({String? module, LogLevel minLevel = LogLevel.debug}) {
    return _recentEntries
        .where((e) =>
            (module == null || e.module == module) &&
            e.level.index >= minLevel.index)
        .toList();
  }

  /// 记录结构化条目到内存缓冲（与文本缓冲同上限）。
  void _remember(LogEntry entry) {
    _recentEntries.add(entry);
    if (_recentEntries.length > _recentEntriesMax) {
      _recentEntries.removeAt(0);
    }
  }

  /// 生成/复用 errorId：相同 (模块, 消息) 在去重窗口内复用同一 id。
  String _errorIdFor(String moduleTag, String message) {
    final key = '$moduleTag|$message';
    final now = DateTime.now().millisecondsSinceEpoch;
    final state = _errorIdState[key];
    if (state != null && now - state.at < errorIdDedupeWindow.inMilliseconds) {
      return state.id;
    }
    final digest = sha256.convert(utf8.encode(key)).toString();
    final id = 'EVG-${digest.substring(0, 8)}';
    _errorIdState[key] = (id: id, at: now);
    return id;
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

  /// 从调用栈提取模块标签（如 'AuthInterceptor'、'ApiService'）。
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
