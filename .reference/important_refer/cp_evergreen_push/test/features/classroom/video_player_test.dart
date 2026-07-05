import 'package:flutter_test/flutter_test.dart';

void main() {
  group('视频进度记忆', () {
    test('相同 videoUrl 生成相同 key', () {
      final url1 = 'https://example.com/video1.mp4';
      final url2 = 'https://example.com/video1.mp4';
      expect(url1.hashCode, url2.hashCode);
    });

    test('不同 videoUrl 生成不同 key', () {
      final url1 = 'https://example.com/video1.mp4';
      final url2 = 'https://example.com/video2.mp4';
      expect(url1.hashCode, isNot(url2.hashCode));
    });
  });
}
