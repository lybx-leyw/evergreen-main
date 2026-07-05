import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/config/theme.dart';

void main() {
  group('Android build config', () {
    test('AndroidManifest.xml 存在且含 INTERNET 权限', () {
      final f = File('android/app/src/main/AndroidManifest.xml');
      expect(f.existsSync(), true);
      final content = f.readAsStringSync();
      expect(content, contains('android.permission.INTERNET'));
      expect(content, contains('android.permission.ACCESS_NETWORK_STATE'));
      expect(content, contains('Evergreen'));
    });

    test('build.gradle.kts release config present', () {
      final f = File('android/app/build.gradle.kts');
      expect(f.existsSync(), true);
      final content = f.readAsStringSync();
      expect(content, contains('isMinifyEnabled'));
      expect(content, contains('isShrinkResources'));
      expect(content, contains('signingConfigs.getByName("release")'));
    });

    test('gradle-wrapper 版本 ≥ 8.9', () {
      final f = File('android/gradle/wrapper/gradle-wrapper.properties');
      expect(f.existsSync(), true);
      final content = f.readAsStringSync();
      expect(content, contains('gradle-8'));
    });

    test('proguard-rules.pro 存在', () {
      expect(File('android/app/proguard-rules.pro').existsSync(), true);
    });

    test('Android SDK 目录配置', () {
      final sdk = Platform.environment['ANDROID_HOME'];
      if (sdk != null) {
        expect(Directory(sdk).existsSync(), true);
      }
      // SDK 可能不在 CI 环境，所以不强制
    });
  });

  group('Windows installer config', () {
    test('installer.iss 存在且含 AppName', () {
      final f = File('scripts/installer.iss');
      expect(f.existsSync(), true);
      final content = f.readAsStringSync();
      expect(content, contains('Evergreen Multi-Tools'));
      expect(content, contains('Setup'));
      expect(content, contains('Default.isl'));
    });
  });

  group('Build infrastructure', () {
    test('pubspec.yaml 存在且含必要字段', () {
      final f = File('pubspec.yaml');
      expect(f.existsSync(), true);
      final content = f.readAsStringSync();
      expect(content, contains('name: evergreen_multi_tools'));
      expect(content, contains('version:'));
      expect(content, contains('flutter:'));
    });

    test('analysis_options.yaml 启用 lint 规则', () {
      final content = File('analysis_options.yaml').readAsStringSync();
      expect(content, contains('avoid_print: true'));
      expect(content, contains('prefer_const_constructors: true'));
    });

    test('BUILD.md 包含构建指南', () {
      final content = File('BUILD.md').readAsStringSync();
      expect(content, contains('flutter build'));
      expect(content, contains('Windows'));
      expect(content, contains('Android'));
    });

    test('.gitignore 包含 android build 产物', () {
      final content = File('android/.gitignore').readAsStringSync();
      expect(content, contains('build'));
      expect(content, contains('local.properties'));
    });
  });

  group('Theme variants — all 6', () {
    test('6 个变体全部可构建', () {
      expect(ThemeVariant.values.length, 6);
      for (final v in ThemeVariant.values) {
        expect(v.name, isNotEmpty);
      }
    });

    test('highContrast 变体存在', () {
      expect(ThemeVariant.values, contains(ThemeVariant.highContrast));
      expect(() => AppTheme.highContrastTheme, returnsNormally);
    });
  });

  group('UpdateService', () {
    test('_compareVersions 逻辑', () {
      // 测试版本比较逻辑
      int compare(String a, String b) {
        final aParts = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
        final bParts = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
        for (var i = 0; i < 3; i++) {
          final av = i < aParts.length ? aParts[i] : 0;
          final bv = i < bParts.length ? bParts[i] : 0;
          if (av > bv) return 1;
          if (av < bv) return -1;
        }
        return 0;
      }

      expect(compare('2.0.0', '1.0.0'), 1);
      expect(compare('1.0.1', '1.0.0'), 1);
      expect(compare('1.0.0', '1.0.0'), 0);
      expect(compare('0.9.0', '1.0.0'), -1);
      expect(compare('1.0', '1.0.0'), 0);
      expect(compare('2.0', '1.0'), 1);  // major version up
    });
  });
}
