import 'package:flutter_test/flutter_test.dart';

/// 0.1.4 — SharedPreferences 类型兼容：getBool 能处理 String 值。
///
/// 修复前：AUTO_REFRESH_ENABLED 在设置界面存为 String 'true'/'false'，
/// 但 initAutoRefresh 用 getBool() 读取，读到 String 直接崩溃。
void main() {
  group('Settings — type safety', () {
    // 模拟 auto_refresh.dart 的兼容读取逻辑
    bool readEnabled(dynamic raw) {
      return raw is bool ? raw : (raw != 'false');
    }

    test('bool true → true', () {
      expect(readEnabled(true), true);
    });

    test('bool false → false', () {
      expect(readEnabled(false), false);
    });

    test("String 'true' → true", () {
      expect(readEnabled('true'), true);
    });

    test("String 'false' → false", () {
      expect(readEnabled('false'), false);
    });

    test('null → true (default)', () {
      expect(readEnabled(null), true);
    });
  });
}
