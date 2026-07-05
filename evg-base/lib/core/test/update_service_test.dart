/// UpdateService 测试——覆盖网络错误降级、构造参数。
library;

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../services/update_service.dart';

void main() {
  group('checkForUpdate', () {
    test('网络错误时返回 hasUpdate=false（静默降级）', () async {
      final service = UpdateService(Dio());
      final (hasUpdate, version, url) = await service.checkForUpdate();
      // stub Dio 抛出 UnimplementedError → 内部 catch 返回 false
      expect(hasUpdate, isFalse);
      expect(version, isNull);
      expect(url, isNull);
    });

    test('自定义 repo 参数正常构造', () async {
      final service = UpdateService(Dio(), repo: 'my-org/my-repo');
      final (hasUpdate, version, url) = await service.checkForUpdate();
      // stub 环境同样抛异常 → 静默降级
      expect(hasUpdate, isFalse);
      expect(version, isNull);
      expect(url, isNull);
    });
  });
}
