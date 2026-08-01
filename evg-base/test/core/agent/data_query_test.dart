import 'dart:io';

import 'package:evergreen_base/core/agent/tools/data_query.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('data_query: 短数据内联返回完整 JSON（不截断）', () async {
    final orch = DataOrchestrator();
    orch.register<Map<String, dynamic>>(
      const DataType(name: 'small', persistentKey: 'small'),
      () async => {'k': 'v', 'n': 1},
    );
    final tool = DataQueryTool(orchestrator: orch);

    final out = await tool.execute({'action': 'get', 'type_name': 'small'});
    expect(out, contains('"k": "v"'));
    expect(out, contains('数据内容'));
    expect(out, isNot(contains('已截断')));
  });

  test('data_query: 超长数据截断预览并把完整文档落盘 ai-assistant 工作区',
      () async {
    final big = List.generate(2000, (i) => {'id': i, 'name': 'x' * 50});
    final orch = DataOrchestrator();
    orch.register<List<dynamic>>(
      const DataType(name: 'big', persistentKey: 'big'),
      () async => big,
    );
    final tool = DataQueryTool(orchestrator: orch);

    final out = await tool.execute({'action': 'get', 'type_name': 'big'});
    expect(out, contains('已截断'));
    expect(out, contains('data_big.json'));

    final file = File('${greenixWorkspaceDir('ai-assistant')}/data_big.json');
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    // 完整文档未被截断。
    expect(content, contains('"id": 1999'));
    expect(content, isNot(contains('已截断')));

    // 清理落盘文件。
    file.deleteSync();
  });

  test('data_query: 未知 type_name 返回错误提示而非崩溃', () async {
    final orch = DataOrchestrator();
    final tool = DataQueryTool(orchestrator: orch);

    final out =
        await tool.execute({'action': 'get', 'type_name': 'nope'});
    expect(out, contains('[data_query 错误]'));
    expect(out, contains('未注册'));
  });
}
