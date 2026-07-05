import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/features/connectivity/providers/connectivity_provider.dart';

void main() {
  group('ConnectivityProvider', () {
    test('connectivityCheckProvider 声明不抛', () {
      expect(connectivityCheckProvider, isNotNull);
    });

    test('connectivity_provider.dart 不依赖 auto_refresh', () {
      final content = File(
              'lib/features/connectivity/providers/connectivity_provider.dart')
          .readAsStringSync();
      expect(content, isNot(contains('auto_refresh.dart')));
    });
  });
}
