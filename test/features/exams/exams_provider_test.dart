import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_multi_tools/features/exams/providers/exams_provider.dart';

void main() {
  group('ExamsProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('examsListProvider 声明不抛', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(examsListProvider, isNotNull);
    });
  });
}
