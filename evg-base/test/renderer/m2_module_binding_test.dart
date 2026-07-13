/// M2 P3-1 模块级 dataBindings 接通测试。
///
/// 验证 [CompositeView] 在 `pages` 为空时，把 [ModuleDescriptor.dataBindings]
/// 经 DataOrchestrator 拉取的行数据注入 [DefaultView]，使其不再恒空（R2）。
///
/// 运行：cd evg-base && flutter test test/renderer/m2_module_binding_test.dart
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/page/composite_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('模块级 dataBindings → DefaultView 注入行数据渲染', (tester) async {
    final orch = DataOrchestrator();
    orch.register(
      DataType<dynamic>(name: 'myRows'),
      () async => [
        {'name': '注入行A'},
        {'name': '注入行B'},
      ],
    );

    final descriptor = ModuleDescriptor(
      id: 'mod1',
      name: 'M1',
      dataBindings: [
        DataBindingDescriptor(dataType: 'myRows', display: 'table'),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dataOrchestratorProvider.overrideWith((ref) => orch)],
        child: MaterialApp(home: Scaffold(body: CompositeView(descriptor: descriptor))),
      ),
    );
    await tester.pumpAndSettle();

    // 注入的行数据应出现在表格单元格中（非恒空）。
    expect(find.text('注入行A'), findsWidgets);
    expect(find.text('注入行B'), findsWidgets);
  });

  testWidgets('无 dataBindings → DefaultView 显示空状态占位，不崩', (tester) async {
    final descriptor = ModuleDescriptor(
      id: 'mod2',
      name: 'M2',
      dataBindings: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dataOrchestratorProvider.overrideWith((ref) => DataOrchestrator())],
        child: MaterialApp(home: Scaffold(body: CompositeView(descriptor: descriptor))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('此模块未配置数据绑定'), findsWidgets);
  });
}
