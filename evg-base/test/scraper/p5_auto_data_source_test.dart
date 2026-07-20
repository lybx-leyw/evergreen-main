/// A-P5 Batch 1（A1+A2+A3 接入设计器自动数据类型闭环）单元测试。
///
/// 覆盖 [AutoDataSourceService]：orch 类型提取、未注册识别、从捕获日志生成
/// data 插件并写回 Slot 的 `dataSource.endpoint`，以及类型名推导。
/// （运行期注册 / CDP / 端到端 widget 测试在后续批次。）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/auto_data_source_service.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/scraper/scraper_workflow.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/scraper/scraper_flow_facade.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/scraper/scraper_exporter.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/data_pluginer.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_component.dart';

/// 假门面：直接返回可预期 schema 与成功结果，不触碰文件系统。
class FakeScraperFlowFacade extends ScraperFlowFacade {
  FakeScraperFlowFacade() : super(workflow: ScraperWorkflow());

  @override
  Future<InferredSchema> analyzeSelection(List<HttpRequestLog> selected) async {
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
  }) async {
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
    pluginId: 'test-p5',
    pluginName: 'P5 测试',
    pages: [
      DesignPage(
        id: 'page_0',
        slots: [
          DesignSlot(id: slotId, component: component),
        ],
      ),
    ],
  );
}

void main() {
  group('AutoDataSourceService.extractOrchType', () {
    test('提取 orch:// 后的类型名', () {
      expect(AutoDataSourceService.extractOrchType('orch://courses'),
          equals('courses'));
    });
    test('非 orch:// 返回 null', () {
      expect(AutoDataSourceService.extractOrchType('https://x.com'),
          isNull);
      expect(AutoDataSourceService.extractOrchType(null), isNull);
    });
  });

  group('AutoDataSourceService.unregisteredOrchTypes', () {
    test('识别未注册类型并去重', () {
      final doc = DesignDocument(
        pluginId: 'p',
        pluginName: 'p',
        pages: [
          DesignPage(
            id: 'page_0',
            slots: [
              DesignSlot(
                id: 's1',
                component: DesignComponent(
                  type: 't',
                  config: {
                    'dataSource': {'endpoint': 'orch://courses'}
                  },
                ),
              ),
              DesignSlot(
                id: 's2',
                component: DesignComponent(
                  type: 't',
                  config: {
                    'dataSource': {'endpoint': 'orch://courses'}
                  },
                ),
              ),
              DesignSlot(
                id: 's3',
                component: DesignComponent(
                  type: 't',
                  config: {
                    'dataSource': {'endpoint': 'orch://weather'}
                  },
                ),
              ),
            ],
          ),
        ],
      );
      final reg = <String>{'weather'};
      final result = AutoDataSourceService.unregisteredOrchTypes(
        doc,
        (t) => reg.contains(t),
      );
      expect(result, equals(['courses']));
    });
  });

  group('AutoDataSourceService.autoGenerateFromCapture', () {
    test('声明 orch://courses → 写回 endpoint 并触发 onGenerated', () async {
      final doc = buildDoc(
        slotId: 'slot_0',
        dataSource: {'endpoint': 'orch://courses'},
      );
      final facade = FakeScraperFlowFacade();

      String? generatedType;
      String? generatedDir;
      final logs = [
        HttpRequestLog(
          timestamp: DateTime.now(),
          method: 'GET',
          url: 'https://api.example.com/courses',
        ),
      ];

      final updated = await AutoDataSourceService().autoGenerateFromCapture(
        doc: doc,
        slotId: 'slot_0',
        capturedLogs: logs,
        facade: facade,
        pluginsDir: '.dart_tool/p5_test/plugins',
        onGenerated: (type, dir) {
          generatedType = type;
          generatedDir = dir;
        },
      );

      final slot = updated.pages.first.slots.first;
      final ep = slot.component?.config['dataSource']?['endpoint'];
      expect(ep, equals('orch://courses'));
      expect(generatedType, equals('courses'));
      expect(generatedDir, equals(p.join('.dart_tool/p5_test/plugins', 'courses')));
    });

    test('无声明类型时从捕获 URL 推导类型名', () async {
      final doc = buildDoc(slotId: 'slot_0');
      final facade = FakeScraperFlowFacade();
      final logs = [
        HttpRequestLog(
          timestamp: DateTime.now(),
          method: 'GET',
          url: 'https://news.example.com/api/list',
        ),
      ];

      final updated = await AutoDataSourceService().autoGenerateFromCapture(
        doc: doc,
        slotId: 'slot_0',
        capturedLogs: logs,
        facade: facade,
        pluginsDir: '.dart_tool/p5_test/plugins',
      );

      final ep = updated.pages.first.slots.first.component
          ?.config['dataSource']?['endpoint'];
      expect(ep, equals('orch://news'));
    });

    test('Slot 不存在时抛 AutoDataSourceException', () async {
      final doc = buildDoc(slotId: 'slot_0');
      final facade = FakeScraperFlowFacade();
      expect(
        () => AutoDataSourceService().autoGenerateFromCapture(
          doc: doc,
          slotId: 'nope',
          capturedLogs: const [],
          facade: facade,
        ),
        throwsA(isA<AutoDataSourceException>()),
      );
    });
  });
}
