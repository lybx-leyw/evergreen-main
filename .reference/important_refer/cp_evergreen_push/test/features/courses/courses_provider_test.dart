import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_multi_tools/features/courses/providers/courses_provider.dart';

void main() {
  group('CoursesProvider', () {
    test('coursesListProvider 声明不抛', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(coursesListProvider, isNotNull);
    });
  });
}
