// 编译冒烟测试：强制编译 scraper_ai_panel.dart + scraper_tools.dart，
// 验证 root cause B 修复（export_and_register_scraper 工具 + 回灌逻辑）编译通过。
// 本环境 flutter analyze 报全局 false-error，编译裁定以 flutter test 为准。
import 'package:evergreen_base/renderer/templates/scraper_modle/agent/scraper_ai_panel.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/agent/tools/scraper_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('createScraperTools 注册 export_and_register_scraper 工具', () {
    final tools = createScraperTools(
      workspaceDir: '.',
      projectRoot: '.',
      resolvePython: () async => null,
      getLogsSummary: () => '',
      enqueueCommand: (_) {},
      getTerminalResult: () async => '',
      exportAndRegister: () async => '✅ ok',
      dataNameProvider: () => 'test_smoke',
      setDataName: (_) {},
      requestOverride: (_, __) async => true,
    );
    final names = tools.map((t) => t.name).toList();
    expect(names, contains('export_and_register_scraper'));
    expect(names, contains('run_python_scraper'));
    expect(names, contains('set_data_name'));
    expect(names, contains('guard_override'));
    // 引用 panel 类型强制其参与编译
    expect(ScraperAIPanel, isNotNull);
  });
}
