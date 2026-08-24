/// 权限弹窗 + 能力桥接测试（M5-3/M5-4 · renderer 侧）。
import 'package:evergreen_base/core/module/capability.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/ability_capability_bridge.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/models.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/permission_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ability_capability_bridge', () {
    test('AbilityDim → CapabilityDimension', () {
      expect(toCoreDim(AbilityDim.agent), CapabilityDimension.agent);
      expect(toCoreDim(AbilityDim.ui), CapabilityDimension.module);
      expect(toCoreDim(AbilityDim.settings), CapabilityDimension.config);
      expect(toCoreDim(AbilityDim.skill), isNull);
    });
    test('CapabilityDimension → AbilityDim', () {
      expect(toAbilityDim(CapabilityDimension.agent), AbilityDim.agent);
      expect(toAbilityDim(CapabilityDimension.module), AbilityDim.ui);
      expect(toAbilityDim(CapabilityDimension.process), isNull);
    });
    test('toCoreDims 过滤 null', () {
      final dims = toCoreDims([AbilityDim.agent, AbilityDim.skill]);
      expect(dims, [CapabilityDimension.agent]);
    });
  });

  group('PermissionConfirmDialog', () {
    testWidgets('默认拒绝：点遮罩/取消不触发 onConfirm', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              await showPermissionConfirmDialog(
                context: ctx,
                pluginName: '测试插件',
                dims: [CapabilityDimension.theme],
                onConfirm: () => confirmed = true,
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // 点取消
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(confirmed, isFalse);
    });

    testWidgets('点确认安装触发 onConfirm', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              await showPermissionConfirmDialog(
                context: ctx,
                pluginName: '测试插件',
                dims: [CapabilityDimension.theme, CapabilityDimension.data],
                onConfirm: () => confirmed = true,
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认安装'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });

    testWidgets('高危维度（process）标题显示高危', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              await showPermissionConfirmDialog(
                context: ctx,
                pluginName: '后端插件',
                dims: [CapabilityDimension.process],
                onConfirm: () {},
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // 弹窗内含风险等级文案与维度名
      expect(find.text('风险等级：高危'), findsOneWidget);
      expect(find.text('后端进程'), findsWidgets);
    });

    testWidgets('安全维度显示安全', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              await showPermissionConfirmDialog(
                context: ctx,
                pluginName: '主题插件',
                dims: [CapabilityDimension.theme],
                onConfirm: () {},
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('风险等级：安全'), findsOneWidget);
    });
  });
}
