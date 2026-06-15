import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/network/network_config.dart';

void main() {
  group('NetworkConfig', () {
    test('常量非空且合理', () {
      expect(NetworkConfig.connectTimeout.inSeconds, 30);
      expect(NetworkConfig.receiveTimeout.inSeconds, 60);
      expect(NetworkConfig.casValidateTimeout.inSeconds, 5);
      expect(NetworkConfig.maxRetries, 3);
      expect(NetworkConfig.maxRetryDelay.inSeconds, 30);
    });

    test('retryableStatusCodes 仅包含 429/502/503', () {
      expect(NetworkConfig.retryableStatusCodes, {429, 502, 503});
    });

    test('isZjuDomain 白名单匹配', () {
      // ZJU 核心域名
      expect(NetworkConfig.isZjuDomain('https://zjuam.zju.edu.cn/cas/login'), true);
      expect(NetworkConfig.isZjuDomain('https://zdbk.zju.edu.cn/jwglxt'), true);
      expect(NetworkConfig.isZjuDomain('https://courses.zju.edu.cn/api'), true);
      expect(NetworkConfig.isZjuDomain('https://classroom.zju.edu.cn/'), true);
      // 智云相关的多域名
      expect(NetworkConfig.isZjuDomain('https://tgmedia.cmc.zju.edu.cn/'), true);
      expect(NetworkConfig.isZjuDomain('https://education.cmc.zju.edu.cn/'), true);
      expect(NetworkConfig.isZjuDomain('https://yjapi.cmc.zju.edu.cn/'), true);
      // 其他 ZJU 服务
      expect(NetworkConfig.isZjuDomain('https://api.lib.zju.edu.cn/'), true);
      expect(NetworkConfig.isZjuDomain('https://elife.zju.edu.cn/'), true);
      // 第三方
      expect(NetworkConfig.isZjuDomain('https://chalaoshi.top/teacher'), true);
    });

    test('isZjuDomain 拒绝非 ZJU 域名', () {
      expect(NetworkConfig.isZjuDomain('https://google.com'), false);
      expect(NetworkConfig.isZjuDomain('https://pintia.cn/api'), false);
      expect(NetworkConfig.isZjuDomain('https://api.deepseek.com/chat'), false);
      expect(NetworkConfig.isZjuDomain(''), false);
      expect(NetworkConfig.isZjuDomain('not-a-url'), false);
      expect(NetworkConfig.isZjuDomain('://'), false);
    });

    test('isZjuDomain 无协议 URL', () {
      expect(NetworkConfig.isZjuDomain('https://zdbk.zju.edu.cn'), true);
      expect(NetworkConfig.isZjuDomain('https://courses.zju.edu.cn/path'), true);
    });

    test('zjuDomains 包含全部 10 个域名', () {
      expect(NetworkConfig.zjuDomains.length, 10);
    });

    test('超时常量合理性', () {
      expect(NetworkConfig.connectTimeout.inSeconds, greaterThan(0));
      expect(NetworkConfig.receiveTimeout.inSeconds, greaterThan(NetworkConfig.connectTimeout.inSeconds));
      expect(NetworkConfig.casValidateTimeout.inSeconds, lessThan(NetworkConfig.connectTimeout.inSeconds));
    });
  });
}
