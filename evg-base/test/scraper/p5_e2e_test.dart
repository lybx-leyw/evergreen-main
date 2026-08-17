/// A-P5 Batch 4（D1+D2 端到端测试）单元测试。
///
/// 不驱动 [ScraperWebView] / [PluginDesignerView]（规避 FAIL #13 的 `flutter_test` 泵陷阱），
/// 改用纯 Dart 服务 [AutoDataSourceService] + 假门面（[FakeManifestFacade]）串联：
///
/// - D1：捕获(含响应体) → analyzeSelection → generateAsDataPlugin → 写出对齐契约的
///   `data/manifest.json` → 注册 fake fetcher → `resolveDataSource('orch://<type>')` 非 null。
/// - D2：集成 plugin-designer 数据链路——未注册 `orch://courses` 的 Slot → 触发自动生成
///   → endpoint 写回 `orch://courses` → 运行期热注册进 `DataOrchestrator` →
///   `DesignToManifest.compile` 不抛错（静态审查入口 wiring 的等价验证）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/register_data_source.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/atomic/data_source_resolver.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_component.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/auto_data_source_service.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/data_pluginer.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/design_to_manifest.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/scraper_exporter.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/scraper_flow_facade.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 假门面：analyzeSelection 保留收到的日志（含响应体样本，便于断言 C1 集成），
/// generateAsDataPlugin 真实写出对齐 `_scanAndRegisterDataSources` 契约的 manifest。
class FakeManifestFacade extends ScraperFlowFacade {
  FakeManifestFacade() : super(workflow: ScraperWorkflow());

  List<HttpRequestLog> lastSelected = [];

  @override
  Future<InferredSchema> analyzeSelection(List<HttpRequestLog> selected) async {
    lastSelected = selected;
    return const InferredSchema(
      sourceUrl: 'https://api.example.com/courses',
      title: 'courses',
      fields: [InferredField(name: 'id', type: 'string', description: 'id')],
    );
  }

  @override
  Future<ExportResult> generateAsDataPlugin({
    required InferredSchema schema,
    required String pluginName,
    required String outputDir,
    String pythonCode = '',
    String? dataTypeName,
    String? category,
    String? displayName,
  }) async {
    final dataDir = Directory(p.join(outputDir, 'data'))..createSync(recursive: true);
    File(p.join(dataDir.path, 'manifest.json')).writeAsStringSync('''
{
  "type": "data-source",
  "script": "scraper.py",
  "dataTypes": [
    {"name": "$pluginName", "typeArg": "$pluginName", "ttl": "5m", "category": "自动生成"}
  ]
}
''');
    return ExportResult(success: true, message: 'ok');
  }
}

DesignDocument buildDoc({
  required String slotId,
  Map<String, dynamic>? dataSource,
}) {
  final component = DesignComponent(
    type: 'data-table',
    config: {
      if (dataSource != null) 'dataSource': dataSource,
    },
  );
  return DesignDocument(
    pluginId: 'test-p5-e2e',
    pluginName: 'P5 E2E 测试',
    pages: [
      DesignPage(
        id: 'page_0',
        slots: [DesignSlot(id: slotId, component: component)],
      ),
    ],
  );
}

