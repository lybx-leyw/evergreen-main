import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:evergreen_multi_tools/core/utils/greenix_path.dart';
import '../../mocks/fake_path_provider.dart';

void main() {
  late FakePathProviderPlatform fakePathProvider;

  setUpAll(() {
    fakePathProvider = FakePathProviderPlatform();
    PathProviderPlatform.instance = fakePathProvider;
  });

  tearDownAll(() {
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  group('greenixMemoriesDir', () {
    test('returns path ending with memories', () async {
      await initGreenixPaths();
      final dir = greenixMemoriesDir;
      expect(dir.endsWith('memories'), isTrue);
      expect(dir.contains('.greenix'), isTrue);
    });

    test('returns consistent result across calls', () async {
      await initGreenixPaths();
      final a = greenixMemoriesDir;
      final b = greenixMemoriesDir;
      expect(a, b);
    });
  });

  group('greenixSkillsDir', () {
    test('returns path ending with skills', () async {
      await initGreenixPaths();
      final dir = greenixSkillsDir;
      expect(dir.endsWith('skills'), isTrue);
      expect(dir.contains('.greenix'), isTrue);
    });
  });

  group('initGreenixPaths', () {
    test('can be called multiple times safely', () async {
      await initGreenixPaths();
      final before = greenixMemoriesDir;
      await initGreenixPaths();
      final after = greenixMemoriesDir;
      expect(before, after);
    });

    test('desktop default is .greenix under cwd', () async {
      // On desktop (Windows in tests), initGreenixPaths is essentially a no-op
      // because Platform.isAndroid and Platform.isIOS are false
      // The default is '.greenix' (relative to cwd)
      await initGreenixPaths();
      expect(greenixSkillsDir, contains('skills'));
      expect(greenixMemoriesDir, contains('memories'));
    });
  });

  group('Greenix paths — idempotency', () {
    test('initGreenixPaths before accessing getters succeeds', () async {
      await initGreenixPaths();
      // Both should return non-empty strings
      expect(greenixMemoriesDir, isNotEmpty);
      expect(greenixSkillsDir, isNotEmpty);
    });
  });
}
