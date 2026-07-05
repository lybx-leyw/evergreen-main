import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/network/dio_client.dart';

void main() {
  group('DioClient providers', () {
    test('dioClientProvider 声明不抛异常', () {
      expect(dioClientProvider, isNotNull);
    });

    test('cookieJarProvider 声明不抛异常', () {
      expect(cookieJarProvider, isNotNull);
    });
  });
}
