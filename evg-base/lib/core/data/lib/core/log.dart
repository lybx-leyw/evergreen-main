import 'dart:io';

/// 日志级别。
enum LogLevel { debug, info, warn, error }

/// 应用日志单例。
///
/// - 输出到 `stderr`
/// - 保留最近 500 条在内存中，可通过 `exportRecent()` 导出
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

  final List<String> _recentBuffer = [];
  static const int _recentBufferMax = 500;

  /// 写入一条日志。
  void _write(String level, String message,
      {Object? data, Object? error, StackTrace? stack}) {
    final now = DateTime.now();
    final timestamp =
        '${now.year}-${_pad(now.month)}-${_pad(now.day)} '
        '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}.'
        '${now.millisecond.toString().padLeft(3, '0')}';

    final buffer = StringBuffer();
    buffer.writeln('[$timestamp] [$level] $message');
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
    stderr.write(line);

    _recentBuffer.add(line);
    while (_recentBuffer.length > _recentBufferMax) {
      _recentBuffer.removeAt(0);
    }
  }

  /// 调试日志。
  void debug(String message, {Object? data}) {
    _write('DEBUG', message, data: data);
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

  /// 导出最近 N 条日志（供反馈时附上）。
  String exportRecent({int lines = 200}) {
    final buffer = StringBuffer();
    final recent = _recentBuffer.length > lines
        ? _recentBuffer.sublist(_recentBuffer.length - lines)
        : _recentBuffer;
    for (final line in recent) {
      buffer.write(line);
    }
    return buffer.toString();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
