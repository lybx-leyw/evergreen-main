/// 多版本 bridge shim 路由测试（M2-6）。
import 'package:test/test.dart';

import '../bridge_shim.dart';

void main() {
  group('BridgeShimRouter (M2-6)', () {
    final router = BridgeShimRouter(
      supported: {1, 2, 3},
      defaultVersion: 1,
    );

    test('旧插件（requested=null）→ 回退默认 shim 1', () {
      expect(router.selectShim(null), 1);
    });

    test('新插件请求 3 → 拿 3', () {
      expect(router.selectShim(3), 3);
    });

    test('插件请求 2（宿主有 1/2/3）→ 拿 2（不强行升 3）', () {
      expect(router.selectShim(2), 2);
    });

    test('插件请求 5（高于宿主）→ 取最高支持 3', () {
      expect(router.selectShim(5), 3);
    });

    test('插件请求 0（低于宿主任何 shim）→ 取最低支持 1', () {
      expect(router.selectShim(0), 1);
    });

    test('defaultVersion 不在 supported → 构造抛', () {
      expect(
        () => BridgeShimRouter(supported: {2, 3}, defaultVersion: 1),
        throwsArgumentError,
      );
    });
  });
}
