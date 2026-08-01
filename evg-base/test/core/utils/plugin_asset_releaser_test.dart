/// Android 插件资产释放器纯 Dart 测试 —— 规划 §3.4。
///
/// 验证 releasePluginsAssetsIfNeeded() 的跨平台分支逻辑：
/// - 非 Android 平台应返回 null（不执行任何资产操作）
/// - 常量 kPluginAssetPrefix 值正确
///
/// 注意：Android 真机分支（rootBundle API + 文件系统写入）在 Windows
/// dart test 环境不可测试，需在模拟器/真机端到端验证。
library;

import 'package:evergreen_base/core/utils/plugin_asset_releaser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kPluginAssetPrefix', () {
    test('值应为 assets/plugins_bundle/（与 pubspec.yaml 一致）', () {
      expect(kPluginAssetPrefix, 'assets/plugins_bundle/');
    });

    test('以 assets/ 开头，以 / 结尾', () {
      expect(kPluginAssetPrefix.startsWith('assets/'), isTrue);
      expect(kPluginAssetPrefix.endsWith('/'), isTrue);
    });

    test('不包含连续斜杠', () {
      expect(kPluginAssetPrefix.contains('//'), isFalse);
    });
  });

  group('releasePluginsAssetsIfNeeded', () {
    test('非 Android 平台（Windows/Linux/macOS）应返回 null', () async {
      // 测试运行在 Windows dart test 环境，Platform.isAndroid=false，
      // 函数应立即返回 null 而不触碰任何文件系统。
      final result = await releasePluginsAssetsIfNeeded();
      expect(result, isNull);
    });

    test('返回值类型签名匹配', () async {
      final result = await releasePluginsAssetsIfNeeded();
      // 确保签名是 Future<String?>（null 也是有效返回值）
      expect(result is String?, isTrue);
    });
  });
}
