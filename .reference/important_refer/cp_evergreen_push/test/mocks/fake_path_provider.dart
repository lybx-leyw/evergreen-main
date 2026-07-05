import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 测试用 PathProviderPlatform 实现——避免 MissingPluginException。
///
/// 用法（setUpAll 中）：
/// ```dart
/// PathProviderPlatform.instance = FakePathProviderPlatform();
/// ```
class FakePathProviderPlatform extends PathProviderPlatform {
  /// Optional: set a fixed documents dir (for tests that need shared state).
  String? _documentsPath;

  /// Pre-set the documents path so multiple calls return the same directory.
  void setDocumentsPath(String path) {
    _documentsPath = path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    if (_documentsPath != null) return _documentsPath;
    final dir = Directory.systemTemp.createTempSync('fpp_docs_');
    _documentsPath = dir.resolveSymbolicLinksSync();
    return _documentsPath;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    final dir = Directory.systemTemp.createTempSync('fpp_');
    return dir.resolveSymbolicLinksSync();
  }

  @override
  Future<String?> getTemporaryPath() async {
    return Directory.systemTemp.path;
  }
}
