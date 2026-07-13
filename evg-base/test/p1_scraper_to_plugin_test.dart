/// P1 端到端测试 — 爬虫输出 → data 插件 → config → 完整插件目录。
///
/// 验证 DataPluginer → ConfigRegister → PluginGenerator 三步流水线。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/renderer/components/document/plugin-designer/services/data_pluginer.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/services/config_register.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/services/plugin_generator.dart';

void main() {
  late String tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('p1_test_').path;
  });

  tearDown(() {
    if (Directory(tmpDir).existsSync()) {
      Directory(tmpDir).deleteSync(recursive: true);
    }
  });

  group('P1 DataPluginer', () {
    test('registerDataPlugin 生成 data manifest.json', () async {
      final pluginer = DataPluginer();
      final schema = InferredSchema(
        sourceUrl: 'https://example.com/api',
        title: '测试API',
        fields: [
          const InferredField(name: 'id', type: 'number'),
          const InferredField(name: 'name', type: 'string'),
          const InferredField(name: 'api_key', type: 'string', description: 'API密钥'),
        ],
      );

      final result = await pluginer.registerDataPlugin(
        name: 'test-scraper',
        outputDir: tmpDir,
        schema: schema,
      );

      expect(result.success, isTrue);
      expect(result.manifestPath, isNotNull);
      expect(File(result.manifestPath!).existsSync(), isTrue);

      // 验证 JSON 内容
      final content = File(result.manifestPath!).readAsStringSync();
      expect(content, contains('"schemaVersion"'));
      expect(content, contains('"2.0"'));
      expect(content, contains('"type": "data-source"'));
      expect(content, contains('"id": "custom-test-scraper"'));
      expect(content, contains('"endpoint": "/data/test-scraper"'));
      expect(content, contains('"fields"'));
      expect(content, contains('"api_key"'));
    });

    test('registerDataPlugin 创建 data/ 目录和 module/ 占位', () async {
      final pluginer = DataPluginer();
      final result = await pluginer.registerDataPlugin(
        name: 'test-dir',
        outputDir: tmpDir,
        schema: InferredSchema(
          sourceUrl: 'https://example.com',
          fields: const [],
        ),
      );

      expect(result.success, isTrue);
      expect(Directory(p.join(tmpDir, 'data')).existsSync(), isTrue);
      expect(Directory(p.join(tmpDir, 'module')).existsSync(), isTrue);
      expect(File(p.join(tmpDir, 'module', 'manifest.json')).existsSync(), isTrue);
    });
  });

  group('P1 ConfigRegister', () {
    test('generateConfig 识别敏感字段', () async {
      final register = ConfigRegister();
      final fields = [
        {'name': 'api_key', 'type': 'string', 'description': 'API密钥'},
        {'name': 'password', 'type': 'string'},
        {'name': 'name', 'type': 'string'},  // 非敏感
        {'name': 'secret_token', 'type': 'string'},
      ];

      final result = await register.generateConfig(
        pluginDir: tmpDir,
        fields: fields,
      );

      expect(result.success, isTrue);
      expect(result.configPath, isNotNull);
      expect(File(result.configPath!).existsSync(), isTrue);

      final content = File(result.configPath!).readAsStringSync();
      expect(content, contains('"API_KEY"'));
      expect(content, contains('"PASSWORD"'));
      expect(content, contains('"SECRET_TOKEN"'));
      // name 非敏感，不应生成配置
      expect(content, isNot(contains('"NAME"')));
    });

    test('generateConfig 密码字段标记为 password 类型', () async {
      final register = ConfigRegister();
      final fields = [
        {'name': 'password', 'type': 'string'},
        {'name': 'api_key', 'type': 'string'},
      ];

      final result = await register.generateConfig(
        pluginDir: tmpDir,
        fields: fields,
      );

      expect(result.success, isTrue);
      final content = File(result.configPath!).readAsStringSync();
      expect(content, contains('"type": "password"'));
      expect(content, contains('"type": "string"')); // api_key 也是 string
    });

    test('generateConfig 创建 config/ 目录', () async {
      final register = ConfigRegister();
      await register.generateConfig(pluginDir: tmpDir, fields: const []);
      expect(Directory(p.join(tmpDir, 'config')).existsSync(), isTrue);
    });
  });

  group('P1 PluginGenerator — 端到端', () {
    test('generateFromScraper 三步流水线成功', () async {
      final generator = PluginGenerator();
      final schema = InferredSchema(
        sourceUrl: 'https://example.com/data',
        title: '端到端测试',
        fields: [
          const InferredField(name: 'id', type: 'number'),
          const InferredField(name: 'value', type: 'string'),
          const InferredField(name: 'api_key', type: 'string', description: '认证密钥'),
        ],
      );

      final result = await generator.generateFromScraper(
        name: 'e2e-test',
        outputDir: tmpDir,
        schema: schema,
      );

      expect(result.success, isTrue, reason: result.message);
      expect(result.pluginDir, tmpDir);

      // 验证三步骤输出
      expect(result.dataManifestPath, isNotNull);
      expect(File(result.dataManifestPath!).existsSync(), isTrue);
      expect(result.configPath, isNotNull);
      expect(File(result.configPath!).existsSync(), isTrue);
      expect(result.moduleManifestPath, isNotNull);
      expect(File(result.moduleManifestPath!).existsSync(), isTrue);

      // 验证完整目录结构
      expect(Directory(p.join(tmpDir, 'data')).existsSync(), isTrue);
      expect(Directory(p.join(tmpDir, 'config')).existsSync(), isTrue);
      expect(Directory(p.join(tmpDir, 'module')).existsSync(), isTrue);

      // 验证 module manifest 含 dataBinding
      final moduleContent = File(result.moduleManifestPath!).readAsStringSync();
      expect(moduleContent, contains('"dataBindings"'));

      // 验证状态
      expect(generator.status.phase, PluginGeneratePhase.done);
      expect(generator.status.progress, 1.0);
    });

    test('generateFromScraper 状态变化跟踪', () async {
      final generator = PluginGenerator();
      final states = <PluginGeneratePhase>[];
      generator.onStatusChanged = (s) => states.add(s.phase);

      final result = await generator.generateFromScraper(
        name: 'status-test',
        outputDir: tmpDir,
        schema: InferredSchema(
          sourceUrl: 'https://example.com',
          fields: const [],
        ),
      );

      expect(result.success, isTrue);
      // 应经历 generatingData → generatingConfig → generatingModule → done
      expect(states.contains(PluginGeneratePhase.generatingData), isTrue);
      expect(states.contains(PluginGeneratePhase.generatingConfig), isTrue);
      expect(states.contains(PluginGeneratePhase.generatingModule), isTrue);
      expect(states.contains(PluginGeneratePhase.done), isTrue);
    });

    test('PluginGenerateStatus idle 默认值', () {
      const status = PluginGenerateStatus.idle();
      expect(status.phase, PluginGeneratePhase.idle);
      expect(status.progress, 0.0);
      expect(status.message, isNull);
    });
  });
}
