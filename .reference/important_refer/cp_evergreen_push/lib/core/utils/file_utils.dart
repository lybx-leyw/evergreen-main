import 'dart:io';
import 'package:flutter/foundation.dart';

/// 跨平台打开文件管理器并定位到文件/目录。
///
/// - Windows: `explorer /select, <path>`
/// - macOS: `open -R <path>`
/// - Linux: `dbus-send ...` 或 `xdg-open <dir>`
void openInFileManager(String path) {
  final file = File(path);
  final dir = file.existsSync() ? file.parent : Directory(path);

  if (!dir.existsSync()) {
    debugPrint('[FileUtils] directory not found: $dir');
    return;
  }

  try {
    if (Platform.isWindows) {
      Process.run('explorer', ['/select,', path]);
    } else if (Platform.isMacOS) {
      Process.run('open', ['-R', path]);
    } else {
      // Linux: 打开所在目录
      Process.run('xdg-open', [dir.path]);
    }
  } catch (e) {
    debugPrint('[FileUtils] openInFileManager failed: $e');
  }
}
