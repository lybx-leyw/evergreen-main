import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0.1.3 — connectivityCheckProvider 不应依赖 autoRefreshTickProvider。
///
/// 修复前：connectionManagerProvider watch 了 autoRefreshTickProvider，
/// 每 3 分钟触发全部 6 个服务的 HTTP 检查。
/// 修复后：connectivity provider 不导入 auto_refresh.dart。
void main() {
  group('Connectivity — no auto refresh dependency', () {
    test(
        'connectivity_provider.dart 不 import auto_refresh.dart',
        () {
      final content = File(
              'lib/features/connectivity/providers/connectivity_provider.dart')
          .readAsStringSync();
      expect(content, isNot(contains('auto_refresh.dart')),
          reason: 'connectivity provider 不应依赖 autoRefreshTickProvider');
    });
  });
}
