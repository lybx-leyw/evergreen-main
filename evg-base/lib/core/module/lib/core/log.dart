/// 日志单例——独立版 stub（对标 data/lib/core/log.dart）。
///
/// 仅输出到 stderr，无文件持久化。
import 'dart:io';

class Log {
  static final Log _instance = Log._();
  factory Log() => _instance;
  Log._();

  void info(String message, {Object? data}) =>
      stderr.writeln('[INFO] $message${data != null ? " | $data" : ""}');

  void warn(String message, {Object? data, Object? error}) =>
      stderr.writeln('[WARN] $message${data != null ? " | $data" : ""}${error != null ? " | $error" : ""}');

  void error(String message, {Object? data, Object? error, StackTrace? stack}) =>
      stderr.writeln('[ERROR] $message${data != null ? " | $data" : ""}${error != null ? " | $error" : ""}');

  void debug(String message, {Object? data}) =>
      stderr.writeln('[DEBUG] $message${data != null ? " | $data" : ""}');
}
