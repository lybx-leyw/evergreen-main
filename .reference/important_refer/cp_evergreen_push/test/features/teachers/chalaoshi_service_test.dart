import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:evergreen_multi_tools/features/teachers/services/chalaoshi_service.dart';
import '../../mocks/mock_dio.dart';
import '../../mocks/fake_path_provider.dart';

/// Test asset JSON — mirrors the structure of the real asset.
const _testData = {
  'colleges': [
    {'id': 1, 'name': '计算机科学与技术学院'},
    {'id': 2, 'name': '数学科学学院'},
  ],
  'teachers': [
    {
      'id': 1001,
      'name': '张三',
      'py': 'zhangsan',
      'sx': 'zs',
      'xy': 1,
      'hot': 42,
      'rate': '4.8'
    },
    {
      'id': 1002,
      'name': '李四',
      'py': 'lisi',
      'sx': 'ls',
      'xy': 2,
      'hot': 15,
      'rate': '4.2'
    },
    {
      'id': 1003,
      'name': '王五',
      'py': 'wangwu',
      'sx': 'ww',
      'xy': 1,
      'hot': 30,
      'rate': '4.5'
    },
  ],
};

/// Write test data to the expected cache file so _loadLocal finds it.
Future<File> _writeTestCacheFile() async {
  final appDir = await getApplicationDocumentsDirectory();
  final file = File(
    '${appDir.path}${Platform.pathSeparator}teacher_ratings.json',
  );
  await file.writeAsString(jsonEncode(_testData));
  return file;
}

/// Remove the cache file between tests.
Future<void> _deleteTestCacheFile() async {
  final appDir = await getApplicationDocumentsDirectory();
  final file = File(
    '${appDir.path}${Platform.pathSeparator}teacher_ratings.json',
  );
  if (await file.exists()) {
    await file.delete();
  }
}

void main() {
  late FakePathProviderPlatform fakePathProvider;
  late Directory _sharedDocsDir;

  setUpAll(() {
    // Create a shared temp directory for document paths so that
    // both the test helpers and ChalaoshiService._getCacheFile()
    // access the same directory.
    _sharedDocsDir = Directory.systemTemp.createTempSync('chalaoshi_test_docs_');
    fakePathProvider = FakePathProviderPlatform();
    fakePathProvider.setDocumentsPath(_sharedDocsDir.path);
    PathProviderPlatform.instance = fakePathProvider;
  });

  tearDownAll(() {
    PathProviderPlatform.instance = FakePathProviderPlatform();
    if (_sharedDocsDir.existsSync()) {
      _sharedDocsDir.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    await _deleteTestCacheFile();
  });

  tearDown(() async {
    await _deleteTestCacheFile();
  });

  /// Create service with mocked Dio (offline mode — sees no cache).
  ChalaoshiService _createService() {
    final (dio, _) = createMockDio();
    return ChalaoshiService(dio);
  }

  group('ChalaoshiService search (cache fallback)', () {
    test('pre-populated cache → search by name', () async {
      await _writeTestCacheFile();
      final service = _createService();

      final results = await service.search('张三');
      expect(results.length, 1);
      expect(results.first.name, '张三');
      expect(results.first.score, 4.8);
      expect(results.first.college, '计算机科学与技术学院');
      expect(results.first.dataSource, 'local');
    });

    test('search by pinyin match', () async {
      await _writeTestCacheFile();
      final service = _createService();

      final results = await service.search('lisi');
      expect(results.length, 1);
      expect(results.first.name, '李四');
      expect(results.first.dataSource, 'local');
    });

    test('search by abbreviation match', () async {
      await _writeTestCacheFile();
      final service = _createService();

      final results = await service.search('ww');
      expect(results.length, 1);
      expect(results.first.name, '王五');
    });

    test('search by partial name', () async {
      await _writeTestCacheFile();
      final service = _createService();

      final results = await service.search('张');
      expect(results.length, 1);
      expect(results.first.name, '张三');
    });

    test('search no match → empty list', () async {
      await _writeTestCacheFile();
      final service = _createService();

      final results = await service.search('不存在');
      expect(results, isEmpty);
    });

    test('search empty string → empty list', () async {
      await _writeTestCacheFile();
      final service = _createService();

      final results = await service.search('');
      expect(results, isEmpty);
    });

    test('search whitespace only → empty list', () async {
      await _writeTestCacheFile();
      final service = _createService();

      final results = await service.search('   ');
      expect(results, isEmpty);
    });

    test('no cache and no asset → empty list gracefully', () async {
      // No cache file written → _loadLocal fails at both levels
      final service = _createService();
      final results = await service.search('张三');
      expect(results, isEmpty);
    });
  });

  group('ChalaoshiService getDetail', () {
    test('getDetail by teacher id returns correct info', () async {
      await _writeTestCacheFile();
      final service = _createService();

      final detail = await service.getDetail(1001, name: '张三');
      expect(detail, isNotNull);
      expect(detail!.name, '张三');
      expect(detail.score, 4.8);
      expect(detail.raters, 42);
      expect(detail.college, '计算机科学与技术学院');
    });

    test('getDetail non-existent id → null', () async {
      await _writeTestCacheFile();
      final service = _createService();

      final detail = await service.getDetail(9999);
      expect(detail, isNull);
    });

    test('getDetail without cache → null gracefully', () async {
      final service = _createService();
      final detail = await service.getDetail(1001);
      expect(detail, isNull);
    });
  });

  group('ChalaoshiService cache persistence path', () {
    test('cache file path is under app documents directory', () async {
      await _writeTestCacheFile();

      final appDir = await getApplicationDocumentsDirectory();
      final cachePath =
          '${appDir.path}${Platform.pathSeparator}teacher_ratings.json';

      final cacheFile = File(cachePath);
      expect(await cacheFile.exists(), isTrue);

      final content = jsonDecode(await cacheFile.readAsString());
      expect(content['teachers'], isNotNull);
      expect((content['teachers'] as List).length, 3);
    });
  });

  group('ChalaoshiService data types', () {
    test('TeacherResult has correct field types', () async {
      await _writeTestCacheFile();
      final service = _createService();
      final results = await service.search('张三');

      final r = results.first;
      expect(r.id, isA<int>());
      expect(r.name, isA<String>());
      expect(r.score, isA<double>());
      expect(r.college, isA<String>());
      expect(r.url, isA<String>());
      expect(r.url, contains('chalaoshi.click'));
      expect(r.dataSource, 'local');
    });

    test('TeacherDetail has correct field types', () async {
      await _writeTestCacheFile();
      final service = _createService();
      final detail = await service.getDetail(1002, name: '李四');

      expect(detail!.id, 1002);
      expect(detail.name, '李四');
      expect(detail.score, 4.2);
      expect(detail.raters, 15);
      expect(detail.college, '数学科学学院');
    });
  });
}
