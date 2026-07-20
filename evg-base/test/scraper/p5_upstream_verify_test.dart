/// A-P5 上游依赖验证 — 覆盖 4 个测试缺口。
///
/// Gap 1: `scraperConfigTemplate` 常量验证
///   模板必须包含 `_get_config`、`{CREDENTIAL_PLACEHOLDER}`、双策略降级。
///
/// Gap 2: `exportAsExe` 签名与预检
///   确认是顶级函数（非类方法），Python 找不到时返回 success:false。
///
/// Gap 3: `ConfigHttpServer` 构造与生命周期
///   可启动/停止，端口有效，`/config/health` 端点可用。
///
/// Gap 4: `ScraperGeneratorView` / `ScraperWorkflow` 可导入与实例化
///   验证 ScraperWorkflow 状态机基本行为。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/scraper/scraper_exporter.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/scraper/scraper_workflow.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/scraper/scraper_flow_facade.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/scraper/scraper_generator_view.dart';
import 'package:evergreen_base/core/config/config_http_server.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/data_pluginer.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Gap 1: scraperConfigTemplate 常量验证
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  group('Gap1 scraperConfigTemplate 常量', () {
    test('模板非空', () {
      expect(scraperConfigTemplate, isNotEmpty);
      expect(scraperConfigTemplate.length, greaterThan(500),
          reason: '配置模板应包含完整双策略降级逻辑');
    });

    test('模板包含 _get_config(key) 函数', () {
      expect(scraperConfigTemplate, contains('def _get_config(key)'));
    });

    test('模板包含 CREDENTIAL_PLACEHOLDER 占位符', () {
      expect(scraperConfigTemplate, contains('{CREDENTIAL_PLACEHOLDER}'),
          reason: 'AI 只能填充此占位符');
    });

    test('模板包含双策略降级注释', () {
      final content = scraperConfigTemplate;
      // 策略1：HTTP 从 ConfigHttpServer 读取
      expect(content, contains('ConfigHttpServer'));
      expect(content, contains('config/settings'));
      expect(content, contains('urllib.request.Request'));
      // 策略2：环境变量兜底
      expect(content, contains('os.environ.get'));
    });

    test('模板包含 .config_port 发现逻辑', () {
      expect(scraperConfigTemplate, contains('.config_port'));
    });

    test('模板占位符唯一（仅一处）', () {
      final count = '{CREDENTIAL_PLACEHOLDER}'.allMatches(scraperConfigTemplate).length;
      expect(count, equals(1),
          reason: 'CREDENTIAL_PLACEHOLDER 应仅出现一次，确保 AI 替换点明确');
    });

    test('configReaderPy 与 scraperConfigTemplate 相同', () {
      expect(configReaderPy, equals(scraperConfigTemplate),
          reason: '保留兼容导出别名，内容应与模板一致');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Gap 2: exportAsExe 签名与预检
  // ═══════════════════════════════════════════════════════════════════════════

  group('Gap2 exportAsExe 签名与预检', () {
    late String tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('p5_exe_test_').path;
    });

    tearDown(() {
      if (Directory(tmpDir).existsSync()) {
        Directory(tmpDir).deleteSync(recursive: true);
      }
    });

    test('exportAsExe 是顶级函数（非类方法）', () {
      // 类型推断验证：可直接作为函数签名引用
      final Object fn = exportAsExe;
      expect(fn, isA<Function>());
      // 不应是某个类的方法 — 用 toString 验证不含类名前缀
      final sig = fn.toString();
      expect(sig, isNot(contains('ScraperExporter.')),
          reason: 'exportAsExe 应为顶级函数，非 ScraperExporter 类方法');
    });

    test('Python 不可用时返回 success:false', () async {
      final result = await exportAsExe(
        '# test',
        tmpDir,
        () async => null, // 模拟 Python 不存在
      );

      expect(result.success, isFalse,
          reason: 'Python 找不到时应返回 success:false（禁止崩溃）');
      expect(result.message, isNotEmpty);
      expect(result.message, contains('Python'),
          reason: '错误消息应明确提到缺少 Python');
    });

    test('exportAsExe 内部调用 exportAsPython（有 manifestConfig 时自动生成 manifest）',
        () async {
      // 即使 Python 不存在，exportAsPython 应先成功写入 scraper.py
      final result = await exportAsExe(
        'print("hello")',
        tmpDir,
        () async => null, // Python 不存在 → PyInstaller 跳过
        manifestConfig: ExportManifestConfig(
          name: 'test-exe',
          schema: InferredSchema(
            sourceUrl: 'https://example.com',
            title: 'EXE测试',
            fields: const [InferredField(name: 'id', type: 'number')],
          ),
        ),
      );

      // Python 不存在，应在 exportAsPython 成功后、PyInstaller 阶段失败
      expect(result.success, isFalse,
          reason: '无 Python → PyInstaller 阶段必然失败');
      expect(result.message, contains('Python'));

      // 但 exportAsPython 阶段应已成功写入 scraper.py
      expect(File(p.join(tmpDir, 'scraper.py')).existsSync(), isTrue);
    });

    /// 条件测试：若 Python 可用则走完整导出。
    /// 此测试关注签名正确性，非执行正确性。
    test('签名参数完整性验证', () {
      // 确认 4 个参数：pythonCode, outputDir, resolvePython, {manifestConfig}
      // 编译期验证：此调用若参数类型不匹配将无法编译
      Future<ExportResult> fn() => exportAsExe(
            'code',
            '/tmp',
            () async => null,
          );

      expect(fn, isNotNull); // 仅验证可编译，实际不执行
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Gap 3: ConfigHttpServer 构造与生命周期
  // ═══════════════════════════════════════════════════════════════════════════

  group('Gap3 ConfigHttpServer 构造与生命周期', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('基础构造 + 端口初始为 0', () async {
      final prefs = await SharedPreferences.getInstance();
      final server = ConfigHttpServer(prefs, port: 0);

      expect(server.isRunning, isFalse);
      expect(server.port, equals(0));

      await server.stop();
    });

    test('start 后 isRunning 为 true 且分配端口', () async {
      final prefs = await SharedPreferences.getInstance();
      final server = ConfigHttpServer(prefs, port: 0);
      final assignedPort = await server.start();

      expect(assignedPort, greaterThan(0),
          reason: '系统应分配一个可用端口');
      expect(server.isRunning, isTrue);
      expect(server.port, equals(assignedPort));

      // 重复 start 不改变端口
      final secondPort = await server.start();
      expect(secondPort, equals(assignedPort));

      await server.stop();
    });

    test('stop 后 isRunning 为 false 且 port = 0', () async {
      final prefs = await SharedPreferences.getInstance();
      final server = ConfigHttpServer(prefs, port: 0);
      await server.start();
      await server.stop();

      expect(server.isRunning, isFalse);
      expect(server.port, equals(0));
    });

    test('指定端口绑定', () async {
      final prefs = await SharedPreferences.getInstance();

      // 先获取一个临时端口用于绑定测试
      final tempServer = await HttpServer.bind('127.0.0.1', 0);
      final testPort = tempServer.port;
      await tempServer.close();

      final server = ConfigHttpServer(prefs, port: testPort);
      final assigned = await server.start();

      expect(assigned, equals(testPort),
          reason: '指定端口时应绑定到该端口');
      expect(server.isRunning, isTrue);

      await server.stop();
    });

    test('registerSetting / unregisterSetting 动态注册', () async {
      final prefs = await SharedPreferences.getInstance();
      final server = ConfigHttpServer(prefs, port: 0);

      server.registerSetting('MY_TOKEN', '我的令牌');
      // 无法直接断言内部状态，但可通过 start 后无异常验证不崩溃
      await server.start();
      expect(server.isRunning, isTrue);

      server.unregisterSetting('MY_TOKEN');
      await server.stop();
    });

    test('health 端点响应 200', () async {
      final prefs = await SharedPreferences.getInstance();
      final server = ConfigHttpServer(prefs, port: 0);
      final port = await server.start();

      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/config/health'),
        );
        final response = await request.close().timeout(
              const Duration(seconds: 5),
            );
        final body = await response.transform(utf8.decoder).join();

        expect(response.statusCode, equals(200));
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(json['status'], equals('ok'));
        expect(json['settingsCount'], isA<int>());
      } finally {
        client.close();
        await server.stop();
      }
    });

    test('settings 端点响应 200（空配置）', () async {
      final prefs = await SharedPreferences.getInstance();
      final server = ConfigHttpServer(prefs, port: 0);
      final port = await server.start();

      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/config/settings'),
        );
        final response = await request.close().timeout(
              const Duration(seconds: 5),
            );
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        expect(response.statusCode, equals(200));
        expect(json['settings'], isA<List>());
        expect((json['settings'] as List).every((s) => s is Map),
            isTrue);
      } finally {
        client.close();
        await server.stop();
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Gap 4: ScraperGenerator 组件可导入与实例化
  // ═══════════════════════════════════════════════════════════════════════════

  group('Gap4 ScraperGeneratorView / ScraperWorkflow', () {
    test('ScraperWorkflow 构造 + 基础状态机', () {
      final workflow = ScraperWorkflow();

      expect(workflow.phase, equals(ScraperPhase.idle));
      expect(workflow.logs, isEmpty);
      expect(workflow.debugCount, equals(0));

      // onChanged 回调可设置
      var changed = false;
      workflow.onChanged = () => changed = true;

      workflow.startCapturing();
      expect(workflow.phase, equals(ScraperPhase.capturing));
      expect(changed, isTrue, reason: 'onChanged 应在状态变更时触发');

      workflow.reset();
      expect(workflow.phase, equals(ScraperPhase.idle));
    });

    test('ScraperWorkflow.addLog 添加日志', () {
      final workflow = ScraperWorkflow();
      final log = HttpRequestLog(
        timestamp: DateTime.now(),
        method: 'GET',
        url: 'https://example.com/api',
      );

      workflow.addLog(log);
      expect(workflow.logs.length, equals(1));
      expect(workflow.logs[0].url, equals('https://example.com/api'));
      expect(workflow.logs[0].method, equals('GET'));
    });

    test('ScraperWorkflow maxDebugRounds 常量', () {
      expect(ScraperWorkflow.maxDebugRounds, greaterThan(0),
          reason: '最大调试轮数应 > 0');
      expect(ScraperWorkflow.maxDebugRounds, lessThanOrEqualTo(10),
          reason: '默认上限应合理（≤10）');
    });

    test('ScraperWorkflow.dispose 释放资源', () {
      final workflow = ScraperWorkflow();
      workflow.startCapturing();

      // dispose 不应抛
      workflow.dispose();

      // 二次 dispose 也应安全（幂等）
      workflow.dispose();
    });

    test('HttpRequestLog.toJson / fromJson 序列化', () {
      final log = HttpRequestLog(
        timestamp: DateTime(2026, 7, 14, 0, 0),
        method: 'POST',
        url: 'https://api.example.com/items',
        responseBody: '{"id":1}',
        headers: {'Content-Type': 'application/json'},
        body: '{"query":"test"}',
      );

      final json = log.toJson();
      expect(json['method'], equals('POST'));
      expect(json['url'], equals('https://api.example.com/items'));
      expect(json['responseBody'], equals('{"id":1}'));
      expect(json['headers'], isA<Map>());
      expect(json['body'], equals('{"query":"test"}'));

      final restored = HttpRequestLog.fromJson(json);
      expect(restored.method, equals('POST'));
      expect(restored.url, equals('https://api.example.com/items'));
      expect(restored.responseBody, equals('{"id":1}'));
    });

    test('ScraperPhase 9 个枚举值', () {
      expect(ScraperPhase.values.length, equals(9));
      // 所有阶段名应非空
      for (final phase in ScraperPhase.values) {
        expect(phase.name, isNotEmpty);
      }
    });

    test('ScraperFlowFacade 构造 + dispose', () {
      final workflow = ScraperWorkflow();
      final facade = ScraperFlowFacade(workflow: workflow);

      expect(facade.aiFieldInferrer, isNull);

      facade.dispose();
    });
  });
}
