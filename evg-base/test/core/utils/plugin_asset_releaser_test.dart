/// 运行时资产释放器测试。
///
/// 验证：
/// - 插件/脚本资产前缀常量与 pubspec.yaml 一致
/// - releaseBundledAssets() 在无资产环境下安全空跑（不抛异常、不落盘）
///
/// 注意：真机分支（rootBundle 实际资产 + 文件系统写入）需在模拟器/真机
/// 端到端验证（见 lib/core/utils/plugin_asset_releaser.dart）。
library;

import 'package:evergreen_base/core/utils/plugin_asset_releaser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('资产前缀常量', () {
    test('kPluginAssetPrefix 值应为 assets/plugins_bundle/（与 pubspec.yaml 一致）', () {
      expect(kPluginAssetPrefix, 'assets/plugins_bundle/');
    });

    test('kScriptsAssetPrefix 值应为 assets/scripts_bundle/', () {
      expect(kScriptsAssetPrefix, 'assets/scripts_bundle/');
    });

    test('两个前缀均以 assets/ 开头、以 / 结尾、不含连续斜杠', () {
      for (final p in [kPluginAssetPrefix, kScriptsAssetPrefix]) {
        expect(p.startsWith('assets/'), isTrue);
        expect(p.endsWith('/'), isTrue);
        expect(p.contains('//'), isFalse);
      }
    });
  });

  group('releaseBundledAssets', () {
    test('无资产环境下安全空跑（不抛异常）', () async {
      // 测试环境无 plugins/scripts 资产，函数应安全返回。
      await releaseBundledAssets();
    });

    test('返回 Future<void>，可 await 完成', () async {
      final future = releaseBundledAssets();
      expect(future, isA<Future<void>>());
      await future;
    });
  });
}
