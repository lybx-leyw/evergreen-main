import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 测试用 PathProviderPlatform 实现——避免 MissingPluginException。
///
/// 用法（setUpAll 中）：
/// ```dart
/// PathProviderPlatform.instance = FakePathProviderPlatform();
/// ```
class FakePathProviderPlatform extends PathProviderPlatform {
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