void main() {
  group('D1 链路：捕获→生成→注册→解析 非 null', () {
    test('含响应体的捕获 → manifest 契约对齐 → resolve 出数', () async {
      final dir = Directory(p.join('.dart_tool', 'p5_e2e_test', 'plugins'))
        ..createSync(recursive: true);
      final doc = buildDoc(
        slotId: 'slot_0',
        dataSource: {'endpoint': 'orch://courses'},
      );
      final facade = FakeManifestFacade();
      final logs = [
        HttpRequestLog(
          timestamp: DateTime.now(),
          method: 'GET',
          url: 'https://api.example.com/courses',
          responseBody: '{"id":1,"title":"数学"}',
        ),
      ];

      String? genType;
      String? genDir;
      final updated = await AutoDataSourceService().autoGenerateFromCapture(
        doc: doc,
        slotId: 'slot_0',
        capturedLogs: logs,
        facade: facade,
        pluginsDir: dir.path,
        onGenerated: (type, d) {
          genType = type;
          genDir = d;
        },
      );

      // 写回 endpoint
      expect(
        updated.pages.first.slots.first.component!.config['dataSource'],
        equals({'endpoint': 'orch://courses'}),
      );
      expect(genType, 'courses');

      // 生成的 manifest 对齐启动扫描契约（type + dataTypes[].name == <type>）
      final manifestFile = File(p.join(genDir!, 'data', 'manifest.json'));
      expect(manifestFile.existsSync(), isTrue);
      final m = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      expect(m['type'], 'data-source');
      expect((m['dataTypes'] as List).first['name'], 'courses');

      // C1 集成：推断 schema 时确实收到了响应体样本
      expect(
        facade.lastSelected.any((l) => l.responseBody != null),
        isTrue,
        reason: 'AI 推断应使用响应体样本',
      );

      // 注册 fake fetcher → resolve 非 null（闭环出数）
      final orch = DataOrchestrator();
      orch.register<Map<String, dynamic>>(
        const DataType<Map<String, dynamic>>(name: 'courses'),
        () async => {
          'source': 'evergreen',
          'items': [
            {'id': 1, 'title': '数学'},
            {'id': 2, 'title': '物理'},
          ]
        },
      );
      final data = await resolveDataSource(
        ds: const DataSourceDescriptor(endpoint: 'orch://courses'),
        orch: orch,
      );
      expect(data, isNotNull);
      expect((data['items'] as List).length, 2);

      dir.deleteSync(recursive: true);
    });
  });

  group('D2 集成 plugin-designer 数据链路（非 widget）', () {
    test('未注册 orch → 自动生成 → 回写+运行期注册+compile 不抛', () async {
      final dir = Directory(p.join('.dart_tool', 'p5_e2e_test', 'plugins2'))
        ..createSync(recursive: true);
      final orch = DataOrchestrator();
      final doc = buildDoc(
        slotId: 'slot_x',
        dataSource: {'endpoint': 'orch://courses'},
      );

      // 初始：未注册 + 被识别为缺失
      expect(orch.isRegistered(const DataType(name: 'courses')), isFalse);
      expect(
        AutoDataSourceService.unregisteredOrchTypes(
          doc,
          (t) => orch.registeredTypes.contains(t),
        ),
        equals(['courses']),
      );

      final facade = FakeManifestFacade();
      String? genType;
      final updated = await AutoDataSourceService().autoGenerateFromCapture(
        doc: doc,
        slotId: 'slot_x',
        capturedLogs: [
          HttpRequestLog(
            timestamp: DateTime.now(),
            method: 'GET',
            url: 'https://api.example.com/courses',
          ),
        ],
        facade: facade,
        pluginsDir: dir.path,
        onGenerated: (type, d) {
          genType = type;
          // 等价 PluginDesignerView.onGenerated：生成后运行期热注册
          registerDataSourcesFromManifest(
            orch: orch,
            pluginDir: d,
            projectRoot: '.',
          );
        },
      );

      expect(genType, 'courses');
      // endpoint 写回
      expect(
        updated.pages.first.slots.first.component!.config['dataSource'],
        equals({'endpoint': 'orch://courses'}),
      );
      // 运行期注册已生效（CLI fetcher 注册成功，即便脚本不存在）
      expect(orch.isRegistered(const DataType(name: 'courses')), isTrue);
      // 缺失列表现已清空
      expect(
        AutoDataSourceService.unregisteredOrchTypes(
          updated,
          (t) => orch.registeredTypes.contains(t),
        ),
        isEmpty,
      );
      // DesignToManifest.compile 不抛（入口 wiring 等价验证）
      expect(() => DesignToManifest.compile(updated), returnsNormally);

      dir.deleteSync(recursive: true);
    });
  });
}
