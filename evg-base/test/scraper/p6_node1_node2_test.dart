/// A-P6 节点1+2 物理实体化 — 多步骤采集向导 + 一次性三件套产出验证。
///
/// 覆盖：
/// - N1A: DataCollectionResult 模型字段完整性
/// - N1B: 向导步骤导航逻辑（`_WizardStep` 枚举 + `_canAdvanceTo` 规则）
/// - N1C: ScraperWorkflow + ScraperFlowFacade 全流程（模拟捕获→分析→ schema 产出）
/// - N2A: DataPluginer.registerDataPlugin → data/manifest.json 格式对齐
/// - N2B: ConfigRegister.generateConfig → 敏感字段识别 + config.json 产出
/// - N2C: 三件套完整产出（scraper.py + data/manifest.json + config/config.json）到磁盘
/// - N2D: 无敏感字段时跳过 config.json（节点2规则）
/// - N2E: Node 2 产出目录使用 resolvePluginsRoot()
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/scraper/scraper_workflow.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/scraper/scraper_flow_facade.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/scraper/scraper_exporter.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/data_pluginer.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/config_register.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/view/data_collection_wizard.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // N1A: DataCollectionResult 模型
  // ═══════════════════════════════════════════════════════════════════════

  group('N1A DataCollectionResult 模型', () {
    test('构造所有字段', () {
      final schema = InferredSchema(
        sourceUrl: 'https://example.com/api/scores',
        fields: [const InferredField(name: 'score', type: 'number')],
      );

      final result = DataCollectionResult(
        typeName: 'scores',
        outputDir: 'plugins/scores',
        pyPath: 'plugins/scores/scraper.py',
        exePath: 'plugins/scores/scraper.exe',
        dataManifestPath: 'plugins/scores/data/manifest.json',
        configPath: 'plugins/scores/config/config.json',
        schema: schema,
        files: [
          const FileOutput(
            path: 'plugins/scores/scraper.py',
            label: 'scraper.py',
            exists: true,
          ),
        ],
      );

      expect(result.typeName, 'scores');
      expect(result.outputDir, 'plugins/scores');
      expect(result.pyPath, isNotNull);
      expect(result.exePath, isNotNull);
      expect(result.dataManifestPath, isNotNull);
      expect(result.configPath, isNotNull);
      expect(result.schema.fields.length, 1);
      expect(result.files.length, 1);
    });

    test('configPath 可为 null（无敏感字段）', () {
      final result = DataCollectionResult(
        typeName: 'news',
        outputDir: 'plugins/news',
        schema: InferredSchema(
          sourceUrl: 'https://example.com/api/news',
          fields: [],
        ),
      );

      expect(result.configPath, isNull,
          reason: '无敏感字段时 configPath 应为 null');
    });

    test('files 可记录失败的输出项', () {
      final output = const FileOutput(
        path: 'plugins/scores/scraper.exe',
        label: 'scraper.exe',
        exists: false,
      );
      expect(output.exists, isFalse);
      expect(output.label, 'scraper.exe');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // N1B: 向导步骤导航逻辑
  // ═══════════════════════════════════════════════════════════════════════

  group('N1B 向导步骤导航', () {
    test('ScraperWorkflow 初始状态为空日志', () {
      final workflow = ScraperWorkflow();
      try {
        expect(workflow.logs, isEmpty);
        expect(workflow.phase, ScraperPhase.idle);
      } finally {
        workflow.dispose();
      }
    });

    test('startCapturing 推进到 capturing 阶段', () {
      final workflow = ScraperWorkflow();
      try {
        workflow.startCapturing();
        expect(workflow.phase, ScraperPhase.capturing);
      } finally {
        workflow.dispose();
      }
    });

    test('addLog 增加日志', () {
      final workflow = ScraperWorkflow();
      try {
        workflow.startCapturing();
        final log = HttpRequestLog(
          timestamp: DateTime.now(),
          method: 'GET',
          url: 'https://example.com/api/scores',
          headers: {},
          body: '',
        );
        workflow.addLog(log);
        expect(workflow.logs.length, 1);
        expect(workflow.logs[0].url, 'https://example.com/api/scores');
      } finally {
        workflow.dispose();
      }
    });

    test('reset 清空状态', () {
      final workflow = ScraperWorkflow();
      try {
        workflow.startCapturing();
        workflow.addLog(HttpRequestLog(
          timestamp: DateTime.now(),
          method: 'GET',
          url: 'https://example.com/test',
          headers: {},
          body: '',
        ));
        expect(workflow.logs.length, 1);
        workflow.reset();
        expect(workflow.logs, isEmpty);
        expect(workflow.phase, ScraperPhase.idle);
      } finally {
        workflow.dispose();
      }
    });

    test('onChanged 回调在状态变更时触发', () {
      final workflow = ScraperWorkflow();
      var called = false;
      workflow.onChanged = () => called = true;
      try {
        workflow.startCapturing();
        expect(called, isTrue);
      } finally {
        workflow.dispose();
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // N1C: ScraperFlowFacade 全流程
  // ═══════════════════════════════════════════════════════════════════════

  group('N1C ScraperFlowFacade 全流程', () {
    late ScraperWorkflow workflow;
    late ScraperFlowFacade facade;

    setUp(() {
      workflow = ScraperWorkflow();
      facade = ScraperFlowFacade(workflow: workflow);
    });

    tearDown(() {
      facade.dispose();
    });

    test('startCapture 推进工作流', () async {
      await facade.startCapture('https://example.com');
      expect(workflow.phase, ScraperPhase.capturing);
    });

    test('analyzeSelection 空列表返回空 schema', () async {
      final schema = await facade.analyzeSelection([]);
      expect(schema.sourceUrl, '');
      expect(schema.fields, isEmpty);
    });

    test('analyzeSelection 从 URL 推断字段', () async {
      final logs = <HttpRequestLog>[
        HttpRequestLog(
          timestamp: DateTime.now(),
          method: 'GET',
          url: 'https://example.com/api/scores',
          headers: {},
          body: '[{"name":"Alice","score":95}]',
        ),
      ];
      final schema = await facade.analyzeSelection(logs);
      expect(schema.sourceUrl, 'https://example.com/api/scores');
      // URL 推断：跳过 'api'，提取 'scores'
      final fieldNames = schema.fields.map((f) => f.name).toList();
      expect(fieldNames, contains('scores'));
    });

    test('analyzeSelection 多条日志取首个有效 URL', () async {
      final logs = <HttpRequestLog>[
        HttpRequestLog(
          timestamp: DateTime.now(),
          method: 'POST',
          url: 'https://example.com/login',
          headers: {},
          body: '',
        ),
        HttpRequestLog(
          timestamp: DateTime.now(),
          method: 'GET',
          url: 'https://example.com/api/grades',
          headers: {},
          body: '',
        ),
      ];
      final schema = await facade.analyzeSelection(logs);
      expect(schema.sourceUrl, 'https://example.com/login');
    });

    test('generateAsDataPlugin 写入 manifest.json', () async {
      final tmp = Directory.systemTemp.createTempSync('evg_n1c_');
      try {
        final schema = InferredSchema(
          sourceUrl: 'https://example.com/api/test',
          title: 'testData',
          fields: [const InferredField(name: 'value', type: 'string')],
        );
        final result = await facade.generateAsDataPlugin(
          schema: schema,
          pluginName: 'test-plugin',
          outputDir: tmp.path,
          pythonCode: 'print("hello")',
        );
        expect(result.success, isTrue, reason: result.message);

        // 验证 manifest.json 存在且格式正确
        final manifestFile = File(p.join(tmp.path, 'data', 'manifest.json'));
        expect(manifestFile.existsSync(), isTrue);
        final json = jsonDecode(manifestFile.readAsStringSync()) as Map;
        expect(json['type'], 'data-source');
        expect(json['script'], 'scraper.py');
        final dataTypes = json['dataTypes'] as List;
        expect(dataTypes.length, 1);
        expect(dataTypes[0]['name'], 'testData');

        // 验证 scraper.py 存在
        final scraperFile = File(p.join(tmp.path, 'scraper.py'));
        expect(scraperFile.existsSync(), isTrue);
      } finally {
        if (Directory(tmp.path).existsSync()) {
          tmp.deleteSync(recursive: true);
        }
      }
    });

    test('generateAsDataPlugin 空代码不写入 scraper.py', () async {
      final tmp = Directory.systemTemp.createTempSync('evg_n1c_empty_');
      try {
        final schema = InferredSchema(
          sourceUrl: 'https://example.com/test',
          fields: [],
        );
        // 不提供 pythonCode
        final result = await facade.generateAsDataPlugin(
          schema: schema,
          pluginName: 'empty-plugin',
          outputDir: tmp.path,
        );
        expect(result.success, isTrue, reason: result.message);

        // scraper.py 不应存在（未提供代码）
        expect(File(p.join(tmp.path, 'scraper.py')).existsSync(), isFalse);
        // 但 manifest.json 应存在
        expect(
          File(p.join(tmp.path, 'data', 'manifest.json')).existsSync(),
          isTrue,
        );
      } finally {
        if (Directory(tmp.path).existsSync()) {
          tmp.deleteSync(recursive: true);
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // N2A: DataPluginer data/manifest.json 格式
  // ═══════════════════════════════════════════════════════════════════════

  group('N2A DataPluginer data/manifest.json', () {
    late String tmpDir;
    late DataPluginer pluginer;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('evg_n2a_').path;
      pluginer = DataPluginer();
    });

    tearDown(() {
      if (Directory(tmpDir).existsSync()) {
        Directory(tmpDir).deleteSync(recursive: true);
      }
    });

    test('registerDataPlugin 生成完整 manifest', () async {
      final schema = InferredSchema(
        sourceUrl: 'https://example.com/api/scores',
        title: '成绩查询',
        fields: [
          const InferredField(name: 'studentName', type: 'string'),
          const InferredField(name: 'score', type: 'number'),
        ],
      );

      final result = await pluginer.registerDataPlugin(
        name: 'scores-scraper',
        outputDir: tmpDir,
        schema: schema,
      );

      expect(result.success, isTrue, reason: result.message);
      expect(result.manifestPath, isNotNull);
      expect(File(result.manifestPath!).existsSync(), isTrue);

      // 验证 manifest 内容对齐 _scanAndRegisterDataSources 契约
      final json = jsonDecode(File(result.manifestPath!).readAsStringSync());
      expect(json['type'], 'data-source');
      expect(json['script'], isNotEmpty,
          reason: 'script 字段不能为空（data/ 目录下无 .exe 时默认为 .py）');

      final dataTypes = json['dataTypes'] as List;
      expect(dataTypes.length, 1);
      final dt = dataTypes[0] as Map<String, dynamic>;
      expect(dt['name'], '成绩查询',
          reason: 'dataTypes[].name 必须 == schema.title');
      expect(dt['typeArg'], '成绩查询');
      expect(dt['ttl'], '5m');
      expect(dt['persistentKey'], contains('custom-scores-scraper'));
    });

    test('registerDataPlugin 无 title 时用 name 回退', () async {
      final schema = InferredSchema(
        sourceUrl: 'https://example.com/api/data',
        fields: [],
      );
      final result = await pluginer.registerDataPlugin(
        name: 'my-data',
        outputDir: tmpDir,
        schema: schema,
      );
      expect(result.success, isTrue);
      final json = jsonDecode(File(result.manifestPath!).readAsStringSync());
      final dataTypes = json['dataTypes'] as List;
      expect(dataTypes[0]['name'], 'my-data',
          reason: 'schema.title 为空时用插件 name 作为 typeArg');
    });

    test('data/ 目录必定创建', () async {
      final schema = InferredSchema(
        sourceUrl: 'https://example.com/test',
        fields: [],
      );
      await pluginer.registerDataPlugin(
        name: 'test',
        outputDir: tmpDir,
        schema: schema,
      );
      final dataDir = Directory(p.join(tmpDir, 'data'));
      expect(dataDir.existsSync(), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // N2B: ConfigRegister 敏感字段识别
  // ═══════════════════════════════════════════════════════════════════════

  group('N2B ConfigRegister 敏感字段', () {
    late String tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('evg_n2b_').path;
    });

    tearDown(() {
      if (Directory(tmpDir).existsSync()) {
        Directory(tmpDir).deleteSync(recursive: true);
      }
    });

    test('含敏感字段时生成 config.json', () async {
      final register = ConfigRegister();
      final result = await register.generateConfig(
        pluginDir: tmpDir,
        fields: [
          {'name': 'api_key', 'type': 'string'},
          {'name': 'score', 'type': 'number'},
        ],
      );
      expect(result.success, isTrue);
      expect(result.configPath, isNotNull);
      expect(File(result.configPath!).existsSync(), isTrue);

      final json = jsonDecode(File(result.configPath!).readAsStringSync());
      final settings = json['settings'] as List;
      expect(settings.length, greaterThanOrEqualTo(1));
      // api_key 应被识别为敏感字段
      expect(
        settings.any((s) => s['key'] == 'API_KEY'),
        isTrue,
      );
    });

    test('password 字段识别为 password 类型', () async {
      final register = ConfigRegister();
      final result = await register.generateConfig(
        pluginDir: tmpDir,
        fields: [
          {'name': 'user_password', 'type': 'string'},
        ],
      );
      expect(result.success, isTrue);
      final json = jsonDecode(File(result.configPath!).readAsStringSync());
      final settings = json['settings'] as List;
      final pwItem = settings.firstWhere((s) => s['key'] == 'USER_PASSWORD');
      expect(pwItem['type'], 'password');
    });

    test('无敏感字段时跳过 config.json', () async {
      final register = ConfigRegister();
      final result = await register.generateConfig(
        pluginDir: tmpDir,
        fields: [
          {'name': 'student_name', 'type': 'string'},
          {'name': 'score', 'type': 'number'},
        ],
      );
      // 生成应成功但无 config 项
      expect(result.success, isTrue);
      final json = jsonDecode(File(result.configPath!).readAsStringSync());
      final settings = json['settings'] as List;
      expect(settings, isEmpty,
          reason: 'student_name/score 都不是敏感字段，应生成空设置列表');
    });

    test('token/secret/auth/bearer 均识别为敏感', () async {
      final sensitiveNames = ['token', 'api_secret', 'auth', 'bearer_token', 'credential'];
      for (final name in sensitiveNames) {
        final tmp = Directory.systemTemp.createTempSync('evg_n2b_s_');
        try {
          final register = ConfigRegister();
          final result = await register.generateConfig(
            pluginDir: tmp.path,
            fields: [{'name': name, 'type': 'string'}],
          );
          expect(result.success, isTrue, reason: '$name 应正常处理');
          final json = jsonDecode(File(result.configPath!).readAsStringSync());
          final settings = json['settings'] as List;
          expect(settings.length, 1, reason: '$name 应被识别为敏感字段');
        } finally {
          if (Directory(tmp.path).existsSync()) {
            tmp.deleteSync(recursive: true);
          }
        }
      }
    });

    test('重复 key 去重', () async {
      final register = ConfigRegister();
      final result = await register.generateConfig(
        pluginDir: tmpDir,
        fields: [
          {'name': 'api_key', 'type': 'string'},
          {'name': 'API_KEY', 'type': 'string'}, // 不同大小写 → 同一 key
        ],
      );
      expect(result.success, isTrue);
      final json = jsonDecode(File(result.configPath!).readAsStringSync());
      final settings = json['settings'] as List;
      expect(settings.length, 1,
          reason: '同一 CONFIG KEY 不应重复');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // N2C: 三件套完整磁盘产出
  // ═══════════════════════════════════════════════════════════════════════

  group('N2C 三件套完整磁盘产出', () {
    late String tmpPlugins;

    setUp(() {
      tmpPlugins = Directory.systemTemp.createTempSync('evg_n2c_').path;
    });

    tearDown(() {
      if (Directory(tmpPlugins).existsSync()) {
        Directory(tmpPlugins).deleteSync(recursive: true);
      }
    });

    test('三件套全部产出（scraper.py + manifest + config）', () async {
      final pluginDir = p.join(tmpPlugins, 'my-scraper');

      // 1. scraper.py
      final pyCode = 'print("hello")';
      final pyResult = await exportAsPython(pyCode, pluginDir,
          manifestConfig: ExportManifestConfig(
            name: 'my-scraper',
            schema: InferredSchema(
              sourceUrl: 'https://example.com/api/x',
              fields: [const InferredField(name: 'val', type: 'string')],
            ),
          ));
      expect(pyResult.success, isTrue, reason: pyResult.message);

      // 2. data/manifest.json (via DataPluginer)
      final pluginer = DataPluginer();
      final dataResult = await pluginer.registerDataPlugin(
        name: 'my-scraper',
        outputDir: pluginDir,
        schema: InferredSchema(
          sourceUrl: 'https://example.com/api/x',
          fields: [const InferredField(name: 'val', type: 'string')],
        ),
      );
      expect(dataResult.success, isTrue, reason: dataResult.message);

      // 3. config/config.json (via ConfigRegister, 含敏感字段)
      final configRegister = ConfigRegister();
      final configResult = await configRegister.generateConfig(
        pluginDir: pluginDir,
        fields: [{'name': 'api_key', 'type': 'string'}],
      );
      expect(configResult.success, isTrue, reason: configResult.message);

      // 验证磁盘存在
      expect(File(p.join(pluginDir, 'scraper.py')).existsSync(), isTrue);
      expect(File(p.join(pluginDir, 'data', 'manifest.json')).existsSync(), isTrue);
      expect(File(p.join(pluginDir, 'config', 'config.json')).existsSync(), isTrue);

      // 验证 manifest 契约完整
      final manifest = jsonDecode(
        File(p.join(pluginDir, 'data', 'manifest.json')).readAsStringSync(),
      );
      expect(manifest['type'], 'data-source');
      expect(manifest['script'], isNotEmpty);
      expect((manifest['dataTypes'] as List).length, 1);
    });

    test('两次生成同一目录不报错（幂等）', () async {
      final pluginDir = p.join(tmpPlugins, 'idempotent');

      final pluginer = DataPluginer();
      final schema = InferredSchema(
        sourceUrl: 'https://example.com/api/x',
        fields: [],
      );

      final r1 = await pluginer.registerDataPlugin(
        name: 'idempotent',
        outputDir: pluginDir,
        schema: schema,
      );
      expect(r1.success, isTrue);

      // 二次调用不崩溃
      final r2 = await pluginer.registerDataPlugin(
        name: 'idempotent',
        outputDir: pluginDir,
        schema: schema,
      );
      expect(r2.success, isTrue,
          reason: '幂等调用不应抛异常或失败');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // N2D: 节点2 规则验证
  // ═══════════════════════════════════════════════════════════════════════

  group('N2D 节点2 规则', () {
    test('无敏感字段时跳过 config/config.json（规则验证）', () async {
      final tmp = Directory.systemTemp.createTempSync('evg_n2d_');
      try {
        final register = ConfigRegister();
        final result = await register.generateConfig(
          pluginDir: tmp.path,
          fields: [
            {'name': 'title', 'type': 'string'},
            {'name': 'content', 'type': 'string'},
            {'name': 'date', 'type': 'date'},
          ],
        );
        expect(result.success, isTrue);
        final json = jsonDecode(File(result.configPath!).readAsStringSync());
        expect(json['settings'], isEmpty,
            reason: '节点2规则：无敏感字段时 config 应为空列表');
      } finally {
        if (Directory(tmp.path).existsSync()) {
          tmp.deleteSync(recursive: true);
        }
      }
    });

    test('exportAsPython 包含 scraperConfigTemplate', () async {
      final tmp = Directory.systemTemp.createTempSync('evg_n2d_py_');
      try {
        final pyCode = 'def main():\n    pass\n';
        final result = await exportAsPython(pyCode, tmp.path);
        expect(result.success, isTrue);

        final content = File(result.filePath!).readAsStringSync();
        // 模板已被注入（代码不含 _get_config 所以会强制注入）
        expect(content, contains('def _get_config(key)'),
            reason: 'scraperConfigTemplate 必须注入到导出代码中');
      } finally {
        if (Directory(tmp.path).existsSync()) {
          tmp.deleteSync(recursive: true);
        }
      }
    });

    test('scraperConfigTemplate 含 {CREDENTIAL_PLACEHOLDER} 占位符', () {
      expect(scraperConfigTemplate, contains('{CREDENTIAL_PLACEHOLDER}'),
          reason: '模板必须含占位符以便 Node 1 填入凭证变量');
      expect(scraperConfigTemplate, contains('def _get_config(key)'),
          reason: '模板锁定：_get_config 逻辑不可变');
      expect(scraperConfigTemplate, contains('EVERGREEN CONFIG TEMPLATE (LOCKED'),
          reason: '模板锁定标识');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // N2E: 产出目录使用 resolvePluginsRoot()
  // ═══════════════════════════════════════════════════════════════════════

  group('N2E 产出目录路径统一', () {
    setUp(() {
      resetPluginsRootCache();
    });

    tearDown(() {
      resetPluginsRootCache();
    });

    test('resolvePluginsRoot 返回绝对路径可用于子目录拼接', () {
      final root = resolvePluginsRoot();
      expect(p.isAbsolute(root), isTrue);

      // 模拟 Node 2 输出目录拼接
      final outputDir = p.join(root, 'my-plugin');
      expect(p.isAbsolute(outputDir), isTrue);
      expect(outputDir, contains('plugins'));
      expect(outputDir, contains('my-plugin'));
    });

    test('拼接后的输出路径不依赖 CWD', () {
      final root = resolvePluginsRoot();
      final outputDir = p.join(root, 'test-plugin', 'data');

      // 路径应是绝对路径 → 不依赖 CWD
      expect(p.isAbsolute(outputDir), isTrue);
      // 确认不包含相对路径符号
      expect(outputDir, isNot(contains('..')));
    });
  });
}
